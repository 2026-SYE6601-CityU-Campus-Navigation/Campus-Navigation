import Foundation
import SwiftData

@MainActor
protocol RecordingPersisting: AnyObject {
    func createTrack(name: String, area: Area?, startedAt: Int64) throws -> Track
    func append(_ drafts: [TrackPointDraft], to track: Track) throws
    func finalize(_ track: Track, endedAt: Int64) throws
    func delete(_ track: Track) throws
}

@MainActor
final class SwiftDataRecordingStore: RecordingPersisting, TrackMediaPersisting, TrackNodePersisting, TrackStructurePersisting, RawIMUPersisting {
    private let context: ModelContext
    private let save: @MainActor (ModelContext) throws -> Void

    init(
        context: ModelContext,
        save: @escaping @MainActor (ModelContext) throws -> Void = { try $0.save() }
    ) {
        self.context = context
        self.save = save
    }

    func createTrack(name: String, area: Area?, startedAt: Int64) throws -> Track {
        let track = Track(name: name, area: nil, startedAt: startedAt, isGlobalRecording: true)
        context.insert(track)
        try context.save()
        return track
    }

    func append(_ drafts: [TrackPointDraft], to track: Track) throws {
        guard track.endedAt == nil else { throw RecordingError.finalizedTrack }
        guard !drafts.isEmpty else { return }

        if track.isSegmentedRecording {
            try validatePoints(drafts, in: track)
        } else if drafts.contains(where: { $0.segmentID != nil }) {
            throw TrackStructureError.wrongSegment
        }
        prepareTrackMutation(track)
        insertPoints(drafts, to: track)
        do {
            context.processPendingChanges()
            try save(context)
        } catch {
            context.rollback()
            throw error
        }
    }

    private func insertPoints(_ drafts: [TrackPointDraft], to track: Track) {
        for draft in drafts {
            let point = TrackPoint(
                track: nil,
                timeMs: draft.timeMs,
                latitude: draft.latitude,
                longitude: draft.longitude,
                altitude: draft.altitude,
                accuracy: draft.accuracy,
                pressureHpa: draft.pressureHpa,
                magneticX: draft.magneticX,
                magneticY: draft.magneticY,
                magneticZ: draft.magneticZ,
                headingDeg: draft.headingDeg,
                wifiAvailability: draft.wifiAvailability,
                wifiCount: draft.wifiCount,
                wifiTop: draft.wifiTop,
                segmentID: draft.segmentID
            )
            // Register before linking: rollback must own the inverse change.
            context.insert(point)
            point.track = track
        }
    }

    private func validatePoints(_ drafts: [TrackPointDraft], in track: Track) throws {
        var previous = track.points.map(\.timeMs).max()
        for draft in drafts {
            try TrackSegmentRules.validate(draft, in: track)
            if let previous, draft.timeMs <= previous { throw TrackStructureError.invalidTimestamp }
            previous = draft.timeMs
        }
    }

    private func prepareTrackMutation(_ track: Track) {
        // Materialize unchanged relations before rollback can snapshot the Track.
        // Otherwise SwiftData can restore a lazy future as an array on access.
        _ = track.points.count
        _ = track.tags.count
        _ = track.photos.count
        _ = track.segments.count
        _ = track.corners.count
        _ = track.imuBatches.count
        context.processPendingChanges()
    }

    func finalize(_ track: Track, endedAt: Int64) throws {
        guard track.endedAt == nil else { throw RecordingError.finalizedTrack }
        prepareTrackMutation(track)
        if track.isSegmentedRecording {
            let segment = try TrackSegmentRules.current(in: track)
            guard endedAt >= segment.startedAt,
                  endedAt >= TrackSegmentRules.latestEvidenceTime(in: track) else {
                throw TrackStructureError.invalidTimestamp
            }
            segment.endedAt = endedAt
        }
        track.endedAt = endedAt
        do {
            try save(context)
        } catch {
            context.rollback()
            throw error
        }
    }

    func delete(_ track: Track) throws {
        context.delete(track)
        do {
            try save(context)
        } catch {
            context.rollback()
            throw error
        }
    }

