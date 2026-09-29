import CropViewController
import SwiftUI

/// Sheet wrapper for cropping profile images using CropViewController
struct ProfileImageCropSheet: UIViewControllerRepresentable {
  let image: UIImage
  let onCrop: (UIImage) -> Void
  let onCancel: () -> Void

  func makeUIViewController(context: Context) -> UINavigationController {
    // Use default (square) cropping style - squircle clipping is applied at display time
    let cropViewController = CropViewController(croppingStyle: .default, image: image)
    cropViewController.delegate = context.coordinator

    // Hide rotate buttons for cleaner UI
    cropViewController.rotateButtonsHidden = true
    cropViewController.rotateClockwiseButtonHidden = true

    // Lock to square aspect ratio for avatar use
    cropViewController.aspectRatioPreset = CGSize(width: 1, height: 1)
    cropViewController.aspectRatioLockEnabled = true
    cropViewController.resetAspectRatioEnabled = false
    cropViewController.aspectRatioPickerButtonHidden = true

    // One instruction above the photo, and the confirm action in brand blue instead of the library's yellow.
    // iOS 26 and later show icon-only toolbar buttons without VoiceOver labels, so label them here.
    cropViewController.title = String(localized: .profileImageCropTitle)
    cropViewController.doneButtonColor = UIColor(Color.tidexBlue)
    cropViewController.toolbar.doneIconButton.accessibilityLabel = String(localized: .profileImageCropConfirm)
    cropViewController.toolbar.cancelIconButton.accessibilityLabel = String(localized: .commonCancel)

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
      _: CropViewController, didCropToImage image: UIImage,
      withRect _: CGRect,
      angle _: Int
    ) {
      onCrop(image)
    }

    func cropViewController(
      _: CropViewController, didCropToCircularImage image: UIImage,
      withRect _: CGRect,
      angle _: Int
    ) {
      onCrop(image)
    }

    func cropViewController(
      _: CropViewController, didFinishCancelled cancelled: Bool
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
