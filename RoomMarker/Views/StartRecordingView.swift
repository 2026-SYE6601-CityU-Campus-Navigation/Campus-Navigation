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
    @State private var environment: TrackEnvironment = .unknown
    @State private var collectRawIMU = false

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
                    Picker("初始环境", selection: $environment) {
                        ForEach(TrackEnvironment.allCases, id: \.self) { value in
                            Text(value.title).tag(value)
                        }
                    }
                    Text("室内外由您手动标注；未知不等于室内。记录中可切换环境，旧数据不自动推断。")
                        .font(.caption).foregroundStyle(.secondary)
                    Picker("首个标签默认区域", selection: $selectedAreaID) {
                        Text("未分区").tag(UUID?.none)
                        ForEach(areas, id: \.id) { area in
                            Text(area.name).tag(Optional(area.id))
                        }
                    }
                    Text("轨迹不属于单一区域，可连续跨楼记录。此选择只用于首个标签，之后可逐个修改区域和楼层。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Toggle("采集原始 IMU", isOn: $collectRawIMU)
                        .disabled(!coordinator.supportsRawIMU)
                    Text("可选采集原始加速度（含重力，g）及角速度（rad/s），每路请求 50 Hz；实际频率由系统决定。增加耗电与存储，仅前台采集，后台/锁屏暂停且不补点。")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("由您在前台开始后，后台定位会在 iOS 允许时继续。后台不保证精确每秒执行，可能出现真实时间间隔；停止轨迹会停止后台定位。持续定位会增加电量消耗。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("iOS 不扫描附近 Wi‑Fi，也不会补造延迟或暂停期间的历史采样点。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
            && coordinator.state == .idle
    }

    private func start() {
        do {
            try coordinator.start(name: name, area: selectedArea, environment: environment, collectRawIMU: collectRawIMU)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
