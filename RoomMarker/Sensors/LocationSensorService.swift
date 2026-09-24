import CoreLocation
import Foundation

@MainActor
final class CoreLocationSensorService: NSObject, LocationSensorServicing {
    private let manager: CLLocationManager
    private var locationStaleTask: Task<Void, Never>?
    private var headingStaleTask: Task<Void, Never>?
    private var isRunning = false

    private(set) var permissionState: LocationPermissionState
    private(set) var locationState: SensorValueState<LocationReading> = .waiting
    private(set) var headingState: SensorValueState<Double> = .waiting
    var onChange: (@MainActor () -> Void)?

    init(manager: CLLocationManager = CLLocationManager()) {
        self.manager = manager
        permissionState = Self.permissionState(for: manager.authorizationStatus)
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.headingFilter = 1
    }

    func requestWhenInUseAuthorization() {
        permissionState = Self.permissionState(for: manager.authorizationStatus)
        guard permissionState == .notDetermined else {
            publish()
            return
        }
        manager.requestWhenInUseAuthorization()
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        permissionState = Self.permissionState(for: manager.authorizationStatus)
        configureLocationForCurrentPermission()

        if CLLocationManager.headingAvailable() {
            headingState = .waiting
            manager.startUpdatingHeading()
        } else {
            headingState = .unsupported
        }
        publish()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        locationStaleTask?.cancel()
        headingStaleTask?.cancel()
        locationStaleTask = nil
        headingStaleTask = nil
    }

    static func permissionState(for status: CLAuthorizationStatus) -> LocationPermissionState {
        switch status {
        case .notDetermined:
            .notDetermined
        case .denied:
            .denied
        case .restricted:
            .restricted
        case .authorizedWhenInUse:
            .authorizedWhenInUse
        case .authorizedAlways:
            .authorizedAlways
        @unknown default:
            .restricted
        }
    }

    static func normalizedHeading(_ heading: CLHeading) -> Double? {
        guard heading.headingAccuracy >= 0,
              heading.magneticHeading.isFinite
        else {
            return nil
        }
        let normalized = heading.magneticHeading.truncatingRemainder(dividingBy: 360)
        return normalized >= 0 ? normalized : normalized + 360
    }

    private func configureLocationForCurrentPermission() {
        guard isRunning else { return }
        switch permissionState {
        case .authorizedWhenInUse, .authorizedAlways:
            locationState = .waiting
            manager.startUpdatingLocation()
        case .notDetermined:
            locationState = .waiting
        case .denied:
            locationState = .permissionDenied
        case .restricted:
            locationState = .restricted
        }
    }

    private func publish() {
        onChange?()
    }

    private func markLocationStale(after sample: TimestampedSensorValue<LocationReading>) {
        locationStaleTask?.cancel()
        locationStaleTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(15))
            } catch {
                return
            }
            guard let self, self.isRunning,
                  case let .available(current) = self.locationState,
                  current.capturedAt == sample.capturedAt
            else { return }
            self.locationState = .stale(current)
            self.publish()
        }
    }

    private func markHeadingStale(after sample: TimestampedSensorValue<Double>) {
        headingStaleTask?.cancel()
        headingStaleTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(5))
            } catch {
                return
            }
            guard let self, self.isRunning,
                  case let .available(current) = self.headingState,
                  current.capturedAt == sample.capturedAt
            else { return }
            self.headingState = .stale(current)
            self.publish()
        }
    }
}

extension CoreLocationSensorService: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        permissionState = Self.permissionState(for: manager.authorizationStatus)
        configureLocationForCurrentPermission()
        publish()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isRunning,
              let location = locations.last,
              CLLocationCoordinate2DIsValid(location.coordinate),
              location.horizontalAccuracy >= 0
        else { return }

        let reading = LocationReading(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            altitude: location.verticalAccuracy >= 0 ? location.altitude : nil,
            horizontalAccuracy: location.horizontalAccuracy.isFinite ? location.horizontalAccuracy : nil
        )
        let sample = TimestampedSensorValue(value: reading, capturedAt: location.timestamp)
        locationState = .available(sample)
        markLocationStale(after: sample)
        publish()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard isRunning, let heading = Self.normalizedHeading(newHeading) else { return }
        let sample = TimestampedSensorValue(value: heading, capturedAt: newHeading.timestamp)
        headingState = .available(sample)
        markHeadingStale(after: sample)
        publish()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard isRunning else { return }
        if let locationError = error as? CLError, locationError.code == .denied {
            permissionState = Self.permissionState(for: manager.authorizationStatus)
            locationState = switch permissionState {
            case .denied: .permissionDenied
            case .restricted: .restricted
            default: .unavailable
            }
        } else if locationState.availableValue == nil {
            locationState = .unavailable
        }
        publish()
    }
}
