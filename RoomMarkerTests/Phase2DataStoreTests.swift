import SwiftData
import Testing
@testable import RoomMarker

@Suite("Phase 2 CRUD operations")
@MainActor
struct Phase2DataStoreTests {
    @Test("Creating an Area trims persisted input")
    func createArea() throws {
        let fixture = try Fixture()

        let area = try fixture.store.createArea(
            name: "  教学楼A  ",
            note: "  Phase 2 test area  ",
            createdAt: 10
        )

        #expect(area.name == "教学楼A")
        #expect(area.note == "Phase 2 test area")
        #expect(try fixture.context.fetch(FetchDescriptor<Area>()).count == 1)
    }

    @Test("Editing an Area updates trimmed values")
    func editArea() throws {
        let fixture = try Fixture()
        let area = try fixture.store.createArea(name: "Old", note: "", createdAt: 10)

        try fixture.store.updateArea(area, name: "  New  ", note: "  Updated  ")

        #expect(area.name == "New")
        #expect(area.note == "Updated")
    }

    @Test("Area names containing only whitespace are rejected")
    func areaNameValidation() throws {
        let fixture = try Fixture()

        #expect(throws: Phase2ValidationError.emptyName) {
            try fixture.store.createArea(name: " \n\t ", note: "")
        }
        #expect(try fixture.context.fetch(FetchDescriptor<Area>()).isEmpty)
    }

    @Test("Creating a Room can assign it to an Area")
    func createAssignedRoom() throws {
        let fixture = try Fixture()
        let area = try fixture.store.createArea(name: "Area", note: "", createdAt: 10)

        let room = try fixture.store.createRoom(name: "A101", note: "", area: area, createdAt: 20)

        #expect(room.area?.id == area.id)
        #expect(area.rooms.contains { $0.id == room.id })
    }

    @Test("Creating an unassigned Room does not create a fake Area")
    func createUnassignedRoom() throws {
        let fixture = try Fixture()

        let room = try fixture.store.createRoom(name: "A101", note: "", area: nil, createdAt: 20)

        #expect(room.area == nil)
        #expect(try fixture.context.fetch(FetchDescriptor<Area>()).isEmpty)
    }

    @Test("Editing a Room changes its Area assignment")
    func changeRoomArea() throws {
        let fixture = try Fixture()
        let first = try fixture.store.createArea(name: "First", note: "", createdAt: 10)
        let second = try fixture.store.createArea(name: "Second", note: "", createdAt: 11)
        let room = try fixture.store.createRoom(name: "Room", note: "", area: first, createdAt: 20)

        try fixture.store.updateRoom(room, name: room.name, note: room.note, area: second)
        #expect(room.area?.id == second.id)

        try fixture.store.updateRoom(room, name: room.name, note: room.note, area: nil)
        #expect(room.area == nil)
    }

    @Test("Deleting an Area preserves its Rooms as unassigned")
    func deleteAreaPreservesRooms() throws {
        let fixture = try Fixture()
        let area = try fixture.store.createArea(name: "Area", note: "", createdAt: 10)
        let room = try fixture.store.createRoom(name: "Room", note: "", area: area, createdAt: 20)

        try fixture.store.deleteAreaPreservingContents(area)

        #expect(try fixture.context.fetch(FetchDescriptor<Area>()).isEmpty)
        #expect(room.area == nil)
        #expect(try fixture.context.fetch(FetchDescriptor<Room>()).count == 1)
    }

    @Test("Creating a Marker preserves its compatible raw type")
    func createMarker() throws {
        let fixture = try Fixture()
        let room = try fixture.store.createRoom(name: "Room", note: "", area: nil, createdAt: 20)

        let marker = try fixture.store.createMarker(
            room: room,
            name: "正门",
            markerType: .frontDoor,
            createdAt: 30
        )

        #expect(marker.markerTypeRawValue == "前门")
        #expect(marker.markerType == .frontDoor)
        #expect(MarkerType(rawValue: marker.markerTypeRawValue) != nil)
    }

    @Test("Deleting a Room removes its associated Markers")
    func deleteRoomCascadesMarkers() throws {
        let fixture = try Fixture()
        let room = try fixture.store.createRoom(name: "Room", note: "", area: nil, createdAt: 20)
        try fixture.store.createMarker(room: room, name: "Marker", markerType: .custom, createdAt: 30)

        try fixture.store.deleteRoom(room)

        #expect(try fixture.context.fetch(FetchDescriptor<Room>()).isEmpty)
        #expect(try fixture.context.fetch(FetchDescriptor<Marker>()).isEmpty)
    }

    @Test("Phase 2 creation does not fabricate sensor values")
    func creationLeavesSensorsUnavailable() throws {
        let fixture = try Fixture()
        let room = try fixture.store.createRoom(name: "Room", note: "", area: nil, createdAt: 20)
        let marker = try fixture.store.createMarker(
            room: room,
            name: "Marker",
            markerType: .frontDoor,
            createdAt: 30
        )

        #expect(room.latitude == nil)
        #expect(room.longitude == nil)
        #expect(room.altitude == nil)
        #expect(room.pressureHpa == nil)
        #expect(marker.latitude == nil)
        #expect(marker.longitude == nil)
        #expect(marker.altitude == nil)
        #expect(marker.accuracy == nil)
        #expect(marker.pressureHpa == nil)
        #expect(marker.magneticX == nil)
        #expect(marker.magneticY == nil)
        #expect(marker.magneticZ == nil)
    }

    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let store: Phase2DataStore

        init() throws {
            container = try RoomMarkerModelContainer.make(inMemory: true)
            context = container.mainContext
            store = Phase2DataStore(context: context)
        }
    }
}
