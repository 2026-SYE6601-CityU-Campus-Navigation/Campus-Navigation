import Foundation

@MainActor
protocol SensorSnapshotCapturing: AnyObject {
    func capture() async throws -> SensorSnapshot
}

@MainActor
final class SensorSnapshotService: SensorSnapshotCapturing {
    static let defaultTimeout: Duration = .seconds(4)

    private let hub: any SensorHubProtocol
    private let timeout: Duration
    private let pollingInterval: Duration
    private let nowMilliseconds: @MainActor () -> Int64

    init(
        hub: any SensorHubProtocol,
        timeout: Duration = SensorSnapshotService.defaultTimeout,
        pollingInterval: Duration = .milliseconds(50),
        nowMilliseconds: @escaping @MainActor () -> Int64 = {
            Int64((Date().timeIntervalSince1970 * 1_000).rounded())
        }
    ) {
        self.hub = hub
        self.timeout = timeout
        self.pollingInterval = pollingInterval
        self.nowMilliseconds = nowMilliseconds
    }

    func capture() async throws -> SensorSnapshot {
        hub.start(consumer: .snapshot, requestLocationAuthorization: true)
        defer { hub.stop(consumer: .snapshot) }

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        while !hub.state.allMeasurementsSettledForSnapshot {
            try Task.checkCancellation()
            if clock.now >= deadline {
                return makeSnapshot(from: hub.state, timedOut: true)
            }
            try await Task.sleep(for: pollingInterval)
        }

        try Task.checkCancellation()
        return makeSnapshot(from: hub.state, timedOut: false)
    }

    private func makeSnapshot(from state: LiveSensorState, timedOut: Bool) -> SensorSnapshot {
        let location = state.location.availableValue
        let magnetic = state.magneticField.availableValue

        return SensorSnapshot(
            capturedAt: nowMilliseconds(),
            latitude: location?.latitude,
            longitude: location?.longitude,
            altitude: location?.altitude,
            accuracy: location?.horizontalAccuracy,
            pressureHpa: state.pressureHpa.availableValue,
            magneticX: magnetic?.x,
            magneticY: magnetic?.y,
            magneticZ: magnetic?.z,
            headingDeg: state.headingDeg.availableValue,
            outcomes: SensorSnapshotOutcomes(
                location: outcome(for: state.location, timedOut: timedOut),
                pressure: outcome(for: state.pressureHpa, timedOut: timedOut),
                magnetometer: outcome(for: state.magneticField, timedOut: timedOut),
                heading: outcome(for: state.headingDeg, timedOut: timedOut)
            )
        )
    }

    private func outcome<Value: Sendable>(
        for state: SensorValueState<Value>,
        timedOut: Bool
    ) -> SensorCaptureOutcome {
        switch state {
        case .waiting:
            timedOut ? .timedOut : .unavailable
        case .unsupported:
            .unsupported
        case .unavailable:
            .unavailable
        case .permissionDenied:
            .permissionDenied
        case .restricted:
            .restricted
        case .stale:
            .stale
        case .available:
            .available
        }
    }
}
