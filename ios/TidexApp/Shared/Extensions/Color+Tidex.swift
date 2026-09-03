// swiftlint:disable:next blanket_disable_command
// swiftlint:disable line_length superfluous_disable_command
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable explicit_acl explicit_top_level_acl explicit_type_interface file_types_order
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable line_length multiline_arguments_brackets no_magic_numbers sorted_enum_cases
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable type_contents_order vertical_whitespace_between_cases
import SwiftUI
import UIKit

// MARK: - Tidex Adaptive Color System
//
// This color system automatically adapts to iOS system appearance (light/dark mode).
// Semantic text, filled-control, and boundary tokens are chosen against WCAG 2.x
// contrast formulas: text and filled-control foregrounds meet AA contrast, while
// surface boundaries meet the 3:1 non-text contrast requirement.
//
// Usage: Always use these semantic colors in views (e.g., Color.tidexBackground)
// rather than hardcoded values. This ensures consistent theming across the app.

extension Color {
  /// Launch screen background - adapts to light/dark mode
  /// Light: soft off-white (matches tidexBackground)
  /// Dark: deep navy (matches tidexBackground)
  static var tidexLaunchBackground: Color {
    Color("LaunchBackground")
  }

  /// Legacy alias retained only to provide compiler guidance.
  @available(
    *, unavailable, renamed: "tidexTextReversedByTheme",
    message:
      "Use tidexTextReversedByTheme for theme-reversed text, or role tokens (tidexTextOnBrand/tidexTextOnWarning/tidexTextOnDanger/tidexTextOnSuccess) for filled controls."
  )
  static var tidexTextInverse: Color {
    tidexTextReversedByTheme
  }

  /// Info color - blue (matches brand)
  static var tidexInfo: Color {
    tidexBlue
  }

  /// Purple color for Max tier branding
  /// HSlocalized(258, 70%, 60%) - vibrant purple
  static var tidexPurple: Color {
    Color(hue: 258 / 360, saturation: 0.70, brightness: 0.75)
  }

  /// Employment analytics accent - green with stronger contrast on dark chart surfaces.
  static var tidexEmploymentAccent: Color {
    tidexSuccess
  }

  // MARK: - Gradient Colors

  /// Logo gradient colors from short-logo-gradient.svg
  /// These remain constant regardless of appearance mode
  static let logoGradientColors = [
    Color(red: 0, green: 212 / 255, blue: 1),  // #00D4FF - cyan (top)
    Color(red: 123 / 255, green: 97 / 255, blue: 1),  // #7B61FF - purple (middle)
    Color(red: 155 / 255, green: 77 / 255, blue: 202 / 255),  // #9B4DCA - magenta (bottom)
  ]

}

// MARK: - Programmatic Adaptive Colors
//
// These are used as fallbacks and for the widget (which can't access main app assets)

extension Color {
  /// Light mode background - soft off-white
  static let tidexLightBackground = Color(hue: 220 / 360, saturation: 0.40, brightness: 0.98)

  /// Dark mode background - deep navy
  static let tidexDarkBackgroundColor = Color(hue: 222.2 / 360, saturation: 0.84, brightness: 0.11)

  /// Light mode surface primary - Pure white for maximum contrast against blue-tinted background
  static let tidexLightSurfacePrimary = Color.white

  /// Dark mode surface primary - same navy hue family as the app background (#151F32)
  static let tidexDarkSurfacePrimary = Color(red: 0.082, green: 0.122, blue: 0.196)

  /// Light mode surface secondary - lifted blue-gray for contrast against app backgrounds (#EAF0F7)
  static let tidexLightSurfaceSecondary = Color(red: 0.918, green: 0.941, blue: 0.969)

  /// Dark mode surface secondary - lifted navy for nested controls (#1B2942)
  static let tidexDarkSurfaceSecondary = Color(red: 0.106, green: 0.161, blue: 0.259)

  /// Light mode text primary
  static let tidexLightTextPrimary = Color(hue: 222 / 360, saturation: 0.84, brightness: 0.08)

