import SwiftData
import SwiftUI

struct AreaEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private let area: Area?
    @State private var name: String
    @State private var note: String
    @State private var errorMessage: String?

    init(area: Area? = nil) {
        self.area = area
        _name = State(initialValue: area?.name ?? "")
        _note = State(initialValue: area?.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("区域信息") {
                    TextField("区域名称", text: $name)
                        .textInputAutocapitalization(.never)
                        .accessibilityLabel("区域名称")
                    TextField("备注（可选）", text: $note, axis: .vertical)
                        .lineLimit(2 ... 5)
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
            .navigationTitle(area == nil ? "新建区域" : "编辑区域")
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
            if let area {
                try store.updateArea(area, name: name, note: note)
            } else {
                try store.createArea(name: name, note: note)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
