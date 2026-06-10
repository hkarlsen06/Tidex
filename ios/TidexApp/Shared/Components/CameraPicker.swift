// swiftlint:disable:next blanket_disable_command
// swiftlint:disable line_length superfluous_disable_command
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable explicit_acl explicit_top_level_acl explicit_type_interface no_empty_block
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable required_deinit type_contents_order unused_parameter
import SwiftUI
import UIKit

/// A SwiftUI wrapper for UIImagePickerController to capture photos from the camera
struct CameraPicker: UIViewControllerRepresentable {
  @Environment(\.dismiss) private var dismiss

  /// Callback with the captured image
  let onImageCaptured: (UIImage) -> Void

  func makeUIViewController(context: Context) -> UIImagePickerController {
    let picker = UIImagePickerController()
    picker.sourceType = .camera
    picker.allowsEditing = false
    picker.delegate = context.coordinator
    return picker
  }

  func updateUIViewController(_: UIImagePickerController, context _: Context) {}

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    let parent: CameraPicker

    init(parent: CameraPicker) {
      self.parent = parent
    }

    func imagePickerController(
      _: UIImagePickerController,
      didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
      if let image = info[.originalImage] as? UIImage {
        parent.onImageCaptured(image)
      }
      parent.dismiss()
    }

    func imagePickerControllerDidCancel(_: UIImagePickerController) {
      parent.dismiss()
    }
  }
}
