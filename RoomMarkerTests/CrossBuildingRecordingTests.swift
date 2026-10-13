import Foundation
import SwiftData
import Testing
@testable import RoomMarker

@Suite("Cross-building recording and tag context")
@MainActor
struct CrossBuildingRecordingTests {
    @Test("A new recording can start without an Area")
    func startsWithoutArea() throws {
        let fixture = try CrossBuildingFixture()

        try fixture.coordinator.start(name: "  Global walk  ")

        let track = try #require(fixture.coordinator.activeTrack)
        #expect(track.name == "Global walk")
        #expect(track.area == nil)
        #expect(track.isGlobalRecording)
        #expect(fixture.coordinator.isRecording)
        let tag = try fixture.coordinator.addTag(type: .door, note: "")
        #expect(tag.areaID == nil)
        #expect(tag.areaStateRawValue == "unassigned")
        #expect(tag.floor.isEmpty)
    }

    @Test("The start Area seeds only the first tag, not Track ownership")
    func startAreaIsOnlyInitialContext() throws {
        let fixture = try CrossBuildingFixture()
        let area = try fixture.insertArea("Building A")

        try fixture.coordinator.start(name: "Cross-building walk", area: area)
        let tag = try fixture.coordinator.addTag(type: .door, note: "Entrance")

        let track = try #require(fixture.coordinator.activeTrack)
        #expect(track.area == nil)
        #expect(track.isGlobalRecording)
        #expect(tag.track?.id == track.id)
        #expect(tag.areaID == area.id)
        #expect(tag.areaStateRawValue == "assigned")
        #expect(tag.floor.isEmpty)
    }

    @Test("One global Track stores nodes in different Areas and floors")
    func switchesAreaWithinOneTrack() throws {
        let fixture = try CrossBuildingFixture()
        let areaA = try fixture.insertArea("Building A")
        let areaB = try fixture.insertArea("Building B")
        try fixture.coordinator.start(name: "Two buildings", area: areaA)

        let first = try fixture.coordinator.addTag(type: .door, note: "", area: areaA, floor: "G")
        let second = try fixture.coordinator.addTag(type: .stairs, note: "", area: areaB, floor: "  2/F  ")

        #expect(first.track?.id == second.track?.id)
        #expect(first.areaID == areaA.id)
        #expect(first.floor == "G")
        #expect(second.areaID == areaB.id)
        #expect(second.floor == "2/F")
        #expect(try fixture.context.fetchCount(FetchDescriptor<Track>()) == 1)
        #expect(fixture.coordinator.activeTrack?.area == nil)
    }

    @Test("Inheritance follows successful capture order at identical timestamps")
    func inheritsCaptureOrderNotTimestampOrUUID() throws {
        let fixture = try CrossBuildingFixture()
        let areaA = try fixture.insertArea("Building A")
        let areaB = try fixture.insertArea("Building B")
        try fixture.coordinator.start(name: "Same timestamp", area: areaA)
        let first = try fixture.coordinator.addTag(type: .door, note: "", area: areaA, floor: "1")
        let second = try fixture.coordinator.addTag(type: .stairs, note: "", area: areaB, floor: "3")

        let inherited = try fixture.coordinator.addTag(type: .classroom, note: "")

        #expect(first.timeMs == second.timeMs)
        #expect(second.timeMs == inherited.timeMs)
        #expect(inherited.areaID == areaB.id)
        #expect(inherited.areaStateRawValue == "assigned")
        #expect(inherited.floor == "3")
    }

    @Test("Explicit unassigned Area and empty floor remain the inheritance context")
    func explicitUnassignedAndEmptyFloorRemain() throws {
        let fixture = try CrossBuildingFixture()
        let area = try fixture.insertArea("Building A")
        try fixture.coordinator.start(name: "Outdoor connection", area: area)
        _ = try fixture.coordinator.addTag(type: .stairs, note: "", area: area, floor: "4")
        let outside = try fixture.coordinator.addTag(type: .door, note: "", area: nil, floor: "")

        let inherited = try fixture.coordinator.addTag(type: .gate, note: "")

        #expect(outside.areaID == nil)
        #expect(outside.areaStateRawValue == "unassigned")
        #expect(outside.floor.isEmpty)
        #expect(inherited.areaID == nil)
        #expect(inherited.areaStateRawValue == "unassigned")
        #expect(inherited.floor.isEmpty)
    }

    @Test("An explicit empty floor is not replaced by an older nonempty floor")
    func explicitEmptyFloorRemainsWithinArea() throws {
        let fixture = try CrossBuildingFixture()
        let area = try fixture.insertArea("Building A")
        try fixture.coordinator.start(name: "Unknown floor", area: area)
        _ = try fixture.coordinator.addTag(type: .stairs, note: "", area: area, floor: "7")
        _ = try fixture.coordinator.addTag(type: .door, note: "", area: area, floor: "   ")

        let inherited = try fixture.coordinator.addTag(type: .gate, note: "")

        #expect(inherited.areaID == area.id)
        #expect(inherited.areaStateRawValue == "assigned")
        #expect(inherited.floor.isEmpty)
    }

