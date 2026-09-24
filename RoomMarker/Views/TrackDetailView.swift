import SwiftUI

struct TrackDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var track: Track
    let coordinator: RecordingCoordinator

    @State private var isConfirmingDeletion = false
    @State private var errorMessage: String?

    private var points: [TrackPoint] {
        track.points.sorted { $0.timeMs < $1.timeMs }
    }

    var body: some View {
        List {
            Section("概览") {
                LabeledContent("区域", value: track.area?.name ?? "未分区")
                LabeledContent("状态", value: statusText)
                LabeledContent("开始", value: formatDate(track.startedAt))
                LabeledContent("结束", value: track.endedAt.map(formatDate) ?? "未完整结束")
                LabeledContent("采样点", value: "\(track.pointCount)")
            }

            Section("采样点") {
                ForEach(points, id: \.id) { point in
                    pointRow(point)
                }
                if points.isEmpty {
                    Text("还没有已保存的采样点。")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(track.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("删除", systemImage: "trash", role: .destructive) {
                    isConfirmingDeletion = true
                }
                .disabled(coordinator.isActive(track))
            }
        }
        .confirmationDialog(
            "删除轨迹“\(track.name)”？",
            isPresented: $isConfirmingDeletion,
            titleVisibility: .visible
        ) {
            Button("删除轨迹及其数据", role: .destructive, action: deleteTrack)
            Button("取消", role: .cancel) {}
        } message: {
            Text("该轨迹的采样点、标签和照片元数据会级联删除。")
        }
        .alert("无法删除轨迹", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "未知错误")
        }
    }

    @ViewBuilder
    private func pointRow(_ point: TrackPoint) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(formatDate(point.timeMs)).font(.subheadline)
            if let latitude = point.latitude, let longitude = point.longitude {
                Text("位置 \(latitude.formatted(.number.precision(.fractionLength(6)))), \(longitude.formatted(.number.precision(.fractionLength(6))))")
            }
            optionalLine("海拔", value: point.altitude, unit: "m")
            optionalLine("水平精度", value: point.accuracy, unit: "m")
            optionalLine("气压", value: point.pressureHpa, unit: "hPa")
            optionalLine("朝向", value: point.headingDeg, unit: "°")
            if let x = point.magneticX, let y = point.magneticY, let z = point.magneticZ {
                Text("磁场 X \(format(x)) / Y \(format(y)) / Z \(format(z)) µT")
            }
            if hasNoHardwareReading(point) {
                Text("此采样点没有可用的硬件读数。")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func optionalLine(_ label: String, value: Double?, unit: String) -> some View {
        if let value {
            Text("\(label) \(format(value)) \(unit)")
        }
    }

    private var statusText: String {
        if coordinator.isActive(track) { return "进行中（仅前台）" }
        return track.endedAt == nil ? "未完整结束" : "已结束"
    }

    private func hasNoHardwareReading(_ point: TrackPoint) -> Bool {
        point.latitude == nil
            && point.longitude == nil
            && point.altitude == nil
            && point.accuracy == nil
            && point.pressureHpa == nil
            && point.magneticX == nil
            && point.magneticY == nil
            && point.magneticZ == nil
            && point.headingDeg == nil
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)))
    }

    private func formatDate(_ milliseconds: Int64) -> String {
        Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
            .formatted(date: .abbreviated, time: .standard)
    }

    private func deleteTrack() {
        do {
            try coordinator.delete(track)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
