import SwiftData
import SwiftUI

@MainActor
enum TrackPointPage {
    static let size = 100
    enum Failure: Error { case invalidPage }

    static func load(trackID: UUID, page: Int, context: ModelContext) throws -> [TrackPoint] {
        guard page >= 0, page <= Int.max / size else { throw Failure.invalidPage }
        var descriptor = FetchDescriptor<TrackPoint>(
            predicate: #Predicate { $0.track?.id == trackID },
            sortBy: [SortDescriptor(\TrackPoint.timeMs)]
        )
        descriptor.fetchOffset = page * size
        descriptor.fetchLimit = size
        return try context.fetch(descriptor)
    }
}

struct TrackPointDetailSection: View {
    @Environment(\.modelContext) private var context
    @Bindable var track: Track
    @State private var page = 0
    @State private var points: [TrackPoint] = []
    @State private var failed = false

    var body: some View {
        Section("采样点") {
            Text("共 \(track.pointCount) 个已保存点 · 每页 \(TrackPointPage.size) 个。分页只影响显示，导出保留全部数据。")
                .font(.caption).foregroundStyle(.secondary)
            if failed {
                Text("采样点读取失败，请保留数据后重试。").foregroundStyle(.red)
                Button("重试读取", action: reload)
            } else if track.pointCount == 0 {
                Text("还没有已保存的采样点。").foregroundStyle(.secondary)
            } else {
                ForEach(points, id: \.id) { point in TrackPointDetailRow(point: point) }
            }
            if track.pointCount > TrackPointPage.size {
                HStack {
                    Button("上一页") { page -= 1 }.disabled(page == 0)
                    Spacer()
                    Text("第 \(page + 1) 页").font(.caption)
                    Spacer()
                    Button("下一页") { page += 1 }
                        .disabled((page + 1) * TrackPointPage.size >= track.pointCount)
                }.buttonStyle(.borderless)
            }
        }
        .task(id: "\(track.id)-\(page)-\(track.pointCount)") { reload() }
    }

    private func reload() {
        do {
            points = try TrackPointPage.load(trackID: track.id, page: page, context: context)
            failed = false
        } catch { failed = true }
    }
}

private struct TrackPointDetailRow: View {
    let point: TrackPoint
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Date(timeIntervalSince1970: Double(point.timeMs) / 1_000)
                .formatted(date: .abbreviated, time: .standard)).font(.subheadline)
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
            if point.latitude == nil && point.longitude == nil && point.altitude == nil
                && point.accuracy == nil && point.pressureHpa == nil && point.headingDeg == nil
                && point.magneticX == nil && point.magneticY == nil && point.magneticZ == nil {
                Text("此采样点没有可用的硬件读数。").foregroundStyle(.secondary)
            }
        }.font(.caption).padding(.vertical, 3)
    }
    @ViewBuilder private func optionalLine(_ label: String, value: Double?, unit: String) -> some View {
        if let value { Text("\(label) \(format(value)) \(unit)") }
    }
    private func format(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(2))) }
}
