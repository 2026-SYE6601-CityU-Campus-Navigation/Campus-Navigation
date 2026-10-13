import Foundation
import Observation

@MainActor
@Observable
final class RecordingCoordinator {
    private(set) var state: RecordingState = .idle
    private(set) var activeTrack: Track?
    private(set) var currentSampleCount = 0
    private(set) var transitionHistory: [RecordingPhase] = [.idle]
    private(set) var backgroundStatus: BackgroundLocationSessionStatus = .inactive
    private(set) var mediaCleanupMessage: String?
    let rawIMU: RawIMURecorder?
    var supportsRawIMU: Bool { rawIMU != nil && persistence is any TrackStructurePersisting }

    @ObservationIgnored private let hub: any SensorHubProtocol
    @ObservationIgnored private let ticker: any RecordingTicking
    @ObservationIgnored private let persistence: any RecordingPersisting
    @ObservationIgnored private let assembler: SampleAssembler
    @ObservationIgnored private let metadataAssembler: TrackCaptureMetadataAssembler
    @ObservationIgnored private let mediaPersistence: (any TrackMediaPersisting)?
    @ObservationIgnored private let photoStorage: (any PhotoFileStoring)?
    @ObservationIgnored private let backgroundSession: any BackgroundLocationSession
    @ObservationIgnored private let nowMilliseconds: @MainActor @Sendable () -> Int64
    @ObservationIgnored private var pending: [TrackPointDraft] = []
    @ObservationIgnored private var lastAcceptedTickMs: Int64?
    @ObservationIgnored private var initialTagLocationContext = TagLocationContext(
        areaID: nil,
        areaStateRawValue: TrackTagAreaState.unknown.rawValue,
        floor: ""
    )
    @ObservationIgnored private var savedTagsInCaptureOrder: [TrackTag] = []
    @ObservationIgnored private var savedCaptureIDs: Set<UUID> = []
    @ObservationIgnored private var pendingPhotoCleanup: Set<String> = []

    init(
        hub: any SensorHubProtocol,
        ticker: any RecordingTicking = ForegroundRecordingTicker(),
        persistence: any RecordingPersisting,
        assembler: SampleAssembler = SampleAssembler(),
        metadataAssembler: TrackCaptureMetadataAssembler = TrackCaptureMetadataAssembler(),
        mediaPersistence: (any TrackMediaPersisting)? = nil,
        photoStorage: (any PhotoFileStoring)? = nil,
        backgroundSession: any BackgroundLocationSession = ForegroundOnlyBackgroundLocationSession(),
        rawIMU: RawIMURecorder? = nil,
        nowMilliseconds: @escaping @MainActor @Sendable () -> Int64 = {
            Int64(Date().timeIntervalSince1970 * 1_000)
        }
    ) {
        self.hub = hub
        self.ticker = ticker
        self.persistence = persistence
        self.assembler = assembler
        self.metadataAssembler = metadataAssembler
        self.mediaPersistence = mediaPersistence
        self.photoStorage = photoStorage
        self.backgroundSession = backgroundSession
        self.rawIMU = rawIMU
        self.nowMilliseconds = nowMilliseconds
    }

    var isRecording: Bool {
        if case .recording = state { return true }
        return false
    }

    var activeTrackID: UUID? {
        activeTrack?.id
    }

    var tagLocationContext: TagLocationContext {
        guard let tag = savedTagsInCaptureOrder.last else {
            return initialTagLocationContext
        }
        return TagLocationContext(
            areaID: tag.areaID,
            areaStateRawValue: tag.areaStateRawValue,
            floor: tag.floor
        )
    }

    var activeSegment: TrackSegment? {
        guard let activeTrack else { return nil }
        return try? TrackSegmentRules.current(in: activeTrack)
    }

