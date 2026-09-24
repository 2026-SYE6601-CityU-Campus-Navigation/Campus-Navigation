import Foundation
import SwiftData
import Testing
@testable import RoomMarker

@Suite("Phase 4 foreground recording")
@MainActor
struct Phase4RecordingTests {
    @Test("Recording follows the explicit clean state path")
    func cleanStateTransitions() async throws {
        let fixture = makeFixture()

        try fixture.coordinator.start(name: " Walk ", area: fixture.area)
        try await fixture.coordinator.stop()

        #expect(fixture.coordinator.transitionHistory == [
            .idle, .preparing, .recording, .stopping, .idle,
        ])
        #expect(fixture.store.tracks.first?.name == "Walk")
    }

    @Test("A second start is rejected without a duplicate Track")
    func doubleStartRejected() throws {
        let fixture = makeFixture()
        try fixture.coordinator.start(name: "First", area: fixture.area)

        #expect(throws: RecordingError.alreadyActive) {
            try fixture.coordinator.start(name: "Second", area: fixture.area)
        }
        #expect(fixture.store.tracks.count == 1)
        #expect(fixture.ticker.startCalls == 1)
    }

    @Test("Stopping while idle is rejected safely")
    func idleStopRejected() async {
        let fixture = makeFixture()
        do {
            try await fixture.coordinator.stop()
            Issue.record("Expected notRecording")
        } catch let error as RecordingError {
            #expect(error == .notRecording)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(fixture.hub.stopCalls == 0)
    }

    @Test("One manual tick creates exactly one logical sample")
    func oneTickOneSample() async throws {
        let fixture = makeFixture()
        try fixture.coordinator.start(name: "One", area: fixture.area)

        await fixture.ticker.fire(at: 1_001)

        #expect(fixture.coordinator.currentSampleCount == 1)
        #expect(fixture.store.persistedDrafts.isEmpty)
    }

    @Test("Ordered ticks remain ordered after final flush")
    func orderedTicksPersistInOrder() async throws {
        let fixture = makeFixture()
        try fixture.coordinator.start(name: "Ordered", area: fixture.area)
        for time in [2_000, 3_000, 4_000] {
            await fixture.ticker.fire(at: Int64(time))
        }

        try await fixture.coordinator.stop()

        #expect(fixture.store.persistedDrafts.map(\.timeMs) == [2_000, 3_000, 4_000])
    }

    @Test("A point may contain only the available sensors")
    func partialPoint() async throws {
        let fixture = makeFixture(state: LiveSensorState(
            permission: .authorizedWhenInUse,
            location: available(LocationReading(
                latitude: 22.3,
                longitude: 114.2,
                altitude: nil,
                horizontalAccuracy: 8
            )),
            pressureHpa: .unsupported,
            magneticField: .unavailable,
            headingDeg: available(45)
        ))
        try fixture.coordinator.start(name: "Partial", area: fixture.area)
        await fixture.ticker.fire(at: 2_000)
        try await fixture.coordinator.stop()

        let point = try #require(fixture.store.persistedDrafts.first)
        #expect(point.latitude == 22.3)
        #expect(point.longitude == 114.2)
        #expect(point.accuracy == 8)
        #expect(point.pressureHpa == nil)
        #expect(point.magneticX == nil)
        #expect(point.headingDeg == 45)
    }

    @Test("Stale readings are omitted")
    func staleReadingsExcluded() {
        let date = Date(timeIntervalSince1970: 1)
        let state = LiveSensorState(
            permission: .authorizedWhenInUse,
            location: .stale(TimestampedSensorValue(
                value: LocationReading(latitude: 1, longitude: 2, altitude: 3, horizontalAccuracy: 4),
                capturedAt: date
            )),
            pressureHpa: available(1001),
            magneticField: .stale(TimestampedSensorValue(
                value: MagneticFieldReading(x: 5, y: 6, z: 7),
                capturedAt: date
            )),
            headingDeg: .stale(TimestampedSensorValue(value: 90, capturedAt: date))
        )

        let draft = SampleAssembler().assemble(timeMs: 9, state: state)

        #expect(draft.latitude == nil)
        #expect(draft.longitude == nil)
        #expect(draft.pressureHpa == 1001)
        #expect(draft.magneticX == nil)
        #expect(draft.headingDeg == nil)
    }

    @Test("Unavailable sensors never become numeric zero")
    func missingSensorsRemainNil() {
        let draft = SampleAssembler().assemble(timeMs: 9, state: .waiting)

        #expect(draft.latitude == nil)
        #expect(draft.longitude == nil)
        #expect(draft.altitude == nil)
        #expect(draft.accuracy == nil)
        #expect(draft.pressureHpa == nil)
        #expect(draft.magneticX == nil)
        #expect(draft.magneticY == nil)
        #expect(draft.magneticZ == nil)
        #expect(draft.headingDeg == nil)
    }

    @Test("The fifth sample triggers one five-point batch")
    func fifthSampleFlushesBatch() async throws {
        let fixture = makeFixture()
        try fixture.coordinator.start(name: "Five", area: fixture.area)
        await fire(5, ticker: fixture.ticker)

        #expect(fixture.store.batches.map(\.count) == [5])
        #expect(fixture.store.saveBatchCalls == 1)
    }

    @Test("Four samples remain pending")
    func fourSamplesStayPending() async throws {
        let fixture = makeFixture()
        try fixture.coordinator.start(name: "Four", area: fixture.area)
        await fire(4, ticker: fixture.ticker)

        #expect(fixture.coordinator.currentSampleCount == 4)
        #expect(fixture.store.batches.isEmpty)
    }

    @Test("Stop flushes every tail size from one through four")
    func stopFlushesTail() async throws {
        for count in 1...4 {
            let fixture = makeFixture()
            try fixture.coordinator.start(name: "Tail", area: fixture.area)
            await fire(count, ticker: fixture.ticker)
            try await fixture.coordinator.stop()

            #expect(fixture.store.batches.map(\.count) == [count])
            #expect(fixture.store.persistedDrafts.count == count)
        }
    }

    @Test("Ten samples produce two complete batches")
    func tenSamplesTwoBatches() async throws {
        let fixture = makeFixture()
        try fixture.coordinator.start(name: "Ten", area: fixture.area)
        await fire(10, ticker: fixture.ticker)

        #expect(fixture.store.batches.map(\.count) == [5, 5])
        #expect(fixture.store.persistedDrafts.count == 10)
    }

    @Test("Batch boundaries introduce no duplicate points")
    func noDuplicatesAcrossFlushes() async throws {
        let fixture = makeFixture()
        try fixture.coordinator.start(name: "Unique", area: fixture.area)
        await fire(12, ticker: fixture.ticker)
        try await fixture.coordinator.stop()

        let times = fixture.store.persistedDrafts.map(\.timeMs)
        #expect(times.count == 12)
        #expect(Set(times).count == 12)
        #expect(fixture.store.batches.map(\.count) == [5, 5, 2])
    }

    @Test("A delivered tick adjacent to stop is persisted once")
    func stopNearTickIsRaceSafe() async throws {
        let fixture = makeFixture()
        try fixture.coordinator.start(name: "Race", area: fixture.area)

        await fixture.ticker.fire(at: 2_000)
        try await fixture.coordinator.stop()

        #expect(fixture.store.persistedDrafts.map(\.timeMs) == [2_000])
        #expect(fixture.ticker.stopCalls == 1)
    }

    @Test("A clean stop assigns endedAt after flushing")
    func cleanStopFinalizes() async throws {
        let clock = TestNow(1_000)
        let fixture = makeFixture(clock: clock)
        try fixture.coordinator.start(name: "Final", area: fixture.area)
        await fixture.ticker.fire(at: 2_000)
        clock.value = 3_000

        try await fixture.coordinator.stop()

        #expect(fixture.store.finalizedAfterDraftCount == 1)
        #expect(fixture.store.tracks.first?.endedAt == 3_000)
    }

    @Test("No point can arrive after clean finalization")
    func noPointAfterFinalization() async throws {
        let fixture = makeFixture()
        try fixture.coordinator.start(name: "Closed", area: fixture.area)
        await fixture.ticker.fire(at: 2_000)
        try await fixture.coordinator.stop()
        await fixture.ticker.fire(at: 3_000)

        #expect(fixture.store.persistedDrafts.map(\.timeMs) == [2_000])
    }

    @Test("A persistence failure preserves an incomplete Track")
    func failureLeavesIncompleteTrack() async throws {
        let fixture = makeFixture()
        fixture.store.failOnAppend = true
        try fixture.coordinator.start(name: "Interrupted", area: fixture.area)
        await fire(5, ticker: fixture.ticker)

        #expect(fixture.coordinator.state.phase == .failed)
        #expect(fixture.store.tracks.first?.endedAt == nil)
        #expect(fixture.store.deleteCalls == 0)
    }

    @Test("Deleting through the Phase 4 store cascades TrackPoints")
    func deleteCascadesTrackPoints() throws {
        let container = try RoomMarkerModelContainer.make(inMemory: true)
        let context = container.mainContext
        let area = Area(name: "Area", createdAt: 1)
        context.insert(area)
        try context.save()
        let store = SwiftDataRecordingStore(context: context)
        let track = try store.createTrack(name: "Track", area: area, startedAt: 2)
        try store.append([draft(timeMs: 3), draft(timeMs: 4)], to: track)

        try store.delete(track)

        #expect(try context.fetch(FetchDescriptor<Track>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<TrackPoint>()).isEmpty)
    }

    @Test("The recording sensor consumer is released after stop")
    func sensorsReleasedAfterStop() async throws {
        let fixture = makeFixture()
        try fixture.coordinator.start(name: "Sensors", area: fixture.area)
        #expect(fixture.hub.consumers == [.recording])

        try await fixture.coordinator.stop()

        #expect(fixture.hub.consumers.isEmpty)
        #expect(fixture.hub.stopCalls == 1)
    }

    @Test("Track samples never contain fake Wi-Fi observations")
    func wifiAlwaysUnsupported() {
        let draft = SampleAssembler().assemble(timeMs: 1, state: completeState())

        #expect(draft.wifiAvailability == .unsupported)
        #expect(draft.wifiCount == nil)
        #expect(draft.wifiTop == nil)
    }

    @Test("Recording requires a real Area")
    func areaRequired() throws {
        let fixture = makeFixture()

        #expect(throws: RecordingError.areaRequired) {
            try fixture.coordinator.start(name: "No Area", area: nil)
        }
        #expect(fixture.store.tracks.isEmpty)
    }

    @Test("Duplicate and out-of-order ticks are ignored without backfill")
    func duplicateTicksIgnored() async throws {
        let fixture = makeFixture()
        try fixture.coordinator.start(name: "Ticks", area: fixture.area)
        await fixture.ticker.fire(at: 2_000)
        await fixture.ticker.fire(at: 2_000)
        await fixture.ticker.fire(at: 1_999)
        await fixture.ticker.fire(at: 3_000)
        try await fixture.coordinator.stop()

        #expect(fixture.store.persistedDrafts.map(\.timeMs) == [2_000, 3_000])
    }

    @Test("Stopping recording keeps another sensor consumer alive")
    func sharedSensorLeaseSurvives() async throws {
        let fixture = makeFixture()
        fixture.hub.consumers.insert(.liveSensors)
        try fixture.coordinator.start(name: "Shared", area: fixture.area)

        try await fixture.coordinator.stop()

        #expect(fixture.hub.consumers == [.liveSensors])
    }

    private func makeFixture(
        state: LiveSensorState = .waiting,
        clock: TestNow = TestNow(1_000)
    ) -> Fixture {
        let hub = ManualSensorHub(state: state)
        let ticker = ManualRecordingTicker()
        let store = FakeRecordingStore()
        let coordinator = RecordingCoordinator(
            hub: hub,
            ticker: ticker,
            persistence: store,
            nowMilliseconds: { clock.value }
        )
        return Fixture(
            coordinator: coordinator,
            hub: hub,
            ticker: ticker,
            store: store,
            area: Area(name: "Area", createdAt: 1)
        )
    }

    private func fire(_ count: Int, ticker: ManualRecordingTicker) async {
        for index in 1...count {
            await ticker.fire(at: Int64(index * 1_000))
        }
    }

    private func available<Value: Sendable>(_ value: Value) -> SensorValueState<Value> {
        .available(TimestampedSensorValue(value: value, capturedAt: Date()))
    }

    private func completeState() -> LiveSensorState {
        LiveSensorState(
            permission: .authorizedWhenInUse,
            location: available(LocationReading(
                latitude: 22.3,
                longitude: 114.2,
                altitude: 10,
                horizontalAccuracy: 4
            )),
            pressureHpa: available(1008),
            magneticField: available(MagneticFieldReading(x: 1, y: 2, z: 3)),
            headingDeg: available(90)
        )
    }

    private func draft(timeMs: Int64) -> TrackPointDraft {
        TrackPointDraft(
            timeMs: timeMs,
            latitude: nil,
            longitude: nil,
            altitude: nil,
            accuracy: nil,
            pressureHpa: nil,
            magneticX: nil,
            magneticY: nil,
            magneticZ: nil,
            headingDeg: nil,
            wifiAvailability: .unsupported,
            wifiCount: nil,
            wifiTop: nil
        )
    }
}

