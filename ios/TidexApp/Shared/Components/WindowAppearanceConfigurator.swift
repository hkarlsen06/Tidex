// swiftlint:disable:next blanket_disable_command
// swiftlint:disable line_length superfluous_disable_command
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable conditional_returns_on_newline explicit_acl explicit_top_level_acl explicit_type_interface
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable file_types_order required_deinit unused_parameter
import SwiftUI
import UIKit

/// Applies the cached app theme to the hosting window as soon as it is attached.
@MainActor
struct WindowAppearanceConfigurator: UIViewRepresentable {
  func makeUIView(context _: Context) -> WindowAppearanceHostingView {
    WindowAppearanceHostingView()
  }

  func updateUIView(_ uiView: WindowAppearanceHostingView, context _: Context) {
    uiView.applyCachedAppearance()
  }
}

@MainActor
final class WindowAppearanceHostingView: UIView {
  override func didMoveToWindow() {
    super.didMoveToWindow()
    applyCachedAppearance()
  }

  func applyCachedAppearance() {
    guard let window else { return }

    let style = AppearanceManager.shared.theme.userInterfaceStyle
    if window.overrideUserInterfaceStyle != style {
      window.overrideUserInterfaceStyle = style
    }

    if window.rootViewController?.overrideUserInterfaceStyle != style {
      window.rootViewController?.overrideUserInterfaceStyle = style
    }
  }
}
