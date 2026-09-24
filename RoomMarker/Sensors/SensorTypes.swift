import Foundation

enum LocationPermissionState: String, Sendable {
    case notDetermined
    case denied
    case restricted
    case authorizedWhenInUse
    case authorizedAlways
}

struct TimestampedSensorValue<Value: Sendable>: Sendable {
    let value: Value
    let capturedAt: Date
}

extension TimestampedSensorValue: Equatable where Value: Equatable {}

enum SensorValueState<Value: Sendable>: Sendable {
    case waiting
    case unsupported
    case unavailable
    case permissionDenied
    case restricted
    case stale(TimestampedSensorValue<Value>)
    case available(TimestampedSensorValue<Value>)

    var availableValue: Value? {
        guard case let .available(sample) = self else { return nil }
        return sample.value
    }

    var isSettledForSnapshot: Bool {
        if case .waiting = self {
            return false
        }
        return true
    }
}

extension SensorValueState: Equatable where Value: Equatable {}

struct LocationReading: Equatable, Sendable {
    let latitude: Double
    let longitude: Double
    let altitude: Double?
    let horizontalAccuracy: Double?
}

struct MagneticFieldReading: Equatable, Sendable {
    let x: Double
    let y: Double
    let z: Double
}

struct LiveSensorState: Equatable, Sendable {
    var permission: LocationPermissionState
    var location: SensorValueState<LocationReading>
    var pressureHpa: SensorValueState<Double>
    var magneticField: SensorValueState<MagneticFieldReading>
    var headingDeg: SensorValueState<Double>

    static let waiting = LiveSensorState(
        permission: .notDetermined,
        location: .waiting,
        pressureHpa: .waiting,
        magneticField: .waiting,
        headingDeg: .waiting
    )

    var allMeasurementsSettledForSnapshot: Bool {
        location.isSettledForSnapshot
            && pressureHpa.isSettledForSnapshot
            && magneticField.isSettledForSnapshot
            && headingDeg.isSettledForSnapshot
    }
}

enum SensorCaptureOutcome: String, Equatable, Sendable {
    case available
    case unsupported
    case unavailable
    case permissionDenied
    case restricted
    case stale
    case timedOut
}

struct SensorSnapshotOutcomes: Equatable, Sendable {
    let location: SensorCaptureOutcome
    let pressure: SensorCaptureOutcome
    let magnetometer: SensorCaptureOutcome
    let heading: SensorCaptureOutcome
}

struct SensorSnapshot: Equatable, Sendable {
    let capturedAt: Int64
    let latitude: Double?
    let longitude: Double?
    let altitude: Double?
    let accuracy: Double?
    let pressureHpa: Double?
    let magneticX: Double?
    let magneticY: Double?
    let magneticZ: Double?
    let headingDeg: Double?
    let outcomes: SensorSnapshotOutcomes
}

enum SensorConsumer: Hashable, Sendable {
    case liveSensors
    case snapshot
}
