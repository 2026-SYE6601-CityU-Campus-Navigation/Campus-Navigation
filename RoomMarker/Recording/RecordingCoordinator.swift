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

    init(
        hub: any SensorHubProtocol,
        ticker: any RecordingTicking = ForegroundRecordingTicker(),
        persistence: any RecordingPersisting,
        assembler: SampleAssembler = SampleAssembler(),
        metadataAssembler: TrackCaptureMetadataAssembler = TrackCaptureMetadataAssembler(),
        mediaPersistence: (any TrackMediaPersisting)? = nil,
        photoStorage: (any PhotoFileStoring)? = nil,
        backgroundSession: any BackgroundLocationSession = ForegroundOnlyBackgroundLocationSession(),
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
        self.nowMilliseconds = nowMilliseconds
    }

    var isRecording: Bool {
        if case .recording = state { return true }
        return false
    }

    var activeTrackID: UUID? {
        activeTrack?.id
    }

    func start(name: String, area: Area?) throws {
        guard state == .idle else { throw RecordingError.alreadyActive }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw RecordingError.emptyName }
        guard let area else { throw RecordingError.areaRequired }

        transition(to: .preparing)
        do {
            let track = try persistence.createTrack(
                name: trimmedName,
                area: area,
                startedAt: nowMilliseconds()
            )
            activeTrack = track
            currentSampleCount = 0
            pending.removeAll(keepingCapacity: true)
            lastAcceptedTickMs = nil

            hub.start(consumer: .recording, requestLocationAuthorization: true)
            backgroundStatus = backgroundSession.acquire()
            ticker.start { [weak self] timeMs in
                guard let self else { return false }
                return self.acceptTick(timeMs)
            }
            transition(to: .recording(trackID: track.id))
        } catch {
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
        try persistence.delete(track)
        try photoStorage?.deleteTrackDirectory(trackID: track.id)
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
        guard phase == .background else { return }

        do {
            // Protect an in-memory tail before suspension. Normal five-point
            // batching resumes with one shared buffer when execution continues.
            try flushPending(to: track)
        } catch {
            backgroundSession.release()
            backgroundStatus = .inactive
            hub.stop(consumer: .recording)
            transition(to: .failed(message: error.localizedDescription, trackID: track.id))
        }
    }

    @discardableResult
    func addTag(type: TrackTagType, note: String) throws -> TrackTag {
        let track = try requireActiveTrack()
        guard let mediaPersistence else { throw TrackMediaError.servicesUnavailable }
        let timeMs = nowMilliseconds()
        let draft = TrackTagDraft(
            timeMs: timeMs,
            tagType: type,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            metadata: metadataAssembler.assemble(from: hub.state),
            createdAt: timeMs
        )
        return try mediaPersistence.createTag(draft, for: track)
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
        try mediaPersistence.deleteTag(tag)
    }

    func deletePhoto(_ photo: TrackPhoto) throws {
        guard let mediaPersistence, let photoStorage else {
            throw TrackMediaError.servicesUnavailable
        }
        try photoStorage.validate(relativePath: photo.filePath)
        try mediaPersistence.deletePhoto(photo)
        try photoStorage.delete(relativePath: photo.filePath)
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

    private func acceptTick(_ timeMs: Int64) -> Bool {
        guard case .recording = state,
              let track = activeTrack,
              track.endedAt == nil else {
            return false
        }
        if let lastAcceptedTickMs, timeMs <= lastAcceptedTickMs {
            return true
        }

        pending.append(assembler.assemble(timeMs: timeMs, state: hub.state))
        lastAcceptedTickMs = timeMs
        currentSampleCount += 1

        guard pending.count >= 5 else { return true }
        do {
            try flushPending(to: track)
            return true
        } catch {
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
            return try mediaPersistence.createPhoto(draft, for: track)
        } catch {
            try? photoStorage.delete(relativePath: relativePath)
            throw error
        }
    }

    private func clearSession() {
        activeTrack = nil
        currentSampleCount = 0
        pending.removeAll(keepingCapacity: false)
        lastAcceptedTickMs = nil
        backgroundStatus = .inactive
    }

    private func transition(to newState: RecordingState) {
        state = newState
        transitionHistory.append(newState.phase)
    }
}
