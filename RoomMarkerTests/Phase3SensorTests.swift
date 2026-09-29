import Foundation
import Testing
@testable import RoomMarker

@Suite("Phase 3 sensor foundation")
@MainActor
struct Phase3SensorTests {
    private let sampleDate = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("Complete synthetic snapshot preserves every supplied value")
    func completeSnapshot() async throws {
        let hub = FakeSensorHub(state: completeState())
        let snapshot = try await makeService(hub: hub).capture()

        #expect(snapshot.capturedAt == 1_700_000_999_000)
        #expect(snapshot.latitude == 22.336)
        #expect(snapshot.longitude == 114.172)
        #expect(snapshot.altitude == 18.5)
        #expect(snapshot.accuracy == 4.25)
        #expect(snapshot.pressureHpa == 1007.8)
        #expect(snapshot.magneticX == 11.0)
        #expect(snapshot.magneticY == -8.0)
        #expect(snapshot.magneticZ == 42.0)
        #expect(snapshot.headingDeg == 271.5)
        #expect(snapshot.outcomes == SensorSnapshotOutcomes(
            location: .available,
            pressure: .available,
            magnetometer: .available,
            heading: .available
        ))
        #expect(hub.startCalls == 1)
        #expect(hub.stopCalls == 1)
    }

    @Test("A partial snapshot is a successful result")
    func partialSnapshot() async throws {
        var state = completeState()
        state.pressureHpa = .unsupported
        state.headingDeg = .unavailable
        let snapshot = try await makeService(hub: FakeSensorHub(state: state)).capture()

        #expect(snapshot.latitude == 22.336)
        #expect(snapshot.magneticX == 11.0)
        #expect(snapshot.pressureHpa == nil)
        #expect(snapshot.headingDeg == nil)
        #expect(snapshot.outcomes.pressure == .unsupported)
        #expect(snapshot.outcomes.heading == .unavailable)
    }

    @Test("Location denial remains explicit")
    func locationDenied() async throws {
        var state = terminalUnavailableState()
        state.permission = .denied
        state.location = .permissionDenied
        let snapshot = try await makeService(hub: FakeSensorHub(state: state)).capture()

        #expect(snapshot.latitude == nil)
        #expect(snapshot.outcomes.location == .permissionDenied)
    }

    @Test("Temporary location unavailability remains explicit")
    func locationUnavailable() async throws {
        var state = terminalUnavailableState()
        state.location = .unavailable
        let snapshot = try await makeService(hub: FakeSensorHub(state: state)).capture()

        #expect(snapshot.latitude == nil)
        #expect(snapshot.outcomes.location == .unavailable)
    }

    @Test("Pressure unavailability does not invalidate other readings")
    func pressureUnavailable() async throws {
        var state = completeState()
        state.pressureHpa = .unavailable
        let snapshot = try await makeService(hub: FakeSensorHub(state: state)).capture()

        #expect(snapshot.pressureHpa == nil)
        #expect(snapshot.latitude != nil)
        #expect(snapshot.outcomes.pressure == .unavailable)
    }

    @Test("Magnetometer unavailability is not replaced")
    func magnetometerUnavailable() async throws {
        var state = completeState()
        state.magneticField = .unavailable
        let snapshot = try await makeService(hub: FakeSensorHub(state: state)).capture()

        #expect(snapshot.magneticX == nil)
        #expect(snapshot.magneticY == nil)
        #expect(snapshot.magneticZ == nil)
        #expect(snapshot.outcomes.magnetometer == .unavailable)
    }

    @Test("Heading unavailability is not replaced")
    func headingUnavailable() async throws {
        var state = completeState()
        state.headingDeg = .unavailable
        let snapshot = try await makeService(hub: FakeSensorHub(state: state)).capture()

        #expect(snapshot.headingDeg == nil)
        #expect(snapshot.outcomes.heading == .unavailable)
    }

    @Test("Snapshot timeout returns available fields and marks waiting fields")
    func timeoutReturnsPartialSnapshot() async throws {
        var state = LiveSensorState.waiting
        state.permission = .authorizedWhenInUse
        state.location = available(LocationReading(
            latitude: 1,
            longitude: 2,
            altitude: nil,
            horizontalAccuracy: nil
        ))
        let hub = FakeSensorHub(state: state)
        let service = SensorSnapshotService(
            hub: hub,
            timeout: .milliseconds(20),
            pollingInterval: .milliseconds(1),
            nowMilliseconds: { 99 }
        )

        let snapshot = try await service.capture()

        #expect(snapshot.latitude == 1)
        #expect(snapshot.pressureHpa == nil)
        #expect(snapshot.outcomes.location == .available)
        #expect(snapshot.outcomes.pressure == .timedOut)
        #expect(snapshot.outcomes.magnetometer == .timedOut)
        #expect(snapshot.outcomes.heading == .timedOut)
        #expect(hub.stopCalls == 1)
    }

    @Test("Cancelling a snapshot releases its sensor consumer")
    func cancellationStopsCapture() async {
        let hub = FakeSensorHub(state: .waiting)
        let service = SensorSnapshotService(
            hub: hub,
            timeout: .seconds(5),
            pollingInterval: .milliseconds(5)
        )
        let task = Task { try await service.capture() }

        await Task.yield()
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(hub.stopCalls == 1)
        #expect(hub.activeConsumerCount == 0)
    }

    @Test("CMAltimeter kPa converts to Harmony-compatible hPa")
    func pressureConversion() {
        #expect(CoreMotionPressureService.hectopascals(fromKilopascals: 101.325) == 1013.25)
        #expect(CoreMotionPressureService.hectopascals(fromKilopascals: -.infinity) == nil)
        #expect(CoreMotionPressureService.hectopascals(fromKilopascals: -1) == nil)
    }

    @Test("No missing measurement becomes numeric zero")
    func missingMeasurementsStayNil() async throws {
        let snapshot = try await makeService(hub: FakeSensorHub(state: terminalUnavailableState())).capture()

        #expect(snapshot.latitude == nil)
        #expect(snapshot.longitude == nil)
        #expect(snapshot.altitude == nil)
        #expect(snapshot.accuracy == nil)
        #expect(snapshot.pressureHpa == nil)
        #expect(snapshot.magneticX == nil)
        #expect(snapshot.magneticY == nil)
        #expect(snapshot.magneticZ == nil)
        #expect(snapshot.headingDeg == nil)
    }

    @Test("Live state represents mixed capability outcomes")
    func mixedLiveState() {
        let state = LiveSensorState(
            permission: .authorizedWhenInUse,
            location: available(LocationReading(
                latitude: 22.3,
                longitude: 114.2,
                altitude: nil,
                horizontalAccuracy: 8
            )),
            pressureHpa: .unsupported,
            magneticField: .waiting,
            headingDeg: .unavailable
        )

        #expect(state.location.availableValue?.latitude == 22.3)
        #expect(state.pressureHpa == .unsupported)
        #expect(state.magneticField == .waiting)
        #expect(state.headingDeg == .unavailable)
        #expect(!state.allMeasurementsSettledForSnapshot)
    }

    @Test("Sensor hub starts once and stops after its final consumer")
    func hubLifecycle() {
        let location = FakeLocationService()
        let magnetometer = FakeMagnetometerService()
        let pressure = FakePressureService()
        let hub = SensorHub(
            locationService: location,
            magnetometerService: magnetometer,
            pressureService: pressure
        )

        hub.start(consumer: .liveSensors, requestLocationAuthorization: false)
        hub.start(consumer: .snapshot, requestLocationAuthorization: true)

        #expect(location.startCalls == 1)
        #expect(magnetometer.startCalls == 1)
        #expect(pressure.startCalls == 1)
        #expect(location.authorizationRequests == 1)
        #expect(hub.activeConsumerCount == 2)

        hub.stop(consumer: .liveSensors)
        #expect(location.stopCalls == 0)

        hub.stop(consumer: .snapshot)
        #expect(location.stopCalls == 1)
        #expect(magnetometer.stopCalls == 1)
        #expect(pressure.stopCalls == 1)
        #expect(hub.activeConsumerCount == 0)
    }

    private func completeState() -> LiveSensorState {
        LiveSensorState(
            permission: .authorizedWhenInUse,
            location: available(LocationReading(
                latitude: 22.336,
                longitude: 114.172,
                altitude: 18.5,
                horizontalAccuracy: 4.25
            )),
            pressureHpa: available(1007.8),
            magneticField: available(MagneticFieldReading(x: 11, y: -8, z: 42)),
            headingDeg: available(271.5)
        )
    }

    private func terminalUnavailableState() -> LiveSensorState {
        LiveSensorState(
            permission: .notDetermined,
            location: .unavailable,
            pressureHpa: .unavailable,
            magneticField: .unavailable,
            headingDeg: .unavailable
        )
    }

    private func available<Value: Sendable>(_ value: Value) -> SensorValueState<Value> {
        .available(TimestampedSensorValue(value: value, capturedAt: sampleDate))
    }

    private func makeService(hub: FakeSensorHub) -> SensorSnapshotService {
        SensorSnapshotService(
            hub: hub,
            timeout: .milliseconds(20),
            pollingInterval: .milliseconds(1),
            nowMilliseconds: { 1_700_000_999_000 }
        )
    }
}

