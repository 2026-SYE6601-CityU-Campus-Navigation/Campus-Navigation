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

    private let snapshotBuilder: AreaExportSnapshotBuilder
    private let stagingService: ExportStagingService
    private let archiveService: any ZIPArchiveCreating
    private let nowMilliseconds: () -> Int64
    private let makeSessionID: () -> UUID
    private var currentTask: Task<Void, Never>?
    private var currentStaging: ExportStagingResult?
    private var currentArchive: ZIPArchiveResult?

    init(
        photoStorage: any PhotoFileStoring,
        stagingService: ExportStagingService = ExportStagingService(),
        archiveService: any ZIPArchiveCreating = StoredZIPArchiveService(),
        nowMilliseconds: @escaping () -> Int64 = {
            Int64(Date().timeIntervalSince1970 * 1_000)
        },
        makeSessionID: @escaping () -> UUID = UUID.init
    ) {
        snapshotBuilder = AreaExportSnapshotBuilder(photoStorage: photoStorage)
        self.stagingService = stagingService
        self.archiveService = archiveService
        self.nowMilliseconds = nowMilliseconds
        self.makeSessionID = makeSessionID
    }

    func start(area: Area) throws {
        try begin { [snapshotBuilder, nowMilliseconds] in
            try snapshotBuilder.build(area: area, exportedAt: nowMilliseconds())
        }
    }

    func startUnassigned(tracks: [Track]) throws {
        try begin { [snapshotBuilder, nowMilliseconds] in
            try snapshotBuilder.buildUnassigned(
                tracks: tracks,
                exportedAt: nowMilliseconds()
            )
        }
    }

    func waitForCurrentExport() async {
        await currentTask?.value
    }

    func resetAfterSharing() {
        removeCurrentArchive()
        transition(to: .idle)
    }

    func cancelAndReset() {
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

    private func begin(snapshot: @escaping @MainActor () throws -> AreaExportSnapshot) throws {
        guard !state.isBusy else { throw ExportWorkflowError.exportAlreadyInProgress }
        cleanCurrentStaging()
        removeCurrentArchive()
        transition(to: .preparingSnapshot)
        currentTask = Task { [weak self] in
            guard let self else { return }
            await self.run(snapshot: snapshot)
        }
    }

    private func run(snapshot: @escaping @MainActor () throws -> AreaExportSnapshot) async {
        do {
            await Task.yield()
            try Task.checkCancellation()
            let immutableSnapshot = try snapshot()

            transition(to: .staging)
            await Task.yield()
            try Task.checkCancellation()
            let sessionID = makeSessionID()
            let staging = try stagingService.stage(immutableSnapshot, sessionID: sessionID)
            currentStaging = staging

            transition(to: .archiving)
            await Task.yield()
            try Task.checkCancellation()
            let archive = try archiveService.createArchive(
                from: staging,
                areaName: immutableSnapshot.area.name,
                exportedAt: immutableSnapshot.exportedAt,
                archiveID: sessionID
            )
            currentArchive = archive
            cleanCurrentStaging()
            transition(to: .readyToShare(archive))
        } catch is CancellationError {
            cleanCurrentStaging()
            removeCurrentArchive()
            transition(to: .idle)
        } catch {
            cleanCurrentStaging()
            removeCurrentArchive()
            transition(to: .failed(ExportErrorPresenter.failure(for: error)))
        }
        currentTask = nil
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
