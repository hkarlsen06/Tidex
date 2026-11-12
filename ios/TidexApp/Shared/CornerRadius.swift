// swiftlint:disable:next blanket_disable_command
// swiftlint:disable line_length superfluous_disable_command
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable explicit_acl explicit_top_level_acl
import SwiftUI

/// Corner radii for the app's rounded shapes, ordered by size.
///
/// Main action buttons draw as `Capsule()` and person avatars as `Circle()`,
/// so neither has a token here.
///
/// ```swift
/// .clipShape(RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous))
/// ```
enum CornerRadius {
  /// 4pt. Small bars, skeleton lines, indicators and bubble tails.
  static let xxs: CGFloat = 4

  /// 6pt. Small icons, skeleton blocks and inline value boxes.
  static let xs: CGFloat = 6

  /// 8pt. Chips, badges and compact inline buttons.
  static let sm: CGFloat = 8

  /// 10pt. Option buttons, workplace badges, inline banners and admin tiles.
  static let md: CGFloat = 10

  /// 12pt. Option cards, rule cards, picker backgrounds and small panels.
  static let lg: CGFloat = 12

  /// 12pt. Text fields, note editors and code boxes.
  static let field: CGFloat = 12

  /// 14pt. Share destination tiles and the shareable calendar.
  static let xl: CGFloat = 14

  /// 16pt. Sheet sections and detail cards.
  static let xxl: CGFloat = 16

  /// 18pt. Chat bubbles.
  static let bubble: CGFloat = 18

  /// 20pt. Shift, friend and dashboard cards, toasts and status pills.
  static let card: CGFloat = 20

  /// 32pt. Floating panels and prompts.
  static let panel: CGFloat = 32
}
