import SwiftUI
import UIKit

struct PhotoNoteView: View {
    @Environment(\.dismiss) private var dismiss

    let jpegData: Data
    let onSave: (String) -> Void
    let onDiscard: () -> Void

    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("预览") {
                    if let image = UIImage(data: jpegData) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 320)
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("照片数据无法读取", systemImage: "photo.badge.exclamationmark")
                            .foregroundStyle(.secondary)
                    }
                }
                Section("备注") {
                    TextField("备注（可选）", text: $note, axis: .vertical)
                }
            }
            .navigationTitle("保存照片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("丢弃", role: .destructive) {
                        onDiscard()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存并关联") {
                        onSave(note)
                        dismiss()
                    }
                }
            }
            .interactiveDismissDisabled()
        }
    }
}
