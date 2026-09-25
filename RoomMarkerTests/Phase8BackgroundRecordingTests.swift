import Foundation
import Testing
@testable import RoomMarker

@Suite("Phase 8 background recording")
@MainActor
struct Phase8BackgroundRecordingTests {
    @Test("1. Starting a Track acquires one background session")
    func startAcquiresBackgroundSession() throws {
        let fixture = makeFixture()

        try fixture.coordinator.start(name: "Track", area: fixture.area)

        #expect(fixture.background.acquireCalls == 1)
        #expect(fixture.background.isAcquired)
        #expect(fixture.coordinator.backgroundStatus == .active)
    }

    @Test("2. Double start does not acquire a second background session")
    func doubleStartDoesNotReacquire() throws {
        let fixture = makeFixture()
        try fixture.coordinator.start(name: "One", area: fixture.area)

        #expect(throws: RecordingError.alreadyActive) {
            try fixture.coordinator.start(name: "Two", area: fixture.area)
        }
        #expect(fixture.background.acquireCalls == 1)
    }

    @Test("3. Clean stop releases the background session")
    func stopReleasesBackgroundSession() async throws {
        let fixture = makeFixture()
        try fixture.coordinator.start(name: "Track", area: fixture.area)

        try await fixture.coordinator.stop()

        #expect(fixture.background.releaseCalls == 1)
        #expect(!fixture.background.isAcquired)
        #expect(fixture.coordinator.backgroundStatus == .inactive)
    }

    @Test("4. Persistence failure releases the background session")
    func failureReleasesBackgroundSession() async throws {
        let fixture = makeFixture()
        fixture.store.failOnAppend = true
        try fixture.coordinator.start(name: "Track", area: fixture.area)

        await fire([1, 2, 3, 4, 5], ticker: fixture.ticker)

        #expect(fixture.coordinator.state.phase == .failed)
        #expect(fixture.background.releaseCalls == 1)
        #expect(!fixture.background.isAcquired)
    }

    @Test("5. Foreground to background does not stop the active Track")
    func backgroundDoesNotStopTrack() throws {
        let fixture = makeFixture()
        try fixture.coordinator.start(name: "Track", area: fixture.area)

        fixture.coordinator.handleLifecycleTransition(.inactive)
        fixture.coordinator.handleLifecycleTransition(.background)

        #expect(fixture.coordinator.state.phase == .recording)
        #expect(fixture.background.releaseCalls == 0)
        #expect(fixture.ticker.stopCalls == 0)
    }

    @Test("6. Returning to foreground does not create a duplicate ticker")
    func foregroundReturnDoesNotRestartTicker() throws {
        let fixture = makeFixture()
        try fixture.coordinator.start(name: "Track", area: fixture.area)
        fixture.coordinator.handleLifecycleTransition(.background)

        fixture.coordinator.handleLifecycleTransition(.active)

        #expect(fixture.ticker.startCalls == 1)
        #expect(fixture.background.acquireCalls == 1)
    }

    @Test("7. Actual sampling cycles produce one point each")
    func samplingCyclesProduceOnePoint() async throws {
        let fixture = makeFixture()
        try fixture.coordinator.start(name: "Track", area: fixture.area)

        await fire([1_000, 2_000, 3_000], ticker: fixture.ticker)
        try await fixture.coordinator.stop()

        #expect(fixture.store.persisted.map(\.timeMs) == [1_000, 2_000, 3_000])
    }

    @Test("8. A delayed gap produces no synthetic points")
    func delayedGapDoesNotBackfill() async throws {
        let fixture = makeFixture()
        try fixture.coordinator.start(name: "Track", area: fixture.area)

        await fire([1_000, 2_000, 10_000], ticker: fixture.ticker)
        try await fixture.coordinator.stop()

        #expect(fixture.store.persisted.map(\.timeMs) == [1_000, 2_000, 10_000])
    }

    @Test("9. Foreground return performs no historical catch-up sampling")
    func foregroundReturnDoesNotCatchUp() async throws {
        let fixture = makeFixture()
        try fixture.coordinator.start(name: "Track", area: fixture.area)
        await fixture.ticker.fire(at: 1_000)
        fixture.coordinator.handleLifecycleTransition(.background)
        fixture.coordinator.handleLifecycleTransition(.active)
        await fixture.ticker.fire(at: 12_000)
        try await fixture.coordinator.stop()

        #expect(fixture.store.persisted.map(\.timeMs) == [1_000, 12_000])
    }

    @Test("10. Persisted timestamps preserve the real suspension gap")
    func timestampsPreserveGap() async throws {
        let fixture = makeFixture()
        try fixture.coordinator.start(name: "Track", area: fixture.area)
        await fire([3_000, 4_000, 12_000], ticker: fixture.ticker)
        try await fixture.coordinator.stop()

        let times = fixture.store.persisted.map(\.timeMs)
        #expect(times[2] - times[1] == 8_000)
    }

    @Test("11. Unavailable background sensors remain nil")
    func partialBackgroundSensorsRemainNil() async throws {
        let state = LiveSensorState(
            permission: .authorizedWhenInUse,
            location: .available(TimestampedSensorValue(
                value: LocationReading(latitude: 22.3, longitude: 114.2, altitude: nil, horizontalAccuracy: 8),
                capturedAt: Date()
            )),
            pressureHpa: .unavailable,
            magneticField: .stale(TimestampedSensorValue(
                value: MagneticFieldReading(x: 1, y: 2, z: 3),
                capturedAt: Date()
            )),
            headingDeg: .waiting
        )
        let fixture = makeFixture(state: state)
        try fixture.coordinator.start(name: "Track", area: fixture.area)
        await fixture.ticker.fire(at: 1_000)
        try await fixture.coordinator.stop()

        let point = try #require(fixture.store.persisted.first)
        #expect(point.latitude == 22.3)
        #expect(point.pressureHpa == nil)
        #expect(point.magneticX == nil)
        #expect(point.headingDeg == nil)
    }

    @Test("12. Missing background values never become zero")
    func missingValuesNeverBecomeZero() async throws {
        let fixture = makeFixture(state: .waiting)
        try fixture.coordinator.start(name: "Track", area: fixture.area)
        await fixture.ticker.fire(at: 1_000)
        try await fixture.coordinator.stop()

        let point = try #require(fixture.store.persisted.first)
        #expect(point.latitude == nil)
        #expect(point.pressureHpa == nil)
        #expect(point.magneticX == nil)
        #expect(point.headingDeg == nil)
    }

    @Test("13. Normal five-point batching remains unchanged")
    func fivePointBatchingRemains() async throws {
        let fixture = makeFixture()
        try fixture.coordinator.start(name: "Track", area: fixture.area)

        await fire([1, 2, 3, 4, 5], ticker: fixture.ticker)

        #expect(fixture.store.batches.map(\.count) == [5])
    }

    @Test("14. Lifecycle flush protects the tail without duplicating points")
    func lifecycleFlushDoesNotDuplicate() async throws {
        let fixture = makeFixture()
        try fixture.coordinator.start(name: "Track", area: fixture.area)
        await fire([1, 2, 3], ticker: fixture.ticker)

        fixture.coordinator.handleLifecycleTransition(.background)
        fixture.coordinator.handleLifecycleTransition(.active)
        await fire([4, 5], ticker: fixture.ticker)
        try await fixture.coordinator.stop()

        #expect(fixture.store.batches.map(\.count) == [3, 2])
        #expect(fixture.store.persisted.map(\.timeMs) == [1, 2, 3, 4, 5])
    }

    @Test("15. Stop still flushes the remaining tail")
    func stopFlushesRemainingTail() async throws {
        let fixture = makeFixture()
        try fixture.coordinator.start(name: "Track", area: fixture.area)
        await fire([1, 2, 3, 4, 5, 6, 7], ticker: fixture.ticker)

        try await fixture.coordinator.stop()

        #expect(fixture.store.batches.map(\.count) == [5, 2])
    }

    @Test("16. Track pointCount remains relationship-derived")
    func pointCountIsRelationshipDerived() {
        let track = Track(name: "Track", startedAt: 1)
        #expect(track.pointCount == 0)
        track.points.append(TrackPoint(track: track, timeMs: 2))
        #expect(track.pointCount == track.points.count)
        #expect(track.pointCount == 1)
    }

    @Test("17. Elapsed time derives from timestamps across a gap")
    func elapsedTimeUsesWallClock() {
        #expect(RecordingElapsedTime.seconds(startedAt: 1_000, now: 12_000) == 11)
    }

    @Test("18. Incomplete Tracks are detected on relaunch")
    func incompleteTrackDetected() {
        let incomplete = Track(name: "Interrupted", startedAt: 1, endedAt: nil)
        let completed = Track(name: "Done", startedAt: 2, endedAt: 3)

        let detected = IncompleteTrackRecovery.detected(
            in: [completed, incomplete],
            activeTrackID: nil
        )

        #expect(detected.map(\.id) == [incomplete.id])
    }

    @Test("19. Detection never automatically marks an incomplete Track completed")
    func incompleteTrackNotAutoCompleted() {
        let track = Track(name: "Interrupted", startedAt: 1, endedAt: nil)

        _ = IncompleteTrackRecovery.detected(in: [track], activeTrackID: nil)

        #expect(track.endedAt == nil)
    }

    @Test("20. Recovery finalization requires an explicit action")
    func recoveryFinalizationIsExplicit() throws {
        let fixture = makeFixture(clock: Phase8Clock(9_000))
        let track = Track(name: "Interrupted", startedAt: 1_000, endedAt: nil)

        try fixture.coordinator.finalizeInterrupted(track)

        #expect(track.endedAt == 9_000)
        #expect(fixture.store.finalizeCalls == 1)
    }

    @Test("21. Active Track deletion remains rejected")
    func activeTrackDeletionRejected() throws {
        let fixture = makeFixture()
        try fixture.coordinator.start(name: "Track", area: fixture.area)
        let active = try #require(fixture.coordinator.activeTrack)

        #expect(throws: RecordingError.activeTrackCannotBeDeleted) {
            try fixture.coordinator.delete(active)
        }
    }

    @Test("22. Background session is inactive while recording is idle")
    func backgroundSessionInactiveWhileIdle() {
        let fixture = makeFixture()

        #expect(fixture.coordinator.state == .idle)
        #expect(fixture.coordinator.backgroundStatus == .inactive)
        #expect(fixture.background.acquireCalls == 0)
    }

    @Test("23. Background capability is acquired only for recording")
    func capabilityOnlyAcquiredForRecording() async throws {
        let fixture = makeFixture()
        fixture.coordinator.handleLifecycleTransition(.background)
        #expect(fixture.background.acquireCalls == 0)

        try fixture.coordinator.start(name: "Track", area: fixture.area)
        #expect(fixture.background.acquireCalls == 1)

        try await fixture.coordinator.stop()
        #expect(fixture.background.releaseCalls == 1)
    }

    @Test("24. Live Sensors lease survives recording stop")
    func liveSensorLeaseSurvives() async throws {
        let fixture = makeFixture()
        fixture.hub.consumers.insert(.liveSensors)
        try fixture.coordinator.start(name: "Track", area: fixture.area)

        try await fixture.coordinator.stop()

        #expect(fixture.hub.consumers == [.liveSensors])
    }

    @Test("25. Snapshot lease survives recording stop")
    func snapshotLeaseSurvives() async throws {
        let fixture = makeFixture()
        fixture.hub.consumers.insert(.snapshot)
        try fixture.coordinator.start(name: "Track", area: fixture.area)

        try await fixture.coordinator.stop()

        #expect(fixture.hub.consumers == [.snapshot])
    }

    @Test("26. Authorization denial is represented without claiming background success")
    func denialRepresentedHonestly() throws {
        let fixture = makeFixture(
            permission: .denied,
            acquireResult: .unavailable(.authorizationDenied)
        )

        try fixture.coordinator.start(name: "Track", area: fixture.area)

        #expect(fixture.coordinator.state.phase == .recording)
        #expect(fixture.coordinator.backgroundStatus == .unavailable(.authorizationDenied))
        #expect(!fixture.background.isAcquired)
    }

    @Test("27. Pending temporary authorization never fabricates an active background session")
    func pendingAuthorizationRepresentedHonestly() throws {
        let fixture = makeFixture(
            permission: .notDetermined,
            acquireResult: .unavailable(.authorizationPending)
        )

        try fixture.coordinator.start(name: "Track", area: fixture.area)

        #expect(fixture.coordinator.backgroundStatus == .unavailable(.authorizationPending))
        #expect(fixture.background.acquireCalls == 1)
    }

    @Test("28. Export preserves a Track containing timestamp gaps")
    func exportPreservesTimestampGaps() throws {
        let trackID = UUID()
        let snapshot = TrackExportSnapshot(
            id: trackID,
            name: "Gap",
            startedAt: 1_000,
            endedAt: 12_500,
            points: [1_000, 2_000, 10_000].map {
                TrackPointExportSnapshot(
                    id: UUID(),
                    timeMs: $0,
                    latitude: nil,
                    longitude: nil,
                    altitude: nil,
                    accuracy: nil,
                    pressureHpa: nil,
                    magneticX: nil,
                    magneticY: nil,
                    magneticZ: nil,
                    headingDeg: nil
                )
            },
            tags: [],
            photos: []
        )

        let dto = ExportDTOMapper().track(from: snapshot, areaName: "Area")
        try ExportContractValidator.validate(track: dto, trackID: trackID)

        #expect(dto.points.map(\.timeMs) == [1_000, 2_000, 10_000])
        #expect(dto.pointCount == 3)
    }

    @Test("29. Production session rejects a missing location background mode safely")
    func productionSessionRequiresBackgroundMode() {
        let location = Phase8LocationConfiguration(permission: .authorizedWhenInUse)
        let session = CoreLocationBackgroundSession(
            locationService: location,
            hasLocationBackgroundMode: { false }
        )

        #expect(session.acquire() == .unavailable(.backgroundModeMissing))
        #expect(!session.isAcquired)
        #expect(location.enabledValues.isEmpty)
    }

    @Test("30. Production session does not enable background delivery when denied")
    func productionSessionHonorsDeniedAuthorization() {
        let location = Phase8LocationConfiguration(permission: .denied)
        let session = CoreLocationBackgroundSession(
            locationService: location,
            hasLocationBackgroundMode: { true }
        )

        #expect(session.acquire() == .unavailable(.authorizationDenied))
        #expect(!session.isAcquired)
        #expect(location.enabledValues.isEmpty)
    }

    @Test("31. Runtime authorization degradation releases the lease and stays visible")
    func runtimeAuthorizationDegradationIsHonest() throws {
        let fixture = makeFixture()
        try fixture.coordinator.start(name: "Track", area: fixture.area)

        fixture.hub.state.permission = .denied
        fixture.coordinator.handleLifecycleTransition(.background)
        fixture.coordinator.handleLifecycleTransition(.active)

        #expect(fixture.background.releaseCalls == 1)
        #expect(!fixture.background.isAcquired)
        #expect(fixture.coordinator.backgroundStatus == .unavailable(.authorizationDenied))
        #expect(fixture.coordinator.state.phase == .recording)
    }

    private func makeFixture(
        state: LiveSensorState? = nil,
        permission: LocationPermissionState = .authorizedWhenInUse,
        acquireResult: BackgroundLocationSessionStatus = .active,
        clock: Phase8Clock = Phase8Clock(1_000)
    ) -> Phase8Fixture {
        var sensorState = state ?? .waiting
        sensorState.permission = permission
        let hub = Phase8SensorHub(state: sensorState)
        let ticker = Phase8Ticker()
        let store = Phase8RecordingStore()
        let background = Phase8BackgroundSession(acquireResult: acquireResult)
        let coordinator = RecordingCoordinator(
            hub: hub,
            ticker: ticker,
            persistence: store,
            backgroundSession: background,
            nowMilliseconds: { clock.value }
        )
        return Phase8Fixture(
            coordinator: coordinator,
            hub: hub,
            ticker: ticker,
            store: store,
            background: background,
            area: Area(name: "Area", createdAt: 1)
        )
    }

    private func fire(_ times: [Int64], ticker: Phase8Ticker) async {
        for time in times {
            await ticker.fire(at: time)
        }
    }
}