    @Test("A failed tag save does not replace the last successful context")
    func failedTagDoesNotAdvanceContext() throws {
        let fixture = try CrossBuildingFixture()
        let areaA = try fixture.insertArea("Building A")
        let areaB = try fixture.insertArea("Building B")
        try fixture.coordinator.start(name: "Save retry", area: areaA)
        _ = try fixture.coordinator.addTag(type: .door, note: "", area: areaA, floor: "1")
        fixture.media.failNextTag = true

        #expect(throws: CrossBuildingFailure.tagSave) {
            try fixture.coordinator.addTag(type: .stairs, note: "", area: areaB, floor: "9")
        }
        let inherited = try fixture.coordinator.addTag(type: .gate, note: "")

        #expect(inherited.areaID == areaA.id)
        #expect(inherited.floor == "1")
        #expect(try fixture.context.fetchCount(FetchDescriptor<TrackTag>()) == 2)
        #expect(fixture.coordinator.isRecording)
    }

    @Test("Editing the latest saved tag updates subsequent inheritance")
    func latestTagEditUpdatesContext() throws {
        let fixture = try CrossBuildingFixture()
        let areaA = try fixture.insertArea("Building A")
        let areaB = try fixture.insertArea("Building B")
        try fixture.coordinator.start(name: "Edited node", area: areaA)
        let latest = try fixture.coordinator.addTag(type: .door, note: "", area: areaA, floor: "1")
        latest.areaID = areaB.id
        latest.areaStateRawValue = "assigned"
        latest.floor = "5"
        try fixture.context.save()

        let inherited = try fixture.coordinator.addTag(type: .stairs, note: "")

        #expect(inherited.areaID == areaB.id)
        #expect(inherited.floor == "5")
    }

    @Test("Deleting the latest tag restores the prior successful tag context")
    func latestTagDeleteRestoresPreviousContext() throws {
        let fixture = try CrossBuildingFixture()
        let areaA = try fixture.insertArea("Building A")
        let areaB = try fixture.insertArea("Building B")
        try fixture.coordinator.start(name: "Deleted node", area: areaA)
        _ = try fixture.coordinator.addTag(type: .door, note: "", area: areaA, floor: "1")
        let latest = try fixture.coordinator.addTag(type: .stairs, note: "", area: areaB, floor: "8")

        try fixture.coordinator.deleteTag(latest)
        let inherited = try fixture.coordinator.addTag(type: .gate, note: "")

        #expect(inherited.areaID == areaA.id)
        #expect(inherited.floor == "1")
        #expect(try fixture.context.fetchCount(FetchDescriptor<TrackTag>()) == 2)
    }

    @Test("A deleted initial Area is downgraded rather than resurrected")
    func deletedInitialAreaCannotBecomeDanglingTagID() throws {
        let fixture = try CrossBuildingFixture()
        let area = try fixture.insertArea("Temporary building")
        try fixture.coordinator.start(name: "Area removed", area: area)
        fixture.context.delete(area)
        try fixture.context.save()

        let tag = try fixture.coordinator.addTag(type: .door, note: "")
        let inherited = try fixture.coordinator.addTag(type: .gate, note: "")

        #expect(tag.areaID == nil)
        #expect(tag.areaStateRawValue == "unassigned")
        #expect(inherited.areaID == nil)
        #expect(inherited.areaStateRawValue == "unassigned")
        #expect(fixture.coordinator.tagLocationContext.areaID == nil)
        #expect(try fixture.context.fetchCount(FetchDescriptor<Area>()) == 0)
    }

    @Test("A deleted latest-tag Area is validated again before inheritance persists")
    func deletedLatestAreaCannotBecomeDanglingTagID() throws {
        let fixture = try CrossBuildingFixture()
        let area = try fixture.insertArea("Temporary building")
        try fixture.coordinator.start(name: "Context removed")
        _ = try fixture.coordinator.addTag(type: .stairs, note: "", area: area, floor: "2")
        fixture.context.delete(area)
        try fixture.context.save()

        let inherited = try fixture.coordinator.addTag(type: .door, note: "")

        #expect(inherited.areaID == nil)
        #expect(inherited.areaStateRawValue == "unassigned")
        #expect(inherited.floor == "2")
        #expect(fixture.coordinator.tagLocationContext.areaStateRawValue == "unassigned")
    }

    @Test("Global Track and tag location fields survive a fresh persistence context")
    func fieldsPersistAndDoNotFabricateSensorValues() throws {
        let fixture = try CrossBuildingFixture()
        let area = try fixture.insertArea("Building A")
        try fixture.coordinator.start(name: "Persisted walk")
        let tag = try fixture.coordinator.addTag(type: .classroom, note: "  Node  ", area: area, floor: "6")

        let reopened = ModelContext(fixture.container)
        let persistedTag = try #require(reopened.fetch(FetchDescriptor<TrackTag>()).first)
        let persistedTrack = try #require(reopened.fetch(FetchDescriptor<Track>()).first)

        #expect(persistedTag.id == tag.id)
        #expect(persistedTag.areaID == area.id)
        #expect(persistedTag.areaStateRawValue == "assigned")
        #expect(persistedTag.floor == "6")
        #expect(persistedTag.note == "Node")
        #expect(persistedTag.latitude == nil)
        #expect(persistedTag.longitude == nil)
        #expect(persistedTag.altitude == nil)
        #expect(persistedTag.headingDeg == nil)
        #expect(persistedTrack.area == nil)
        #expect(persistedTrack.isGlobalRecording)
    }

    @Test("A new recording does not inherit the previous recording context")
    func restartingResetsContext() async throws {
        let fixture = try CrossBuildingFixture()
        let area = try fixture.insertArea("Building A")
        try fixture.coordinator.start(name: "First walk", area: area)
        _ = try fixture.coordinator.addTag(type: .stairs, note: "", area: area, floor: "3")
        try await fixture.coordinator.stop()

        try fixture.coordinator.start(name: "Second walk")
        let tag = try fixture.coordinator.addTag(type: .door, note: "")

        #expect(tag.areaID == nil)
        #expect(tag.areaStateRawValue == "unassigned")
        #expect(tag.floor.isEmpty)
        #expect(try fixture.context.fetchCount(FetchDescriptor<Track>()) == 2)
    }

    @Test("A legacy draft without area evidence remains unknown")
    func legacyDraftDoesNotInventLocationContext() throws {
        let fixture = try CrossBuildingFixture()
        let track = try fixture.store.createTrack(name: "Draft compatibility", area: nil, startedAt: 1)
        let draft = TrackTagDraft(
            timeMs: 2,
            tagType: .door,
            note: "",
            metadata: TrackCaptureMetadata(latitude: nil, longitude: nil, altitude: nil, headingDeg: nil),
            createdAt: 2
        )

        let tag = try fixture.store.createTag(draft, for: track)

        #expect(draft.areaStateRawValue == "unknown")
        #expect(tag.areaID == nil)
        #expect(tag.areaStateRawValue == "unknown")
        #expect(tag.floor.isEmpty)
    }
}

