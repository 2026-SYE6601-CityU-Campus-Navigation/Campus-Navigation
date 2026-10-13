import Foundation

nonisolated enum RawIMUPolicy {
    static let interval: TimeInterval = 0.02
    static let batchSize = 100
}

nonisolated enum RawIMUKind: String, Codable, CaseIterable, Hashable, Sendable {
    case accelerometer
    case gyroscope
    var title: String { self == .accelerometer ? "加速度" : "角速度" }
    var unit: String { self == .accelerometer ? "g" : "rad/s" }
}

nonisolated enum RawIMUChannelState: String, Codable, Sendable {
    case notRequested, waiting, receiving, unsupported, denied, unavailable, paused, stopped
    var title: String {
        switch self {
        case .notRequested: "未开启"
        case .waiting: "等待读数"
        case .receiving: "接收中"
        case .unsupported: "硬件不支持"
        case .denied: "权限拒绝"
        case .unavailable: "暂不可用"
        case .paused: "后台已暂停"
        case .stopped: "已停止"
        }
    }
}

nonisolated struct RawIMUReading: Equatable, Sendable {
    let kind: RawIMUKind
    let sensorTimeSeconds: Double
    let x: Double
    let y: Double
    let z: Double
}

nonisolated struct RawIMUSample: Codable, Equatable, Sendable {
    let kind: RawIMUKind
    let sensorTimeSeconds: Double
    // A fixed session UTC/uptime anchor, not the delayed callback arrival time.
    let timeMs: Int64
    let receivedAtMs: Int64
    let segmentID: UUID
    let x: Double
    let y: Double
    let z: Double
    var isFinite: Bool {
        sensorTimeSeconds.isFinite && sensorTimeSeconds >= 0 && x.isFinite && y.isFinite && z.isFinite
    }
}

nonisolated struct RawIMUStatus: Equatable, Sendable {
    var accelerometer: RawIMUChannelState = .notRequested
    var gyroscope: RawIMUChannelState = .notRequested
    var rejectedCount = 0
    subscript(_ kind: RawIMUKind) -> RawIMUChannelState {
        get { kind == .accelerometer ? accelerometer : gyroscope }
        set { if kind == .accelerometer { accelerometer = newValue } else { gyroscope = newValue } }
    }
}

nonisolated enum RawIMUEvent: Sendable {
    case reading(RawIMUReading)
    case state(RawIMUKind, RawIMUChannelState)
}

nonisolated enum RawIMUError: LocalizedError, Equatable {
    case unavailable, invalidBatch, wrongSegment, pendingSave
    var errorDescription: String? {
        switch self {
        case .unavailable: "原始 IMU 服务不可用，未开始采集。"
        case .invalidBatch: "原始 IMU 数据批次无效，已保留待检查。"
        case .wrongSegment: "原始 IMU 与轨迹分段不一致，未保存。"
        case .pendingSave: "原始 IMU 尚有未保存数据，请先重试保存；不会静默丢弃。"
        }
    }
}

@MainActor
protocol RawIMUServicing: AnyObject {
    func start(interval: TimeInterval, handler: @escaping @MainActor @Sendable (RawIMUEvent) -> Void)
    func stop()
}

@MainActor
protocol RawIMUPersisting: AnyObject {
    // The caller reuses an ID on retry, including a save that committed before reporting failure.
    func saveIMU(id: UUID, samples: [RawIMUSample], status: RawIMUStatus, for track: Track) throws
}
