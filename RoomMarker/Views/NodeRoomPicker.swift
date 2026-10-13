import SwiftUI

struct NodeRoomPicker: View {
    let rooms: [Room]
    let areaID: UUID?
    let type: TrackTagType
    @Binding var roomID: UUID?
    @Binding var doorRole: String

    private var candidates: [Room] {
        rooms.filter { areaID != nil && $0.area?.id == areaID }.sorted {
            ($0.code, $0.name, $0.id.uuidString) < ($1.code, $1.name, $1.id.uuidString)
        }
    }

    var body: some View {
        if NodeRoomBinding.supports(type) || roomID != nil {
            Picker("绑定房间（可选）", selection: $roomID) {
                Text("不绑定房间").tag(UUID?.none)
                if NodeRoomBinding.supports(type) {
                    ForEach(candidates, id: \.id) { room in
                        Text("\(room.code) \(room.name) \(room.floor)").tag(Optional(room.id))
                    }
                }
                if let roomID, !NodeRoomBinding.supports(type) || !candidates.contains(where: { $0.id == roomID }) {
                    Text("原选择不适用，请重新选择或取消绑定").tag(Optional(roomID))
                }
            }
            if roomID != nil && [.door, .gate].contains(type) {
                Picker("房间门类型", selection: $doorRole) {
                    Text("前门").tag("前门")
                    Text("后门").tag("后门")
                }
            }
            Text("仅关联所选区域的现有房间。换区域或类型后须核对绑定；不自动新建、合并房间或房间标记。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