@MainActor
private struct Fixture {
    let coordinator: RecordingCoordinator
    let hub: ManualSensorHub
    let ticker: ManualRecordingTicker
    let store: FakeRecordingStore
    let area: Area
}

@MainActor
private final class TestNow {
    var value: Int64
    init(_ value: Int64) { self.value = value }
}

@MainActor
private final class ManualRecordingTicker: RecordingTicking {
    private var handler: Handler?
    private(set) var startCalls = 0
    private(set) var stopCalls = 0

    func start(handler: @escaping Handler) {
        startCalls += 1
        self.handler = handler
    }

    func stop() async {
        stopCalls += 1
        handler = nil
    }

    func fire(at timeMs: Int64) async {
        guard let handler else { return }
        if !(await handler(timeMs)) {
            self.handler = nil
        }
    }
}

@MainActor
private final class ManualSensorHub: SensorHubProtocol {
    var state: LiveSensorState
    var consumers: Set<SensorConsumer> = []
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

private enum FakePersistenceError: LocalizedError {
    case appendFailed

    var errorDescription: String? { "Synthetic append failure" }
}

@MainActor
private final class FakeRecordingStore: RecordingPersisting {
    private(set) var tracks: [Track] = []
    private(set) var batches: [[TrackPointDraft]] = []
    private(set) var persistedDrafts: [TrackPointDraft] = []
    private(set) var saveBatchCalls = 0
    private(set) var deleteCalls = 0
    private(set) var finalizedAfterDraftCount: Int?
    var failOnAppend = false

    func createTrack(name: String, area: Area, startedAt: Int64) throws -> Track {
        let track = Track(name: name, area: area, startedAt: startedAt)
        tracks.append(track)
        return track
    }

    func append(_ drafts: [TrackPointDraft], to track: Track) throws {
        if failOnAppend { throw FakePersistenceError.appendFailed }
        saveBatchCalls += 1
        batches.append(drafts)
        persistedDrafts.append(contentsOf: drafts)
    }

    func finalize(_ track: Track, endedAt: Int64) throws {
        finalizedAfterDraftCount = persistedDrafts.count
        track.endedAt = endedAt
    }

    func delete(_ track: Track) throws {
        deleteCalls += 1
        tracks.removeAll { $0.id == track.id }
    }
}
