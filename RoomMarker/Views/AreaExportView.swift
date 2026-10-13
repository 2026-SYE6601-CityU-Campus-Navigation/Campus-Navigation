import SwiftUI
import UIKit

struct AreaExportSection: View {
    @Bindable var coordinator: AreaExportCoordinator
    let areaName: String
    let startExport: () throws -> Void
    var isRecordingActive = false
    var exportTitle = "导出区域"
    var isSelectionEmpty = false

    @State private var isShowingShareSheet = false
    @State private var isShowingUploadSettings = false
    @State private var isUploading = false
    @State private var uploadMessage: String?
    @State private var startError: String?

    var body: some View {
        Section("导出") {
            VStack(alignment: .leading, spacing: 8) {
                Label(statusText, systemImage: statusIcon)
                    .foregroundStyle(statusColor)
                Text("将“\(areaName)”导出为包含清单、完整 JSON v3 轨迹、原照片和离线照片索引的 ZIP。请先停止录制并完成保存。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if case let .failed(failure) = coordinator.state {
                VStack(alignment: .leading, spacing: 4) {
                    Text(failure.title).font(.headline)
                    Text(failure.message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.red)
            }

            Button(action: exportOrShare) {
                Label(actionTitle, systemImage: actionIcon)
            }
            .disabled(coordinator.state.isBusy || isRecordingActive || isSelectionEmpty)
            if case let .readyToShare(result) = coordinator.state {
                Button {
                    upload(result.archiveURL)
                } label: {
                    Label(isUploading ? "正在上传…" : "上传 ZIP", systemImage: "icloud.and.arrow.up")
                }
                .disabled(isUploading)
                Button("上传设置", systemImage: "gearshape") { isShowingUploadSettings = true }
            }
            if let uploadMessage {
                Text(uploadMessage).font(.footnote)
                    .foregroundStyle(uploadMessage.hasPrefix("上传完成") ? .green : .red)
            }
            if coordinator.state.isBusy {
                Button("取消导出", role: .cancel) { coordinator.cancelAndReset() }
                Text("正在后台处理；大轨迹可能需要较长时间。请保持应用在前台，取消不会删除原数据。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $isShowingShareSheet, onDismiss: {
            coordinator.resetAfterSharing()
        }) {
            if case let .readyToShare(result) = coordinator.state {
                ActivityShareSheet(payload: ExportSharePayload(result: result))
            }
        }
        .sheet(isPresented: $isShowingUploadSettings) {
            NavigationStack { UploadSettingsView() }
        }
        .alert("无法开始导出", isPresented: Binding(
            get: { startError != nil },
            set: { if !$0 { startError = nil } }
        )) {
            Button("好", role: .cancel) { startError = nil }
        } message: {
            Text(startError ?? "请稍后重试。")
        }
        .onDisappear {
            coordinator.cleanUpWhenLeaving(isShareSheetPresented: isShowingShareSheet)
        }
    }

    private var statusText: String {
        switch coordinator.state {
        case .idle: "准备导出"
        case .preparingSnapshot: "正在准备快照…"
        case .staging: "正在验证和暂存…"
        case .archiving: "正在创建压缩包…"
        case .readyToShare: "压缩包已准备好"
        case .failed: "导出未完成"
        }
    }

    private var statusIcon: String {
        switch coordinator.state {
        case .idle: "square.and.arrow.up"
        case .preparingSnapshot, .staging, .archiving: "hourglass"
        case .readyToShare: "checkmark.circle"
        case .failed: "exclamationmark.triangle"
        }
    }

    private var statusColor: Color {
        switch coordinator.state {
        case .readyToShare: .green
        case .failed: .red
        default: .primary
        }
    }

    private var actionTitle: String {
        switch coordinator.state {
        case .readyToShare: "分享 ZIP"
        case .failed: "重试导出"
        default: exportTitle
        }
    }

    private var actionIcon: String {
        if case .readyToShare = coordinator.state { "square.and.arrow.up" } else { "archivebox" }
    }

    private func exportOrShare() {
        if case .readyToShare = coordinator.state {
            isShowingShareSheet = true
            return
        }
        do {
            try startExport()
        } catch {
            startError = error.localizedDescription
        }
    }

    private func upload(_ archive: URL) {
        let configuration = ZIPUploadSettings.load()
        do { _ = try ZIPUploadConfigurationValidator.validate(configuration) }
        catch {
            uploadMessage = error.localizedDescription
            isShowingUploadSettings = true
            return
        }
        isUploading = true
        uploadMessage = nil
        Task {
            do {
                let result = try await URLSessionZIPUploader().upload(archive: archive, configuration: configuration)
                await MainActor.run {
                    uploadMessage = result.responseBody.isEmpty ? "上传完成（HTTP \(result.statusCode)）" : "上传完成：\(result.responseBody)"
                    isUploading = false
                }
            } catch {
                await MainActor.run {
                    uploadMessage = "上传失败：\(error.localizedDescription)"
                    isUploading = false
                }
            }
        }
    }
}

struct ActivityShareSheet: UIViewControllerRepresentable {
    let payload: ExportSharePayload

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: payload.items,
            applicationActivities: nil
        )
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
