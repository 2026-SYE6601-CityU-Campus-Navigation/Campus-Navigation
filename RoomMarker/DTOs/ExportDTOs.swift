import Foundation

enum NearbyWiFiFingerprintCapability: String, Codable, Sendable {
    case collected
    case unsupported
}

struct ExportCapabilitiesDTO: Codable, Equatable, Sendable {
    let nearbyWifiFingerprint: NearbyWiFiFingerprintCapability
}

struct ExportedPointDTO: Codable, Equatable, Sendable {
    let timeMs: Int64
    let latitude: Double?
    let longitude: Double?
    let altitude: Double?
    let accuracy: Double?
    let pressureHpa: Double?
    let magneticX: Double?
    let magneticY: Double?
    let magneticZ: Double?
    let headingDeg: Double?
    let wifiCount: Int?
    let wifiTop: String?

    init(
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
        wifiCount: Int? = nil,
        wifiTop: String? = nil
    ) {
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
        self.wifiCount = wifiCount
        self.wifiTop = wifiTop
    }
}

struct ExportedTagDTO: Codable, Equatable, Sendable {
    let timeMs: Int64
    let tagType: String
    let note: String
    let latitude: Double?
    let longitude: Double?
    let altitude: Double?
    let headingDeg: Double?
}

struct ExportedPhotoDTO: Codable, Equatable, Sendable {
    let timeMs: Int64
    let file: String
    let note: String
    let latitude: Double?
    let longitude: Double?
    let altitude: Double?
    let headingDeg: Double?
    let fileMissing: Bool?
}

struct ExportedTrackDTO: Codable, Equatable, Sendable {
    let version: Int
    let sourcePlatform: String?
    let capabilities: ExportCapabilitiesDTO?
    let name: String
    let area: String
    let startedAt: Int64
    let endedAt: Int64?
    let pointCount: Int
    let points: [ExportedPointDTO]
    let tags: [ExportedTagDTO]
    let photos: [ExportedPhotoDTO]
}

struct ManifestAreaDTO: Codable, Equatable, Sendable {
    let id: Int64?
    let name: String
}

struct ManifestTrackDTO: Codable, Equatable, Sendable {
    let file: String
    let name: String
    let startedAt: Int64
    let pointCount: Int
}

struct ExportManifestDTO: Codable, Equatable, Sendable {
    let version: Int?
    let app: String
    let sourcePlatform: String?
    let capabilities: ExportCapabilitiesDTO?
    let exportedAt: Int64
    let area: ManifestAreaDTO
    let trackCount: Int
    let tracks: [ManifestTrackDTO]
}
