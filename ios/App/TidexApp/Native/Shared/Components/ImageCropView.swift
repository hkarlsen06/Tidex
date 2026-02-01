import SwiftUI
import TOCropViewController

/// Reusable SwiftUI wrapper for TOCropViewController
/// Provides a familiar iOS Photos-style cropping experience
struct ImageCropView: UIViewControllerRepresentable {
    let image: UIImage
    let croppingStyle: TOCropViewCroppingStyle
    let onCrop: (UIImage) -> Void
    let onCancel: () -> Void

    init(
        image: UIImage,
        croppingStyle: TOCropViewCroppingStyle = .circular,
        onCrop: @escaping (UIImage) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.image = image
        self.croppingStyle = croppingStyle
        self.onCrop = onCrop
        self.onCancel = onCancel
    }

    func makeUIViewController(context: Context) -> UINavigationController {
        let cropViewController = TOCropViewController(croppingStyle: croppingStyle, image: image)
        cropViewController.delegate = context.coordinator

        // Hide rotate buttons for cleaner UI
        cropViewController.rotateButtonsHidden = true
        cropViewController.rotateClockwiseButtonHidden = true

        // Wrap in navigation controller
        let navigationController = UINavigationController(rootViewController: cropViewController)
        navigationController.modalPresentationStyle = .fullScreen

        return navigationController
    }

    func updateUIViewController(_: UINavigationController, context _: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCrop: onCrop, onCancel: onCancel)
    }

    class Coordinator: NSObject, TOCropViewControllerDelegate {
        let onCrop: (UIImage) -> Void
        let onCancel: () -> Void

        init(onCrop: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onCrop = onCrop
            self.onCancel = onCancel
        }

        func cropViewController(_ cropViewController: TOCropViewController, didCropTo image: UIImage, with cropRect: CGRect, angle: Int) {
            onCrop(image)
        }

        func cropViewController(_ cropViewController: TOCropViewController, didFinishCancelled cancelled: Bool) {
            if cancelled {
                onCancel()
            }
        }
    }
}