@MainActor
private final class CrossBuildingFixture {
    let container: ModelContainer
    let context: ModelContext
    let store: SwiftDataRecordingStore
    let media: CrossBuildingMediaStore
    let coordinator: RecordingCoordinator

    init() throws {
        let container = try RoomMarkerModelContainer.make(inMemory: true)
        let context = container.mainContext
        let store = SwiftDataRecordingStore(context: context)
        let media = CrossBuildingMediaStore(store: store)
        self.container = container
        self.context = context
        self.store = store
        self.media = media
        coordinator = RecordingCoordinator(
            hub: CrossBuildingSensorHub(),
            ticker: CrossBuildingTicker(),
            persistence: store,
            mediaPersistence: media,
            nowMilliseconds: { 1_000 }
        )
    }

    func insertArea(_ name: String) throws -> Area {
        let area = Area(name: name, createdAt: 1)
        context.insert(area)
        try context.save()
        return area
    }
}

@MainActor
private final class CrossBuildingSensorHub: SensorHubProtocol {
    let state: LiveSensorState = .waiting
    private var consumers: Set<SensorConsumer> = []
    var activeConsumerCount: Int { consumers.count }

    func start(consumer: SensorConsumer, requestLocationAuthorization: Bool) {
        consumers.insert(consumer)
    }

    func requestLocationAuthorization() {}

    func stop(consumer: SensorConsumer) {
        consumers.remove(consumer)
    }
}

@MainActor
private final class CrossBuildingTicker: RecordingTicking {
    private var handler: Handler?

    func start(handler: @escaping Handler) {
        self.handler = handler
    }

    func stop() async {
        handler = nil
    }
}

private enum CrossBuildingFailure: Error, Equatable {
    case tagSave
}

@MainActor
private final class CrossBuildingMediaStore: TrackMediaPersisting {
    let store: SwiftDataRecordingStore
    var failNextTag = false

    init(store: SwiftDataRecordingStore) {
        self.store = store
    }

    func createTag(_ draft: TrackTagDraft, for track: Track) throws -> TrackTag {
        if failNextTag {
            failNextTag = false
            throw CrossBuildingFailure.tagSave
        }
        return try store.createTag(draft, for: track)
    }

    func createPhoto(_ draft: TrackPhotoDraft, for track: Track) throws -> TrackPhoto {
        try store.createPhoto(draft, for: track)
    }

    func deleteTag(_ tag: TrackTag) throws {
        try store.deleteTag(tag)
    }

    func deletePhoto(_ photo: TrackPhoto) throws {
        try store.deletePhoto(photo)
    }
}
