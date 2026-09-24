import Foundation

struct TrackCaptureMetadata: Equatable, Sendable {
    let latitude: Double?
    let longitude: Double?
    let altitude: Double?
    let headingDeg: Double?
}

struct TrackTagDraft: Equatable, Sendable {
    let timeMs: Int64
    let tagType: TrackTagType
    let note: String
    let metadata: TrackCaptureMetadata
    let createdAt: Int64
}

struct TrackPhotoDraft: Equatable, Sendable {
    let timeMs: Int64
    let filePath: String
    let note: String
    let metadata: TrackCaptureMetadata
    let createdAt: Int64
}

struct TrackCaptureMetadataAssembler: Sendable {
    private let sampleAssembler = SampleAssembler()

    func assemble(from state: LiveSensorState) -> TrackCaptureMetadata {
        let sample = sampleAssembler.assemble(timeMs: 0, state: state)
        return TrackCaptureMetadata(
            latitude: sample.latitude,
            longitude: sample.longitude,
            altitude: sample.altitude,
            headingDeg: sample.headingDeg
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
}
