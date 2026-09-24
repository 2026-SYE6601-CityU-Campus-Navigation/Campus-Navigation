import SwiftData
import SwiftUI

struct RoomDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var room: Room

    @State private var isShowingRoomEditor = false
    @State private var editingMarker: Marker?
    @State private var isShowingMarkerEditor = false
    @State private var markerPendingDeletion: Marker?
    @State private var isConfirmingRoomDeletion = false
    @State private var errorMessage: String?

    private var sortedMarkers: [Marker] {
        room.markers.sorted { $0.createdAt < $1.createdAt }
    }

    private var hasRoomSensorData: Bool {
        room.latitude != nil || room.longitude != nil || room.altitude != nil || room.pressureHpa != nil
    }

    var body: some View {
        List {
            Section("房间信息") {
                LabeledContent("所属区域", value: room.area?.name ?? "未分区")
                if !room.note.isEmpty {
                    LabeledContent("备注") {
                        Text(room.note)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }

            Section("已有传感器数据") {
                if hasRoomSensorData {
                    if let latitude = room.latitude, let longitude = room.longitude {
                        LabeledContent("位置", value: String(format: "%.6f, %.6f", latitude, longitude))
                    }
                    if let altitude = room.altitude {
                        LabeledContent("海拔", value: String(format: "%.1f m", altitude))
                    }
                    if let pressure = room.pressureHpa {
                        LabeledContent("气压", value: String(format: "%.1f hPa", pressure))
                    }
                } else {
                    Label("未采集；Phase 2 不提供传感器采集", systemImage: "sensor.tag.radiowaves.forward.slash")
                        .foregroundStyle(.secondary)
                }
            }

            Section("标记（\(sortedMarkers.count)）") {
                ForEach(sortedMarkers, id: \.id) { marker in
                    markerRow(marker)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            editingMarker = marker
                            isShowingMarkerEditor = true
                        }
                        .swipeActions(edge: .trailing) {
                            Button("删除", role: .destructive) {
                                markerPendingDeletion = marker
                            }
                            Button("编辑") {
                                editingMarker = marker
                                isShowingMarkerEditor = true
                            }
                            .tint(.blue)
                        }
                }

                if sortedMarkers.isEmpty {
                    Phase2EmptyState(
                        "还没有标记",
                        systemImage: "mappin.slash",
                        message: "手动添加门、窗户或其他房间标记。",
                        actionTitle: "新建标记",
                        action: presentNewMarker
                    )
                    .listRowBackground(Color.clear)
                }
            }
        }
        .navigationTitle(room.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(action: presentNewMarker) {
                    Label("新建标记", systemImage: "plus")
                }
                Menu {
                    Button("编辑房间", systemImage: "pencil") {
                        isShowingRoomEditor = true
                    }
                    Button("删除房间", systemImage: "trash", role: .destructive) {
                        isConfirmingRoomDeletion = true
                    }
                } label: {
                    Label("更多", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $isShowingRoomEditor) {
            RoomEditorView(room: room)
        }
        .sheet(isPresented: $isShowingMarkerEditor) {
            MarkerEditorView(room: room, marker: editingMarker)
        }
        .confirmationDialog(
            "删除房间“\(room.name)”？",
            isPresented: $isConfirmingRoomDeletion,
            titleVisibility: .visible
        ) {
            Button("删除房间及 \(room.markers.count) 个标记", role: .destructive, action: deleteRoom)
            Button("取消", role: .cancel) {}
        } message: {
            Text("房间及其所有标记会被永久删除，且无法撤销。")
        }
        .confirmationDialog(
            "删除标记“\(markerPendingDeletion?.name ?? "")”？",
            isPresented: Binding(
                get: { markerPendingDeletion != nil },
                set: { if !$0 { markerPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除标记", role: .destructive) {
                deletePendingMarker()
            }
            Button("取消", role: .cancel) {
                markerPendingDeletion = nil
            }
        } message: {
            Text("此操作无法撤销。")
        }
        .persistenceErrorAlert($errorMessage)
    }

    @ViewBuilder
    private func markerRow(_ marker: Marker) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(marker.name)
                Spacer()
                Text(marker.markerTypeRawValue)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if markerHasSensorData(marker) {
                Text(markerSensorSummary(marker))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("手动创建 · 无传感器数据")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func presentNewMarker() {
        editingMarker = nil
        isShowingMarkerEditor = true
    }

    private func deleteRoom() {
        do {
            try Phase2DataStore(context: modelContext).deleteRoom(room)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deletePendingMarker() {
        guard let markerPendingDeletion else { return }
        do {
            try Phase2DataStore(context: modelContext).deleteMarker(markerPendingDeletion)
            self.markerPendingDeletion = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func markerHasSensorData(_ marker: Marker) -> Bool {
        marker.latitude != nil || marker.longitude != nil || marker.altitude != nil
            || marker.accuracy != nil || marker.pressureHpa != nil
            || marker.magneticX != nil || marker.magneticY != nil || marker.magneticZ != nil
    }

    private func markerSensorSummary(_ marker: Marker) -> String {
        var parts: [String] = []
        if let latitude = marker.latitude, let longitude = marker.longitude {
            parts.append(String(format: "%.6f, %.6f", latitude, longitude))
        }
        if let pressure = marker.pressureHpa {
            parts.append(String(format: "%.1f hPa", pressure))
        }
        if let x = marker.magneticX, let y = marker.magneticY, let z = marker.magneticZ {
            parts.append(String(format: "磁场 %.1f / %.1f / %.1f µT", x, y, z))
        }
        return parts.joined(separator: " · ")
    }
}