@MainActor
private struct Phase8Fixture {
    let coordinator: RecordingCoordinator
    let hub: Phase8SensorHub
    let ticker: Phase8Ticker
    let store: Phase8RecordingStore
    let background: Phase8BackgroundSession
    let area: Area
}

@MainActor
private final class Phase8Clock {
    var value: Int64
    init(_ value: Int64) { self.value = value }
}

@MainActor
private final class Phase8BackgroundSession: BackgroundLocationSession {
    private let acquireResult: BackgroundLocationSessionStatus
    private(set) var isAcquired = false
    private(set) var acquireCalls = 0
    private(set) var releaseCalls = 0

    init(acquireResult: BackgroundLocationSessionStatus) {
        self.acquireResult = acquireResult
    }

    func acquire() -> BackgroundLocationSessionStatus {
        acquireCalls += 1
        isAcquired = switch acquireResult {
        case .active, .unavailable(.authorizationPending): true
        case .inactive, .unavailable: false
        }
        return acquireResult
    }

    func status(for permission: LocationPermissionState) -> BackgroundLocationSessionStatus {
        guard isAcquired else { return .inactive }
        return switch permission {
        case .authorizedWhenInUse, .authorizedAlways: .active
        case .notDetermined: .unavailable(.authorizationPending)
        case .denied: .unavailable(.authorizationDenied)
        case .restricted: .unavailable(.authorizationRestricted)
        }
    }

