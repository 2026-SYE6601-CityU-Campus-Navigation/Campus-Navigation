import SwiftUI

struct TrackTagCaptureView: View {
    @Environment(\.dismiss) private var dismiss

    let coordinator: RecordingCoordinator

    @State private var selectedType: TrackTagType = .toilet
    @State private var note = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("标签") {
                    Picker("类型", selection: $selectedType) {
                        ForEach(TrackTagType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    TextField("备注（可选）", text: $note, axis: .vertical)
                }

                Section {
                    Text("保存时会关联当前可用的位置、海拔和朝向；不可用的字段会保持为空。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("添加标签")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save)
                }
            }
            .alert("无法保存标签", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "未知错误")
            }
        }
    }

    private func save() {
        do {
            try coordinator.addTag(type: selectedType, note: note)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
