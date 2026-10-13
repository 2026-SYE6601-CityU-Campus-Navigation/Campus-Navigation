import Foundation
import SwiftData

enum Phase2ValidationError: LocalizedError, Equatable {
    case emptyName

    var errorDescription: String? {
        switch self {
        case .emptyName:
            "名称不能为空。"
        }
    }
}

@MainActor
final class Phase2DataStore {
    private let context: ModelContext
    private let repository: SwiftDataRepository

    init(context: ModelContext) {
        self.context = context
        repository = SwiftDataRepository(context: context)
    }

    @discardableResult
    func createArea(
        name: String,
        note: String,
        createdAt: Int64 = Phase2DataStore.nowMilliseconds(), category: String = ""
    ) throws -> Area {
        let input = try validated(name: name, note: note)
        let area = Area(name: input.name, note: input.note, createdAt: createdAt)
        area.category = category.trimmingCharacters(in: .whitespacesAndNewlines)
        context.insert(area)
        try repository.save()
        return area
    }

    func updateArea(_ area: Area, name: String, note: String, category: String? = nil) throws {
        let input = try validated(name: name, note: note)
        area.name = input.name
        area.note = input.note
        if let category { area.category = category.trimmingCharacters(in: .whitespacesAndNewlines) }
        try repository.save()
    }

    @discardableResult
    func createRoom(
        name: String,
        note: String,
        area: Area?,
        createdAt: Int64 = Phase2DataStore.nowMilliseconds(), code: String = "", floor: String = ""
    ) throws -> Room {
        let input = try validated(name: name, note: note)
        let room = Room(name: input.name, note: input.note, area: area, createdAt: createdAt)
        room.code = code.trimmingCharacters(in: .whitespacesAndNewlines)
        room.floor = CampusCatalog.floor(floor)
        context.insert(room)
        try repository.save()
        return room
    }

    func updateRoom(_ room: Room, name: String, note: String, area: Area?, code: String? = nil, floor: String? = nil) throws {
        let input = try validated(name: name, note: note)
        room.name = input.name
        room.note = input.note
        room.area = area
        if let code { room.code = code.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let floor { room.floor = CampusCatalog.floor(floor) }
        try repository.save()
    }

    func replaceRoomReference(_ room: Room, with snapshot: SensorSnapshot) throws {
        room.latitude = snapshot.latitude
        room.longitude = snapshot.longitude
        room.altitude = snapshot.altitude
        room.pressureHpa = snapshot.pressureHpa
        try repository.save()
    }

    @discardableResult
    func createMarker(
        room: Room,
        name: String,
        markerType: MarkerType,
        snapshot: SensorSnapshot? = nil,
        createdAt: Int64 = Phase2DataStore.nowMilliseconds()
    ) throws -> Marker {
        let input = try validated(name: name, note: "")
        let marker = Marker(
            room: room,
            name: input.name,
            markerType: markerType,
            latitude: snapshot?.latitude,
            longitude: snapshot?.longitude,
            altitude: snapshot?.altitude,
            accuracy: snapshot?.accuracy,
            pressureHpa: snapshot?.pressureHpa,
            magneticX: snapshot?.magneticX,
            magneticY: snapshot?.magneticY,
            magneticZ: snapshot?.magneticZ,
            createdAt: createdAt
        )
        context.insert(marker)
        try repository.save()
        return marker
    }

    func updateMarker(_ marker: Marker, name: String, markerType: MarkerType) throws {
        let input = try validated(name: name, note: "")
        marker.name = input.name
        marker.markerType = markerType
        try repository.save()
    }

    func deleteAreaPreservingContents(_ area: Area) throws {
        try repository.deleteAreaPreservingContents(area)
    }

    func deleteRoom(_ room: Room) throws {
        try repository.deleteRoom(room)
    }

    func deleteMarker(_ marker: Marker) throws {
        context.delete(marker)
        try repository.save()
    }

    /// Metadata-only edit: never refresh timestamps, sampled values or photo records.
    func updateTagLocation(_ tag: TrackTag, area: Area?, floor: String) throws {
        // Existing callers preserve the historical room snapshot, even after relocation.
        try updateTagLocationAndRoom(tag, area: area, floor: floor, updateRoomBinding: false, roomSelection: nil)
    }

    func updateTagLocationAndRoom(_ tag: TrackTag, area: Area?, floor: String,
                                  updateRoomBinding: Bool = true, roomSelection: NodeRoomSelection?) throws {
        if updateRoomBinding && !tag.isNode && roomSelection != nil { throw NodeRoomError.unsupportedType }
        let room = try updateRoomBinding ? NodeRoomBinding.resolve(roomSelection,
            type: tag.tagType ?? .otherIndoor, areaID: area?.id, context: context) : nil
        tag.areaID = area?.id
        tag.areaStateRawValue = area == nil ? "unassigned" : "assigned"
        tag.floor = CampusCatalog.floor(floor)
        if updateRoomBinding && (tag.roomID != roomSelection?.roomID || tag.roomDoorRole != roomSelection?.doorRole) {
            NodeRoomBinding.apply(roomSelection, room: room, to: tag)
        }
        do {
            try repository.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    private func validated(name: String, note: String) throws -> (name: String, note: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw Phase2ValidationError.emptyName
        }
        return (
            trimmedName,
            note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    nonisolated static func nowMilliseconds() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1_000)
    }
}
