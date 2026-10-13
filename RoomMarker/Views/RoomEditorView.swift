import SwiftData
import SwiftUI

struct RoomEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Area.createdAt) private var areas: [Area]

    private let room: Room?
    @State private var name: String
    @State private var note: String
    @State private var code: String
    @State private var floor: String
    @State private var selectedAreaID: UUID?
    @State private var errorMessage: String?

    init(room: Room? = nil, initialArea: Area? = nil) {
        self.room = room
        _name = State(initialValue: room?.name ?? "")
        _note = State(initialValue: room?.note ?? "")
        _code = State(initialValue: room?.code ?? "")
        _floor = State(initialValue: room?.floor ?? "")
        _selectedAreaID = State(initialValue: room?.area?.id ?? initialArea?.id)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("房间信息") {
                    TextField("教室代码（可选，如 LT-1）", text: $code).textInputAutocapitalization(.characters)
                    TextField("楼层（可选，如 4/F）", text: $floor)
                    TextField("房间名称", text: $name)
                        .textInputAutocapitalization(.never)
                        .accessibilityLabel("房间名称")
                    TextField("备注（可选）", text: $note, axis: .vertical)
                        .lineLimit(2 ... 5)
                }

                Section {
                    Picker("区域", selection: $selectedAreaID) {
                        Text("未分区").tag(UUID?.none)
                        ForEach(areas, id: \.id) { area in
                            Text(area.name).tag(Optional(area.id))
                        }
                        if let selectedAreaID, !areas.contains(where: { $0.id == selectedAreaID }) {
                            Text("原区域不可用，请重新选择").tag(Optional(selectedAreaID))
                        }
                    }
                } header: {
                    Text("所属区域")
                } footer: {
                    Text("选择“未分区”会保留房间，但不将它归入任何持久化区域。")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .accessibilityLabel("错误：\(errorMessage)")
                    }
                }
            }
            .navigationTitle(room == nil ? "新建房间" : "编辑房间")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save)
                }
            }
        }
    }

    private func save() {
        do {
            if let selectedAreaID, !areas.contains(where: { $0.id == selectedAreaID }) { throw NodeCaptureError.areaUnavailable }
            let selectedArea = areas.first { $0.id == selectedAreaID }
            let store = Phase2DataStore(context: modelContext)
            if let room {
                try store.updateRoom(room, name: name, note: note, area: selectedArea, code: code, floor: floor)
            } else {
                try store.createRoom(name: name, note: note, area: selectedArea, code: code, floor: floor)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
