import Foundation
import SwiftData

struct CatalogAreaState: Equatable {
    let id: UUID
    let name: String
    let note: String
    let category: String
    let key: String?
}

struct CatalogRoomState: Equatable {
    let id: UUID
    let areaID: UUID?
    let name: String
    let code: String
    let floor: String
    let note: String
    let key: String?
}

struct CatalogState: Equatable {
    var areas: [CatalogAreaState]
    var rooms: [CatalogRoomState]
}

struct CatalogImportPlan {
    let baseline: CatalogState
    var newAreas: [CatalogAreaState] = []
    var newRooms: [CatalogRoomState] = []
    var skipped: [String] = []
    var conflicts: [String] = []
    var canApply: Bool { conflicts.isEmpty && (!newAreas.isEmpty || !newRooms.isEmpty) }
}

enum CatalogImportError: LocalizedError, Equatable {
    case stalePreview, conflicts, pendingChanges
    var errorDescription: String? {
        switch self {
        case .stalePreview: "目录在预览后已变化，请重新预览。未导入任何条目。"
        case .conflicts: "清单有冲突或无效行，请修正后重新预览。未导入任何条目。"
        case .pendingChanges: "当前有尚未保存的更改，请完成保存后重新预览。"
        }
    }
}

@MainActor
final class CatalogImportStore {
    let context: ModelContext
    private let save: (ModelContext) throws -> Void

    init(context: ModelContext, save: @escaping (ModelContext) throws -> Void = { try $0.save() }) {
        self.context = context
        self.save = save
    }

    func state() throws -> CatalogState {
        let areas = try context.fetch(FetchDescriptor<Area>()).map {
            CatalogAreaState(id: $0.id, name: $0.name, note: $0.note, category: $0.category, key: $0.catalogKey)
        }.sorted { $0.id.uuidString < $1.id.uuidString }
        let rooms = try context.fetch(FetchDescriptor<Room>()).map {
            CatalogRoomState(id: $0.id, areaID: $0.area?.id, name: $0.name,
                             code: $0.code, floor: $0.floor, note: $0.note, key: $0.catalogKey)
        }.sorted { $0.id.uuidString < $1.id.uuidString }
        return CatalogState(areas: areas, rooms: rooms)
    }

    func preview(text: String, includeBuildings: Bool, includeCandidates: Bool) throws -> CatalogImportPlan {
        let parsed = ClassroomImportParser.parse(text)
        return try preview(rows: parsed.rows + (includeCandidates ? CampusCatalog.candidateClassrooms : []),
                           includeBuildings: includeBuildings, errors: parsed.errors)
    }

    func preview(rows: [ClassroomImportRow], includeBuildings: Bool = false,
                 errors: [String] = []) throws -> CatalogImportPlan {
        var plan = CatalogImportPlan(baseline: try state())
        plan.conflicts = errors
        if includeBuildings {
            for building in CampusCatalog.buildings {
                _ = resolveArea(building.name, plan: &plan)
            }
        }
        for row in rows {
            let code = row.code.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = row.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !CampusCatalog.key(row.building).isEmpty, !code.isEmpty, !name.isEmpty else {
                plan.conflicts.append("教室缺少建筑、代码或名称。"); continue
            }
            guard let area = resolveArea(row.building, plan: &plan) else { continue }
            let key = CampusCatalog.key(code)
            let rooms = (plan.baseline.rooms + plan.newRooms).filter { $0.areaID == area.id }
            let matches = rooms.filter {
                $0.key == key || CampusCatalog.key($0.code) == key ||
                    CampusCatalog.key($0.name) == CampusCatalog.key(name)
            }
            let label = "\(area.name) / \(code) · \(name)"
            if matches.count > 1 {
                plan.conflicts.append("\(label)：匹配多个旧房间，须先人工消歧。")
            } else if let old = matches.first {
                // Stable import identity survives edits. Never overwrite user metadata.
                // In-batch contradictory rows remain conflicts instead of first-row-wins.
                let isExistingImport = old.key == key && plan.baseline.rooms.contains(where: { $0.id == old.id })
                let exact = CampusCatalog.key(old.code) == key && CampusCatalog.key(old.name) == CampusCatalog.key(name) &&
                    old.floor == CampusCatalog.floor(row.floor) && old.note == row.note.trimmingCharacters(in: .whitespacesAndNewlines)
                if isExistingImport || exact {
                    plan.skipped.append("\(label)：已存在，保留原记录。")
                } else {
                    plan.conflicts.append("\(label)：代码/名称与旧房间或本批条目冲突，不覆盖。")
                }
            } else {
                plan.newRooms.append(.init(id: UUID(), areaID: area.id, name: name, code: code,
                    floor: CampusCatalog.floor(row.floor), note: row.note.trimmingCharacters(in: .whitespacesAndNewlines), key: key))
            }
        }
        return plan
    }

    @discardableResult
    func apply(_ plan: CatalogImportPlan, createdAt: Int64 = Phase2DataStore.nowMilliseconds()) throws -> Int {
        guard plan.conflicts.isEmpty else { throw CatalogImportError.conflicts }
        guard !context.hasChanges else { throw CatalogImportError.pendingChanges }
        guard try state() == plan.baseline else { throw CatalogImportError.stalePreview }
        // One atomic save; warm inverses before insertion so rollback restores lists too.
        var areas = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<Area>()).map { ($0.id, $0) })
        for area in areas.values { _ = area.rooms.count }
        context.processPendingChanges()
        do {
            for draft in plan.newAreas {
                let area = Area(id: draft.id, name: draft.name, note: draft.note, createdAt: createdAt)
                area.category = draft.category
                area.catalogKey = draft.key
                context.insert(area)
                areas[area.id] = area
            }
            for draft in plan.newRooms {
                guard let areaID = draft.areaID, let area = areas[areaID] else { throw CatalogImportError.stalePreview }
                let room = Room(id: draft.id, name: draft.name, note: draft.note, createdAt: createdAt)
                room.code = draft.code
                room.floor = draft.floor
                room.catalogKey = draft.key
                context.insert(room)
                room.area = area
            }
            context.processPendingChanges()
            try save(context)
            return plan.newAreas.count + plan.newRooms.count
        } catch {
            context.rollback()
            throw error
        }
    }

    private func resolveArea(_ input: String, plan: inout CatalogImportPlan) -> CatalogAreaState? {
        let building = CampusCatalog.building(input)
        let name = building?.name ?? input.trimmingCharacters(in: .whitespacesAndNewlines)
        let identity = building.map { "cityu:\($0.id)" } ?? "custom:\(CampusCatalog.key(name))"
        let matches = (plan.baseline.areas + plan.newAreas).filter {
            $0.key == identity || CampusCatalog.key($0.name) == CampusCatalog.key(name) ||
                (building != nil && CampusCatalog.building($0.name)?.id == building?.id)
        }
        guard matches.count <= 1 else {
            plan.conflicts.append("\(name)：匹配多个区域，未按名称合并；请先人工消歧。")
            return nil
        }
        if let area = matches.first { return area }
        let area = CatalogAreaState(id: UUID(), name: name, note: building?.note ?? "",
                                    category: building == nil ? "" : "城市大学", key: identity)
        plan.newAreas.append(area)
        return area
    }
}
