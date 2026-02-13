import SwiftUI
import CropViewController

/// Reusable SwiftUI wrapper for CropViewController
/// Provides a familiar iOS Photos-style cropping experience
struct ImageCropView: UIViewControllerRepresentable {
  let image: UIImage
  let croppingStyle: CropViewCroppingStyle
  let onCrop: (UIImage) -> Void
  let onCancel: () -> Void

  init(
    image: UIImage,
    croppingStyle: CropViewCroppingStyle = .circular,
    onCrop: @escaping (UIImage) -> Void,
    onCancel: @escaping () -> Void
  ) {
    self.image = image
    self.croppingStyle = croppingStyle
    self.onCrop = onCrop
    self.onCancel = onCancel
  }

  func makeUIViewController(context: Context) -> UINavigationController {
    let cropViewController = CropViewController(croppingStyle: croppingStyle, image: image)
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
