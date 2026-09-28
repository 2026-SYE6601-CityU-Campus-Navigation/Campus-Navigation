import SwiftData
import SwiftUI

struct MarkerEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private let room: Room
    private let marker: Marker?
    private let snapshotService: any SensorSnapshotCapturing
    @State private var name: String
    @State private var markerType: MarkerType
    @State private var errorMessage: String?
    @State private var saveTask: Task<Void, Never>?
    @State private var isSaving = false

    init(
        room: Room,
        marker: Marker? = nil,
        snapshotService: any SensorSnapshotCapturing
    ) {
        self.room = room
        self.marker = marker
        self.snapshotService = snapshotService
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
                    if marker == nil {
                        Label("保存时采集一次传感器快照", systemImage: "sensor.tag.radiowaves.forward")
                    } else {
                        Label("编辑只更新名称与类型", systemImage: "pencil")
                    }
                } footer: {
                    Text(marker == nil
                        ? "最多等待 4 秒；位置、精度、气压或地磁不可用时仍会创建标记，缺失字段保持为空。"
                        : "已有定位、精度、气压和地磁值会原样保留；修改名称不会自动重新采集。")
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
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(marker == nil ? "采集并保存" : "保存", action: save)
                        .disabled(isSaving)
                }
            }
            .overlay {
                if isSaving {
                    ProgressView("正在采集传感器快照…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .onDisappear {
                saveTask?.cancel()
                saveTask = nil
            }
        }
    }

    private func save() {
        errorMessage = nil
        let store = Phase2DataStore(context: modelContext)

        if let marker {
            do {
                try store.updateMarker(marker, name: name, markerType: markerType)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            return
        }

        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = Phase2ValidationError.emptyName.localizedDescription
            return
        }

        saveTask?.cancel()
        isSaving = true
        saveTask = Task {
            defer {
                isSaving = false
                saveTask = nil
            }
            do {
                try await RoomMarkerSnapshotWorkflow(
                    snapshotService: snapshotService
                ).captureAndCreateMarker(
                    in: room,
                    name: name,
                    markerType: markerType,
                    using: store
                )
                dismiss()
            } catch is CancellationError {
                // Cancelling the sheet deliberately cancels capture and releases the sensor lease.
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
