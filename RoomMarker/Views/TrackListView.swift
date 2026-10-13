import SwiftData
import SwiftUI

struct TrackListView: View {
    @Query(sort: \Track.startedAt, order: .reverse) private var tracks: [Track]
    @Query private var areas: [Area]
    @Query private var rooms: [Room]

    let coordinator: RecordingCoordinator
    let initialArea: Area?
    let showUnassignedOnly: Bool
    private let photoStorage: any PhotoFileStoring

    @State private var isShowingStart = false
    @State private var trackPendingDeletion: Track?
    @State private var errorMessage: String?
    @State private var exportCoordinator: AreaExportCoordinator

    init(coordinator: RecordingCoordinator, photoStorage: any PhotoFileStoring, initialArea: Area? = nil, showUnassignedOnly: Bool = false) {
        self.coordinator = coordinator
        self.initialArea = initialArea
        self.showUnassignedOnly = showUnassignedOnly
        self.photoStorage = photoStorage
        _exportCoordinator = State(initialValue: AreaExportCoordinator(photoStorage: photoStorage, activeTrackID: { coordinator.activeTrackID }))
    }

    var body: some View {
        List {
            interruptedSection

            Section {
                NavigationLink {
                    TrackSelectionExportView(recording: coordinator, photoStorage: photoStorage)
                } label: {
                    Label("选择轨迹导出", systemImage: "checklist")
                }
                .disabled(exportCoordinator.state.isBusy)
            }

            if initialArea == nil && !showUnassignedOnly {
                AreaExportSection(coordinator: exportCoordinator, areaName: "全部轨迹", startExport: {
                    try exportCoordinator.startAllV3(tracks: tracks, areas: areas, rooms: rooms)
                }, isRecordingActive: coordinator.activeTrackID != nil, exportTitle: "导出全部轨迹")
            }

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
                        description: Text("可直接开始记录；区域列表按标签归属显示完整轨迹。无标签和历史未知区域轨迹请在全部轨迹中查看。")
                    )
                    .listRowBackground(Color.clear)
                }
            }
        }
        .navigationTitle(initialArea.map { "\($0.name)的轨迹" } ?? (showUnassignedOnly ? "未分区标签轨迹" : "全部轨迹"))
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
            Text("采样点、标签、照片元数据和 RoomMarker 拥有的照片文件都会删除。此操作无法撤销。")
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
        if showUnassignedOnly { return TrackAreaIndex.unassigned(in: tracks) }
        guard let initialArea else { return tracks }
        return TrackAreaIndex.tracks(in: initialArea.id, from: tracks)
    }

    private var interruptedTracks: [Track] {
        IncompleteTrackRecovery.detected(
            in: filteredTracks,
            activeTrackID: coordinator.activeTrackID
        )
    }

    @ViewBuilder
    private var interruptedSection: some View {
        if !interruptedTracks.isEmpty {
            Section {
                ForEach(interruptedTracks, id: \.id) { track in
                    interruptedTrackLink(track)
                }
            } header: {
                Text("需要处理")
            } footer: {
                Text("应用不会自动恢复或伪造结束时间。请打开轨迹检查后手动结束或删除。")
            }
        }
    }

    private func interruptedTrackLink(_ track: Track) -> some View {
        NavigationLink {
            TrackDetailView(track: track, coordinator: coordinator)
        } label: {
            Label {
                Text(track.name)
            } icon: {
                Image(systemName: "exclamationmark.triangle")
            }
        }
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
            Text("\(track.isGlobalRecording ? "全局轨迹" : "历史轨迹") · \(formatDate(track.startedAt))")
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
