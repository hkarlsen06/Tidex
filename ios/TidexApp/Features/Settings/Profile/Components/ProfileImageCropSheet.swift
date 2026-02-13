import SwiftUI
import CropViewController

/// Sheet wrapper for cropping profile images using CropViewController
struct ProfileImageCropSheet: UIViewControllerRepresentable {
  let image: UIImage
  let onCrop: (UIImage) -> Void
  let onCancel: () -> Void

  func makeUIViewController(context: Context) -> UINavigationController {
    // Use circular cropping style - perfect for profile pictures
    let cropViewController = CropViewController(croppingStyle: .circular, image: image)
    cropViewController.delegate = context.coordinator

    // Hide rotate buttons for cleaner UI
    cropViewController.rotateButtonsHidden = true
    cropViewController.rotateClockwiseButtonHidden = true

    // Customize button titles
    cropViewController.doneButtonTitle = NSLocalizedString("profile.imageCrop.confirm", comment: "")
    cropViewController.cancelButtonTitle = NSLocalizedString("common.cancel", comment: "")

    // Wrap in navigation controller for proper presentation
    let navigationController = UINavigationController(rootViewController: cropViewController)
    navigationController.modalPresentationStyle = .fullScreen

    return navigationController
  }

  func updateUIViewController(_: UINavigationController, context _: Context) {}

  func makeCoordinator() -> Coordinator {
    Coordinator(onCrop: onCrop, onCancel: onCancel)
  }

  class Coordinator: NSObject, CropViewControllerDelegate {
    let onCrop: (UIImage) -> Void
    let onCancel: () -> Void

    init(onCrop: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
      self.onCrop = onCrop
      self.onCancel = onCancel
    }

    func cropViewController(
      _ cropViewController: CropViewController, didCropToImage image: UIImage, withRect cropRect: CGRect,
      angle: Int
    ) {
      onCrop(image)
    }

    func cropViewController(
      _ cropViewController: CropViewController, didCropToCircularImage image: UIImage, withRect cropRect: CGRect,
      angle: Int
    ) {
      onCrop(image)
    }

    func cropViewController(
      _ cropViewController: CropViewController, didFinishCancelled cancelled: Bool
    ) {
      if cancelled {
        onCancel()
      }
    }
  }
}

// MARK: - Preview

// swiftlint:disable force_unwrapping
#Preview {
  ProfileImageCropSheet(
    image: UIImage(systemName: "person.circle.fill")!,
    onCrop: { _ in },
    onCancel: {}
  )
}
// swiftlint:enable force_unwrapping
