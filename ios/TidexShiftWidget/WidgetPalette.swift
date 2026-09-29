import SwiftUI
import UIKit

/// Widget copies of the app colors in Color+Tidex.swift and the app color assets.
/// The widget target cannot read the app's asset catalog, so the RGB values live here.
/// Each color resolves for the widget's current light or dark appearance.
internal enum WidgetPalette {
  /// TidexBlue (#2563EB), the same in light and dark mode
  internal static let blue: Color = .init(red: 0.145, green: 0.388, blue: 0.922)

  /// TidexBlueText (light #1D4ED8, dark #7AA0F3). Use for blue text; `blue` is only a fill.
  internal static let blueText: Color = adaptive(
    light: UIColor(red: 0.114, green: 0.306, blue: 0.847, alpha: 1),
    dark: UIColor(red: 0.478, green: 0.627, blue: 0.953, alpha: 1)
  )

  /// TidexSuccess (light #0F703C, dark #22C55E). Use for green text and indicators.
  internal static let success: Color = adaptive(
    light: UIColor(red: 0.059, green: 0.439, blue: 0.235, alpha: 1),
    dark: UIColor(red: 0.133, green: 0.773, blue: 0.369, alpha: 1)
  )

  /// TidexBackground
  internal static let background: Color = adaptive(
    light: UIColor(red: 0.961, green: 0.961, blue: 0.953, alpha: 1),
    dark: UIColor(red: 0.027, green: 0.043, blue: 0.071, alpha: 1)
  )

  /// TidexTextPrimary
  internal static let textPrimary: Color = adaptive(
    light: UIColor(red: 0.133, green: 0.149, blue: 0.176, alpha: 1),
    dark: UIColor(red: 0.953, green: 0.957, blue: 0.965, alpha: 1)
  )

  /// TidexTextSecondary
  internal static let textSecondary: Color = adaptive(
    light: UIColor(red: 0.318, green: 0.345, blue: 0.380, alpha: 1),
    dark: UIColor(red: 0.741, green: 0.765, blue: 0.796, alpha: 1)
  )

  /// TidexTextMuted
  internal static let textMuted: Color = adaptive(
    light: UIColor(red: 0.384, green: 0.412, blue: 0.451, alpha: 1),
    dark: UIColor(red: 0.604, green: 0.639, blue: 0.686, alpha: 1)
  )

  private static func adaptive(light: UIColor, dark: UIColor) -> Color {
    Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
  }
}