  /// Dark mode text primary
  static let tidexDarkTextPrimary = Color(hue: 210 / 360, saturation: 0.40, brightness: 0.98)

  /// Light mode text secondary
  static let tidexLightTextSecondary = Color(hue: 214 / 360, saturation: 0.28, brightness: 0.35)

  /// Dark mode text secondary
  static let tidexDarkTextSecondary = Color(hue: 214 / 360, saturation: 0.32, brightness: 0.85)

  /// Light mode text muted - Darker for better contrast (#596B80)
  static let tidexLightTextMuted = Color(red: 0.35, green: 0.42, blue: 0.50)

  /// Dark mode text muted
  static let tidexDarkTextMuted = Color(hue: 215 / 360, saturation: 0.20, brightness: 0.70)

  /// Light mode brand blue - WCAG AA with tidexTextOnBrand
  static let tidexLightBlue = Color(red: 0.145, green: 0.388, blue: 0.922)

  /// Dark mode brand blue - WCAG AA with tidexTextOnBrand
  static let tidexDarkBlue = tidexLightBlue

  /// Light mode border - WCAG non-text boundary against light surfaces (#838A94)
  static let tidexLightBorder = Color(red: 0.514, green: 0.541, blue: 0.580)

  /// Dark mode border - WCAG non-text boundary against dark surfaces (#6B7280)
  static let tidexDarkBorder = Color(red: 0.420, green: 0.447, blue: 0.502)

  /// Light mode subtle border - intentionally shares the compliant surface boundary color.
  static let tidexLightBorderSubtle = tidexLightBorder

  /// Dark mode subtle border - intentionally shares the compliant surface boundary color.
  static let tidexDarkBorderSubtle = tidexDarkBorder

  /// Default glass surface tint, matched to the lifted surface color.
  static var tidexGlassSurface: Color {
    Color(
      UIColor { traitCollection in
        switch traitCollection.userInterfaceStyle {
        case .dark:
          return UIColor(red: 0.082, green: 0.122, blue: 0.196, alpha: 1)

        default:
          return UIColor.white
        }
      })
  }
}

// MARK: - Card Shadow Colors
//
// Subtle shadows for elevated card surfaces in light mode
// iOS-native approach to add depth and visual separation

extension Color {
  /// Light mode card shadow - subtle blue-gray shadow
  static let tidexCardShadowLight = Color(red: 0.4, green: 0.45, blue: 0.55).opacity(0.12)

  /// Dark mode card shadow - deeper shadow for contrast
  static let tidexCardShadowDark = Color.black.opacity(0.4)
}

// MARK: - Card Shadow View Modifiers
//
// iOS-native shadow styles for elevated surfaces
// Light mode uses drop shadows; dark mode uses a directional rim highlight.

/// Shadow elevation levels for cards
enum TidexShadowLevel {
  /// Very light shadow for nested/inner cards
  case subtle
  /// Subtle shadow for standard cards (shift cards, settings rows)
  case card
  /// Medium shadow for modals and popovers
  case elevated
  /// Strong shadow for floating action buttons
  case floating
}

/// View modifier that applies adaptive card elevation.
struct TidexCardShadowModifier: ViewModifier {
  @Environment(\.colorScheme) private var colorScheme
  let level: TidexShadowLevel
  let customCornerRadius: CGFloat?

  func body(content: Content) -> some View {
    if colorScheme == .dark {
      content.overlay(
        RoundedRectangle(cornerRadius: cornerRadius)
          .strokeBorder(
            LinearGradient(
              colors: [
                Color.tidexTextPrimary.opacity(rimOpacity),
                Color.tidexTextPrimary.opacity(rimOpacity * 0.3),
                Color.clear,
              ],
              startPoint: .top,
              endPoint: .bottom
            ),
            lineWidth: 1
          )
      )
    } else {
      content.shadow(
        color: shadowColor,
        radius: shadowRadius,
        x: 0,
        y: shadowY
      )
    }
  }

