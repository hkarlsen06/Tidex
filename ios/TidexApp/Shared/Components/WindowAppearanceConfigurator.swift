import SwiftUI
import UIKit

/// Applies the cached app theme to the hosting window as soon as it is attached.
@MainActor
struct WindowAppearanceConfigurator: UIViewRepresentable {
  func makeUIView(context: Context) -> WindowAppearanceHostingView {
    WindowAppearanceHostingView()
  }

  func updateUIView(_ uiView: WindowAppearanceHostingView, context: Context) {
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
