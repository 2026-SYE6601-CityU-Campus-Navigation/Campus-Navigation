import Foundation
import SwiftData

@Model
final class Room {
    @Attribute(.unique) var id: UUID
    var name: String
    var note: String
    var latitude: Double?
    var longitude: Double?
    var altitude: Double?
    var pressureHpa: Double?
    var createdAt: Int64
    var area: Area?
    var code: String = ""
    var floor: String = ""
    // Original import code key survives later user edits to name/code.
    var catalogKey: String?

    @Relationship(deleteRule: .cascade, inverse: \Marker.room)
    var markers: [Marker]

    init(
        id: UUID = UUID(),
        name: String,
        note: String = "",
        area: Area? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        altitude: Double? = nil,
        pressureHpa: Double? = nil,
        createdAt: Int64
    ) {
        self.id = id
        self.name = name
        self.note = note
        self.area = area
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.pressureHpa = pressureHpa
        self.createdAt = createdAt
        markers = []
    }
}
