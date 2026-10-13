import SwiftData
import SwiftUI

struct CatalogImportView: View {
    @Environment(\.modelContext) private var context
    @State private var text = ""
    @State private var includeBuildings = true
    @State private var includeCandidates = false
    @State private var plan: CatalogImportPlan?
    @State private var isConfirming = false
    @State private var message: String?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("建筑／教室目录") {
                Toggle("导入 11 栋城大建筑", isOn: $includeBuildings)
                Toggle("加入 19 个候选讲堂", isOn: $includeCandidates)
                Text("非官方全量目录。AC1 LT-1…LT-18 编号来自鸿蒙候选表的推导，须现场核对；不会生成坐标、传感器值或已采集证据。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("粘贴教室清单（可选）") {
                Text("每行：建筑,代码,名称,备注,楼层。后三项中的备注、楼层可留空；前三项必填。也支持制表符、竖线、顿号，不支持带引号的 CSV。")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("例：AC2,1503,教室1503,,1/F")
                    .font(.caption).textSelection(.enabled)
                TextEditor(text: $text).frame(minHeight: 130).accessibilityLabel("教室导入清单")
                Button("生成导入预览", action: preview)
            }
            if let plan {
                Section("预览：新建筑 \(plan.newAreas.count) · 新房间 \(plan.newRooms.count)") {
                    ForEach(plan.newAreas, id: \.id) { Text("建筑：\($0.name)") }
                    ForEach(plan.newRooms, id: \.id) { room in
                        let area = (plan.baseline.areas + plan.newAreas).first { $0.id == room.areaID }
                        Text("\(area?.name ?? "") / \(room.code) · \(room.name) · \(room.floor)")
                    }
                    if plan.newAreas.isEmpty && plan.newRooms.isEmpty { Text("没有需要新增的条目。") }
                }
                if !plan.skipped.isEmpty {
                    Section("已存在／跳过 \(plan.skipped.count)") {
                        ForEach(Array(plan.skipped.enumerated()), id: \.offset) { Text($0.element).font(.caption) }
                    }
                }
                if !plan.conflicts.isEmpty {
                    Section("须先修正 \(plan.conflicts.count)") {
                        ForEach(Array(plan.conflicts.enumerated()), id: \.offset) {
                            Text($0.element).font(.caption).foregroundStyle(.orange)
                        }
                    }
                }
                Section {
                    Button("确认导入新增条目") { isConfirming = true }.disabled(!plan.canApply)
                    Text("仅新增，不覆盖旧 UUID、名称、参考点或标记。任何冲突会阻止整批导入；目录在预览后变化则必须重新预览。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            if let message { Section { Text(message) } }
        }
        .navigationTitle("目录导入")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: text) { _, _ in plan = nil; message = nil }
        .onChange(of: includeBuildings) { _, _ in plan = nil; message = nil }
        .onChange(of: includeCandidates) { _, _ in plan = nil; message = nil }
        .confirmationDialog("导入预览中的新增建筑／房间？", isPresented: $isConfirming, titleVisibility: .visible) {
            Button("导入") { apply() }
            Button("取消", role: .cancel) {}
        }
        .persistenceErrorAlert($errorMessage)
    }

    private func preview() {
        do {
            plan = try CatalogImportStore(context: context).preview(text: text,
                includeBuildings: includeBuildings, includeCandidates: includeCandidates)
            message = nil
        } catch { errorMessage = error.localizedDescription }
    }

    private func apply() {
        guard let plan else { return }
        do {
            let count = try CatalogImportStore(context: context).apply(plan)
            self.plan = nil
            message = "已新增 \(count) 个条目。可重复预览验证幂等；旧数据未覆盖。"
        } catch { errorMessage = error.localizedDescription }
    }
}
