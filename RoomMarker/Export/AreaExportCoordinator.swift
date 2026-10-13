import Foundation
import Observation

enum AreaExportState: Equatable, Sendable {
    case idle
    case preparingSnapshot
    case staging
    case archiving
    case readyToShare(ZIPArchiveResult)
    case failed(ExportFailure)

    var isBusy: Bool {
        switch self {
        case .preparingSnapshot, .staging, .archiving:
            true
        case .idle, .readyToShare, .failed:
            false
        }
    }
}

struct ExportFailure: Equatable, Sendable {
    let title: String
    let message: String
}

enum ExportWorkflowError: LocalizedError, Equatable {
    case exportAlreadyInProgress

    var errorDescription: String? {
        switch self {
        case .exportAlreadyInProgress:
            "已有导出正在进行，请等待完成。"
        }
    }
}

struct ExportSharePayload: Equatable, Sendable {
    let items: [URL]

    init(result: ZIPArchiveResult) {
        items = [result.archiveURL]
    }
}

@Observable
@MainActor
final class AreaExportCoordinator {
    private(set) var state: AreaExportState = .idle
    private(set) var stateHistory: [AreaExportState] = [.idle]
    private(set) var lastStreamingMetrics: V3ExportMetrics?

    private let snapshotBuilder: AreaExportSnapshotBuilder
    private let v3Builder: ExportV3SnapshotBuilder
    private let stagingService: ExportStagingService
    private let archiveService: any ZIPArchiveCreating
    private let nowMilliseconds: () -> Int64
    private let makeSessionID: () -> UUID
    private let activeTrackID: () -> UUID?
    private let canStreamPhotos: Bool
    private var currentTask: Task<Void, Never>?
    private var currentStaging: ExportStagingResult?
    private var currentArchive: ZIPArchiveResult?
    private var generation = UUID()

    init(
        photoStorage: any PhotoFileStoring,
        stagingService: ExportStagingService = ExportStagingService(),
        archiveService: any ZIPArchiveCreating = StoredZIPArchiveService(),
        nowMilliseconds: @escaping () -> Int64 = {
            Int64(Date().timeIntervalSince1970 * 1_000)
        },
        makeSessionID: @escaping () -> UUID = UUID.init,
        activeTrackID: @escaping () -> UUID? = { nil }
    ) {
        snapshotBuilder = AreaExportSnapshotBuilder(photoStorage: photoStorage)
        v3Builder = ExportV3SnapshotBuilder(photoStorage: photoStorage)
        self.stagingService = stagingService
        self.archiveService = archiveService
        self.nowMilliseconds = nowMilliseconds
        self.makeSessionID = makeSessionID
        self.activeTrackID = activeTrackID
        canStreamPhotos = photoStorage is LocalPhotoFileStore
    }

    func start(area: Area, allTracks: [Track]? = nil) throws {
        try begin { [snapshotBuilder, nowMilliseconds] in
            .v2(try snapshotBuilder.build(area: area, exportedAt: nowMilliseconds(), allTracks: allTracks))
        }
    }

    func startUnassigned(tracks: [Track]) throws {
        try begin { [snapshotBuilder, nowMilliseconds] in
            .v2(try snapshotBuilder.buildUnassigned(
                tracks: tracks,
                exportedAt: nowMilliseconds()
            ))
        }
    }

    func startV3(area: Area, allTracks: [Track]? = nil, allAreas: [Area]? = nil) throws {
        try begin { [self] in
            let preparation = streamingPreparation()
            let value = try v3Builder.build(area: area, tracks: allTracks, areas: allAreas,
                exportedAt: nowMilliseconds(), activeTrackID: activeTrackID(), preparation: preparation)
            return preparation.map { .prepared($0.freeze(value)) } ?? .v3(value)
        }
    }

    func startAllV3(tracks: [Track], areas: [Area]? = nil, rooms: [Room]? = nil) throws {
        try startV3Selection(kind: "all", tracks: tracks, areas: areas, rooms: rooms)
    }

    func startUnassignedV3(tracks: [Track], areas: [Area]? = nil, rooms: [Room]? = nil) throws {
        try startV3Selection(kind: "unassigned", tracks: tracks, areas: areas, rooms: rooms)
    }

    func startSelectedV3(ids: Set<UUID>, tracks: [Track], areas: [Area]? = nil, rooms: [Room]? = nil) throws {
        try startV3Selection(kind: "selected", tracks: tracks, areas: areas, rooms: rooms, ids: ids)
    }

    private func startV3Selection(kind: String, tracks: [Track], areas: [Area]?, rooms: [Room]?, ids: Set<UUID>? = nil) throws {
        try begin { [self] in
            let preparation = streamingPreparation()
            let value = try v3Builder.build(kind: kind, tracks: tracks, areas: areas, rooms: rooms,
                exportedAt: nowMilliseconds(), activeTrackID: activeTrackID(), selectedIDs: ids, preparation: preparation)
            return preparation.map { .prepared($0.freeze(value)) } ?? .v3(value)
        }
    }

    private func streamingPreparation() -> V3ExportPreparation? {
        canStreamPhotos && stagingService.streamingBaseDirectory != nil && archiveService is StoredZIPArchiveService
            ? V3ExportPreparation() : nil
    }

    func waitForCurrentExport() async {
        await currentTask?.value
    }

    func resetAfterSharing() {
        removeCurrentArchive()
        transition(to: .idle)
    }

    func cancelAndReset() {
        generation = UUID()
        currentTask?.cancel()
        cleanCurrentStaging()
        removeCurrentArchive()
        currentTask = nil
        transition(to: .idle)
    }

    func cleanUpWhenLeaving(isShareSheetPresented: Bool) {
        guard !isShareSheetPresented else { return }
        cancelAndReset()
    }

