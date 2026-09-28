import Foundation
import SwiftData

@Model
final class Marker {
    @Attribute(.unique) var id: UUID
    var name: String
    var markerTypeRawValue: String
    var latitude: Double?
    var longitude: Double?
    var altitude: Double?
    var accuracy: Double?
    var pressureHpa: Double?
    var magneticX: Double?
    var magneticY: Double?
    var magneticZ: Double?
    var createdAt: Int64
    var room: Room?

    var markerType: MarkerType? {
        get { MarkerType(rawValue: markerTypeRawValue) }
        set { markerTypeRawValue = newValue?.rawValue ?? markerTypeRawValue }
    }

    init(
        id: UUID = UUID(),
        room: Room,
        name: String,
        markerType: MarkerType,
        latitude: Double? = nil,
        longitude: Double? = nil,
        altitude: Double? = nil,
        accuracy: Double? = nil,
        pressureHpa: Double? = nil,
        magneticX: Double? = nil,
        magneticY: Double? = nil,
        magneticZ: Double? = nil,
        createdAt: Int64
    ) {
        self.id = id
        self.room = room
        self.name = name
        markerTypeRawValue = markerType.rawValue
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.accuracy = accuracy
        self.pressureHpa = pressureHpa
        self.magneticX = magneticX
        self.magneticY = magneticY
        self.magneticZ = magneticZ
        self.createdAt = createdAt
    }
}
