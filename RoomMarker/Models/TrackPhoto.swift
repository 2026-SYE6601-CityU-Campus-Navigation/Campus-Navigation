import Foundation
import SwiftData

@Model
final class TrackPhoto {
    @Attribute(.unique) var id: UUID
    var timeMs: Int64
    var filePath: String
    var note: String
    var latitude: Double?
    var longitude: Double?
    var altitude: Double?
    var headingDeg: Double?
    var createdAt: Int64
    var track: Track?

    init(
        id: UUID = UUID(),
        track: Track,
        timeMs: Int64,
        filePath: String,
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
        self.filePath = filePath
        self.note = note
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.headingDeg = headingDeg
        self.createdAt = createdAt
    }
}
