import SwiftData
import SwiftUI

struct UnassignedRoomsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Room.createdAt) private var allRooms: [Room]
    @Query(sort: \Track.startedAt) private var allTracks: [Track]

    @State private var editingRoom: Room?
    @State private var isShowingRoomEditor = false
    @State private var roomPendingDeletion: Room?
    @State private var errorMessage: String?
    @State private var exportCoordinator: AreaExportCoordinator
    private let snapshotService: any SensorSnapshotCapturing
    private let coordinator: RecordingCoordinator
    private let photoStorage: any PhotoFileStoring

    init(
        coordinator: RecordingCoordinator,
        photoStorage: any PhotoFileStoring,
        snapshotService: any SensorSnapshotCapturing
    ) {
        self.coordinator = coordinator
        self.snapshotService = snapshotService
        self.photoStorage = photoStorage
        _exportCoordinator = State(initialValue: AreaExportCoordinator(photoStorage: photoStorage, activeTrackID: { coordinator.activeTrackID }))
    }

    private var rooms: [Room] {
        allRooms.filter { $0.area == nil }
    }

    private var unassignedTrackCount: Int {
        TrackAreaIndex.unassigned(in: allTracks).count
    }

    var body: some View {
        List {
            Section {
                ForEach(rooms, id: \.id) { room in
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

                if rooms.isEmpty {
                    Phase2EmptyState(
                        "没有未分区房间",
                        systemImage: "tray",
                        message: "可在此创建房间，或把现有房间移动到未分区。",
                        actionTitle: "新建房间",
                        action: presentNewRoom
                    )
                    .listRowBackground(Color.clear)
                }
            } header: {
                Text("房间（\(rooms.count)）")
            } footer: {
                Text("另有 \(unassignedTrackCount) 条包含明确未分区标签的轨迹。无标签和历史未知区域轨迹请查看全部轨迹。")
            }

            NavigationLink("查看未分区标签轨迹（\(unassignedTrackCount)）") {
                TrackListView(coordinator: coordinator, photoStorage: photoStorage, showUnassignedOnly: true)
            }

            AreaExportSection(
                coordinator: exportCoordinator,
                areaName: "未分区",
                startExport: {
                    try exportCoordinator.startUnassignedV3(tracks: allTracks, rooms: allRooms)
                },
                isRecordingActive: coordinator.activeTrackID != nil
            )
            Text("JSON v3 同时保留历史未分区轨迹和明确未分区标签涉及的完整轨迹。无标签或区域未知的新轨迹请从全部轨迹导出。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .navigationTitle("未分区")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: presentNewRoom) {
                    Label("新建房间", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isShowingRoomEditor) {
            RoomEditorView(room: editingRoom)
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
