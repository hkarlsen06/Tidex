import SwiftUI
import UIKit

extension ProfileSettingsView {
  /// Resize `image` to a `size`x`size` square in pixels, independent of screen scale.
  /// `UIGraphicsImageRenderer(size:)` defaults to the screen's scale, so on a 3x device
  /// a "192x192" render would produce a 576x576 pixel image.
  static func resizedAvatarImage(_ image: UIImage, to size: CGFloat) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let renderer = UIGraphicsImageRenderer(
      size: CGSize(width: size, height: size), format: format)
    return renderer.image { _ in
      image.draw(in: CGRect(origin: .zero, size: CGSize(width: size, height: size)))
    }
  }
}
