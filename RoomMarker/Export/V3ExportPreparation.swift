import Foundation

// Populated only on the model's actor. Never passed across actors as a class.
@MainActor
final class V3ExportPreparation {
    var imuPayloads: [String: Data] = [:]
    var photos: [String: V3PhotoSource] = [:]
    func freeze(_ skeleton: ExportV3Snapshot) -> V3PreparedExport {
        .init(skeleton: skeleton, imuPayloads: imuPayloads, photos: photos)
    }
}

nonisolated struct V3PhotoSource: Sendable {
    let root: URL
    let url: URL
}

nonisolated struct V3PreparedExport: Sendable {
    let skeleton: ExportV3Snapshot
    let imuPayloads: [String: Data]
    let photos: [String: V3PhotoSource]
}

nonisolated struct V3ExportMetrics: Equatable, Sendable {
    var maxDecodedIMUSamples = 0
    var copiedPhotoCount = 0
    var maxCopyChunkBytes = 0
    var encodedIMUSamples = 0
    var ranOnMainThread = false
}

nonisolated struct V3StagedExport: Sendable {
    let staging: ExportStagingResult
    let name: String
    let exportedAt: Int64
    let metrics: V3ExportMetrics
}

nonisolated struct V3ArchiveConfiguration: Sendable {
    let directory: URL
    let chunkSize: Int
    func service() -> StoredZIPArchiveService {
        .init(archiveDirectory: directory, writer: .init(chunkSize: chunkSize))
    }
}
