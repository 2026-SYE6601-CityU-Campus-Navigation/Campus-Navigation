import Foundation

enum TrackTagAreaState: String, Equatable, Sendable {
    case assigned
    case unassigned
    case unknown
}

struct TagLocationContext: Equatable, Sendable {
    let areaID: UUID?
    let areaStateRawValue: String
    let floor: String

    init(areaID: UUID?, areaStateRawValue: String, floor: String) {
        self.areaID = areaID
        self.areaStateRawValue = areaStateRawValue
        self.floor = floor
    }

    @MainActor
    init(area: Area?, floor: String = "") {
        areaID = area?.id
        areaStateRawValue = area == nil
            ? TrackTagAreaState.unassigned.rawValue
            : TrackTagAreaState.assigned.rawValue
        self.floor = floor.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct TrackCaptureMetadata: Equatable, Sendable {
    let latitude: Double?
    let longitude: Double?
    let altitude: Double?
    let headingDeg: Double?
    let accuracy: Double?
    let pressureHpa: Double?

    init(latitude: Double?, longitude: Double?, altitude: Double?, headingDeg: Double?,
         accuracy: Double? = nil, pressureHpa: Double? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.headingDeg = headingDeg
        self.accuracy = accuracy
        self.pressureHpa = pressureHpa
    }

    var hasValidQuality: Bool {
        (accuracy.map { $0.isFinite && $0 >= 0 } ?? true) &&
            (pressureHpa.map { $0.isFinite && $0 > 0 } ?? true)
    }
}

struct TrackTagDraft: Equatable, Sendable {
    let timeMs: Int64
    let tagType: TrackTagType
    let note: String
    let metadata: TrackCaptureMetadata
    let createdAt: Int64
    let areaID: UUID?
    let areaStateRawValue: String
    let floor: String
    let roomSelection: NodeRoomSelection?

    init(
        timeMs: Int64,
        tagType: TrackTagType,
        note: String,
        metadata: TrackCaptureMetadata,
        createdAt: Int64,
        areaID: UUID? = nil,
        areaStateRawValue: String = TrackTagAreaState.unknown.rawValue,
        floor: String = "",
        roomSelection: NodeRoomSelection? = nil
    ) {
        self.timeMs = timeMs
        self.tagType = tagType
        self.note = note
        self.metadata = metadata
        self.createdAt = createdAt
        self.areaID = areaID
        self.areaStateRawValue = areaStateRawValue
        self.floor = floor
        self.roomSelection = roomSelection
    }
}

struct TrackPhotoDraft: Equatable, Sendable {
    let timeMs: Int64
    let filePath: String
    let note: String
    let metadata: TrackCaptureMetadata
    let createdAt: Int64
    var kindRawValue: String = "scenery"
    var tagID: UUID? = nil
}

struct TrackCaptureMetadataAssembler: Sendable {
    private let sampleAssembler = SampleAssembler()

    func assemble(from state: LiveSensorState) -> TrackCaptureMetadata {
        let sample = sampleAssembler.assemble(timeMs: 0, state: state)
        return TrackCaptureMetadata(
            latitude: sample.latitude,
            longitude: sample.longitude,
            altitude: sample.altitude,
            headingDeg: sample.headingDeg,
            accuracy: sample.accuracy,
            pressureHpa: sample.pressureHpa.flatMap { $0 > 0 ? $0 : nil }
        )
    }
}

enum CameraCaptureOutcome: Equatable, Sendable {
    case success(jpegData: Data, capturedAt: Int64)
    case cancelled
    case unavailable
    case failed(String)
}

enum TrackMediaError: LocalizedError, Equatable {
    case noActiveTrack
    case servicesUnavailable
    case emptyImageData
    case captureFailed(String)

    var errorDescription: String? {
        switch self {
        case .noActiveTrack:
            "当前没有进行中的轨迹。"
        case .servicesUnavailable:
            "照片或标签服务尚未准备好。"
        case .emptyImageData:
            "相机没有返回可保存的照片数据。"
        case let .captureFailed(message):
            "拍照失败：\(message)"
        }
    }
}

@MainActor
protocol TrackMediaPersisting: AnyObject {
    func createTag(_ draft: TrackTagDraft, for track: Track) throws -> TrackTag
    func createPhoto(_ draft: TrackPhotoDraft, for track: Track) throws -> TrackPhoto
    func deleteTag(_ tag: TrackTag) throws
    func deletePhoto(_ photo: TrackPhoto) throws
}

@MainActor
protocol PhotoFileStoring: AnyObject {
    func storeJPEG(_ data: Data, trackID: UUID, timeMs: Int64) throws -> String
    func validate(relativePath: String) throws
    func read(relativePath: String) throws -> Data
    func delete(relativePath: String) throws
    func deleteTrackDirectory(trackID: UUID) throws
    func retryPendingCleanup(protecting referencedPaths: Set<String>) throws
    func confirmReferenced(relativePath: String) throws
    func prepareDeletion(relativePath: String) throws
}

extension PhotoFileStoring {
    func retryPendingCleanup(protecting referencedPaths: Set<String>) throws {}
    func confirmReferenced(relativePath: String) throws {}
    func prepareDeletion(relativePath: String) throws { try validate(relativePath: relativePath) }
}
