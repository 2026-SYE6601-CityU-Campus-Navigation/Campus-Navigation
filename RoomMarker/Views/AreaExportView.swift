import SwiftUI
import UIKit

struct AreaExportSection: View {
    @Bindable var coordinator: AreaExportCoordinator
    let areaName: String
    let startExport: () throws -> Void

    @State private var isShowingShareSheet = false
    @State private var startError: String?

    var body: some View {
        Section("导出") {
            VStack(alignment: .leading, spacing: 8) {
                Label(statusText, systemImage: statusIcon)
                    .foregroundStyle(statusColor)
                Text("将“\(areaName)”导出为包含清单、轨迹 JSON 和照片的 ZIP。")
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
            .disabled(coordinator.state.isBusy)
        }
        .onChange(of: coordinator.state) { _, newState in
            if case .readyToShare = newState {
                isShowingShareSheet = true
            }
        }
        .sheet(isPresented: $isShowingShareSheet, onDismiss: {
            coordinator.resetAfterSharing()
        }) {
            if case let .readyToShare(result) = coordinator.state {
                ActivityShareSheet(payload: ExportSharePayload(result: result))
            }
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
        default: "导出区域"
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
