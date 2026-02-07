import SwiftUI

/// Design system corner radius constants.
/// Provides consistent border radii throughout the app.
///
/// Usage:
/// ```swift
/// RoundedRectangle(cornerRadius: CornerRadius.lg)
/// .clipShape(RoundedRectangle(cornerRadius: CornerRadius.card))
/// ```
enum CornerRadius {
  /// 4pt - Pills, badges, toggles
  static let xxs: CGFloat = 4

  /// 6pt - Small UI elements, settings icons
  static let xs: CGFloat = 6

  /// 8pt - Input fields, chips
  static let sm: CGFloat = 8

  /// 10pt - Buttons, small cards
  static let md: CGFloat = 10

  /// 12pt - Cards, sections
  static let lg: CGFloat = 12

  /// 14pt - Medium cards
  static let xl: CGFloat = 14

  /// 16pt - Large cards
  static let xxl: CGFloat = 16

  /// 20pt - Major cards, sheets
  static let xxxl: CGFloat = 20

  /// 18pt - Chat bubbles
  static let bubble: CGFloat = 18

  /// 24pt - Primary shift cards
  static let card: CGFloat = 24

  /// 32pt - Pill shapes, large overlays
  static let pill: CGFloat = 32
}