@MainActor
private final class FakeSensorHub: SensorHubProtocol {
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

@MainActor
private final class FakeLocationService: LocationSensorServicing {
    var permissionState: LocationPermissionState = .notDetermined
    var locationState: SensorValueState<LocationReading> = .waiting
    var headingState: SensorValueState<Double> = .waiting
    var onChange: (@MainActor () -> Void)?
    private(set) var startCalls = 0
    private(set) var stopCalls = 0
    private(set) var authorizationRequests = 0

    func requestWhenInUseAuthorization() { authorizationRequests += 1 }
    func start() { startCalls += 1 }
    func stop() { stopCalls += 1 }
}

@MainActor
private final class FakeMagnetometerService: MagnetometerSensorServicing {
    var state: SensorValueState<MagneticFieldReading> = .waiting
    var onChange: (@MainActor () -> Void)?
    private(set) var startCalls = 0
    private(set) var stopCalls = 0

    func start() { startCalls += 1 }
    func stop() { stopCalls += 1 }
}

@MainActor
private final class FakePressureService: PressureSensorServicing {
    var state: SensorValueState<Double> = .waiting
    var onChange: (@MainActor () -> Void)?
    private(set) var startCalls = 0
    private(set) var stopCalls = 0

    func start() { startCalls += 1 }
    func stop() { stopCalls += 1 }
}
