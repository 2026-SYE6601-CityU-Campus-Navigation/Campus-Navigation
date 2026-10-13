import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import RoomMarker

@Suite("Offline batch 3 explicit node-room binding", .serialized)
@MainActor
struct OfflineBatch3BindingTests {
    @Test("Only classroom, door and gate may bind; all other types remain unbound", arguments: TrackTagType.allCases)
    func types(_ type: TrackTagType) throws {
        let f = try Stage4Fixture(); defer { f.dispose() }
        let (area, room) = try catalog(f)
        let selection = NodeRoomSelection(roomID: room.id, doorRole: type == .classroom ? nil : "后门")
        let capture = try capture(f)
        if [.classroom, .door, .gate].contains(type) {
            let node = try f.coordinator.saveNode(capture: capture, type: type, note: "Synthetic",
                location: .init(area: area, floor: "1/F"), roomSelection: selection)
            #expect(node.roomID == room.id && node.roomNameSnapshot == room.name && node.roomCodeSnapshot == "X1")
            #expect(node.roomDoorRole == selection.doorRole)
            #expect(try NodePhotoAssociation.photo(for: node).timeMs == capture.capturedAt)
            #expect(room.markers.isEmpty) // Linking does not fabricate a separate sampled Marker.
        } else {
            #expect(throws: NodeRoomError.unsupportedType) {
                try f.coordinator.saveNode(capture: capture, type: type, note: "",
                    location: .init(area: area), roomSelection: selection)
            }
            #expect(f.track.tags.isEmpty && f.track.photos.isEmpty)
            let node = try f.coordinator.saveNode(capture: capture, type: type, note: "",
                location: .init(area: area))
            #expect(node.roomID == nil && node.roomNameSnapshot == nil)
        }
    }

    @Test("Room choice survives camera return, cancel, retake and immutable Save request")
    func cameraRoundtrip() throws {
        let f = try Stage4Fixture(); defer { f.dispose() }
        let (a, ra) = try catalog(f)
        let data = Phase2DataStore(context: f.context)
        let b = try data.createArea(name: "Synthetic B", note: "")
        let rb = try data.createRoom(name: "B room", note: "", area: b, code: "X1", floor: "2/F")
        let form = NodeCaptureForm(trackID: f.track.id, initialLocation: .init(area: a))
        form.selectedType = .door; form.selectedAreaID = b.id; form.selectedRoomID = rb.id; form.doorRole = "后门"
        try form.receive(capture(f)); try form.receive(nil); try form.receive(capture(f))
        #expect(form.selectedAreaID == b.id && form.selectedRoomID == rb.id)
        let request = try form.request(availableAreaIDs: [a.id, b.id], isNode: true, rooms: [ra, rb])
        form.selectedAreaID = a.id; form.selectedRoomID = ra.id
        let node = try f.coordinator.saveNode(capture: request.capture, type: request.type, note: request.note,
            location: request.location, roomSelection: request.roomSelection)
        #expect(node.areaID == b.id && node.roomID == rb.id && node.roomDoorRole == "后门")
        form.selectedAreaID = b.id
        #expect(throws: NodeRoomError.wrongArea) {
            try form.request(availableAreaIDs: [a.id, b.id], isNode: true, rooms: [ra, rb])
        }
        #expect(form.selectedRoomID == ra.id) // Explicit error, never silently reset.
    }

    @Test("Wrong area, unassigned area, missing room and invalid door role reject atomically", arguments: ["area", "unassigned", "missing", "role", "classroomRole"])
    func invalidSelection(_ kind: String) throws {
        let f = try Stage4Fixture(); defer { f.dispose() }
        let (a, room) = try catalog(f)
        let b = try Phase2DataStore(context: f.context).createArea(name: "Synthetic B", note: "")
        let area = kind == "area" ? b : kind == "unassigned" ? nil : a
        let selection = NodeRoomSelection(roomID: kind == "missing" ? UUID() : room.id,
            doorRole: kind == "role" ? "窗户" : "前门")
        #expect(throws: (any Error).self) {
            try f.coordinator.saveNode(capture: capture(f), type: kind == "classroomRole" ? .classroom : .door,
                note: "", location: .init(area: area), roomSelection: selection)
        }
        #expect(f.track.tags.isEmpty && f.track.photos.isEmpty && room.markers.isEmpty && !f.context.hasChanges)
        #expect(f.coordinator.mediaCleanupMessage == nil)
    }

    @Test("Deleted room between preview and save fails with photo compensation; explicit unbind may retry")
    func deletedDuringCapture() throws {
        let f = try Stage4Fixture(); defer { f.dispose() }
        let (a, room) = try catalog(f)
        let form = NodeCaptureForm(trackID: f.track.id, initialLocation: .init(area: a))
        form.selectedType = .classroom; form.selectedRoomID = room.id
        try form.receive(capture(f))
        let request = try form.request(availableAreaIDs: [a.id], isNode: true, rooms: [room])
        try Phase2DataStore(context: f.context).deleteRoom(room)
        #expect(throws: NodeRoomError.unavailable) {
            try f.coordinator.saveNode(capture: request.capture, type: request.type, note: "",
                location: request.location, roomSelection: request.roomSelection)
        }
        #expect(f.track.tags.isEmpty && f.track.photos.isEmpty)
        #expect(ownedJPEGS(f).isEmpty)
        let node = try f.coordinator.saveNode(capture: request.capture, type: request.type, note: "", location: request.location)
        #expect(node.roomID == nil && ownedJPEGS(f).count == 1)
    }

    @Test("Save failure rolls back link and both records; retry saves exactly once")
    func compensationRetry() throws {
        let f = try Stage4Fixture(); defer { f.dispose() }
        let (a, room) = try catalog(f)
        let capture = try capture(f)
        let selection = NodeRoomSelection(roomID: room.id, doorRole: "前门")
        f.failure.enabled = true
        #expect(throws: Stage4Failure.save) {
            try f.coordinator.saveNode(capture: capture, type: .gate, note: "Synthetic",
                location: .init(area: a), roomSelection: selection)
        }
        #expect(f.track.tags.isEmpty && f.track.photos.isEmpty && !f.context.hasChanges && ownedJPEGS(f).isEmpty)
        #expect(a.rooms.map(\.id) == [room.id])
        f.failure.enabled = false
        let node = try f.coordinator.saveNode(capture: capture, type: .gate, note: "Synthetic",
            location: .init(area: a), roomSelection: selection)
        #expect(node.roomID == room.id && f.track.tags.count == 1 && f.track.photos.count == 1)
        #expect(throws: NodeCaptureError.alreadySaved) {
            try f.coordinator.saveNode(capture: capture, type: .gate, note: "",
                location: .init(area: a), roomSelection: selection)
        }
    }

    @Test("Metadata edits preserve evidence and existing snapshots; explicit unlink leaves independent history alone")
    func editing() throws {
        let f = try Stage4Fixture(); defer { f.dispose() }
        _ = try f.addEvidence()
        let (a, room) = try catalog(f)
        let node = try f.coordinator.saveNode(capture: capture(f), type: .door, note: "Synthetic",
            location: .init(area: a), roomSelection: .init(roomID: room.id, doorRole: "前门"))
        let photo = try NodePhotoAssociation.photo(for: node)
        let bytes = try f.photos.read(relativePath: photo.filePath)
        let time = node.timeMs, count = f.track.photos.count, oldName = node.roomNameSnapshot
        room.name = "Renamed"; try f.context.save()
        let store = Phase2DataStore(context: f.context)
        try store.updateTagLocationAndRoom(node, area: a, floor: "2F", roomSelection: .init(roomID: room.id, doorRole: "前门"))
        #expect(node.roomNameSnapshot == oldName && node.floor == "2/F")
        try store.updateTagLocationAndRoom(node, area: a, floor: "2/F", roomSelection: nil)
        #expect(node.roomID == nil && node.roomNameSnapshot == nil && node.roomCodeSnapshot == nil && node.roomDoorRole == nil)
        #expect(node.timeMs == time && f.track.photos.count == count)
        #expect(SHA256.hash(data: try f.photos.read(relativePath: photo.filePath)) == SHA256.hash(data: bytes))
        #expect(f.track.tags.filter { !$0.isNode }.allSatisfy { $0.roomID == nil })
    }

    @Test("Deleting room/area or moving room preserves node-photo history and exports explicit status", arguments: ["room", "area", "move"])
    func lifecycle(_ operation: String) async throws {
        let f = try Stage4Fixture(); defer { f.dispose() }
        let (a, room) = try catalog(f)
        let roomID = room.id
        let node = try f.coordinator.saveNode(capture: capture(f), type: .classroom, note: "Synthetic",
            location: .init(area: a), roomSelection: .init(roomID: roomID))
        let photo = try NodePhotoAssociation.photo(for: node)
        f.clock.wall = 9000; try await f.coordinator.stop()
        let store = Phase2DataStore(context: f.context)
        switch operation {
        case "room": try store.deleteRoom(room)
        case "area": try store.deleteAreaPreservingContents(a)
        default:
            let b = try store.createArea(name: "Synthetic B", note: "")
            try store.updateRoom(room, name: room.name, note: room.note, area: b)
        }
        #expect(node.roomID == roomID && node.roomNameSnapshot == "Synthetic room")
        #expect(try f.photos.read(relativePath: photo.filePath) == f.jpeg)
        let snapshot = try ExportV3SnapshotBuilder(photoStorage: f.photos).build(tracks: [f.track], exportedAt: 10000)
        #expect(snapshot.tracks.first?.tags.first?.roomBinding?.status == (operation == "room" ? "missing" : "relocated"))
        #expect(!f.context.hasChanges && f.track.photos.count == 1)
    }

    @Test("Deleting node/track does not cascade into catalog or existing room Marker", arguments: ["node", "track"])
    func reverseCascade(_ kind: String) async throws {
        let f = try Stage4Fixture(); defer { f.dispose() }
        let (a, room) = try catalog(f)
        let marker = try Phase2DataStore(context: f.context).createMarker(room: room, name: "Existing", markerType: .frontDoor)
        let node = try f.coordinator.saveNode(capture: capture(f), type: .gate, note: "",
            location: .init(area: a), roomSelection: .init(roomID: room.id, doorRole: "前门"))
        f.clock.wall = 9000; try await f.coordinator.stop()
        if kind == "track" { try f.coordinator.delete(f.track) } else { try f.coordinator.deleteTag(node) }
        #expect(try f.context.fetch(FetchDescriptor<Room>()).map(\.id) == [room.id])
        #expect(room.markers.first?.id == marker.id && ownedJPEGS(f).isEmpty)
    }

    private func catalog(_ f: Stage4Fixture) throws -> (Area, Room) {
        let store = Phase2DataStore(context: f.context)
        let a = try store.createArea(name: "Synthetic A", note: "", category: "测试集")
        let r = try store.createRoom(name: "Synthetic room", note: "", area: a, code: "X1", floor: "1F")
        return (a, r)
    }
    private func capture(_ f: Stage4Fixture) throws -> CapturedTrackPhoto {
        try #require(try f.coordinator.freezePhotoCapture(.success(jpegData: f.jpeg, capturedAt: 5000)))
    }
    private func ownedJPEGS(_ f: Stage4Fixture) -> [URL] {
        (FileManager.default.enumerator(at: f.root, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? [])
            .filter { $0.pathExtension == "jpg" }
    }
}
