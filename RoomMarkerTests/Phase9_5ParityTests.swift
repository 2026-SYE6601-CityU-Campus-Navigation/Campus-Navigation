import Foundation
import SwiftData
import Testing
@testable import RoomMarker

@Suite("Phase 9.5 Room and Marker sensor parity")
@MainActor
struct Phase9_5ParityTests {
    @Test("Room capture persists one complete reference snapshot")
    func completeRoomReference() async throws {
        let fixture = try Fixture()
        let room = try fixture.store.createRoom(name: "Room", note: "", area: nil, createdAt: 1)
        let capture = FakeSnapshotCapture(snapshot: completeSnapshot())

        try await workflow(capture).captureRoomReference(for: room, using: fixture.store)

        #expect(room.latitude == 22.336)
        #expect(room.longitude == 114.172)
        #expect(room.altitude == 18.5)
        #expect(room.pressureHpa == 1007.8)
        #expect(capture.captureCalls == 1)
    }

    @Test("A partial Room capture replaces the prior observation coherently")
    func partialRoomReferenceReplacesOldValues() async throws {
        let fixture = try Fixture()
        let room = Room(
            name: "Room",
            latitude: 1,
            longitude: 2,
            altitude: 3,
            pressureHpa: 4,
            createdAt: 1
        )
        fixture.context.insert(room)
        try fixture.context.save()
        let capture = FakeSnapshotCapture(snapshot: snapshot(latitude: 22.3, longitude: 114.2))

        try await workflow(capture).captureRoomReference(for: room, using: fixture.store)

        #expect(room.latitude == 22.3)
        #expect(room.longitude == 114.2)
        #expect(room.altitude == nil)
        #expect(room.pressureHpa == nil)
    }

    @Test("A Room capture with no available sensors clears the old reference")
    func emptyRoomReferenceRemainsNil() async throws {
        let fixture = try Fixture()
        let room = Room(
            name: "Room",
            latitude: 1,
            longitude: 2,
            altitude: 3,
            pressureHpa: 4,
            createdAt: 1
        )
        fixture.context.insert(room)
        try fixture.context.save()

        try await workflow(FakeSnapshotCapture(snapshot: snapshot()))
            .captureRoomReference(for: room, using: fixture.store)

        #expect(room.latitude == nil)
        #expect(room.longitude == nil)
        #expect(room.altitude == nil)
        #expect(room.pressureHpa == nil)
    }

    @Test("Marker creation persists every supported snapshot field")
    func completeMarkerCapture() async throws {
        let fixture = try Fixture()
        let room = try fixture.store.createRoom(name: "Room", note: "", area: nil, createdAt: 1)
        let marker = try await workflow(FakeSnapshotCapture(snapshot: completeSnapshot()))
            .captureAndCreateMarker(
                in: room,
                name: "Marker",
                markerType: .frontDoor,
                createdAt: 2,
                using: fixture.store
            )

        #expect(marker.latitude == 22.336)
        #expect(marker.longitude == 114.172)
        #expect(marker.altitude == 18.5)
        #expect(marker.accuracy == 4.25)
        #expect(marker.pressureHpa == 1007.8)
        #expect(marker.magneticX == 11)
        #expect(marker.magneticY == -8)
        #expect(marker.magneticZ == 42)
    }

    @Test("Marker creation accepts location-only data")
    func locationOnlyMarker() async throws {
        let fixture = try Fixture()
        let marker = try await makeMarker(
            snapshot: snapshot(latitude: 22.3, longitude: 114.2, altitude: 9, accuracy: 5),
            fixture: fixture
        )

        #expect(marker.latitude == 22.3)
        #expect(marker.longitude == 114.2)
        #expect(marker.altitude == 9)
        #expect(marker.accuracy == 5)
        #expect(marker.pressureHpa == nil)
        #expect(marker.magneticX == nil)
        #expect(marker.magneticY == nil)
        #expect(marker.magneticZ == nil)
    }

    @Test("Marker creation accepts pressure and magnetometer without location")
    func pressureAndMagnetometerMarker() async throws {
        let fixture = try Fixture()
        let marker = try await makeMarker(
            snapshot: snapshot(pressureHpa: 1005, magneticX: 1, magneticY: 2, magneticZ: 3),
            fixture: fixture
        )

        #expect(marker.latitude == nil)
        #expect(marker.longitude == nil)
        #expect(marker.altitude == nil)
        #expect(marker.accuracy == nil)
        #expect(marker.pressureHpa == 1005)
        #expect(marker.magneticX == 1)
        #expect(marker.magneticY == 2)
        #expect(marker.magneticZ == 3)
    }

