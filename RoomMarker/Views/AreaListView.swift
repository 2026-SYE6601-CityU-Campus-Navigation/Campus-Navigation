import SwiftData
import SwiftUI

struct AreaListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Area.createdAt) private var areas: [Area]
    @Query(sort: \Room.createdAt) private var rooms: [Room]
    @Query(sort: \Track.startedAt) private var tracks: [Track]

    @State private var editingArea: Area?
    @State private var isShowingAreaEditor = false
    @State private var areaPendingDeletion: Area?
    @State private var errorMessage: String?

    let sensorHub: SensorHub
    let recordingCoordinator: RecordingCoordinator
    let cameraService: any CameraServicing

    private var unassignedRooms: [Room] {
        rooms.filter { $0.area == nil }
    }

    private var unassignedTracks: [Track] {
        tracks.filter { $0.area == nil }
    }

    var body: some View {
        NavigationStack {
            List {
                if !unassignedRooms.isEmpty {
                    Section {
                        NavigationLink {
                            UnassignedRoomsView()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("未分区")
                                Text("房间 \(unassignedRooms.count) · 轨迹 \(unassignedTracks.count)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    } footer: {
                        Text("未分区代表区域关系为空，不是一个持久化区域。")
                    }
                }

                Section("区域") {
                    ForEach(areas, id: \.id) { area in
                        NavigationLink {
                            AreaDetailView(area: area)
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
                    } label: {
                        Label("传感器", systemImage: "sensor.tag.radiowaves.forward")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        TrackListView(coordinator: recordingCoordinator)
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
                Text("区域本身会被删除；其中的房间和轨迹会保留并移到“未分区”。")
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
    }

    @ViewBuilder
    private func areaRow(_ area: Area) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(area.name)
            Text(area.note.isEmpty
                ? "房间 \(area.rooms.count) · 轨迹 \(area.tracks.count)"
                : "\(area.note) · 房间 \(area.rooms.count) · 轨迹 \(area.tracks.count)")
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
