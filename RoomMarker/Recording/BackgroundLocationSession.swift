import CoreLocation
import Foundation

enum BackgroundLocationUnavailableReason: Equatable, Sendable {
    case authorizationPending
    case authorizationDenied
    case authorizationRestricted
    case backgroundModeMissing
}

enum BackgroundLocationSessionStatus: Equatable, Sendable {
    case inactive
    case active
    case unavailable(BackgroundLocationUnavailableReason)
}

@MainActor
protocol BackgroundLocationSession: AnyObject {
    var isAcquired: Bool { get }

    func acquire() -> BackgroundLocationSessionStatus
    func status(for permission: LocationPermissionState) -> BackgroundLocationSessionStatus
    func release()
}

@MainActor
protocol BackgroundLocationConfiguring: AnyObject {
    var permissionState: LocationPermissionState { get }

    func setBackgroundRecordingEnabled(_ enabled: Bool)
}

@MainActor
final class CoreLocationBackgroundSession: BackgroundLocationSession {
    private let locationService: any BackgroundLocationConfiguring
    private let hasLocationBackgroundMode: @MainActor @Sendable () -> Bool
    private var activitySession: CLBackgroundActivitySession?

    private(set) var isAcquired = false

    init(
        locationService: any BackgroundLocationConfiguring,
        hasLocationBackgroundMode: @escaping @MainActor @Sendable () -> Bool = {
            guard let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]
            else { return false }
            return modes.contains("location")
        }
    ) {
        self.locationService = locationService
        self.hasLocationBackgroundMode = hasLocationBackgroundMode
    }

    func acquire() -> BackgroundLocationSessionStatus {
        guard !isAcquired else {
            return status(for: locationService.permissionState)
        }
        guard hasLocationBackgroundMode() else {
            return .unavailable(.backgroundModeMissing)
        }

        switch locationService.permissionState {
        case .denied:
            return .unavailable(.authorizationDenied)
        case .restricted:
            return .unavailable(.authorizationRestricted)
        case .notDetermined, .authorizedWhenInUse, .authorizedAlways:
            locationService.setBackgroundRecordingEnabled(true)
            activitySession = CLBackgroundActivitySession()
            isAcquired = true
            return status(for: locationService.permissionState)
        }
    }

    func status(for permission: LocationPermissionState) -> BackgroundLocationSessionStatus {
        guard isAcquired else { return .inactive }
        return switch permission {
        case .notDetermined:
            .unavailable(.authorizationPending)
        case .denied:
            .unavailable(.authorizationDenied)
        case .restricted:
            .unavailable(.authorizationRestricted)
        case .authorizedWhenInUse, .authorizedAlways:
            .active
        }
    }

    func release() {
        guard isAcquired else { return }
        activitySession?.invalidate()
        activitySession = nil
        locationService.setBackgroundRecordingEnabled(false)
        isAcquired = false
    }
}

@MainActor
final class ForegroundOnlyBackgroundLocationSession: BackgroundLocationSession {
    var isAcquired: Bool { false }

    func acquire() -> BackgroundLocationSessionStatus {
        .unavailable(.backgroundModeMissing)
    }

    func status(for permission: LocationPermissionState) -> BackgroundLocationSessionStatus {
        .inactive
    }

    func release() {}
}
