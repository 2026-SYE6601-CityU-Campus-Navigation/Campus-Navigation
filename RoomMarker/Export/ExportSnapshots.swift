import Foundation

struct AreaExportSnapshot: Equatable, Sendable {
    let area: ExportAreaSnapshot
    let exportedAt: Int64
    let tracks: [TrackExportSnapshot]
}

struct ExportAreaSnapshot: Equatable, Sendable {
    let id: UUID?
    let name: String

    var isUnassigned: Bool { id == nil }
}

struct TrackExportSnapshot: Equatable, Sendable {
    let id: UUID
    let name: String
    let startedAt: Int64
    let endedAt: Int64?
    let points: [TrackPointExportSnapshot]
    let tags: [TrackTagExportSnapshot]
    let photos: [TrackPhotoExportSnapshot]

    var pointCount: Int { points.count }
    var fileName: String { "tracks/\(id.uuidString.lowercased()).json" }
}

struct TrackPointExportSnapshot: Equatable, Sendable {
    let id: UUID
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
}

struct TrackTagExportSnapshot: Equatable, Sendable {
    let id: UUID
    let timeMs: Int64
    let tagType: TrackTagType
    let note: String
    let latitude: Double?
    let longitude: Double?
    let altitude: Double?
    let headingDeg: Double?
    let createdAt: Int64
}

struct TrackPhotoExportSnapshot: Equatable, Sendable {
    let id: UUID
    let timeMs: Int64
    let relativePath: String
    let note: String
    let latitude: Double?
    let longitude: Double?
    let altitude: Double?
    let headingDeg: Double?
    let createdAt: Int64
    let jpegData: Data
}

enum ExportValidationError: LocalizedError, Equatable, Sendable {
    case trackOutsideArea(trackID: UUID)
    case invalidPhotoPath(trackID: UUID, photoID: UUID)
    case missingPhotoFile(trackID: UUID, photoID: UUID)
    case unreadablePhoto(trackID: UUID, photoID: UUID)
    case corruptPhoto(trackID: UUID, photoID: UUID)
    case nonFiniteSensorValue(trackID: UUID, recordID: UUID, field: String)
    case unsupportedTagValue(trackID: UUID, tagID: UUID, value: String)
    case unexpectedWiFiObservation(trackID: UUID, pointID: UUID)
    case pointCountMismatch(trackID: UUID, declared: Int, actual: Int)
    case unsafeStagingPath(String)
    case stagingSessionAlreadyExists
    case stagingFailure(String)

    var errorDescription: String? {
        switch self {
        case let .trackOutsideArea(trackID):
            "轨迹 \(trackID.uuidString) 不属于当前导出区域。"
        case let .invalidPhotoPath(trackID, photoID):
            "轨迹 \(trackID.uuidString) 的照片 \(photoID.uuidString) 路径无效。"
        case let .missingPhotoFile(trackID, photoID):
            "轨迹 \(trackID.uuidString) 的照片 \(photoID.uuidString) 文件缺失。"
        case let .unreadablePhoto(trackID, photoID):
            "轨迹 \(trackID.uuidString) 的照片 \(photoID.uuidString) 无法读取。"
        case let .corruptPhoto(trackID, photoID):
            "轨迹 \(trackID.uuidString) 的照片 \(photoID.uuidString) 不是有效图片。"
        case let .nonFiniteSensorValue(trackID, recordID, field):
            "轨迹 \(trackID.uuidString) 的记录 \(recordID.uuidString) 包含非有限值：\(field)。"
        case let .unsupportedTagValue(trackID, tagID, value):
            "轨迹 \(trackID.uuidString) 的标签 \(tagID.uuidString) 类型不受支持：\(value)。"
        case let .unexpectedWiFiObservation(trackID, pointID):
            "轨迹 \(trackID.uuidString) 的采样点 \(pointID.uuidString) 包含 iOS 未采集的 Wi-Fi 数据。"
        case let .pointCountMismatch(trackID, declared, actual):
            "轨迹 \(trackID.uuidString) 的 pointCount \(declared) 与采样点数量 \(actual) 不一致。"
        case let .unsafeStagingPath(path):
            "导出暂存路径不安全：\(path)。"
        case .stagingSessionAlreadyExists:
            "导出暂存会话已存在。"
        case let .stagingFailure(reason):
            "导出暂存失败：\(reason)"
        }
    }
}
