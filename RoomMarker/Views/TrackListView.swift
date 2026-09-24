import SwiftData
import SwiftUI

struct TrackListView: View {
    @Query(sort: \Track.startedAt, order: .reverse) private var tracks: [Track]

    let coordinator: RecordingCoordinator
    let initialArea: Area?

    @State private var isShowingStart = false
    @State private var trackPendingDeletion: Track?
    @State private var errorMessage: String?

    init(coordinator: RecordingCoordinator, initialArea: Area? = nil) {
        self.coordinator = coordinator
        self.initialArea = initialArea
    }

    var body: some View {
        List {
            Section("轨迹") {
                ForEach(filteredTracks, id: \.id) { track in
                    NavigationLink {
                        TrackDetailView(track: track, coordinator: coordinator)
                    } label: {
                        trackRow(track)
                    }
                    .swipeActions {
                        Button("删除", role: .destructive) {
                            trackPendingDeletion = track
                        }
                        .disabled(coordinator.isActive(track))
                    }
                }

                if filteredTracks.isEmpty {
                    ContentUnavailableView(
                        "还没有轨迹",
                        systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                        description: Text("创建一个区域后，即可开始前台轨迹记录。")
                    )
                    .listRowBackground(Color.clear)
                }
            }
        }
        .navigationTitle(initialArea.map { "\($0.name)的轨迹" } ?? "轨迹")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingStart = true
                } label: {
                    Label("开始记录", systemImage: "record.circle")
                }
                .disabled(coordinator.state != .idle)
            }
        }
        .sheet(isPresented: $isShowingStart) {
            StartRecordingView(coordinator: coordinator, initialArea: initialArea)
        }
        .confirmationDialog(
            "删除轨迹“\(trackPendingDeletion?.name ?? "")”？",
            isPresented: Binding(
                get: { trackPendingDeletion != nil },
                set: { if !$0 { trackPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除轨迹及其数据", role: .destructive) {
                deletePendingTrack()
            }
            Button("取消", role: .cancel) { trackPendingDeletion = nil }
        } message: {
            Text("采样点、标签和照片元数据会级联删除。此操作无法撤销。")
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "未知错误")
        }
    }

    private var filteredTracks: [Track] {
        guard let initialArea else { return tracks }
        return tracks.filter { $0.area?.id == initialArea.id }
    }

    @ViewBuilder
    private func trackRow(_ track: Track) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(track.name)
                if coordinator.isActive(track) {
                    Text("记录中")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
            Text("\(track.area?.name ?? "未分区") · \(formatDate(track.startedAt))")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(statusText(track)) · \(track.pointCount) 个采样点")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func statusText(_ track: Track) -> String {
        if coordinator.isActive(track) { return "进行中" }
        guard let endedAt = track.endedAt else { return "未完整结束" }
        return "已结束 \(formatDate(endedAt))"
    }

    private func formatDate(_ milliseconds: Int64) -> String {
        Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
            .formatted(date: .abbreviated, time: .standard)
    }

    private func deletePendingTrack() {
        guard let trackPendingDeletion else { return }
        do {
            try coordinator.delete(trackPendingDeletion)
            self.trackPendingDeletion = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
