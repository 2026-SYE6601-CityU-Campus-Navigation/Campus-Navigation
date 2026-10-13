import SwiftData
import SwiftUI

struct AreaListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Area.createdAt) private var areas: [Area]
    @Query(sort: \Room.createdAt) private var rooms: [Room]
    @Query(sort: \Track.startedAt) private var tracks: [Track]

    @State private var editingArea: Area?
    @State private var isShowingAreaEditor = false
    @State private var areaPendingDeletion: Area?
    @State private var errorMessage: String?
    @State private var searchText = ""

    let sensorHub: SensorHub
    let recordingCoordinator: RecordingCoordinator
    let cameraService: any CameraServicing
    let photoStorage: any PhotoFileStoring
    let snapshotService: any SensorSnapshotCapturing

    private var unassignedRooms: [Room] {
        rooms.filter { $0.area == nil }
    }

    private var unassignedTracks: [Track] {
        TrackAreaIndex.unassigned(in: tracks)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { CatalogImportView() } label: {
                        Label("建筑／教室目录导入", systemImage: "building.2.crop.circle")
                    }
                }
                if let message = recordingCoordinator.mediaCleanupMessage {
                    Section("照片清理") {
                        Text(message).foregroundStyle(.orange)
                        Button("重试照片清理") {
                            retryPhotoCleanup()
                        }
                    }
                }
                if !unassignedRooms.isEmpty || !TrackAreaIndex.unassignedV2ExportCandidates(in: tracks).isEmpty {
                    Section {
                        NavigationLink {
                            UnassignedRoomsView(
                                coordinator: recordingCoordinator,
                                photoStorage: photoStorage,
                                snapshotService: snapshotService
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("未分区")
                                Text("房间 \(unassignedRooms.count) · 轨迹 \(unassignedTracks.count)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                if tracks.contains(where: { !$0.isGlobalRecording && $0.area == nil }) {
                                    Text("另可导出历史未分区轨迹（不计入当前标签归属）。")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    } footer: {
                        Text("轨迹按明确未分区的标签统计；无标签或历史区域未知不等于未分区。")
                    }
                }

                Section("区域") {
                    ForEach(areas.filter { searchText.isEmpty || ($0.name + $0.category + $0.note).localizedStandardContains(searchText) }, id: \.id) { area in
                        NavigationLink {
                            AreaDetailView(
                                area: area,
                                coordinator: recordingCoordinator,
                                photoStorage: photoStorage,
                                snapshotService: snapshotService
                            )
                        } label: {
                            areaRow(area)
                        }
                        .swipeActions(edge: .trailing) {
                            Button("删除", role: .destructive) {
                                areaPendingDeletion = area
                            }
                            Button("编辑") {
                                editingArea = area
                                isShowingAreaEditor = true
                            }
                            .tint(.blue)
                        }
                    }

                    if areas.isEmpty {
                        Phase2EmptyState(
                            "还没有区域",
                            systemImage: "building.2",
                            message: "创建第一个区域，用楼栋或楼层整理房间。",
                            actionTitle: "新建区域",
                            action: presentNewArea
                        )
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .navigationTitle("RoomMarker")
            .searchable(text: $searchText, prompt: "搜索建筑或分类")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        NavigationLink {
                            LiveSensorsView(hub: sensorHub)
                        } label: {
                            Label("实时传感器", systemImage: "waveform.path.ecg")
                        }
                        NavigationLink {
                            SensorSnapshotView(hub: sensorHub)
                        } label: {
                            Label("传感器快照", systemImage: "camera.metering.center.weighted")
                        }
                        NavigationLink {
                            PlaceRecognitionView(snapshotService: snapshotService)
                        } label: {
                            Label("我在哪", systemImage: "location.magnifyingglass")
                        }
                        NavigationLink {
                            UploadSettingsView()
                        } label: {
                            Label("上传设置", systemImage: "icloud.and.arrow.up")
                        }
                    } label: {
                        Label("传感器", systemImage: "sensor.tag.radiowaves.forward")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        TrackListView(coordinator: recordingCoordinator, photoStorage: photoStorage)
                    } label: {
                        Label("轨迹", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: presentNewArea) {
                        Label("新建区域", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $isShowingAreaEditor) {
                AreaEditorView(area: editingArea)
            }
            .confirmationDialog(
                "删除区域“\(areaPendingDeletion?.name ?? "")”？",
                isPresented: Binding(
                    get: { areaPendingDeletion != nil },
                    set: { if !$0 { areaPendingDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("删除区域并保留内容", role: .destructive) {
                    deletePendingArea()
                }
                Button("取消", role: .cancel) {
                    areaPendingDeletion = nil
                }
            } message: {
                Text("房间移到未分区；此区域的标签解除区域关联。完整轨迹、采样点、标签楼层和照片保留，其他区域标签不变。")
            }
            .persistenceErrorAlert($errorMessage)
        }
        .safeAreaInset(edge: .bottom) {
            if recordingCoordinator.state != .idle {
                RecordingStatusBanner(
                    coordinator: recordingCoordinator,
                    cameraService: cameraService
                )
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            let recordingPhase: RecordingLifecyclePhase = switch newPhase {
            case .active: .active
            case .inactive: .inactive
            case .background: .background
            @unknown default: .inactive
            }
            recordingCoordinator.handleLifecycleTransition(recordingPhase)
        }
    }

    @ViewBuilder
    private func areaRow(_ area: Area) -> some View {
        let count = TrackAreaIndex.tracks(in: area.id, from: tracks).count
        VStack(alignment: .leading, spacing: 4) {
            Text(area.name)
            if !area.category.isEmpty { Text(area.category).font(.caption).foregroundStyle(.secondary) }
            Text(area.note.isEmpty
                ? "房间 \(area.rooms.count) · 触及轨迹 \(count)"
                : "\(area.note) · 房间 \(area.rooms.count) · 触及轨迹 \(count)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
    }

    private func presentNewArea() {
        editingArea = nil
        isShowingAreaEditor = true
    }

    private func retryPhotoCleanup() {
        do {
            let photos = try modelContext.fetch(FetchDescriptor<TrackPhoto>())
            recordingCoordinator.retryPhotoCleanup(protecting: Set(photos.map(\.filePath)))
        } catch {
            errorMessage = "无法读取照片引用；未执行文件清理。"
        }
    }

    private func deletePendingArea() {
        guard let areaPendingDeletion else { return }
        do {
            try Phase2DataStore(context: modelContext).deleteAreaPreservingContents(areaPendingDeletion)
            self.areaPendingDeletion = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
