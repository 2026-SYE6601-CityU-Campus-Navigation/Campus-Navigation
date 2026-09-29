import SwiftUI
import UIKit

struct LiveSensorsView: View {
    @State private var hub: SensorHub

    init(hub: SensorHub = SensorHub()) {
        _hub = State(initialValue: hub)
    }

    var body: some View {
        List {
            permissionSection
            locationSection
            pressureSection
            magneticSection
            headingSection

            Section("平台说明") {
                Text("iOS 普通应用不支持附近 Wi‑Fi 扫描，因此本页不会显示或伪造 Wi‑Fi 指纹。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("实时传感器")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            hub.start(consumer: .liveSensors, requestLocationAuthorization: false)
        }
        .onDisappear {
            hub.stop(consumer: .liveSensors)
        }
    }

    @ViewBuilder
    private var permissionSection: some View {
        Section("定位权限") {
            LabeledContent("状态", value: permissionText)
            switch hub.state.permission {
            case .notDetermined:
                Button("允许使用期间定位") {
                    hub.requestLocationAuthorization()
                }
                Text("只有点击按钮后才会请求前台定位权限。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .denied:
                Text("定位权限已拒绝。其他可用传感器仍会继续工作。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Link("前往系统设置", destination: URL(string: UIApplication.openSettingsURLString)!)
            case .restricted:
                Text("系统限制了定位权限，应用无法自行更改。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            case .authorizedWhenInUse, .authorizedAlways:
                Text("仅在此页面可见时读取定位；离开页面即停止。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var locationSection: some View {
        Section("位置") {
            switch hub.state.location {
            case let .available(sample):
                locationRows(sample.value)
            case let .stale(sample):
                Label("数据已过期", systemImage: "clock.badge.exclamationmark")
                    .foregroundStyle(.secondary)
                locationRows(sample.value)
            default:
                SensorStateLabel(state: hub.state.location)
            }
        }
    }

    @ViewBuilder
    private var pressureSection: some View {
        Section("气压计") {
            switch hub.state.pressureHpa {
            case let .available(sample):
                LabeledContent("气压", value: sample.value.formatted(.number.precision(.fractionLength(2))) + " hPa")
            case let .stale(sample):
                Label("数据已过期", systemImage: "clock.badge.exclamationmark")
                    .foregroundStyle(.secondary)
                LabeledContent("上次气压", value: sample.value.formatted(.number.precision(.fractionLength(2))) + " hPa")
            default:
                SensorStateLabel(state: hub.state.pressureHpa)
            }
        }
    }

    @ViewBuilder
    private var magneticSection: some View {
        Section("磁力计") {
            switch hub.state.magneticField {
            case let .available(sample):
                magneticRows(sample.value)
            case let .stale(sample):
                Label("数据已过期", systemImage: "clock.badge.exclamationmark")
                    .foregroundStyle(.secondary)
                magneticRows(sample.value)
            default:
                SensorStateLabel(state: hub.state.magneticField)
            }
            Text("单位为 µT；X/Y/Z 使用 Apple 设备坐标系，不假定与 HarmonyOS 轴向一致。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var headingSection: some View {
        Section("设备朝向") {
            switch hub.state.headingDeg {
            case let .available(sample):
                LabeledContent("磁北方位", value: sample.value.formatted(.number.precision(.fractionLength(1))) + "°")
            case let .stale(sample):
                Label("数据已过期", systemImage: "clock.badge.exclamationmark")
                    .foregroundStyle(.secondary)
                LabeledContent("上次方位", value: sample.value.formatted(.number.precision(.fractionLength(1))) + "°")
            default:
                SensorStateLabel(state: hub.state.headingDeg)
            }
        }
    }

    private var permissionText: String {
        switch hub.state.permission {
        case .notDetermined: "尚未请求"
        case .denied: "已拒绝"
        case .restricted: "受系统限制"
        case .authorizedWhenInUse: "使用期间允许"
        case .authorizedAlways: "已允许"
        }
    }

    @ViewBuilder
    private func locationRows(_ reading: LocationReading) -> some View {
        LabeledContent("纬度", value: reading.latitude.formatted(.number.precision(.fractionLength(6))))
        LabeledContent("经度", value: reading.longitude.formatted(.number.precision(.fractionLength(6))))
        LabeledContent("海拔", value: optionalMeasurement(reading.altitude, precision: 1, unit: "m"))
        LabeledContent("水平精度", value: optionalMeasurement(reading.horizontalAccuracy, precision: 1, unit: "m"))
    }

    @ViewBuilder
    private func magneticRows(_ reading: MagneticFieldReading) -> some View {
        LabeledContent("X", value: reading.x.formatted(.number.precision(.fractionLength(2))) + " µT")
        LabeledContent("Y", value: reading.y.formatted(.number.precision(.fractionLength(2))) + " µT")
        LabeledContent("Z", value: reading.z.formatted(.number.precision(.fractionLength(2))) + " µT")
    }

    private func optionalMeasurement(_ value: Double?, precision: Int, unit: String) -> String {
        guard let value else { return "不可用" }
        return value.formatted(.number.precision(.fractionLength(precision))) + " " + unit
    }
}

private struct SensorStateLabel<Value: Sendable>: View {
    let text: String
    let systemImage: String

    init(state: SensorValueState<Value>) {
        switch state {
        case .waiting:
            text = "等待读数…"
            systemImage = "hourglass"
        case .unsupported:
            text = "当前设备或模拟器不支持"
            systemImage = "nosign"
        case .unavailable:
            text = "暂时不可用"
            systemImage = "exclamationmark.triangle"
        case .permissionDenied:
            text = "权限已拒绝"
            systemImage = "lock.slash"
        case .restricted:
            text = "受系统限制"
            systemImage = "hand.raised.slash"
        case .stale:
            text = "数据已过期"
            systemImage = "clock.badge.exclamationmark"
        case .available:
            text = "可用"
            systemImage = "checkmark.circle"
        }
    }

    var body: some View {
        Label(text, systemImage: systemImage)
            .foregroundStyle(.secondary)
    }
}

#Preview {
    NavigationStack {
        LiveSensorsView()
    }
}
