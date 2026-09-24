import SwiftUI

struct RecordingStatusBanner: View {
    let coordinator: RecordingCoordinator

    var body: some View {
        switch coordinator.state {
        case .idle:
            EmptyView()
        case .preparing:
            statusCard(title: "正在准备轨迹…", showsProgress: true)
        case .recording:
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Label("正在前台记录", systemImage: "record.circle.fill")
                            .font(.headline)
                            .foregroundStyle(.red)
                        Text(recordingSummary(at: context.date))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("停止", role: .destructive) {
                        Task { await stop() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
                .padding(12)
                .background(.regularMaterial)
            }
        case .stopping:
            statusCard(title: "正在保存并停止…", showsProgress: true)
        case let .failed(message, _):
            HStack(spacing: 12) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                Spacer()
                Button("关闭") {
                    Task { await coordinator.resetFailure() }
                }
            }
            .padding(12)
            .background(.regularMaterial)
        }
    }

    private func statusCard(title: String, showsProgress: Bool) -> some View {
        HStack(spacing: 10) {
            if showsProgress { ProgressView() }
            Text(title).font(.subheadline)
            Spacer()
        }
        .padding(12)
        .background(.regularMaterial)
    }

    private func recordingSummary(at date: Date) -> String {
        guard let track = coordinator.activeTrack else { return "" }
        let nowMs = Int64(date.timeIntervalSince1970 * 1_000)
        let elapsed = max(0, (nowMs - track.startedAt) / 1_000)
        return "\(track.name) · \(formatDuration(elapsed)) · \(coordinator.currentSampleCount) 个采样"
    }

    private func formatDuration(_ seconds: Int64) -> String {
        String(format: "%02lld:%02lld", seconds / 60, seconds % 60)
    }

    private func stop() async {
        do {
            try await coordinator.stop()
        } catch {
            // The coordinator publishes the failed state and its message.
        }
    }
}
