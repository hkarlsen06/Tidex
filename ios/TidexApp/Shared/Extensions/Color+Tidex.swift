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
  /// Dark: deep ink (matches tidexBackground)
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

  /// Decorative dividers; use tidexBorder for input and control boundaries.
  static var tidexSeparator: Color {
    tidexTextPrimary.opacity(0.10)
  }

}

// MARK: - Programmatic Adaptive Colors
//
// These are used as fallbacks and for the widget (which can't access main app assets)

extension Color {
  /// Light mode background - soft off-white
  static let tidexLightBackground = Color(red: 0.961, green: 0.961, blue: 0.953)

  /// Dark mode background - deep ink
  static let tidexDarkBackgroundColor = Color(red: 0.027, green: 0.043, blue: 0.071)

  /// Light mode surface primary - white against the neutral canvas
  static let tidexLightSurfacePrimary = Color(red: 1.000, green: 1.000, blue: 1.000)

  /// Dark mode surface primary - lifted ink surface
  static let tidexDarkSurfacePrimary = Color(red: 0.082, green: 0.114, blue: 0.165)

  /// Light mode surface secondary - neutral gray for nested controls
  static let tidexLightSurfaceSecondary = Color(red: 0.914, green: 0.922, blue: 0.929)

  /// Dark mode surface secondary - blue-gray for nested controls
  static let tidexDarkSurfaceSecondary = Color(red: 0.125, green: 0.169, blue: 0.235)

  /// Light mode text primary
  static let tidexLightTextPrimary = Color(red: 0.133, green: 0.149, blue: 0.176)

  /// Dark mode text primary
  static let tidexDarkTextPrimary = Color(red: 0.953, green: 0.957, blue: 0.965)

  /// Light mode text secondary
  static let tidexLightTextSecondary = Color(red: 0.318, green: 0.345, blue: 0.380)

  /// Dark mode text secondary
  static let tidexDarkTextSecondary = Color(red: 0.741, green: 0.765, blue: 0.796)

  /// Light mode text muted - readable neutral gray
  static let tidexLightTextMuted = Color(red: 0.384, green: 0.412, blue: 0.451)

  /// Dark mode text muted
  static let tidexDarkTextMuted = Color(red: 0.604, green: 0.639, blue: 0.686)

  /// Light mode brand blue - WCAG AA with tidexTextOnBrand
  static let tidexLightBlue = Color(red: 0.145, green: 0.388, blue: 0.922)

  /// Dark mode brand blue - WCAG AA with tidexTextOnBrand
  static let tidexDarkBlue = tidexLightBlue

  /// Light mode border - WCAG non-text boundary against light surfaces (#7F858E)
  static let tidexLightBorder = Color(red: 0.498, green: 0.522, blue: 0.557)

  /// Dark mode border - WCAG non-text boundary against dark surfaces (#767E89)
  static let tidexDarkBorder = Color(red: 0.463, green: 0.494, blue: 0.537)

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
          return UIColor(red: 0.082, green: 0.114, blue: 0.165, alpha: 1)

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
enum TidexShadowLevel: Equatable {
  /// Flat treatment for nested content
  case subtle
  /// Flat treatment for standard cards (shift cards, settings rows)
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
    if level == .subtle || level == .card {
      content
    } else if colorScheme == .dark {
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
  /// Keeps content cards flat and elevates modal or floating surfaces
  /// Reserve visible elevation for controls that float above the content.
  /// - Parameters:
  ///   - level: Shadow intensity level (default: .card)
  ///   - cornerRadius: Custom corner radius for the dark-mode rim.
  func tidexCardShadow(
    _ level: TidexShadowLevel = .card,
    cornerRadius: CGFloat? = nil
  ) -> some View {
    modifier(TidexCardShadowModifier(level: level, customCornerRadius: cornerRadius))
  }

  /// Applies a flat contained row surface; opt into elevation only for standalone cards.
  func tidexRowSurface(
    cornerRadius: CGFloat,
    fillColor: Color = .tidexSurfacePrimary,
    shadowLevel: TidexShadowLevel? = nil
  ) -> some View {
    modifier(
      TidexRowSurfaceModifier(
        cornerRadius: cornerRadius,
        fillColor: fillColor,
        shadowLevel: shadowLevel
      ))
  }

  /// Keeps chips flat within their containing surface.
  func tidexChipShadow() -> some View {
    modifier(TidexChipShadowModifier())
  }
}

struct TidexRowSurfaceModifier: ViewModifier {
  let cornerRadius: CGFloat
  let fillColor: Color
  let shadowLevel: TidexShadowLevel?

  @ViewBuilder
  func body(content: Content) -> some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

    if let shadowLevel {
      content
        .background(shape.fill(fillColor))
        .clipShape(shape)
        .tidexCardShadow(shadowLevel, cornerRadius: cornerRadius)
    } else {
      content
        .background(shape.fill(fillColor))
        .clipShape(shape)
    }
  }
}

/// Chips sit within content rather than floating above it.
struct TidexChipShadowModifier: ViewModifier {
  func body(content: Content) -> some View {
    content
  }
}