    func createTag(_ draft: TrackTagDraft, for track: Track) throws -> TrackTag {
        guard draft.roomSelection == nil else { throw NodeRoomError.unsupportedType }
        guard draft.metadata.hasValidQuality else { throw NodeCaptureError.invalidSensorMetadata }
        let location = try validatedLocation(for: draft)
        let tag = TrackTag(
            track: track,
            timeMs: draft.timeMs,
            tagType: draft.tagType,
            note: draft.note,
            latitude: draft.metadata.latitude,
            longitude: draft.metadata.longitude,
            altitude: draft.metadata.altitude,
            headingDeg: draft.metadata.headingDeg,
            accuracy: draft.metadata.accuracy,
            pressureHpa: draft.metadata.pressureHpa,
            createdAt: draft.createdAt,
            areaID: location.areaID,
            areaStateRawValue: location.areaStateRawValue,
            floor: location.floor
        )
        context.insert(tag)
        do {
            try context.save()
            return tag
        } catch {
            context.rollback()
            throw error
        }
    }

    private func validatedLocation(for draft: TrackTagDraft, strict: Bool = false) throws -> TagLocationContext {
        let floor = draft.floor.trimmingCharacters(in: .whitespacesAndNewlines)
        guard draft.areaStateRawValue == TrackTagAreaState.assigned.rawValue else {
            let state = draft.areaStateRawValue == TrackTagAreaState.unassigned.rawValue
                ? TrackTagAreaState.unassigned : .unknown
            return TagLocationContext(areaID: nil, areaStateRawValue: state.rawValue, floor: floor)
        }
        guard let areaID = draft.areaID else {
            if strict { throw NodeCaptureError.areaUnavailable }
            return TagLocationContext(area: nil, floor: floor)
        }
        var descriptor = FetchDescriptor<Area>(predicate: #Predicate { $0.id == areaID })
        descriptor.fetchLimit = 1
        let areas = try context.fetch(descriptor)
        guard !areas.isEmpty else {
            if strict { throw NodeCaptureError.areaUnavailable }
            return TagLocationContext(area: nil, floor: floor)
        }
        return TagLocationContext(
            areaID: areaID,
            areaStateRawValue: TrackTagAreaState.assigned.rawValue,
            floor: floor
        )
    }

    func createPhoto(_ draft: TrackPhotoDraft, for track: Track) throws -> TrackPhoto {
        guard draft.metadata.hasValidQuality else { throw NodeCaptureError.invalidSensorMetadata }
        guard draft.kindRawValue == "scenery", draft.tagID == nil else {
            throw NodeCaptureError.invalidAssociation
        }
        let photo = TrackPhoto(
            track: track,
            timeMs: draft.timeMs,
            filePath: draft.filePath,
            note: draft.note,
            latitude: draft.metadata.latitude,
            longitude: draft.metadata.longitude,
            altitude: draft.metadata.altitude,
            headingDeg: draft.metadata.headingDeg,
            accuracy: draft.metadata.accuracy,
            pressureHpa: draft.metadata.pressureHpa,
            createdAt: draft.createdAt,
            kindRawValue: draft.kindRawValue
        )
        context.insert(photo)
        do {
            try context.save()
            return photo
        } catch {
            context.rollback()
            throw error
        }
    }

    func deleteTag(_ tag: TrackTag) throws {
        guard !tag.isNode else { throw NodeCaptureError.invalidAssociation }
        context.delete(tag)
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    func deletePhoto(_ photo: TrackPhoto) throws {
        guard !photo.isNodePhoto, photo.tagID == nil else {
            throw NodeCaptureError.nodePhotoRequiresNodeDeletion
        }
        context.delete(photo)
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    func createNode(
        id: UUID, tag draft: TrackTagDraft, photo photoDraft: TrackPhotoDraft, for track: Track
    ) throws -> TrackTag {
        guard draft.metadata.hasValidQuality, photoDraft.metadata.hasValidQuality else {
            throw NodeCaptureError.invalidSensorMetadata
        }
        guard track.endedAt == nil,
              photoDraft.kindRawValue == "node", photoDraft.tagID == id,
              photoDraft.timeMs == draft.timeMs,
              photoDraft.metadata == draft.metadata,
              NodePhotoAssociation.isOwnedFilePath(photoDraft.filePath, trackID: track.id) else {
            throw NodeCaptureError.invalidAssociation
        }
        let existing = try context.fetch(FetchDescriptor<TrackTag>(predicate: #Predicate { $0.id == id }))
        guard existing.isEmpty else { throw NodeCaptureError.alreadySaved }
        let path = photoDraft.filePath
        let existingPhotos = try context.fetch(FetchDescriptor<TrackPhoto>(
            predicate: #Predicate { $0.tagID == id || $0.filePath == path }
        ))
        guard existingPhotos.isEmpty else { throw NodeCaptureError.invalidAssociation }
        let location = try validatedLocation(for: draft, strict: true)
        let room = try NodeRoomBinding.resolve(draft.roomSelection, type: draft.tagType,
                                              areaID: location.areaID, context: context)
        prepareTrackMutation(track)
        let tag = TrackTag(
            id: id, track: nil, timeMs: draft.timeMs, tagType: draft.tagType,
            note: draft.note, latitude: draft.metadata.latitude, longitude: draft.metadata.longitude,
            altitude: draft.metadata.altitude, headingDeg: draft.metadata.headingDeg,
            accuracy: draft.metadata.accuracy, pressureHpa: draft.metadata.pressureHpa,
            createdAt: draft.createdAt, areaID: location.areaID,
            areaStateRawValue: location.areaStateRawValue, floor: location.floor,
            recordKindRawValue: "node"
        )
        NodeRoomBinding.apply(draft.roomSelection, room: room, to: tag)
        let photo = TrackPhoto(
            track: nil, timeMs: photoDraft.timeMs, filePath: photoDraft.filePath,
            note: photoDraft.note, latitude: photoDraft.metadata.latitude,
            longitude: photoDraft.metadata.longitude, altitude: photoDraft.metadata.altitude,
            headingDeg: photoDraft.metadata.headingDeg,
            accuracy: photoDraft.metadata.accuracy, pressureHpa: photoDraft.metadata.pressureHpa,
            createdAt: photoDraft.createdAt,
            kindRawValue: "node", tagID: id
        )
        context.insert(tag)
        context.insert(photo)
        // Register before changing inverses so rollback restores the in-memory
        // Track as well as removing the two failed database inserts.
        tag.track = track
        photo.track = track
        do {
            // One SwiftData commit: never save one half of a new node.
            context.processPendingChanges()
            try save(context)
            return tag
        } catch {
            context.rollback()
            throw error
        }
    }

    func deleteNode(_ tag: TrackTag) throws {
        let photo = try NodePhotoAssociation.photo(for: tag)
        let tagID = tag.id
        let linked = try context.fetch(FetchDescriptor<TrackPhoto>(predicate: #Predicate { $0.tagID == tagID }))
        guard linked.count == 1, linked.first?.id == photo.id else {
            throw NodeCaptureError.invalidAssociation
        }
        context.delete(photo)
        context.delete(tag)
        do {
            try save(context)
        } catch {
            context.rollback()
            throw error
        }
    }

    func createSegmentedTrack(
        name: String, startedAt: Int64, environment: TrackEnvironment, collectRawIMU: Bool = false
    ) throws -> Track {
        let track = Track(name: name, startedAt: startedAt, isGlobalRecording: true)
        track.isSegmentedRecording = true
        track.rawIMURequested = collectRawIMU
        track.rawIMUInterval = collectRawIMU ? RawIMUPolicy.interval : nil
        if collectRawIMU {
            track.rawAccelState = RawIMUChannelState.waiting.rawValue
            track.rawGyroState = RawIMUChannelState.waiting.rawValue
        }
        context.insert(track)
        let segment = TrackSegment(track: nil, ordinal: 0, startedAt: startedAt, environment: environment)
        context.insert(segment)
        segment.track = track
        do {
            context.processPendingChanges()
            try save(context)
            return track
        } catch {
            context.rollback()
            throw error
        }
    }

    func switchSegment(
        for track: Track, to environment: TrackEnvironment, at timeMs: Int64,
        pendingPoints: [TrackPointDraft]
    ) throws -> TrackSegment {
        let current = try TrackSegmentRules.current(in: track)
        guard current.environment != environment else { return current }
        guard timeMs > current.startedAt,
              timeMs > TrackSegmentRules.latestEvidenceTime(in: track, pending: pendingPoints) else {
            throw TrackStructureError.invalidTimestamp
        }
        try validatePoints(pendingPoints, in: track)
        prepareTrackMutation(track)
        insertPoints(pendingPoints, to: track)
        current.endedAt = timeMs
        let next = TrackSegment(
            track: nil, ordinal: current.ordinal + 1, startedAt: timeMs, environment: environment
        )
        context.insert(next)
        next.track = track
        do {
            context.processPendingChanges()
            try save(context)
            return next
        } catch {
            context.rollback()
            throw error
        }
    }

    func createCorner(sample: TrackPointDraft, note: String, for track: Track) throws -> TrackCorner {
        try TrackSegmentRules.validate(sample, in: track)
        if let lastTime = track.corners.map(\.timeMs).max(), sample.timeMs <= lastTime {
            throw sample.timeMs == lastTime ? TrackStructureError.duplicateCorner : .invalidTimestamp
        }
        guard sample.timeMs >= TrackSegmentRules.latestEvidenceTime(in: track) else {
            throw TrackStructureError.invalidTimestamp
        }
        prepareTrackMutation(track)
        let corner = TrackCorner(track: nil, sample: sample, note: note)
        context.insert(corner)
        corner.track = track
        do {
            context.processPendingChanges()
            try save(context)
            return corner
        } catch {
            context.rollback()
            throw error
        }
    }

    func deleteCorner(_ corner: TrackCorner) throws {
        guard let track = corner.track,
              track.segments.contains(where: { $0.id == corner.segmentID && $0.track?.id == track.id }) else {
            throw TrackStructureError.wrongSegment
        }
        prepareTrackMutation(track)
        context.delete(corner)
        do {
            try save(context)
        } catch {
            context.rollback()
            throw error
        }
    }

    func saveIMU(id: UUID, samples: [RawIMUSample], status: RawIMUStatus, for track: Track) throws {
        guard track.endedAt == nil else { throw RecordingError.finalizedTrack }
        guard track.rawIMURequested, track.rawIMUInterval == RawIMUPolicy.interval,
              samples.count <= RawIMUPolicy.batchSize, status.rejectedCount >= 0,
              samples.allSatisfy(\.isFinite) else { throw RawIMUError.invalidBatch }
        _ = try TrackSegmentRules.current(in: track)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let payload = try encoder.encode(samples)
        let existing = try context.fetch(FetchDescriptor<TrackIMUBatch>(predicate: #Predicate { $0.id == id }))
        if let batch = existing.first {
            guard batch.track?.id == track.id, batch.payload == payload,
                  try batch.decodedSamples() == samples else { throw RawIMUError.invalidBatch }
        } else {
            var last: [RawIMUKind: Double] = [:]
            // Fetch at most one model per channel. Do not walk/materialize the
            // entire growing relationship twice for every 100-event batch.
            // Query persisted truth (including pending changes), not a cursor
            // cache that can become stale after rollback or another writer.
            last[.accelerometer] = try latestIMUTime(for: track, kind: .accelerometer)
            last[.gyroscope] = try latestIMUTime(for: track, kind: .gyroscope)
            for sample in samples {
                guard let segment = track.segments.first(where: { $0.id == sample.segmentID }),
                      segment.track?.id == track.id, sample.timeMs >= segment.startedAt,
                      segment.endedAt.map({ sample.timeMs < $0 }) ?? true else { throw RawIMUError.wrongSegment }
                guard last[sample.kind].map({ sample.sensorTimeSeconds > $0 }) ?? true else {
                    throw RawIMUError.invalidBatch
                }
                last[sample.kind] = sample.sensorTimeSeconds
            }
        }
        prepareTrackMutation(track)
        if existing.isEmpty && !samples.isEmpty {
            let batch = TrackIMUBatch(id: id, samples: samples, payload: payload)
            context.insert(batch)
            batch.track = track
        }
        if track.rawAccelState != status.accelerometer.rawValue { track.rawAccelState = status.accelerometer.rawValue }
        if track.rawGyroState != status.gyroscope.rawValue { track.rawGyroState = status.gyroscope.rawValue }
        if track.rawIMURejectedCount != status.rejectedCount { track.rawIMURejectedCount = status.rejectedCount }
        do {
            context.processPendingChanges()
            try save(context)
        } catch {
            context.rollback()
            throw error
        }
    }

    private func latestIMUTime(for track: Track, kind: RawIMUKind) throws -> Double? {
        let trackID = track.id
        var descriptor: FetchDescriptor<TrackIMUBatch>
        if kind == .accelerometer {
            descriptor = FetchDescriptor(
                predicate: #Predicate { $0.track?.id == trackID && $0.lastAccelerationTime != nil },
                sortBy: [SortDescriptor(\TrackIMUBatch.lastAccelerationTime, order: .reverse)]
            )
        } else {
            descriptor = FetchDescriptor(
                predicate: #Predicate { $0.track?.id == trackID && $0.lastGyroscopeTime != nil },
                sortBy: [SortDescriptor(\TrackIMUBatch.lastGyroscopeTime, order: .reverse)]
            )
        }
        descriptor.fetchLimit = 1
        guard let batch = try context.fetch(descriptor).first else { return nil }
        return kind == .accelerometer ? batch.lastAccelerationTime : batch.lastGyroscopeTime
    }
}
