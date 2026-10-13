import SwiftData
import SwiftUI

struct TrackRoomGenerationSection: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var track: Track
    let areas: [Area]
    let rooms: [Room]

    @State private var preview: [TrackRoomDraft]?

    private var drafts: [TrackRoomDraft] {
        TrackRoomPlanner.drafts(for: track, areas: areas, rooms: rooms)
    }

    var body: some View {
        if !drafts.isEmpty {
            Section("从教室节点生成房间") {
                Text("可按节点所属建筑创建 \(drafts.count) 个房间；同楼同名、已绑定房间和无区域节点会跳过。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("预览并生成房间", systemImage: "door.left.hand.open") {
                    preview = drafts
                }
            }
            .sheet(isPresented: Binding(get: { preview != nil }, set: { if !$0 { preview = nil } })) {
                if let preview {
                    TrackRoomGenerationPreview(track: track, drafts: preview,
                                               store: TrackRoomGenerationStore(context: modelContext))
                }
            }
        }
    }
}

private struct TrackRoomGenerationPreview: View {
    @Environment(\.dismiss) private var dismiss
    let track: Track
    let drafts: [TrackRoomDraft]
    let store: TrackRoomGenerationStore
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("只创建下面列出的房间，并把来源教室节点显式绑定到新房间。不会改动节点照片、时间或传感器值。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(Dictionary(grouping: drafts, by: \.areaName).keys.sorted(), id: \.self) { areaName in
                    Section(areaName) {
                        ForEach(drafts.filter { $0.areaName == areaName }) { draft in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(draft.name)
                                Text(draft.floor.isEmpty ? "楼层未记录" : draft.floor)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("生成房间预览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建 \(drafts.count) 个") {
                        do {
                            _ = try store.create(drafts, for: track)
                            dismiss()
                        } catch { errorMessage = error.localizedDescription }
                    }
                }
            }
            .persistenceErrorAlert($errorMessage)
        }
    }
}
