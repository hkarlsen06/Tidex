import SwiftUI
import UIKit

/// Copies of the app's surface colors for code in ios/Shared that also runs in the share extension.
/// The extension cannot read the app's asset catalog, so the RGB values mirror the Tidex color
/// assets and the fallbacks in Color+Tidex.swift. Each color follows the current light or dark mode.
enum SharedPalette {
  /// TidexBackground
  static let background: Color = adaptive(
    light: UIColor(red: 0.961, green: 0.961, blue: 0.953, alpha: 1),
    dark: UIColor(red: 0.027, green: 0.043, blue: 0.071, alpha: 1)
  )

  /// TidexSurfacePrimary
  static let surfacePrimary: Color = adaptive(
    light: .white,
    dark: UIColor(red: 0.082, green: 0.114, blue: 0.165, alpha: 1)
  )

  /// TidexSurfaceSecondary
  static let surfaceSecondary: Color = adaptive(
    light: UIColor(red: 0.914, green: 0.922, blue: 0.929, alpha: 1),
    dark: UIColor(red: 0.125, green: 0.169, blue: 0.235, alpha: 1)
  )

  /// TidexTextSecondary
  static let textSecondary: Color = adaptive(
    light: UIColor(red: 0.318, green: 0.345, blue: 0.380, alpha: 1),
    dark: UIColor(red: 0.741, green: 0.765, blue: 0.796, alpha: 1)
  )

  /// TidexBlueText (light #1D4ED8, dark #7AA0F3)
  static let blueText: Color = adaptive(
    light: UIColor(red: 0.114, green: 0.306, blue: 0.847, alpha: 1),
    dark: UIColor(red: 0.478, green: 0.627, blue: 0.953, alpha: 1)
  )

  /// TidexError (light #B42D2E, dark #F56B6B)
  static let error: Color = adaptive(
    light: UIColor(red: 0.706, green: 0.176, blue: 0.180, alpha: 1),
    dark: UIColor(red: 0.961, green: 0.420, blue: 0.420, alpha: 1)
  )

  private static func adaptive(light: UIColor, dark: UIColor) -> Color {
    Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
  }
}
