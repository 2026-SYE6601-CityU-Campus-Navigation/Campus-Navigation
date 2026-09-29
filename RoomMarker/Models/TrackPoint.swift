import Foundation
import SwiftData

@Model
final class TrackPoint {
    @Attribute(.unique) var id: UUID
    var timeMs: Int64
    var latitude: Double?
    var longitude: Double?
    var altitude: Double?
    var accuracy: Double?
    var pressureHpa: Double?
    var magneticX: Double?
    var magneticY: Double?
    var magneticZ: Double?
    var headingDeg: Double?
    var wifiAvailabilityRawValue: String
    var wifiCount: Int?
    var wifiTop: String?
    var track: Track?

    var wifiAvailability: WiFiFingerprintAvailability {
        get { WiFiFingerprintAvailability(rawValue: wifiAvailabilityRawValue) ?? .unsupported }
        set { wifiAvailabilityRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        track: Track,
        timeMs: Int64,
        latitude: Double? = nil,
        longitude: Double? = nil,
        altitude: Double? = nil,
        accuracy: Double? = nil,
        pressureHpa: Double? = nil,
        magneticX: Double? = nil,
        magneticY: Double? = nil,
        magneticZ: Double? = nil,
        headingDeg: Double? = nil,
        wifiAvailability: WiFiFingerprintAvailability = .unsupported,
        wifiCount: Int? = nil,
        wifiTop: String? = nil
    ) {
        self.id = id
        self.track = track
        self.timeMs = timeMs
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.accuracy = accuracy
        self.pressureHpa = pressureHpa
        self.magneticX = magneticX
        self.magneticY = magneticY
        self.magneticZ = magneticZ
        self.headingDeg = headingDeg
        wifiAvailabilityRawValue = wifiAvailability.rawValue
        self.wifiCount = wifiCount
        self.wifiTop = wifiTop
    }
}
