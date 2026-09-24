import SwiftData
import SwiftUI

struct MarkerEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private let room: Room
    private let marker: Marker?
    @State private var name: String
    @State private var markerType: MarkerType
    @State private var errorMessage: String?

    init(room: Room, marker: Marker? = nil) {
        self.room = room
        self.marker = marker
        _name = State(initialValue: marker?.name ?? "")
        _markerType = State(initialValue: marker?.markerType ?? .frontDoor)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("标记信息") {
                    TextField("标记名称", text: $name)
                        .textInputAutocapitalization(.never)
                        .accessibilityLabel("标记名称")
                    Picker("类型", selection: $markerType) {
                        ForEach(MarkerType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                }

                Section {
                    Label("本阶段仅手动保存名称与类型", systemImage: "hand.tap")
                } footer: {
                    Text("不会采集或填充定位、气压、地磁等传感器值。")
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
            .navigationTitle(marker == nil ? "新建标记" : "编辑标记")
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
            let store = Phase2DataStore(context: modelContext)
            if let marker {
                try store.updateMarker(marker, name: name, markerType: markerType)
            } else {
                try store.createMarker(room: room, name: name, markerType: markerType)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
