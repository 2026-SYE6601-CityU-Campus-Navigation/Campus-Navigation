import SwiftData
import SwiftUI

struct TrackTagLocationEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Area.createdAt) private var areas: [Area]
    @Query(sort: \Room.createdAt) private var rooms: [Room]
    let tag: TrackTag
    @State private var selectedAreaID: UUID?
    @State private var floor: String
    @State private var roomID: UUID?
    @State private var doorRole: String
    @State private var errorMessage: String?

    init(tag: TrackTag) {
        self.tag = tag
        _selectedAreaID = State(initialValue: tag.areaID)
        _floor = State(initialValue: tag.floor)
        _roomID = State(initialValue: tag.roomID)
        _doorRole = State(initialValue: tag.roomDoorRole ?? "前门")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("标签位置") {
                    Picker("区域", selection: $selectedAreaID) {
                        Text("未分区").tag(UUID?.none)
                        ForEach(areas, id: \.id) { area in
                            Text(area.name).tag(Optional(area.id))
                        }
                        if let id = selectedAreaID, !areas.contains(where: { $0.id == id }) {
                            Text("所选区域不可用（请重新选择）").tag(Optional(id))
                        }
                    }
                    TextField("楼层（可选）", text: $floor)
                    if tag.isNode {
                        NodeRoomPicker(rooms: rooms, areaID: selectedAreaID, type: tag.tagType ?? .otherIndoor,
                                       roomID: $roomID, doorRole: $doorRole)
                    }
                }
                Section {
                    Text("保存只更改区域、楼层和显式房间绑定，不重新采集传感器、不更改原始时间或照片。历史独立标签不会转换为节点。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("编辑标签位置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save)
                }
            }
            .persistenceErrorAlert($errorMessage)
        }
    }

    private func save() {
        do {
            if let selectedAreaID, !areas.contains(where: { $0.id == selectedAreaID }) {
                throw NodeCaptureError.areaUnavailable
            }
            try Phase2DataStore(context: modelContext).updateTagLocationAndRoom(
                tag,
                area: areas.first { $0.id == selectedAreaID },
                floor: floor, roomSelection: tag.isNode ? roomID.map {
                    NodeRoomSelection(roomID: $0, doorRole: tag.tagType == .classroom ? nil : doorRole)
                } : nil
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
