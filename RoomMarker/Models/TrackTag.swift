import Foundation
import SwiftData

@Model
final class TrackTag {
    @Attribute(.unique) var id: UUID
    var timeMs: Int64
    var tagTypeRawValue: String
    var note: String
    var latitude: Double?
    var longitude: Double?
    var altitude: Double?
    var headingDeg: Double?
    var createdAt: Int64
    var track: Track?

    var tagType: TrackTagType? {
        get { TrackTagType(rawValue: tagTypeRawValue) }
        set { tagTypeRawValue = newValue?.rawValue ?? tagTypeRawValue }
    }

    init(
        id: UUID = UUID(),
        track: Track,
        timeMs: Int64,
        tagType: TrackTagType,
        note: String = "",
        latitude: Double? = nil,
        longitude: Double? = nil,
        altitude: Double? = nil,
        headingDeg: Double? = nil,
        createdAt: Int64
    ) {
        self.id = id
        self.track = track
        self.timeMs = timeMs
        tagTypeRawValue = tagType.rawValue
        self.note = note
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.headingDeg = headingDeg
        self.createdAt = createdAt
    }
}
