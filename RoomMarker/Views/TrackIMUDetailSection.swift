import SwiftUI

struct TrackIMUDetailSection: View {
    @Bindable var track: Track
    let coordinator: RecordingCoordinator
    @State private var storedSummary: RawIMUSavedSummary?
    @State private var readFailed = false

    var body: some View {
        Section("原始 IMU") {
            if coordinator.isActive(track), let imu = coordinator.rawIMU, track.rawIMURequested {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    summaryRows(imu.savedSummary)
                }
            } else if let storedSummary {
                summaryRows(storedSummary)
            } else if readFailed {
                Text("IMU 批次无法读取，请保留数据检查。").foregroundStyle(.red)
            } else {
                ProgressView("读取已保存 IMU…")
            }
        }
        .task(id: "\(track.id)-\(track.endedAt.map(String.init) ?? "open")-\(coordinator.isActive(track))") {
            guard !(coordinator.isActive(track) && track.rawIMURequested && coordinator.rawIMU != nil) else { return }
            do {
                storedSummary = try RawIMUSavedSummary.read(track)
                readFailed = false
            } catch { readFailed = true }
        }
    }

    @ViewBuilder
    private func summaryRows(_ summary: RawIMUSavedSummary) -> some View {
        if !track.rawIMURequested && summary.sampleCount == 0 {
            Text("未开启原始 IMU；不会从旧采样、节点或拐点补造。").foregroundStyle(.secondary)
        } else {
            LabeledContent("已保存加速度", value: "\(summary.accelerationCount) 条 · g（含重力）")
            LabeledContent("已保存角速度", value: "\(summary.gyroscopeCount) 条 · rad/s")
            LabeledContent("加速度状态", value: RawIMUChannelState(rawValue: track.rawAccelState)?.title ?? "未知")
            LabeledContent("角速度状态", value: RawIMUChannelState(rawValue: track.rawGyroState)?.title ?? "未知")
            LabeledContent("已拒绝无效/重复样本", value: "\(track.rawIMURejectedCount)")
            Text("原始设备坐标，不随界面旋转变轴；X 向右、Y 向设备顶部、Z 垂直屏幕向外。名义每路 50 Hz，不保证实际频率；后台和锁屏暂停，不补造缺口。")
                .font(.caption).foregroundStyle(.secondary)
            if track.endedAt == nil {
                Text("轨迹尚未完整结束，以上为已落库状态，不代表当前硬件仍在采集。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !summary.recentSamples.isEmpty {
                ForEach(Array(summary.recentSamples.enumerated()), id: \.offset) { _, sample in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(sample.kind.title) · \(sample.timeMs) ms UTC · \(sample.kind.unit)")
                        Text("X \(sample.x) / Y \(sample.y) / Z \(sample.z)")
                        Text("传感器时间 \(sample.sensorTimeSeconds) s（开机时基）")
                    }.font(.caption)
                }
            } else {
                Text("没有已保存的原始 IMU 读数；不会用零值代替。").foregroundStyle(.secondary)
            }
        }
    }
}