  private var cornerRadius: CGFloat {
    if let customCornerRadius {
      return customCornerRadius
    }

    switch level {
    case .subtle:
      return 12

    case .card:
      return 24

    case .elevated:
      return 20

    case .floating:
      return 16
    }
  }

  private var rimOpacity: Double {
    switch level {
    case .subtle:
      return 0.06

    case .card:
      return 0.08

    case .elevated:
      return 0.12

    case .floating:
      return 0.15
    }
  }

  private var shadowColor: Color {
    switch level {
    case .subtle:
      return Color(red: 0.4, green: 0.45, blue: 0.55).opacity(0.06)

    case .card:
      return Color(red: 0.4, green: 0.45, blue: 0.55).opacity(0.10)

    case .elevated:
      return Color(red: 0.4, green: 0.45, blue: 0.55).opacity(0.15)

    case .floating:
      return Color(red: 0.4, green: 0.45, blue: 0.55).opacity(0.20)
    }
  }

  private var shadowRadius: CGFloat {
    switch level {
    case .subtle:
      return 4

    case .card:
      return 8

    case .elevated:
      return 16

    case .floating:
      return 24
    }
  }

  private var shadowY: CGFloat {
    switch level {
    case .subtle:
      return 1

    case .card:
      return 2

    case .elevated:
      return 4

    case .floating:
      return 8
    }
  }
}

extension View {
  /// Applies a subtle card shadow that adapts to light/dark mode
  /// Use on cards, list rows, and other elevated surfaces
  /// - Parameters:
  ///   - level: Shadow intensity level (default: .card)
  ///   - cornerRadius: Custom corner radius for the dark-mode rim.
  func tidexCardShadow(
    _ level: TidexShadowLevel = .card,
    cornerRadius: CGFloat? = nil
  ) -> some View {
    modifier(TidexCardShadowModifier(level: level, customCornerRadius: cornerRadius))
  }

  /// Applies the standard contained row surface for custom lists and sheets.
  func tidexRowSurface(
    cornerRadius: CGFloat,
    fillColor: Color = .tidexSurfacePrimary,
    shadowLevel: TidexShadowLevel = .subtle
  ) -> some View {
    modifier(
      TidexRowSurfaceModifier(
        cornerRadius: cornerRadius,
        fillColor: fillColor,
        shadowLevel: shadowLevel
      ))
  }

  /// Applies a subtle shadow for small chips and status badges
  /// Creates consistent 3D appearance across all chip styles
  func tidexChipShadow() -> some View {
    modifier(TidexChipShadowModifier())
  }
}

struct TidexRowSurfaceModifier: ViewModifier {
  @Environment(\.colorScheme) private var colorScheme
  let cornerRadius: CGFloat
  let fillColor: Color
  let shadowLevel: TidexShadowLevel

  func body(content: Content) -> some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

    content
      .background(shape.fill(fillColor))
      .clipShape(shape)
      .overlay(
        shape.strokeBorder(Color.tidexBorderSubtle.opacity(borderOpacity), lineWidth: 1)
      )
      .tidexCardShadow(shadowLevel, cornerRadius: cornerRadius)
  }

  private var borderOpacity: Double {
    colorScheme == .dark ? 0.48 : 0.28
  }
}

/// View modifier for subtle chip/badge shadows
/// Lighter than card shadows, suitable for small UI elements
struct TidexChipShadowModifier: ViewModifier {
  @Environment(\.colorScheme) private var colorScheme

  func body(content: Content) -> some View {
    content
      .shadow(
        color: shadowColor,
        radius: shadowRadius,
        x: 0,
        y: shadowY
      )
  }

  private var shadowColor: Color {
    colorScheme == .light
      ? Color(red: 0.4, green: 0.45, blue: 0.55).opacity(0.15)
      : Color.black.opacity(0.35)
  }

  private var shadowRadius: CGFloat {
    colorScheme == .light ? 3 : 2
  }

  private var shadowY: CGFloat {
    1
  }
}
