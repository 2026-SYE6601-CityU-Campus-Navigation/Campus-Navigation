import SwiftData
import SwiftUI

struct TrackSelectionExportView: View {
    @Query(sort: \Track.startedAt, order: .reverse) private var tracks: [Track]
    @Query private var areas: [Area]
    @Query private var rooms: [Room]
    let recording: RecordingCoordinator
    @State private var selected: Set<UUID> = []
    @State private var exporter: AreaExportCoordinator

    init(recording: RecordingCoordinator, photoStorage: any PhotoFileStoring) {
        self.recording = recording
        _exporter = State(initialValue: AreaExportCoordinator(photoStorage: photoStorage,
            activeTrackID: { recording.activeTrackID }))
    }

    var body: some View {
        List {
            Section {
                Text("已选 \(selected.count) 条轨迹。来自全部轨迹列表；每条跨楼轨迹将完整导出，不按区域裁剪。")
                Text("未完整结束的历史轨迹可以导出，结束时间仍留空；正在录制时请先停止并保存。")
                    .font(.footnote).foregroundStyle(.secondary)
                HStack {
                    Button("全选") { selected = Set(tracks.filter { !recording.isActive($0) }.map(\.id)) }
                    Spacer()
                    Button("清空") { selected.removeAll() }
                }
                .buttonStyle(.borderless)
                .disabled(exporter.state.isBusy)
            }
            AreaExportSection(coordinator: exporter, areaName: "所选 \(selected.count) 条轨迹", startExport: {
                try exporter.startSelectedV3(ids: selected, tracks: tracks, areas: areas, rooms: rooms)
            }, isRecordingActive: recording.activeTrackID != nil, exportTitle: "导出所选轨迹",
               isSelectionEmpty: selected.isEmpty)
            Section("全部轨迹") {
                ForEach(tracks, id: \.id) { track in
                    Toggle(isOn: Binding(get: { selected.contains(track.id) }, set: { enabled in
                        if enabled { selected.insert(track.id) } else { selected.remove(track.id) }
                    })) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(track.name)
                            Text(Date(timeIntervalSince1970: Double(track.startedAt) / 1_000)
                                .formatted(date: .abbreviated, time: .standard))
                            Text("ID \(track.id.uuidString.lowercased())")
                                .font(.caption2).textSelection(.enabled)
                            Text("\(track.pointCount) 点 · \(track.endedAt == nil ? "未完整结束" : "已结束")")
                        }
                        .font(.caption)
                    }
                    .disabled(exporter.state.isBusy || recording.isActive(track))
                }
            }
        }
        .navigationTitle("选择轨迹导出")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: selected) { _, _ in exporter.cancelAndReset() }
    }
}
