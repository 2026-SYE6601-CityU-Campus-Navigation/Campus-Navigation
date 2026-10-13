import SwiftData
import SwiftUI

struct AreaDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var area: Area
    @Query(sort: \Track.startedAt) private var allTracks: [Track]
    private let coordinator: RecordingCoordinator

    @State private var editingRoom: Room?
    @State private var isShowingRoomEditor = false
    @State private var isShowingAreaEditor = false
    @State private var roomPendingDeletion: Room?
    @State private var isConfirmingAreaDeletion = false
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var exportCoordinator: AreaExportCoordinator
    private let snapshotService: any SensorSnapshotCapturing
    private let photoStorage: any PhotoFileStoring

    init(
        area: Area,
        coordinator: RecordingCoordinator,
        photoStorage: any PhotoFileStoring,
        snapshotService: any SensorSnapshotCapturing
    ) {
        self.area = area
        self.coordinator = coordinator
        self.snapshotService = snapshotService
        self.photoStorage = photoStorage
        _exportCoordinator = State(initialValue: AreaExportCoordinator(photoStorage: photoStorage, activeTrackID: { coordinator.activeTrackID }))
    }

    private var sortedRooms: [Room] {
        area.rooms.filter { searchText.isEmpty || ($0.name + $0.code + $0.floor).localizedStandardContains(searchText) }
            .sorted { ($0.code, $0.name, $0.id.uuidString) < ($1.code, $1.name, $1.id.uuidString) }
    }

    var body: some View {
        List {
            if !area.note.isEmpty {
                Section("备注") {
                    Text(area.note)
                }
            }

            Section("房间（\(sortedRooms.count)）") {
                ForEach(sortedRooms, id: \.id) { room in
                    NavigationLink {
                        RoomDetailView(room: room, snapshotService: snapshotService)
                    } label: {
                        RoomSummaryRow(room: room)
                    }
                    .swipeActions(edge: .trailing) {
                        Button("删除", role: .destructive) {
                            roomPendingDeletion = room
                        }
                        Button("编辑") {
                            editingRoom = room
                            isShowingRoomEditor = true
                        }
                        .tint(.blue)
                    }
                }

                if sortedRooms.isEmpty {
                    Phase2EmptyState(
                        "还没有房间",
                        systemImage: "door.left.hand.closed",
                        message: "在这个区域中创建第一个房间。",
                        actionTitle: "新建房间",
                        action: presentNewRoom
                    )
                    .listRowBackground(Color.clear)
                }
            }

            Section("轨迹") {
                NavigationLink {
                    TrackListView(coordinator: coordinator, photoStorage: photoStorage, initialArea: area)
                } label: {
                    Label("\(TrackAreaIndex.tracks(in: area.id, from: allTracks).count) 条触及轨迹", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                }
                Text("至少一个标签明确属于此区域时，显示整条轨迹；跨楼轨迹可同时出现在多个区域。历史原归属不作标签归属。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            AreaExportSection(
                coordinator: exportCoordinator,
                areaName: area.name,
                startExport: { try exportCoordinator.startV3(area: area, allTracks: allTracks) },
                isRecordingActive: coordinator.activeTrackID != nil
            )
            Section {
                Text("JSON v3 导出所选区域涉及的完整轨迹，包括其他区域节点、照片、分段、拐点和原始 IMU，不按楼截断。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(area.name)
        .searchable(text: $searchText, prompt: "搜索教室代码、名称或楼层")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(action: presentNewRoom) {
                    Label("新建房间", systemImage: "plus")
                }
                Menu {
                    Button("编辑区域", systemImage: "pencil") {
                        isShowingAreaEditor = true
                    }
                    Button("删除区域", systemImage: "trash", role: .destructive) {
                        isConfirmingAreaDeletion = true
                    }
                } label: {
                    Label("更多", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $isShowingRoomEditor) {
            RoomEditorView(room: editingRoom, initialArea: area)
        }
        .sheet(isPresented: $isShowingAreaEditor) {
            AreaEditorView(area: area)
        }
        .confirmationDialog(
            "删除区域“\(area.name)”？",
            isPresented: $isConfirmingAreaDeletion,
            titleVisibility: .visible
        ) {
            Button("删除区域并保留内容", role: .destructive, action: deleteArea)
            Button("取消", role: .cancel) {}
        } message: {
            Text("\(area.rooms.count) 个房间移到未分区；此区域的标签解除区域关联。完整轨迹、采样点、标签楼层和照片保留，其他区域标签不变。")
        }
        .confirmationDialog(
            "删除房间“\(roomPendingDeletion?.name ?? "")”？",
            isPresented: Binding(
                get: { roomPendingDeletion != nil },
                set: { if !$0 { roomPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除房间及其标记", role: .destructive) {
                deletePendingRoom()
            }
            Button("取消", role: .cancel) {
                roomPendingDeletion = nil
            }
        } message: {
            Text("此操作会同时删除该房间的所有标记，且无法撤销。")
        }
        .persistenceErrorAlert($errorMessage)
    }

    private func presentNewRoom() {
        editingRoom = nil
        isShowingRoomEditor = true
    }

    private func deleteArea() {
        do {
            try Phase2DataStore(context: modelContext).deleteAreaPreservingContents(area)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deletePendingRoom() {
        guard let roomPendingDeletion else { return }
        do {
            try Phase2DataStore(context: modelContext).deleteRoom(roomPendingDeletion)
            self.roomPendingDeletion = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