    func release() {
        guard isAcquired else { return }
        releaseCalls += 1
        isAcquired = false
    }
}

@MainActor
private final class Phase8SensorHub: SensorHubProtocol {
    var state: LiveSensorState
    var consumers: Set<SensorConsumer> = []

    var activeConsumerCount: Int { consumers.count }

    init(state: LiveSensorState) {
        self.state = state
    }

    func start(consumer: SensorConsumer, requestLocationAuthorization: Bool) {
        consumers.insert(consumer)
    }

    func requestLocationAuthorization() {}

    func stop(consumer: SensorConsumer) {
        consumers.remove(consumer)
    }
}

@MainActor
private final class Phase8LocationConfiguration: BackgroundLocationConfiguring {
    let permissionState: LocationPermissionState
    private(set) var enabledValues: [Bool] = []

    init(permission: LocationPermissionState) {
        permissionState = permission
    }

    func setBackgroundRecordingEnabled(_ enabled: Bool) {
        enabledValues.append(enabled)
    }
}

@MainActor
private final class Phase8Ticker: RecordingTicking {
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

private enum Phase8TestFailure: Error {
    case append
}

@MainActor
private final class Phase8RecordingStore: RecordingPersisting {
    private(set) var tracks: [Track] = []
    private(set) var batches: [[TrackPointDraft]] = []
    private(set) var persisted: [TrackPointDraft] = []
    private(set) var finalizeCalls = 0
    var failOnAppend = false

    func createTrack(name: String, area: Area, startedAt: Int64) throws -> Track {
        let track = Track(name: name, area: area, startedAt: startedAt)
        tracks.append(track)
        return track
    }

    func append(_ drafts: [TrackPointDraft], to track: Track) throws {
        if failOnAppend { throw Phase8TestFailure.append }
        batches.append(drafts)
        persisted.append(contentsOf: drafts)
    }

    func finalize(_ track: Track, endedAt: Int64) throws {
        finalizeCalls += 1
        track.endedAt = endedAt
    }

    func delete(_ track: Track) throws {
        tracks.removeAll { $0.id == track.id }
    }
}