    private enum Snapshot {
        case v2(AreaExportSnapshot)
        case v3(ExportV3Snapshot)
        case prepared(V3PreparedExport)
        var name: String {
            switch self {
            case let .v2(value): value.area.name
            case let .v3(value): value.manifest.scope.name
            case let .prepared(value): value.skeleton.manifest.scope.name
            }
        }
        var exportedAt: Int64 {
            switch self {
            case let .v2(value): value.exportedAt
            case let .v3(value): value.manifest.exportedAt
            case let .prepared(value): value.skeleton.manifest.exportedAt
            }
        }
    }

    private func begin(snapshot: @escaping @MainActor () throws -> Snapshot) throws {
        guard !state.isBusy else { throw ExportWorkflowError.exportAlreadyInProgress }
        cleanCurrentStaging()
        removeCurrentArchive()
        lastStreamingMetrics = nil
        transition(to: .preparingSnapshot)
        generation = UUID()
        let token = generation
        currentTask = Task { [weak self] in
            guard let self else { return }
            await self.run(snapshot: snapshot, token: token)
        }
    }

    private func run(snapshot: @escaping @MainActor () throws -> Snapshot, token: UUID) async {
        do {
            await Task.yield()
            guard generation == token else { return }
            try Task.checkCancellation()
            let immutableSnapshot = try snapshot()

            if case let .prepared(input) = immutableSnapshot {
                try await runStreaming(input, token: token)
                if generation == token { currentTask = nil }
                return
            }

            transition(to: .staging)
            await Task.yield()
            guard generation == token else { return }
            try Task.checkCancellation()
            let sessionID = makeSessionID()
            let staging: ExportStagingResult
            switch immutableSnapshot {
            case let .v2(value): staging = try stagingService.stage(value, sessionID: sessionID)
            case let .v3(value): staging = try stagingService.stage(value, sessionID: sessionID)
            case .prepared: preconditionFailure("handled above")
            }
            currentStaging = staging

            transition(to: .archiving)
            await Task.yield()
            guard generation == token else { return }
            try Task.checkCancellation()
            let archive = try archiveService.createArchive(
                from: staging,
                areaName: immutableSnapshot.name,
                exportedAt: immutableSnapshot.exportedAt,
                archiveID: sessionID
            )
            currentArchive = archive
            cleanCurrentStaging()
            transition(to: .readyToShare(archive))
        } catch is CancellationError {
            guard generation == token else { return }
            cleanCurrentStaging()
            removeCurrentArchive()
            transition(to: .idle)
        } catch {
            guard generation == token else { return }
            cleanCurrentStaging()
            removeCurrentArchive()
            transition(to: .failed(ExportErrorPresenter.failure(for: error)))
        }
        if generation == token { currentTask = nil }
    }

    private func runStreaming(_ input: V3PreparedExport, token: UUID) async throws {
        guard let base = stagingService.streamingBaseDirectory,
              let service = archiveService as? StoredZIPArchiveService else { throw ExportV3Error.invalid("worker configuration") }
        let config = service.backgroundConfiguration
        let sessionID = makeSessionID()
        transition(to: .staging)
        let worker = Task.detached(priority: .userInitiated) {
            try V3StreamingExporter.stage(input, base: base, sessionID: sessionID)
        }
        let staged = try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: { worker.cancel() }
        // Worker has finished writing. Cancellation/old generations clean only their own session.
        defer { try? stagingService.cleanUp(staged.staging) }
        try Task.checkCancellation()
        guard generation == token else { throw CancellationError() }
        lastStreamingMetrics = staged.metrics
        transition(to: .archiving)
        let zipper = Task.detached(priority: .userInitiated) {
            try config.service().createArchive(from: staged.staging, areaName: staged.name,
                exportedAt: staged.exportedAt, archiveID: sessionID)
        }
        let result = try await withTaskCancellationHandler {
            try await zipper.value
        } onCancel: { zipper.cancel() }
        guard !Task.isCancelled, generation == token else {
            try? archiveService.removeArchive(at: result.archiveURL)
            throw CancellationError()
        }
        currentArchive = result
        transition(to: .readyToShare(result))
    }

    private func transition(to newState: AreaExportState) {
        state = newState
        stateHistory.append(newState)
    }

    private func cleanCurrentStaging() {
        guard let currentStaging else { return }
        try? stagingService.cleanUp(currentStaging)
        self.currentStaging = nil
    }

    private func removeCurrentArchive() {
        guard let currentArchive else { return }
        try? archiveService.removeArchive(at: currentArchive.archiveURL)
        self.currentArchive = nil
    }
}

enum ExportErrorPresenter {
    static func failure(for error: Error) -> ExportFailure {
        switch error {
        case ExportValidationError.missingPhotoFile:
            ExportFailure(title: "照片文件缺失", message: "轨迹引用的照片已不存在，请检查照片后重试。")
        case ExportValidationError.invalidPhotoPath:
            ExportFailure(title: "照片路径无效", message: "导出已停止，以避免读取应用目录之外的文件。")
        case ExportValidationError.corruptPhoto:
            ExportFailure(title: "照片已损坏", message: "轨迹包含无法识别的照片，请检查后重试。")
        case ExportValidationError.unreadablePhoto:
            ExportFailure(title: "照片无法读取", message: "RoomMarker 无法读取轨迹照片，请稍后重试。")
        case is ZIPArchiveError:
            ExportFailure(title: "无法创建压缩包", message: error.localizedDescription)
        case let localized as LocalizedError:
            ExportFailure(title: "导出失败", message: localized.errorDescription ?? "请检查数据后重试。")
        default:
            ExportFailure(title: "导出失败", message: "导出未完成，请稍后重试。")
        }
    }
}
