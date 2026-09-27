import SwiftUI
import UIKit

/// Widget copies of the app colors in Color+Tidex.swift and the app color assets.
/// The widget target cannot read the app's asset catalog, so the RGB values live here.
/// Each color resolves for the widget's current light or dark appearance.
internal enum WidgetPalette {
  /// TidexBlue (#2563EB), the same in light and dark mode
  internal static let blue: Color = .init(red: 0.145, green: 0.388, blue: 0.922)

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
