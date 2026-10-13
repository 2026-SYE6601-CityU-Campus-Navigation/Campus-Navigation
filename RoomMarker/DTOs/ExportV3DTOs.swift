import Foundation

// Separate contract: never silently downgrade structured recordings to v2.
nonisolated struct ExportV3Scope: Codable, Equatable, Sendable {
    let kind: String
    let areaId: String?
    let name: String
    var trackIds: [String]? = nil
}

nonisolated struct ExportV3Area: Codable, Equatable, Sendable {
    let id: String
    let name: String
    let note: String
    let createdAt: Int64
    var category: String? = nil
    var catalogKey: String? = nil
}

nonisolated struct ExportV3Room: Codable, Equatable, Sendable {
    let id: String
    let areaId: String?
    let name: String
    let code: String
    let floor: String
    let note: String
    let catalogKey: String?
    let createdAt: Int64
    let latitude: Double?
    let longitude: Double?
    let altitude: Double?
    let pressureHpa: Double?
}

nonisolated struct ExportV3RoomBinding: Codable, Equatable, Sendable {
    let roomId: String
    let nameSnapshot: String
    let codeSnapshot: String
    let doorRole: String?
    let status: String // linked / missing / relocated; resolved without source writes.
}

nonisolated struct ExportV3Counts: Codable, Equatable, Sendable {
    let pointCount: Int
    let tagCount: Int
    let nodeCount: Int
    let photoCount: Int
    let segmentCount: Int
    let cornerCount: Int
    let imuSampleCount: Int
}

nonisolated struct ExportV3ManifestTrack: Codable, Equatable, Sendable {
    let id: String
    let file: String
    let name: String
    let startedAt: Int64
    let endedAt: Int64?
    let counts: ExportV3Counts
}

nonisolated struct ExportV3Manifest: Codable, Equatable, Sendable {
    let version: Int
    let app: String
    let sourcePlatform: String
    let capabilities: ExportCapabilitiesDTO
    let exportedAt: Int64
    let scope: ExportV3Scope
    let areas: [ExportV3Area]
    let trackCount: Int
    let tracks: [ExportV3ManifestTrack]
    var rooms: [ExportV3Room]? = nil // Absent in earlier v3 archives.
    var photoIndex: String? = nil
}

// Same sensor names/units as v2, with stable identity and explicit membership.
nonisolated struct ExportV3SensorRecord: Codable, Equatable, Sendable {
    let id: String
    let timeMs: Int64
    let segmentId: String?
    let note: String?
    let latitude: Double?
    let longitude: Double?
    let altitude: Double?
    let accuracy: Double?
    let pressureHpa: Double?
    let magneticX: Double?
    let magneticY: Double?
    let magneticZ: Double?
    let headingDeg: Double?
}

nonisolated struct ExportV3Tag: Codable, Equatable, Sendable {
    let id: String
    let timeMs: Int64
    let tagType: String
    let note: String
    let latitude: Double?
    let longitude: Double?
    let altitude: Double?
    let headingDeg: Double?
    let createdAt: Int64
    let recordKind: String
    let areaId: String?
    let areaState: String
    let floor: String
    let photoId: String?
    var accuracy: Double? = nil
    var pressureHpa: Double? = nil
    var roomBinding: ExportV3RoomBinding? = nil
}

nonisolated struct ExportV3Photo: Codable, Equatable, Sendable {
    let id: String
    let timeMs: Int64
    let file: String
    let note: String
    let latitude: Double?
    let longitude: Double?
    let altitude: Double?
    let headingDeg: Double?
    let createdAt: Int64
    let kind: String
    let tagId: String?
    var byteCount: Int
    var sha256: String
    var accuracy: Double? = nil
    var pressureHpa: Double? = nil
}

nonisolated struct ExportV3Segment: Codable, Equatable, Sendable {
    let id: String
    let ordinal: Int
    let startedAt: Int64
    let endedAt: Int64?
    let environment: String
}

nonisolated struct ExportV3IMUSample: Codable, Equatable, Sendable {
    let kind: RawIMUKind
    let sensorTimeSeconds: Double
    let timeMs: Int64
    let receivedAtMs: Int64
    let segmentId: String
    let x: Double
    let y: Double
    let z: Double
}

nonisolated struct ExportV3IMUBatch: Codable, Equatable, Sendable {
    let id: String
    let sampleCount: Int
    let accelerationCount: Int
    let gyroscopeCount: Int
    let firstTimeMs: Int64
    let lastTimeMs: Int64
    let lastAccelerationTime: Double?
    let lastGyroscopeTime: Double?
    let samples: [ExportV3IMUSample]
}

nonisolated struct ExportV3IMU: Codable, Equatable, Sendable {
    let requested: Bool
    let requestedIntervalSeconds: Double?
    let accelerometerUnit: String
    let gyroscopeUnit: String
    let accelerometerIncludesGravity: Bool
    let coordinateFrame: String
    let sensorTimeBase: String
    let measurementTimeMapping: String
    let backgroundPolicy: String
    let accelerometerState: String
    let gyroscopeState: String
    let rejectedCount: Int
    let sampleCount: Int
    let accelerationCount: Int
    let gyroscopeCount: Int
    var batches: [ExportV3IMUBatch]
}

nonisolated struct ExportV3Track: Codable, Equatable, Sendable {
    let version: Int
    let sourcePlatform: String
    let capabilities: ExportCapabilitiesDTO
    let id: String
    let name: String
    let startedAt: Int64
    let endedAt: Int64?
    let isGlobalRecording: Bool
    let legacyAreaId: String?
    let legacyAreaName: String?
    let isSegmentedRecording: Bool
    let counts: ExportV3Counts
    let points: [ExportV3SensorRecord]
    let tags: [ExportV3Tag]
    var photos: [ExportV3Photo]
    let segments: [ExportV3Segment]
    let corners: [ExportV3SensorRecord]
    var imu: ExportV3IMU

    var file: String { "tracks/\(id).json" }
}

struct ExportV3PhotoFile: Equatable, Sendable {
    let path: String
    let data: Data
}

struct ExportV3Snapshot: Equatable, Sendable {
    let manifest: ExportV3Manifest
    let tracks: [ExportV3Track]
    let photos: [ExportV3PhotoFile]
}

nonisolated enum ExportV3Error: LocalizedError, Equatable {
    case invalid(String)
    case activeTrack
    var errorDescription: String? {
        switch self {
        case let .invalid(category): "v3 导出数据校验失败（\(category)）。原始数据未修改，请保留数据检查。"
        case .activeTrack: "请先停止正在录制的轨迹并完成保存，再导出完整数据。"
        }
    }
}
