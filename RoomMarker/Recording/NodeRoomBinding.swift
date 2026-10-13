import Foundation
import SwiftData

struct NodeRoomSelection: Equatable, Sendable {
    let roomID: UUID
    var doorRole: String? = nil
}

enum NodeRoomError: LocalizedError, Equatable {
    case unavailable, wrongArea, unsupportedType, invalidDoorRole
    var errorDescription: String? {
        switch self {
        case .unavailable: "所选房间已不可用，请重新选择或明确取消房间绑定。"
        case .wrongArea: "房间必须属于节点所选区域；未自动改存。请核对区域与房间。"
        case .unsupportedType: "仅教室、门和门禁节点可绑定房间。其他类型请明确取消绑定。"
        case .invalidDoorRole: "门／门禁请选择前门或后门；教室节点不指定门类型。"
        }
    }
}

@MainActor
enum NodeRoomBinding {
    static func supports(_ type: TrackTagType) -> Bool {
        [.classroom, .door, .gate].contains(type)
    }

    static func resolve(_ selection: NodeRoomSelection?, type: TrackTagType,
                        areaID: UUID?, rooms: [Room]) throws -> Room? {
        guard let selection else { return nil }
        guard supports(type) else { throw NodeRoomError.unsupportedType }
        guard let room = rooms.first(where: { $0.id == selection.roomID }) else { throw NodeRoomError.unavailable }
        guard let areaID, room.area?.id == areaID else { throw NodeRoomError.wrongArea }
        if type == .classroom {
            guard selection.doorRole == nil else { throw NodeRoomError.invalidDoorRole }
        } else {
            guard ["前门", "后门"].contains(selection.doorRole ?? "") else { throw NodeRoomError.invalidDoorRole }
        }
        return room
    }

    static func resolve(_ selection: NodeRoomSelection?, type: TrackTagType,
                        areaID: UUID?, context: ModelContext) throws -> Room? {
        guard let selection else { return nil }
        let id = selection.roomID
        return try resolve(selection, type: type, areaID: areaID,
            rooms: context.fetch(FetchDescriptor<Room>(predicate: #Predicate { $0.id == id })))
    }

    static func apply(_ selection: NodeRoomSelection?, room: Room?, to tag: TrackTag) {
        tag.roomID = selection?.roomID
        tag.roomNameSnapshot = room?.name
        tag.roomCodeSnapshot = room?.code
        tag.roomDoorRole = selection?.doorRole
    }

    static func status(for tag: TrackTag, room: Room?) -> String {
        guard let room, room.id == tag.roomID else { return "missing" }
        return tag.areaStateRawValue == "assigned" && room.area?.id == tag.areaID ? "linked" : "relocated"
    }

    static func label(for tag: TrackTag, rooms: [Room]) -> String {
        guard tag.roomID != nil else { return "未绑定房间" }
        let room = rooms.first { $0.id == tag.roomID }
        let status = status(for: tag, room: room)
        let suffix = status == "missing" ? "（房间已删除，保留绑定时快照）" :
            status == "relocated" ? "（房间区域已变化，未自动改绑）" : "（绑定时快照）"
        return [tag.roomCodeSnapshot, tag.roomNameSnapshot, tag.roomDoorRole].compactMap { $0 }
            .filter { !$0.isEmpty }.joined(separator: " · ") + suffix
    }
}
