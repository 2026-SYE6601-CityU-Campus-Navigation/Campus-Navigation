import Foundation
import SwiftData

@Model
final class Track {
    @Attribute(.unique) var id: UUID
    var name: String
    var startedAt: Int64
    var endedAt: Int64?
    // Retained only as the historical area hint for pre-global recordings.
    var area: Area?
    var legacyAreaName: String?
    var isGlobalRecording: Bool = false
    var isSegmentedRecording: Bool = false
    var rawIMURequested: Bool = false
    var rawIMUInterval: Double?
    var rawAccelState: String = "notRequested"
    var rawGyroState: String = "notRequested"
    var rawIMURejectedCount: Int = 0

    @Relationship(deleteRule: .cascade, inverse: \TrackPoint.track)
    var points: [TrackPoint]

    @Relationship(deleteRule: .cascade, inverse: \TrackTag.track)
    var tags: [TrackTag]

    @Relationship(deleteRule: .cascade, inverse: \TrackPhoto.track)
    var photos: [TrackPhoto]

    @Relationship(deleteRule: .cascade, inverse: \TrackSegment.track)
    var segments: [TrackSegment] = []

    @Relationship(deleteRule: .cascade, inverse: \TrackCorner.track)
    var corners: [TrackCorner] = []

    @Relationship(deleteRule: .cascade, inverse: \TrackIMUBatch.track)
    var imuBatches: [TrackIMUBatch] = []

    var pointCount: Int { points.count }

    init(
        id: UUID = UUID(),
        name: String,
        area: Area? = nil,
        startedAt: Int64,
        endedAt: Int64? = nil,
        isGlobalRecording: Bool = false,
        legacyAreaName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.area = area
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.isGlobalRecording = isGlobalRecording
        self.legacyAreaName = legacyAreaName
        points = []
        tags = []
        photos = []
    }
}
