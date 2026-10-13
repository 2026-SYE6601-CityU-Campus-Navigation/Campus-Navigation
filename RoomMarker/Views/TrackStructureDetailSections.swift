import SwiftData
import SwiftUI

struct TrackStructureDetailSections: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var track: Track
    let coordinator: RecordingCoordinator
    @State private var cornerPendingDeletion: TrackCorner?
    @State private var segmentPendingSplit: TrackSegment?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            Section("环境分段（手动标注）") {
                ForEach(TrackSegmentRules.ordered(in: track), id: \.id) { segment in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("第 \(segment.ordinal + 1) 段 · \(segment.environment?.title ?? "无效环境")")
                                .font(.headline)
                            Spacer()
                            if canEditSegments {
                                Menu("修正") {
                                    ForEach(TrackEnvironment.allCases, id: \.self) { environment in
                                        Button(environment.title) { setEnvironment(environment, for: segment) }
                                    }
                                    Button("按节点切分…") { segmentPendingSplit = segment }
                                    if segment.ordinal > 0 {
                                        Button("并入上一段") { merge(segment) }
                                    }
                                }
                            }
                        }
                        Text("开始 \(date(segment.startedAt))")
                        Text("结束 \(segment.endedAt.map(date) ?? (coordinator.isActive(track) ? "进行中" : "未封口 · 未完整结束"))")
                        Text("采样点 \(track.points.filter { $0.segmentID == segment.id }.count) · 拐点 \(track.corners.filter { $0.segmentID == segment.id }.count)")
                    }
                    .font(.caption)
                }
                if track.segments.isEmpty {
                    Text("未记录环境分段；不根据旧采样或节点自动推断。").foregroundStyle(.secondary)
                }
                Text("环境区间不代表连续有采样。后台暂停或锁屏造成的真实间隔仍保留。")
                    .font(.caption).foregroundStyle(.secondary)
                if canEditSegments {
                    Text("结束后可修正状态，或以已有节点为边界切分；修改会原子更新采样点、拐点和原始 IMU 的分段引用，不补造观测。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("拐点（手动采集）") {
                ForEach(track.corners.sorted { $0.timeMs < $1.timeMs }, id: \.id) { corner in
                    cornerRow(corner)
                        .swipeActions {
                            Button("删除拐点", role: .destructive) { cornerPendingDeletion = corner }
                        }
                }
                if track.corners.isEmpty {
                    Text("没有拐点；不会从轨迹形状自动生成。").foregroundStyle(.secondary)
                }
            }
        }
        .confirmationDialog("只删除这个拐点？", isPresented: Binding(
            get: { cornerPendingDeletion != nil },
            set: { if !$0 { cornerPendingDeletion = nil } }
        ), titleVisibility: .visible) {
            Button("删除拐点", role: .destructive) {
                guard let cornerPendingDeletion else { return }
                do {
                    try coordinator.deleteCorner(cornerPendingDeletion)
                    self.cornerPendingDeletion = nil
                } catch { errorMessage = error.localizedDescription }
            }
            Button("取消", role: .cancel) { cornerPendingDeletion = nil }
        } message: {
            Text("只删除手动拐点，不删除定时采样、环境段、节点或照片。")
        }
        .sheet(isPresented: Binding(
            get: { segmentPendingSplit != nil },
            set: { if !$0 { segmentPendingSplit = nil } }
        )) {
            if let segmentPendingSplit {
                TrackSegmentSplitView(track: track, segment: segmentPendingSplit,
                                      editor: TrackStructureEditor(context: modelContext))
            }
        }
        .persistenceErrorAlert($errorMessage)
    }

    private var canEditSegments: Bool {
        track.endedAt != nil && !coordinator.isActive(track) && track.isSegmentedRecording
    }

    private func setEnvironment(_ environment: TrackEnvironment, for segment: TrackSegment) {
        do { try TrackStructureEditor(context: modelContext).setEnvironment(environment, for: segment, in: track) }
        catch { errorMessage = error.localizedDescription }
    }

    private func merge(_ segment: TrackSegment) {
        do { try TrackStructureEditor(context: modelContext).mergeIntoPrevious(segment, in: track) }
        catch { errorMessage = error.localizedDescription }
    }

    private func cornerRow(_ corner: TrackCorner) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(date(corner.timeMs)).font(.subheadline)
            if let segment = track.segments.first(where: { $0.id == corner.segmentID }) {
                Text("第 \(segment.ordinal + 1) 段 · \(segment.environment?.title ?? "无效环境")")
            } else {
                Text("分段关联异常，请保留数据检查。").foregroundStyle(.red)
            }
            if !corner.note.isEmpty { Text(corner.note) }
            if let lat = corner.latitude, let lon = corner.longitude {
                Text("位置 \(lat.formatted(.number.precision(.fractionLength(6)))), \(lon.formatted(.number.precision(.fractionLength(6))))")
            }
            optional("海拔", corner.altitude, "m")
            optional("水平精度", corner.accuracy, "m")
            optional("气压", corner.pressureHpa, "hPa")
            optional("朝向", corner.headingDeg, "°")
            if let x = corner.magneticX, let y = corner.magneticY, let z = corner.magneticZ {
                Text("磁场 X \(x) / Y \(y) / Z \(z) µT")
            }
            if corner.latitude == nil && corner.longitude == nil && corner.altitude == nil &&
                corner.pressureHpa == nil && corner.headingDeg == nil && corner.magneticX == nil {
                Text("没有可用的硬件读数；拐点时间与手动标记仍有效。").foregroundStyle(.secondary)
            }
        }
        .font(.caption)
    }

    @ViewBuilder
    private func optional(_ label: String, _ value: Double?, _ unit: String) -> some View {
        if let value { Text("\(label) \(value.formatted(.number.precision(.fractionLength(2)))) \(unit)") }
    }

    private func date(_ time: Int64) -> String {
        Date(timeIntervalSince1970: Double(time) / 1000).formatted(date: .abbreviated, time: .standard)
    }
}

