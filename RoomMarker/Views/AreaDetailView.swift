import SwiftData
import SwiftUI

struct AreaDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var area: Area

    @State private var editingRoom: Room?
    @State private var isShowingRoomEditor = false
    @State private var isShowingAreaEditor = false
    @State private var roomPendingDeletion: Room?
    @State private var isConfirmingAreaDeletion = false
    @State private var errorMessage: String?

    private var sortedRooms: [Room] {
        area.rooms.sorted { $0.createdAt < $1.createdAt }
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
                        RoomDetailView(room: room)
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
                Label("\(area.tracks.count) 条轨迹", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                Text("轨迹记录将在后续阶段提供。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(area.name)
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
            Text("区域本身会被删除；其中的 \(area.rooms.count) 个房间和 \(area.tracks.count) 条轨迹会移到“未分区”。")
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
