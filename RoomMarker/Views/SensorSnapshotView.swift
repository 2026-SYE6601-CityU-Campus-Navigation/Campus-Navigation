import SwiftUI

struct SensorSnapshotView: View {
    @State private var hub: SensorHub
    @State private var snapshot: SensorSnapshot?
    @State private var captureTask: Task<Void, Never>?
    @State private var isCapturing = false
    @State private var errorMessage: String?

    init(hub: SensorHub = SensorHub()) {
        _hub = State(initialValue: hub)
    }

    var body: some View {
        List {
            Section {
                Button {
                    capture()
                } label: {
                    HStack {
                        Text(isCapturing ? "采集中…" : "采集一次快照")
                        Spacer()
                        if isCapturing {
                            ProgressView()
                        }
                    }
                }
                .disabled(isCapturing)

                Text("最多等待 4 秒。可用数据会组成部分快照；缺失、超时或不支持的值不会替换为 0，也不会自动写入房间或标记。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let snapshot {
                Section("快照") {
                    snapshotRow("纬度", value: snapshot.latitude, precision: 6, outcome: snapshot.outcomes.location)
                    snapshotRow("经度", value: snapshot.longitude, precision: 6, outcome: snapshot.outcomes.location)
                    snapshotRow("海拔", value: snapshot.altitude, precision: 1, unit: "m", outcome: snapshot.outcomes.location)
                    snapshotRow("水平精度", value: snapshot.accuracy, precision: 1, unit: "m", outcome: snapshot.outcomes.location)
                    snapshotRow("气压", value: snapshot.pressureHpa, precision: 2, unit: "hPa", outcome: snapshot.outcomes.pressure)
                    snapshotRow("磁场 X", value: snapshot.magneticX, precision: 2, unit: "µT", outcome: snapshot.outcomes.magnetometer)
                    snapshotRow("磁场 Y", value: snapshot.magneticY, precision: 2, unit: "µT", outcome: snapshot.outcomes.magnetometer)
                    snapshotRow("磁场 Z", value: snapshot.magneticZ, precision: 2, unit: "µT", outcome: snapshot.outcomes.magnetometer)
                    snapshotRow("磁北方位", value: snapshot.headingDeg, precision: 1, unit: "°", outcome: snapshot.outcomes.heading)
                }

                Section("采集状态") {
                    LabeledContent("位置", value: outcomeText(snapshot.outcomes.location))
                    LabeledContent("气压", value: outcomeText(snapshot.outcomes.pressure))
                    LabeledContent("磁力计", value: outcomeText(snapshot.outcomes.magnetometer))
                    LabeledContent("朝向", value: outcomeText(snapshot.outcomes.heading))
                }
            }
        }
        .navigationTitle("传感器快照")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            captureTask?.cancel()
            captureTask = nil
            hub.stop(consumer: .snapshot)
        }
        .alert("无法采集快照", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "未知错误")
        }
    }

    private func capture() {
        captureTask?.cancel()
        isCapturing = true
        errorMessage = nil
        captureTask = Task {
            defer { isCapturing = false }
            do {
                snapshot = try await SensorSnapshotService(hub: hub).capture()
            } catch is CancellationError {
                // Leaving the screen deliberately cancels capture and closes the sensor lease.
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    @ViewBuilder
    private func snapshotRow(
        _ label: String,
        value: Double?,
        precision: Int,
        unit: String = "",
        outcome: SensorCaptureOutcome
    ) -> some View {
        let rendered = value.map {
            $0.formatted(.number.precision(.fractionLength(precision))) + (unit.isEmpty ? "" : " " + unit)
        } ?? outcomeText(outcome)
        LabeledContent(label, value: rendered)
    }

    private func outcomeText(_ outcome: SensorCaptureOutcome) -> String {
        switch outcome {
        case .available: "可用"
        case .unsupported: "不支持"
        case .unavailable: "不可用"
        case .permissionDenied: "权限已拒绝"
        case .restricted: "受系统限制"
        case .stale: "数据已过期"
        case .timedOut: "等待超时"
        }
    }
}

#Preview {
    NavigationStack {
        SensorSnapshotView()
    }
}
