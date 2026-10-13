import Foundation
import SwiftData

struct TrackRoomDraft: Identifiable, Equatable {
    var id: UUID { tagID }
    let tagID: UUID
    let areaID: UUID
    let areaName: String
    let name: String
    let floor: String
    let note: String
    let latitude: Double?
    let longitude: Double?
    let altitude: Double?
    let pressureHpa: Double?
}

enum TrackRoomPlanningError: LocalizedError, Equatable {
    case unavailableNode
    case unavailableArea
    case stalePreview

    var errorDescription: String? {
        switch self {
        case .unavailableNode:
            "教室节点已不可用，没有创建房间。"
        case .unavailableArea:
            "节点所属建筑已不可用，没有创建房间。"
        case .stalePreview:
            "房间或节点已发生变化，请重新生成预览。"
        }
    }
}

@MainActor
enum TrackRoomPlanner {
    static func drafts(for track: Track, areas: [Area], rooms: [Room]) -> [TrackRoomDraft] {
        let areaByID = Dictionary(uniqueKeysWithValues: areas.map { ($0.id, $0) })
        var namesByArea: [UUID: Set<String>] = [:]
        for room in rooms {
            guard let areaID = room.area?.id else { continue }
            namesByArea[areaID, default: []].insert(key(room.name))
        }

        var output: [TrackRoomDraft] = []
        for tag in track.tags.sorted(by: { ($0.timeMs, $0.id.uuidString) < ($1.timeMs, $1.id.uuidString) }) {
            guard tag.isNode, tag.tagType == .classroom,
                  tag.roomID == nil, tag.areaStateRawValue == "assigned",
                  let areaID = tag.areaID, let area = areaByID[areaID] else { continue }
            let name = roomName(for: tag)
            let normalized = key(name)
            guard !normalized.isEmpty, !namesByArea[areaID, default: []].contains(normalized) else { continue }
            namesByArea[areaID, default: []].insert(normalized)
            let details = ["来自轨迹「\(track.name)」", tag.floor.isEmpty ? nil : "楼层 \(tag.floor)",
                           Date(timeIntervalSince1970: Double(tag.timeMs) / 1_000)
                            .formatted(date: .abbreviated, time: .standard)]
                .compactMap { $0 }.joined(separator: " · ")
            output.append(.init(tagID: tag.id, areaID: areaID, areaName: area.name, name: name,
                                floor: tag.floor, note: details, latitude: tag.latitude,
                                longitude: tag.longitude, altitude: tag.altitude, pressureHpa: tag.pressureHpa))
        }
        return output
    }

    static func roomName(for tag: TrackTag) -> String {
        let note = tag.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty { return note }
        let floor = tag.floor.trimmingCharacters(in: .whitespacesAndNewlines)
        return floor.isEmpty ? "教室" : "教室 \(floor)"
    }

    static func key(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .filter { !$0.isWhitespace }
    }
}

@MainActor
final class TrackRoomGenerationStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func create(_ preview: [TrackRoomDraft], for track: Track) throws -> [Room] {
        let areas = try context.fetch(FetchDescriptor<Area>())
        let rooms = try context.fetch(FetchDescriptor<Room>())
        let current = TrackRoomPlanner.drafts(for: track, areas: areas, rooms: rooms)
        guard current == preview else { throw TrackRoomPlanningError.stalePreview }

        let areaByID = Dictionary(uniqueKeysWithValues: areas.map { ($0.id, $0) })
        let tagByID = Dictionary(uniqueKeysWithValues: track.tags.map { ($0.id, $0) })
        var created: [Room] = []
        for draft in preview {
            guard let tag = tagByID[draft.tagID], tag.isNode, tag.tagType == .classroom,
                  tag.roomID == nil else { throw TrackRoomPlanningError.unavailableNode }
            guard let area = areaByID[draft.areaID], tag.areaID == area.id,
                  tag.areaStateRawValue == "assigned" else { throw TrackRoomPlanningError.unavailableArea }
            let room = Room(name: draft.name, note: draft.note, area: area, latitude: draft.latitude,
                            longitude: draft.longitude, altitude: draft.altitude,
                            pressureHpa: draft.pressureHpa, createdAt: Phase2DataStore.nowMilliseconds())
            room.floor = CampusCatalog.floor(draft.floor)
            context.insert(room)
            NodeRoomBinding.apply(NodeRoomSelection(roomID: room.id), room: room, to: tag)
            created.append(room)
        }
        do {
            try context.save()
            return created
        } catch {
            context.rollback()
            throw error
        }
    }
}