    func start(name: String, area: Area? = nil, environment: TrackEnvironment = .unknown, collectRawIMU: Bool = false) throws {
        guard state == .idle else { throw RecordingError.alreadyActive }
        if collectRawIMU && (!supportsRawIMU || rawIMU?.canStart != true) { throw RawIMUError.unavailable }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw RecordingError.emptyName }
        transition(to: .preparing)
        do {
            let track: Track
            if let structure = persistence as? any TrackStructurePersisting {
                track = try structure.createSegmentedTrack(
                    name: trimmedName, startedAt: nowMilliseconds(), environment: environment, collectRawIMU: collectRawIMU
                )
            } else {
                // Older persistence adapters have no structural capability.
                // The UI explicitly disables these actions, never invents data.
                track = try persistence.createTrack(name: trimmedName, area: nil, startedAt: nowMilliseconds())
            }
            activeTrack = track
            currentSampleCount = 0
            pending.removeAll(keepingCapacity: true)
            lastAcceptedTickMs = nil
            initialTagLocationContext = TagLocationContext(area: area)
            savedTagsInCaptureOrder.removeAll(keepingCapacity: true)

            hub.start(consumer: .recording, requestLocationAuthorization: true)
            backgroundStatus = backgroundSession.acquire()
            ticker.start { [weak self] timeMs in
                guard let self else { return false }
                return self.acceptTick(timeMs)
            }
            transition(to: .recording(trackID: track.id))
            if collectRawIMU { try rawIMU?.begin(for: track) }
        } catch {
            try? rawIMU?.stopAndFlush()
            backgroundSession.release()
            backgroundStatus = .inactive
            hub.stop(consumer: .recording)
            transition(to: .failed(message: error.localizedDescription, trackID: nil))
            throw error
        }
    }

    func stop() async throws {
        guard case let .recording(trackID) = state,
              let track = activeTrack,
              track.id == trackID else {
            throw RecordingError.notRecording
        }

        transition(to: .stopping(trackID: trackID))
        await ticker.stop()

        do {
            try rawIMU?.stopAndFlush()
            try flushPending(to: track)
            try persistence.finalize(track, endedAt: nowMilliseconds())
            backgroundSession.release()
            backgroundStatus = .inactive
            hub.stop(consumer: .recording)
            clearSession()
            transition(to: .idle)
        } catch {
            backgroundSession.release()
            backgroundStatus = .inactive
            hub.stop(consumer: .recording)
            transition(to: .failed(message: error.localizedDescription, trackID: track.id))
            throw error
        }
    }

    func resetFailure() async {
        guard case .failed = state else { return }
        await ticker.stop()
        do {
            try rawIMU?.stopAndFlush()
            // A raw-IMU stop failure happens before the ordinary TrackPoint tail
            // is flushed. Do not discard that tail when dismissing this failure.
            if let track = activeTrack, track.rawIMURequested { try flushPending(to: track) }
        } catch {
            let message = rawIMU?.errorMessage == nil ? error.localizedDescription : RawIMUError.pendingSave.localizedDescription
            transition(to: .failed(message: message, trackID: activeTrackID))
            return
        }
        backgroundSession.release()
        backgroundStatus = .inactive
        hub.stop(consumer: .recording)
        clearSession()
        transition(to: .idle)
    }

    func delete(_ track: Track) throws {
        guard activeTrackID != track.id else {
            throw RecordingError.activeTrackCannotBeDeleted
        }
        let trackID = track.id
        try photoStorage?.prepareDeletion(relativePath: "photos/\(trackID.uuidString.lowercased())")
        try persistence.delete(track)
        guard let photoStorage else { return }
        do {
            try photoStorage.deleteTrackDirectory(trackID: trackID)
        } catch {
            pendingPhotoCleanup.insert("photos/\(trackID.uuidString.lowercased())")
            mediaCleanupMessage = "轨迹数据已删除，但照片目录清理未完成。请重试照片清理。"
        }
    }

    func finalizeInterrupted(_ track: Track, at finalizedAt: Int64? = nil) throws {
        guard track.endedAt == nil, !isActive(track) else {
            throw RecordingError.trackIsNotIncomplete
        }
        try persistence.finalize(
            track,
            endedAt: max(track.startedAt, finalizedAt ?? nowMilliseconds())
        )
    }

    func handleLifecycleTransition(_ phase: RecordingLifecyclePhase) {
        guard case let .recording(trackID) = state,
              let track = activeTrack,
              track.id == trackID else {
            return
        }

        let observedBackgroundStatus = backgroundSession.status(for: hub.state.permission)
        if observedBackgroundStatus != .inactive || backgroundStatus == .active {
            backgroundStatus = observedBackgroundStatus
        }
        if case let .unavailable(reason) = observedBackgroundStatus,
           reason == .authorizationDenied || reason == .authorizationRestricted {
            backgroundSession.release()
        }
        if phase == .background { rawIMU?.pauseForBackground() }
        if phase == .active { rawIMU?.resumeForeground() }
        guard phase == .background else { return }

        do {
            // Protect an in-memory tail before suspension. Normal five-point
            // batching resumes with one shared buffer when execution continues.
            try flushPending(to: track)
        } catch {
            try? rawIMU?.stopAndFlush()
            backgroundSession.release()
            backgroundStatus = .inactive
            hub.stop(consumer: .recording)
            transition(to: .failed(message: error.localizedDescription, trackID: track.id))
        }
    }

    @discardableResult
    func addTag(type: TrackTagType, note: String) throws -> TrackTag {
        try addTag(type: type, note: note, location: tagLocationContext)
    }

    @discardableResult
    func addTag(type: TrackTagType, note: String, area: Area?, floor: String) throws -> TrackTag {
        try addTag(type: type, note: note, location: TagLocationContext(area: area, floor: floor))
    }

    private func addTag(type: TrackTagType, note: String, location: TagLocationContext) throws -> TrackTag {
        let track = try requireActiveTrack()
        guard let mediaPersistence else { throw TrackMediaError.servicesUnavailable }
        let timeMs = nowMilliseconds()
        let draft = TrackTagDraft(
            timeMs: timeMs,
            tagType: type,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            metadata: metadataAssembler.assemble(from: hub.state),
            createdAt: timeMs,
            areaID: location.areaID,
            areaStateRawValue: location.areaStateRawValue,
            floor: location.floor
        )
        let tag = try mediaPersistence.createTag(draft, for: track)
        // Capture order is the successful persistence order, including equal
        // timestamps. Reading the model also reflects edits to the latest tag.
        savedTagsInCaptureOrder.append(tag)
        return tag
    }

    @discardableResult
    func handlePhotoCapture(
        _ outcome: CameraCaptureOutcome,
        note: String = ""
    ) throws -> TrackPhoto? {
        switch outcome {
        case .cancelled, .unavailable:
            return nil
        case let .failed(message):
            throw TrackMediaError.captureFailed(message)
        case let .success(jpegData, capturedAt):
            return try saveCapturedPhoto(
                jpegData: jpegData,
                capturedAt: capturedAt,
                note: note
            )
        }
    }

    func deleteTag(_ tag: TrackTag) throws {
        guard let mediaPersistence else { throw TrackMediaError.servicesUnavailable }
        let tagID = tag.id
        let remainingTags = savedTagsInCaptureOrder.filter { $0.id != tagID }
        if tag.isNode {
            guard let nodes = mediaPersistence as? any TrackNodePersisting, let photoStorage else {
                throw TrackMediaError.servicesUnavailable
            }
            let photo = try NodePhotoAssociation.photo(for: tag)
            let path = photo.filePath
            try photoStorage.validate(relativePath: path)
            try photoStorage.prepareDeletion(relativePath: path)
            try nodes.deleteNode(tag)
            cleanupPhoto(path)
        } else {
            try mediaPersistence.deleteTag(tag)
        }
        savedTagsInCaptureOrder = remainingTags
    }

    func deletePhoto(_ photo: TrackPhoto) throws {
        guard let mediaPersistence, let photoStorage else {
            throw TrackMediaError.servicesUnavailable
        }
        guard !photo.isNodePhoto, photo.tagID == nil else {
            throw NodeCaptureError.nodePhotoRequiresNodeDeletion
        }
        let path = photo.filePath
        try photoStorage.validate(relativePath: path)
        try photoStorage.prepareDeletion(relativePath: path)
        try mediaPersistence.deletePhoto(photo)
        cleanupPhoto(path)
    }

    func freezePhotoCapture(_ outcome: CameraCaptureOutcome) throws -> CapturedTrackPhoto? {
        switch outcome {
        case .cancelled, .unavailable: return nil
        case let .failed(message): throw TrackMediaError.captureFailed(message)
        case let .success(data, time):
            let track = try requireActiveTrack()
            guard !data.isEmpty else { throw TrackMediaError.emptyImageData }
            guard NodeJPEGValidation.isReadable(data) else { throw NodeCaptureError.invalidImage }
            return CapturedTrackPhoto(
                id: UUID(), trackID: track.id, jpegData: data, capturedAt: time,
                metadata: metadataAssembler.assemble(from: hub.state)
            )
        }
    }

    @discardableResult
    func saveNode(
        capture: CapturedTrackPhoto, type: TrackTagType, note: String,
        area: Area?, floor: String
    ) throws -> TrackTag {
        try saveNode(capture: capture, type: type, note: note, location: TagLocationContext(area: area, floor: floor))
    }

    @discardableResult
    func saveNode(
        capture: CapturedTrackPhoto, type: TrackTagType, note: String,
        location: TagLocationContext, roomSelection: NodeRoomSelection? = nil
    ) throws -> TrackTag {
        let track = try track(for: capture)
        guard capture.metadata.hasValidQuality else { throw NodeCaptureError.invalidSensorMetadata }
        guard let nodes = mediaPersistence as? any TrackNodePersisting, let photoStorage else {
            throw TrackMediaError.servicesUnavailable
        }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let draft = TrackTagDraft(
            timeMs: capture.capturedAt, tagType: type, note: trimmedNote,
            metadata: capture.metadata, createdAt: nowMilliseconds(),
            areaID: location.areaID, areaStateRawValue: location.areaStateRawValue, floor: location.floor,
            roomSelection: roomSelection
        )
        let path = try photoStorage.storeJPEG(
            capture.jpegData, trackID: track.id, timeMs: capture.capturedAt
        )
        let photo = TrackPhotoDraft(
            timeMs: capture.capturedAt, filePath: path, note: trimmedNote,
            metadata: capture.metadata, createdAt: draft.createdAt,
            kindRawValue: "node", tagID: capture.id
        )
        do {
            let tag = try nodes.createNode(id: capture.id, tag: draft, photo: photo, for: track)
            savedCaptureIDs.insert(capture.id)
            savedTagsInCaptureOrder.append(tag)
            confirmStoredPhoto(path)
            return tag
        } catch {
            let originalError = error
            cleanupPhoto(path)
            if pendingPhotoCleanup.contains(path) { throw NodeCaptureError.compensationPending }
            throw originalError
        }
    }

    @discardableResult
    func saveScenery(capture: CapturedTrackPhoto, note: String) throws -> TrackPhoto {
        let track = try track(for: capture)
        guard capture.metadata.hasValidQuality else { throw NodeCaptureError.invalidSensorMetadata }
        guard let mediaPersistence, let photoStorage else { throw TrackMediaError.servicesUnavailable }
        let path = try photoStorage.storeJPEG(capture.jpegData, trackID: track.id, timeMs: capture.capturedAt)
        do {
            let photo = try mediaPersistence.createPhoto(TrackPhotoDraft(
                timeMs: capture.capturedAt, filePath: path,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                metadata: capture.metadata, createdAt: nowMilliseconds()
            ), for: track)
            savedCaptureIDs.insert(capture.id)
            confirmStoredPhoto(path)
            return photo
        } catch {
            let originalError = error
            cleanupPhoto(path)
            if pendingPhotoCleanup.contains(path) { throw NodeCaptureError.compensationPending }
            throw originalError
        }
    }

    // Never clear this warning merely because a view closes. On disk, deletion
    // intents survive relaunch; referenced photos are always protected on retry.
    func retryPhotoCleanup(protecting referencedPaths: Set<String>) {
        guard let photoStorage else { return }
        do {
            for path in pendingPhotoCleanup {
                try photoStorage.prepareDeletion(relativePath: path)
            }
            try photoStorage.retryPendingCleanup(protecting: referencedPaths)
            pendingPhotoCleanup.removeAll()
            mediaCleanupMessage = nil
        } catch {
            mediaCleanupMessage = "照片清理仍未完成，请保留应用并重试。"
        }
    }

    private func track(for capture: CapturedTrackPhoto) throws -> Track {
        let track = try requireActiveTrack()
        guard capture.trackID == track.id else { throw NodeCaptureError.changedSession }
        guard !savedCaptureIDs.contains(capture.id) else { throw NodeCaptureError.alreadySaved }
        guard NodeJPEGValidation.isReadable(capture.jpegData) else { throw NodeCaptureError.invalidImage }
        return track
    }

    private func cleanupPhoto(_ path: String) {
        guard let photoStorage else { return }
        do {
            try photoStorage.delete(relativePath: path)
            pendingPhotoCleanup.remove(path)
        } catch {
            pendingPhotoCleanup.insert(path)
            mediaCleanupMessage = "照片文件清理未完成。请点“重试照片清理”；未影响其他照片。"
        }
    }

    private func confirmStoredPhoto(_ path: String) {
        do {
            try photoStorage?.confirmReferenced(relativePath: path)
        } catch {
            // DB success must not become a failed capture: startup/retry resolves
            // the intent using actual SwiftData references, without deleting it.
            mediaCleanupMessage = "照片已保存；清理记录更新未完成，请重试照片清理。"
        }
    }

    func loadPhotoContent(_ photo: TrackPhoto) -> PhotoContent {
        guard let photoStorage else {
            return PhotoContent(status: .missing, data: nil, image: nil)
        }
        return PhotoContentLoader(storage: photoStorage).load(relativePath: photo.filePath)
    }

    func isActive(_ track: Track) -> Bool {
        activeTrackID == track.id
    }

    @discardableResult
    func captureCorner(note: String = "") throws -> TrackCorner {
        let track = try requireActiveTrack()
        guard let structure = persistence as? any TrackStructurePersisting else {
            throw TrackStructureError.unavailable
        }
        let segment = try TrackSegmentRules.current(in: track)
        let timeMs = nowMilliseconds()
        guard timeMs >= (lastAcceptedTickMs ?? track.startedAt) else {
            throw TrackStructureError.invalidTimestamp
        }
        var sample = assembler.assemble(timeMs: timeMs, state: hub.state)
        sample.segmentID = segment.id
        return try structure.createCorner(sample: sample, note: note, for: track)
    }

    func changeEnvironment(to environment: TrackEnvironment) throws {
        let track = try requireActiveTrack()
        guard let structure = persistence as? any TrackStructurePersisting else {
            throw TrackStructureError.unavailable
        }
        let segment = try TrackSegmentRules.current(in: track)
        guard segment.environment != environment else { return }
        let timeMs = nowMilliseconds()
        if track.rawIMURequested, let latest = rawIMU?.latestTimeMs, timeMs <= latest {
            throw TrackStructureError.invalidTimestamp
        }
        guard timeMs > (lastAcceptedTickMs ?? track.startedAt) else {
            throw TrackStructureError.invalidTimestamp
        }
        _ = try structure.switchSegment(
            for: track, to: environment, at: timeMs, pendingPoints: pending
        )
        // Clear only after the tail + boundary commit succeeds. On failure the
        // old segment stays open and this exact tail is retained for retry/stop.
        pending.removeAll(keepingCapacity: true)
    }

    func deleteCorner(_ corner: TrackCorner) throws {
        guard let structure = persistence as? any TrackStructurePersisting else {
            throw TrackStructureError.unavailable
        }
        try structure.deleteCorner(corner)
    }

    private func acceptTick(_ timeMs: Int64) -> Bool {
        guard case .recording = state,
              let track = activeTrack,
              track.endedAt == nil else {
            return false
        }
        if let lastAcceptedTickMs, timeMs <= lastAcceptedTickMs {
            return true
        }

        var sample = assembler.assemble(timeMs: timeMs, state: hub.state)
        if track.isSegmentedRecording {
            do {
                let segment = try TrackSegmentRules.current(in: track)
                // A delayed pre-boundary tick is not a new-segment observation.
                guard timeMs >= segment.startedAt else { return true }
                sample.segmentID = segment.id
            } catch {
                try? rawIMU?.stopAndFlush()
                backgroundSession.release()
                backgroundStatus = .inactive
                hub.stop(consumer: .recording)
                transition(to: .failed(message: error.localizedDescription, trackID: track.id))
                return false
            }
        }
        pending.append(sample)
        lastAcceptedTickMs = timeMs
        currentSampleCount += 1

        guard pending.count >= 5 else { return true }
        do {
            try flushPending(to: track)
            return true
        } catch {
            try? rawIMU?.stopAndFlush()
            backgroundSession.release()
            backgroundStatus = .inactive
            hub.stop(consumer: .recording)
            transition(to: .failed(message: error.localizedDescription, trackID: track.id))
            return false
        }
    }

    private func flushPending(to track: Track) throws {
        guard !pending.isEmpty else { return }
        let batch = pending
        try persistence.append(batch, to: track)
        pending.removeAll(keepingCapacity: true)
    }

    private func requireActiveTrack() throws -> Track {
        guard case let .recording(trackID) = state,
              let track = activeTrack,
              track.id == trackID,
              track.endedAt == nil else {
            throw TrackMediaError.noActiveTrack
        }
        return track
    }

    private func saveCapturedPhoto(
        jpegData: Data,
        capturedAt: Int64,
        note: String
    ) throws -> TrackPhoto {
        guard !jpegData.isEmpty else { throw TrackMediaError.emptyImageData }
        let track = try requireActiveTrack()
        guard let mediaPersistence, let photoStorage else {
            throw TrackMediaError.servicesUnavailable
        }

        let relativePath = try photoStorage.storeJPEG(
            jpegData,
            trackID: track.id,
            timeMs: capturedAt
        )
        let draft = TrackPhotoDraft(
            timeMs: capturedAt,
            filePath: relativePath,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            metadata: metadataAssembler.assemble(from: hub.state),
            createdAt: nowMilliseconds()
        )

        do {
            let photo = try mediaPersistence.createPhoto(draft, for: track)
            confirmStoredPhoto(relativePath)
            return photo
        } catch {
            let originalError = error
            cleanupPhoto(relativePath)
            if pendingPhotoCleanup.contains(relativePath) { throw NodeCaptureError.compensationPending }
            throw originalError
        }
    }

    private func clearSession() {
        activeTrack = nil
        currentSampleCount = 0
        pending.removeAll(keepingCapacity: false)
        lastAcceptedTickMs = nil
        savedTagsInCaptureOrder.removeAll(keepingCapacity: false)
        initialTagLocationContext = TagLocationContext(
            areaID: nil,
            areaStateRawValue: TrackTagAreaState.unknown.rawValue,
            floor: ""
        )
        backgroundStatus = .inactive
    }

    private func transition(to newState: RecordingState) {
        state = newState
        transitionHistory.append(newState.phase)
    }
}
