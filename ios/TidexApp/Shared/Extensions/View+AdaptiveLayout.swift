// swiftlint:disable:next blanket_disable_command
// swiftlint:disable line_length superfluous_disable_command
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable convenience_type explicit_acl explicit_top_level_acl explicit_type_interface
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable file_types_order no_magic_numbers type_contents_order unused_parameter
import SwiftUI
import UIKit

// MARK: - Adaptive Layout Constants

/// Standard max widths for different content types
/// These ensure content doesn't stretch too wide on iPad landscape
enum AdaptiveMaxWidth {
  /// Max width for form content (login, signup, etc.)
  static let form: CGFloat = 480

  /// Max width for onboarding content screens
  static let content: CGFloat = 560

  /// Max width for full-width onboarding containers
  static let onboarding: CGFloat = 600

  /// Max width for card-based layouts
  static let card: CGFloat = 520

  /// Max width for main tab content (matches tab bar width on iPad)
  static let tabContent: CGFloat = 500
}

// MARK: - View Modifier for Adaptive Max Width

/// Constrains content to a max width and centers it horizontally
/// Ideal for iPad landscape where full-width forms look stretched
struct AdaptiveMaxWidthModifier: ViewModifier {
  let maxWidth: CGFloat
  let alignment: Alignment

  func body(content: Content) -> some View {
    GeometryReader { geometry in
      let effectiveMaxWidth = min(maxWidth, geometry.size.width)
      content
        .frame(maxWidth: effectiveMaxWidth)
        .frame(maxWidth: .infinity, alignment: alignment)
    }
  }
}

/// Constrains content width with proper centering (non-GeometryReader version)
/// Simpler approach that works well for most cases
struct SimpleAdaptiveModifier: ViewModifier {
  let maxWidth: CGFloat

  func body(content: Content) -> some View {
    content
      .frame(maxWidth: maxWidth)
      .frame(maxWidth: .infinity)
  }
}

// MARK: - View Extensions

extension View {
  /// Constrains the view to a max width, centering it on larger screens
  /// Use for auth forms, onboarding content, etc.
  ///
  /// - Parameters:
  ///   - maxWidth: Maximum width for the content (default: form width)
  ///   - alignment: Horizontal alignment when constrained (default: center)
  func adaptiveMaxWidth(
    _ maxWidth: CGFloat = AdaptiveMaxWidth.form,
    alignment _: Alignment = .center
  ) -> some View {
    modifier(SimpleAdaptiveModifier(maxWidth: maxWidth))
  }

  /// Constrains the view to form-appropriate width for iPad
  /// Best for login, signup, password reset forms
  func adaptiveFormWidth() -> some View {
    adaptiveMaxWidth(AdaptiveMaxWidth.form)
  }

  /// Constrains the view to content-appropriate width for iPad
  /// Best for onboarding screens with mixed content
  func adaptiveContentWidth() -> some View {
    adaptiveMaxWidth(AdaptiveMaxWidth.content)
  }

  /// Constrains the view to card-appropriate width for iPad
  /// Best for card-based layouts in auth flows
  func adaptiveCardWidth() -> some View {
    adaptiveMaxWidth(AdaptiveMaxWidth.card)
  }
}

// MARK: - Truncation Fade Effect

/// View modifier that creates a fade-out effect for truncated text
/// Mimics the CSS `truncate-fade` utility from the Next.js web app
struct TruncationFadeModifier: ViewModifier {
  let fadeWidth: CGFloat

  func body(content: Content) -> some View {
    content
      .mask(
        LinearGradient(
          gradient: Gradient(stops: [
            .init(color: .black, location: 0),
            .init(color: .black, location: 1 - (fadeWidth / 200)),  // Approximate position
            .init(color: .clear, location: 1),
          ]),
          startPoint: .leading,
          endPoint: .trailing
        )
      )
  }
}

extension View {
  /// Applies a fade-out effect to truncated text
  /// Creates a smooth gradient fade at the trailing edge instead of hard truncation
  ///
  /// - Parameter fadeWidth: Width of the fade gradient (default: 24pt to match web CSS)
  func truncationFade(fadeWidth: CGFloat = 24) -> some View {
    modifier(TruncationFadeModifier(fadeWidth: fadeWidth))
  }
}

// MARK: - Horizontal Size Class Helper

/// View modifier that provides size class information
struct SizeClassReader: ViewModifier {
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  let action: (Bool) -> Void

  func body(content: Content) -> some View {
    content
      .onAppear {
        action(horizontalSizeClass == .regular)
      }
      .onChange(of: horizontalSizeClass) { _, newValue in
        action(newValue == .regular)
      }
  }
}

extension View {
  /// Executes a closure with the current regular width state
  /// Use this instead of the deprecated UIScreen.main approach
  func onSizeClass(_ action: @escaping (Bool) -> Void) -> some View {
    modifier(SizeClassReader(action: action))
  }
}

// MARK: - iPad Detection Helper

/// Check if running on iPad
private var isIPad: Bool {
  UIDevice.current.userInterfaceIdiom == .pad
}

// MARK: - iPad-Only View Modifiers

extension View {
  /// Keeps the system default toolbar appearance (no custom color/material override).
  func iPadToolbarBackground() -> some View {
    self
  }

  /// Disables toolbar animations only on iPad
  /// Prevents layout shifts when toolbar items change on iPad
  @ViewBuilder
  func iPadToolbarTransaction() -> some View {
    if isIPad {
      self.transaction { $0.animation = nil }
    } else {
      self
    }
  }

  /// Applies fixed height only on iPad to prevent toolbar layout shifts
  @ViewBuilder
  func iPadFixedHeight(_ height: CGFloat) -> some View {
    if isIPad {
      self.frame(height: height)
    } else {
      self
    }
  }
}

// MARK: - iPad Landscape Detection

/// Observable class that tracks device orientation changes
@MainActor
class OrientationTracker: ObservableObject {
  static let shared = OrientationTracker()

  @Published private(set) var isLandscape: Bool = false

  private init() {
    // Set initial value
    updateOrientation()

    // Listen for orientation changes
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(orientationDidChange),
      name: UIDevice.orientationDidChangeNotification,
      object: nil
    )
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  @objc private func orientationDidChange() {
    updateOrientation()
  }

  private func updateOrientation() {
    // Use window scene for more reliable orientation detection
    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
      if #available(iOS 26.0, *) {
        let orientation = windowScene.effectiveGeometry.interfaceOrientation
        isLandscape = orientation.isLandscape
      } else {
        let orientation = windowScene.interfaceOrientation
        isLandscape = orientation.isLandscape
      }
    } else {
      // Fallback to device orientation
      let orientation = UIDevice.current.orientation
      isLandscape = orientation.isLandscape
    }
  }
}

// MARK: - Preview

#Preview("Adaptive Width Demo") {
  VStack(spacing: Spacing.mlg) {
    Text("Form Width (480pt)")
      .padding()
      .background(Color.blue.opacity(0.2))
      .adaptiveFormWidth()

    Text("Content Width (560pt)")
      .padding()
      .background(Color.green.opacity(0.2))
      .adaptiveContentWidth()

    Text("Card Width (520pt)")
      .padding()
      .background(Color.orange.opacity(0.2))
      .adaptiveCardWidth()
  }
  .frame(maxWidth: .infinity, maxHeight: .infinity)
  .background(Color.gray.opacity(0.1))
}
