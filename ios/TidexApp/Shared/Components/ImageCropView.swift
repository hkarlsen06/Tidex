// swiftlint:disable:next blanket_disable_command
// swiftlint:disable line_length superfluous_disable_command
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable explicit_acl explicit_top_level_acl explicit_type_interface no_empty_block
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable required_deinit sorted_imports type_contents_order unused_parameter
import CropViewController
import SwiftUI

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
      _: CropViewController, didCropToImage image: UIImage, withRect _: CGRect,
      angle _: Int
    ) {
      onCrop(image)
    }

    func cropViewController(
      _: CropViewController, didCropToCircularImage image: UIImage, withRect _: CGRect,
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
