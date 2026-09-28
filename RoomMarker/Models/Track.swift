import Foundation
import SwiftData

@Model
final class Track {
    @Attribute(.unique) var id: UUID
    var name: String
    var startedAt: Int64
    var endedAt: Int64?
    var area: Area?

    @Relationship(deleteRule: .cascade, inverse: \TrackPoint.track)
    var points: [TrackPoint]

    @Relationship(deleteRule: .cascade, inverse: \TrackTag.track)
    var tags: [TrackTag]

    @Relationship(deleteRule: .cascade, inverse: \TrackPhoto.track)
    var photos: [TrackPhoto]

    var pointCount: Int { points.count }

    init(
        id: UUID = UUID(),
        name: String,
        area: Area? = nil,
        startedAt: Int64,
        endedAt: Int64? = nil
    ) {
        self.id = id
        self.name = name
        self.area = area
        self.startedAt = startedAt
        self.endedAt = endedAt
        points = []
        tags = []
        photos = []
    }
}
