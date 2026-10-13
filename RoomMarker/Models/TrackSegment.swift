import Foundation
import SwiftData

@Model
final class TrackSegment {
    @Attribute(.unique) var id: UUID
    var ordinal: Int
    var startedAt: Int64
    var endedAt: Int64?
    var environmentRawValue: String
    var track: Track?

    var environment: TrackEnvironment? { TrackEnvironment(rawValue: environmentRawValue) }

    init(
        id: UUID = UUID(), track: Track?, ordinal: Int,
        startedAt: Int64, endedAt: Int64? = nil, environment: TrackEnvironment
    ) {
        self.id = id
        self.track = track
        self.ordinal = ordinal
        self.startedAt = startedAt
        self.endedAt = endedAt
        environmentRawValue = environment.rawValue
    }
}
