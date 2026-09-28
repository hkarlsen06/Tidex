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

  private static func adaptive(light: UIColor, dark: UIColor) -> Color {
    Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
  }
}
