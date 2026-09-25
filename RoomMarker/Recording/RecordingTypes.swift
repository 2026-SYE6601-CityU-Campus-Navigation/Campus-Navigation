import Foundation

enum RecordingPhase: String, Equatable, Sendable {
    case idle
    case preparing
    case recording
    case stopping
    case failed
}

enum RecordingState: Equatable, Sendable {
    case idle
    case preparing
    case recording(trackID: UUID)
    case stopping(trackID: UUID)
    case failed(message: String, trackID: UUID?)

    var phase: RecordingPhase {
        switch self {
        case .idle: .idle
        case .preparing: .preparing
        case .recording: .recording
        case .stopping: .stopping
        case .failed: .failed
        }
    }
}

enum RecordingError: LocalizedError, Equatable {
    case emptyName
    case areaRequired
    case alreadyActive
    case notRecording
    case activeTrackCannotBeDeleted
    case finalizedTrack
    case trackIsNotIncomplete

    var errorDescription: String? {
        switch self {
        case .emptyName:
            "轨迹名称不能为空。"
        case .areaRequired:
            "开始记录前必须选择一个区域。"
        case .alreadyActive:
            "已有轨迹正在准备、记录或停止。"
        case .notRecording:
            "当前没有可停止的轨迹。"
        case .activeTrackCannotBeDeleted:
            "正在记录的轨迹不能删除；请先停止记录。"
        case .finalizedTrack:
            "已结束的轨迹不能再追加采样点。"
        case .trackIsNotIncomplete:
            "只有未完整结束且当前未在记录的轨迹可以手动结束。"
        }
    }
}

struct TrackPointDraft: Equatable, Sendable {
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
    let wifiAvailability: WiFiFingerprintAvailability
    let wifiCount: Int?
    let wifiTop: String?
}
