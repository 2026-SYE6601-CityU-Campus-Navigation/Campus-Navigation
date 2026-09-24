import SwiftData

@MainActor
protocol RecordingPersisting: AnyObject {
    func createTrack(name: String, area: Area, startedAt: Int64) throws -> Track
    func append(_ drafts: [TrackPointDraft], to track: Track) throws
    func finalize(_ track: Track, endedAt: Int64) throws
    func delete(_ track: Track) throws
}

@MainActor
final class SwiftDataRecordingStore: RecordingPersisting {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func createTrack(name: String, area: Area, startedAt: Int64) throws -> Track {
        let track = Track(name: name, area: area, startedAt: startedAt)
        context.insert(track)
        try context.save()
        return track
    }

    func append(_ drafts: [TrackPointDraft], to track: Track) throws {
        guard track.endedAt == nil else { throw RecordingError.finalizedTrack }
        guard !drafts.isEmpty else { return }

        for draft in drafts {
            context.insert(TrackPoint(
                track: track,
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
                wifiTop: draft.wifiTop
            ))
        }
        try context.save()
    }

    func finalize(_ track: Track, endedAt: Int64) throws {
        guard track.endedAt == nil else { throw RecordingError.finalizedTrack }
        track.endedAt = endedAt
        try context.save()
    }

    func delete(_ track: Track) throws {
        context.delete(track)
        try context.save()
    }
}
