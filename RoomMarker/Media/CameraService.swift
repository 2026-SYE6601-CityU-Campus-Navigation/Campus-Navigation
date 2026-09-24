import AVFoundation
import UIKit

enum CameraAuthorizationState: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted
}

@MainActor
protocol CameraServicing: AnyObject {
    var authorizationState: CameraAuthorizationState { get }
    var isCameraAvailable: Bool { get }
    func requestAuthorization() async -> CameraAuthorizationState
}

@MainActor
final class SystemCameraService: CameraServicing {
    var authorizationState: CameraAuthorizationState {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined: .notDetermined
        case .authorized: .authorized
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .restricted
        }
    }

    var isCameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func requestAuthorization() async -> CameraAuthorizationState {
        guard authorizationState == .notDetermined else { return authorizationState }
        _ = await AVCaptureDevice.requestAccess(for: .video)
        return authorizationState
    }
}