private struct TrackSegmentSplitView: View {
    @Environment(\.dismiss) private var dismiss
    let track: Track
    let segment: TrackSegment
    let editor: TrackStructureEditor
    @State private var selectedTagID: UUID?
    @State private var environment: TrackEnvironment = .unknown
    @State private var errorMessage: String?

    private var candidates: [TrackTag] {
        guard let end = segment.endedAt else { return [] }
        return track.tags.filter { $0.isNode && $0.timeMs > segment.startedAt && $0.timeMs < end }
            .sorted { ($0.timeMs, $0.id.uuidString) < ($1.timeMs, $1.id.uuidString) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("分界节点") {
                    if candidates.isEmpty {
                        Text("这一段内部没有可作为分界的节点。")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("节点", selection: $selectedTagID) {
                            Text("请选择").tag(UUID?.none)
                            ForEach(candidates, id: \.id) { tag in
                                Text("\(tag.tagTypeRawValue) · \(tag.note.isEmpty ? date(tag.timeMs) : tag.note)")
                                    .tag(Optional(tag.id))
                            }
                        }
                        Picker("后一段环境", selection: $environment) {
                            ForEach(TrackEnvironment.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                    }
                }
                Section {
                    Text("节点时刻以前保留在原段；该时刻及之后的采样点、拐点与 IMU 改为新段。原始数值与时间不变。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("切分环境段")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("切分") {
                        guard let id = selectedTagID, let tag = candidates.first(where: { $0.id == id }) else { return }
                        do {
                            try editor.split(segment, at: tag, newEnvironment: environment, in: track)
                            dismiss()
                        } catch { errorMessage = error.localizedDescription }
                    }
                    .disabled(selectedTagID == nil)
                }
            }
            .persistenceErrorAlert($errorMessage)
        }
    }

    private func date(_ time: Int64) -> String {
        Date(timeIntervalSince1970: Double(time) / 1000).formatted(date: .omitted, time: .standard)
    }
}
