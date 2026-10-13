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
    var accuracy: Double?
    var pressureHpa: Double?
    var createdAt: Int64
    var track: Track?
    // Scalar ownership avoids a delete cascade from an Area into a cross-building track.
    var areaID: UUID?
    var areaStateRawValue: String = "unknown"
    var floor: String = ""
    // Migration never infers a node from an old independent tag.
    var recordKindRawValue: String = "legacy"
    // Non-owning historical link: deleting a room must not delete track evidence.
    var roomID: UUID?
    var roomNameSnapshot: String?
    var roomCodeSnapshot: String?
    var roomDoorRole: String?

    var isNode: Bool { recordKindRawValue == "node" }

    var tagType: TrackTagType? {
        get { TrackTagType(rawValue: tagTypeRawValue) }
        set { tagTypeRawValue = newValue?.rawValue ?? tagTypeRawValue }
    }

    init(
        id: UUID = UUID(),
        track: Track?,
        timeMs: Int64,
        tagType: TrackTagType,
        note: String = "",
        latitude: Double? = nil,
        longitude: Double? = nil,
        altitude: Double? = nil,
        headingDeg: Double? = nil,
        accuracy: Double? = nil,
        pressureHpa: Double? = nil,
        createdAt: Int64,
        areaID: UUID? = nil,
        areaStateRawValue: String = "unknown",
        floor: String = "",
        recordKindRawValue: String = "legacy"
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
        self.accuracy = accuracy
        self.pressureHpa = pressureHpa
        self.createdAt = createdAt
        self.areaID = areaID
        self.areaStateRawValue = areaStateRawValue
        self.floor = floor
        self.recordKindRawValue = recordKindRawValue
    }
}
