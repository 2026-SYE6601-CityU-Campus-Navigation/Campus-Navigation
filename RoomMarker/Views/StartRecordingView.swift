import SwiftData
import SwiftUI

struct StartRecordingView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Area.createdAt) private var areas: [Area]

    let coordinator: RecordingCoordinator
    let initialArea: Area?

    @State private var name = ""
    @State private var selectedAreaID: UUID?
    @State private var errorMessage: String?

    init(coordinator: RecordingCoordinator, initialArea: Area? = nil) {
        self.coordinator = coordinator
        self.initialArea = initialArea
        _selectedAreaID = State(initialValue: initialArea?.id)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("轨迹") {
                    TextField("轨迹名称", text: $name)
                    Picker("区域", selection: $selectedAreaID) {
                        Text("请选择").tag(UUID?.none)
                        ForEach(areas, id: \.id) { area in
                            Text(area.name).tag(Optional(area.id))
                        }
                    }
                }

                Section {
                    Text("前台运行时约每秒采集一次；每 5 个点保存一批。iOS 不扫描附近 Wi‑Fi，也不会补造延迟期间的历史点。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if areas.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "还没有区域",
                            systemImage: "building.2",
                            description: Text("请先回到首页创建区域，再开始记录。")
                        )
                    }
                }
            }
            .navigationTitle("开始记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("开始") { start() }
                        .disabled(!canStart)
                }
            }
            .onAppear {
                if selectedAreaID == nil {
                    selectedAreaID = areas.first?.id
                }
            }
            .alert("无法开始记录", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "未知错误")
            }
        }
    }

    private var selectedArea: Area? {
        guard let selectedAreaID else { return nil }
        return areas.first { $0.id == selectedAreaID }
    }

    private var canStart: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && selectedArea != nil
            && coordinator.state == .idle
    }

    private func start() {
        do {
            try coordinator.start(name: name, area: selectedArea)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
