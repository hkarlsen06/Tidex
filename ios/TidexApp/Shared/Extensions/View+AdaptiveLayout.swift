// swiftlint:disable:next blanket_disable_command
// swiftlint:disable line_length superfluous_disable_command
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable convenience_type explicit_acl explicit_top_level_acl explicit_type_interface
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable file_types_order no_magic_numbers type_contents_order unused_parameter
import SwiftUI

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

private struct AdaptiveToolbarTransaction: ViewModifier {
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  func body(content: Content) -> some View {
    content.transaction { transaction in
      if horizontalSizeClass == .regular {
        transaction.animation = nil
      }
    }
  }
}

private struct AdaptiveFixedHeight: ViewModifier {
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  let height: CGFloat

  func body(content: Content) -> some View {
    content.frame(height: horizontalSizeClass == .regular ? height : nil)
  }
}

extension View {
  func adaptiveToolbarTransaction() -> some View {
    modifier(AdaptiveToolbarTransaction())
  }

  func adaptiveFixedHeight(_ height: CGFloat) -> some View {
    modifier(AdaptiveFixedHeight(height: height))
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