    @Test("Marker creation succeeds when no sensor is available")
    func emptyMarkerSnapshot() async throws {
        let fixture = try Fixture()
        let marker = try await makeMarker(snapshot: snapshot(), fixture: fixture)

        #expect(marker.name == "Marker")
        #expect(marker.latitude == nil)
        #expect(marker.longitude == nil)
        #expect(marker.altitude == nil)
        #expect(marker.accuracy == nil)
        #expect(marker.pressureHpa == nil)
        #expect(marker.magneticX == nil)
        #expect(marker.magneticY == nil)
        #expect(marker.magneticZ == nil)
    }

    @Test("No missing Room or Marker measurement becomes zero")
    func missingValuesNeverBecomeZero() async throws {
        let fixture = try Fixture()
        let room = try fixture.store.createRoom(name: "Room", note: "", area: nil, createdAt: 1)
        try await workflow(FakeSnapshotCapture(snapshot: snapshot()))
            .captureRoomReference(for: room, using: fixture.store)
        let marker = try await makeMarker(snapshot: snapshot(), fixture: fixture)

        #expect([room.latitude, room.longitude, room.altitude, room.pressureHpa].allSatisfy { $0 == nil })
        #expect([
            marker.latitude, marker.longitude, marker.altitude, marker.accuracy,
            marker.pressureHpa, marker.magneticX, marker.magneticY, marker.magneticZ,
        ].allSatisfy { $0 == nil })
    }

    @Test("Marker name and type edits preserve captured sensor values")
    func markerEditingPreservesSnapshot() async throws {
        let fixture = try Fixture()
        let room = try fixture.store.createRoom(name: "Room", note: "", area: nil, createdAt: 1)
        let marker = try fixture.store.createMarker(
            room: room,
            name: "Old",
            markerType: .frontDoor,
            snapshot: completeSnapshot(),
            createdAt: 2
        )

        try fixture.store.updateMarker(marker, name: "New", markerType: .window)

        #expect(marker.name == "New")
        #expect(marker.markerType == .window)
        #expect(marker.latitude == 22.336)
        #expect(marker.longitude == 114.172)
        #expect(marker.altitude == 18.5)
        #expect(marker.accuracy == 4.25)
        #expect(marker.pressureHpa == 1007.8)
        #expect(marker.magneticX == 11)
        #expect(marker.magneticY == -8)
        #expect(marker.magneticZ == 42)
    }

    @Test("Location denial still permits Marker creation with unavailable fields")
    func deniedLocationDoesNotBlockMarker() async throws {
        let denied = SensorSnapshot(
            capturedAt: 10,
            latitude: nil,
            longitude: nil,
            altitude: nil,
            accuracy: nil,
            pressureHpa: 1001,
            magneticX: nil,
            magneticY: nil,
            magneticZ: nil,
            headingDeg: nil,
            outcomes: SensorSnapshotOutcomes(
                location: .permissionDenied,
                pressure: .available,
                magnetometer: .unsupported,
                heading: .permissionDenied
            )
        )

        let fixture = try Fixture()
        let marker = try await makeMarker(snapshot: denied, fixture: fixture)

        #expect(marker.latitude == nil)
        #expect(marker.longitude == nil)
        #expect(marker.pressureHpa == 1001)
    }

    @Test("Production snapshot service acquires and releases one shared hub consumer")
    func sharedSnapshotLifecycle() async throws {
        let hub = ParityFakeSensorHub(state: completeState())
        let service = SensorSnapshotService(
            hub: hub,
            timeout: .milliseconds(20),
            pollingInterval: .milliseconds(1),
            nowMilliseconds: { 10 }
        )
        let fixture = try Fixture()
        let room = try fixture.store.createRoom(name: "Room", note: "", area: nil, createdAt: 1)

        try await workflow(service).captureRoomReference(for: room, using: fixture.store)

        #expect(hub.startCalls == 1)
        #expect(hub.stopCalls == 1)
        #expect(hub.activeConsumerCount == 0)
    }

    @Test("Room deletion still cascades captured Markers")
    func roomDeletionSemanticsRemainUnchanged() async throws {
        let fixture = try Fixture()
        let room = try fixture.store.createRoom(name: "Room", note: "", area: nil, createdAt: 1)
        try fixture.store.createMarker(
            room: room,
            name: "Marker",
            markerType: .custom,
            snapshot: completeSnapshot(),
            createdAt: 2
        )

        try fixture.store.deleteRoom(room)

        #expect(try fixture.context.fetch(FetchDescriptor<Room>()).isEmpty)
        #expect(try fixture.context.fetch(FetchDescriptor<Marker>()).isEmpty)
    }

    @Test("Individual Marker deletion remains unchanged after capture")
    func markerDeletionSemanticsRemainUnchanged() async throws {
        let fixture = try Fixture()
        let room = try fixture.store.createRoom(name: "Room", note: "", area: nil, createdAt: 1)
        let marker = try fixture.store.createMarker(
            room: room,
            name: "Marker",
            markerType: .custom,
            snapshot: completeSnapshot(),
            createdAt: 2
        )

        try fixture.store.deleteMarker(marker)

        #expect(try fixture.context.fetch(FetchDescriptor<Room>()).count == 1)
        #expect(try fixture.context.fetch(FetchDescriptor<Marker>()).isEmpty)
    }

    private func makeMarker(
        snapshot: SensorSnapshot,
        fixture: Fixture
    ) async throws -> Marker {
        let room = try fixture.store.createRoom(name: "Room", note: "", area: nil, createdAt: 1)
        return try await workflow(FakeSnapshotCapture(snapshot: snapshot))
            .captureAndCreateMarker(
                in: room,
                name: "Marker",
                markerType: .frontDoor,
                createdAt: 2,
                using: fixture.store
            )
    }

    private func workflow(_ capture: any SensorSnapshotCapturing) -> RoomMarkerSnapshotWorkflow {
        RoomMarkerSnapshotWorkflow(snapshotService: capture)
    }

    private func completeSnapshot() -> SensorSnapshot {
        snapshot(
            latitude: 22.336,
            longitude: 114.172,
            altitude: 18.5,
            accuracy: 4.25,
            pressureHpa: 1007.8,
            magneticX: 11,
            magneticY: -8,
            magneticZ: 42
        )
    }

    private func snapshot(
        latitude: Double? = nil,
        longitude: Double? = nil,
        altitude: Double? = nil,
        accuracy: Double? = nil,
        pressureHpa: Double? = nil,
        magneticX: Double? = nil,
        magneticY: Double? = nil,
        magneticZ: Double? = nil
    ) -> SensorSnapshot {
        SensorSnapshot(
            capturedAt: 10,
            latitude: latitude,
            longitude: longitude,
            altitude: altitude,
            accuracy: accuracy,
            pressureHpa: pressureHpa,
            magneticX: magneticX,
            magneticY: magneticY,
            magneticZ: magneticZ,
            headingDeg: nil,
            outcomes: SensorSnapshotOutcomes(
                location: latitude == nil ? .unavailable : .available,
                pressure: pressureHpa == nil ? .unsupported : .available,
                magnetometer: magneticX == nil ? .unsupported : .available,
                heading: .unsupported
            )
        )
    }

    private func completeState() -> LiveSensorState {
        let date = Date(timeIntervalSince1970: 1)
        return LiveSensorState(
            permission: .authorizedWhenInUse,
            location: .available(TimestampedSensorValue(
                value: LocationReading(
                    latitude: 22.336,
                    longitude: 114.172,
                    altitude: 18.5,
                    horizontalAccuracy: 4.25
                ),
                capturedAt: date
            )),
            pressureHpa: .available(TimestampedSensorValue(value: 1007.8, capturedAt: date)),
            magneticField: .available(TimestampedSensorValue(
                value: MagneticFieldReading(x: 11, y: -8, z: 42),
                capturedAt: date
            )),
            headingDeg: .unsupported
        )
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

@MainActor
private final class FakeSnapshotCapture: SensorSnapshotCapturing {
    let snapshot: SensorSnapshot
    private(set) var captureCalls = 0

    init(snapshot: SensorSnapshot) {
        self.snapshot = snapshot
    }

    func capture() async throws -> SensorSnapshot {
        captureCalls += 1
        return snapshot
    }
}

@MainActor
private final class ParityFakeSensorHub: SensorHubProtocol {
    var state: LiveSensorState
    private(set) var consumers: Set<SensorConsumer> = []
    private(set) var startCalls = 0
    private(set) var stopCalls = 0

    var activeConsumerCount: Int { consumers.count }

    init(state: LiveSensorState) {
        self.state = state
    }

    func start(consumer: SensorConsumer, requestLocationAuthorization: Bool) {
        startCalls += 1
        consumers.insert(consumer)
    }

    func requestLocationAuthorization() {}

    func stop(consumer: SensorConsumer) {
        stopCalls += 1
        consumers.remove(consumer)
    }
}
