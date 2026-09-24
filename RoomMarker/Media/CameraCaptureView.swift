import SwiftUI
import UIKit

struct CameraCaptureView: UIViewControllerRepresentable {
    static let jpegCompressionQuality: CGFloat = 0.82

    let onResult: (CameraCaptureOutcome) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onResult: onResult)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let onResult: (CameraCaptureOutcome) -> Void

        init(onResult: @escaping (CameraCaptureOutcome) -> Void) {
            self.onResult = onResult
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onResult(.cancelled)
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let image = info[.originalImage] as? UIImage else {
                onResult(.failed("相机没有返回图像。"))
                return
            }

            let normalized = image.normalizedForRoomMarkerJPEG()
            guard let data = normalized.jpegData(
                compressionQuality: CameraCaptureView.jpegCompressionQuality
            ) else {
                onResult(.failed("无法编码 JPEG。"))
                return
            }

            let capturedAt = Int64((Date().timeIntervalSince1970 * 1_000).rounded())
            onResult(.success(jpegData: data, capturedAt: capturedAt))
        }
    }
}

private extension UIImage {
    func normalizedForRoomMarkerJPEG() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
