// swiftlint:disable:next blanket_disable_command
// swiftlint:disable line_length superfluous_disable_command
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable explicit_acl explicit_top_level_acl
import SwiftUI

/// Design system spacing constants based on 8pt grid system.
/// All spacing values are multiples of 4pt (half-unit) for flexibility.
///
/// Usage:
/// ```swift
/// .padding(.horizontal, Spacing.md)
/// HStack(spacing: Spacing.sm) { ... }
/// .frame(height: Spacing.buttonHeight)
/// ```
enum Spacing {
  // MARK: - Base Units

  /// 2pt - Micro spacing (tight UI elements)
  static let micro: CGFloat = 2

  /// 4pt - Half unit, for tight spacing (icon pairs, compact lists)
  static let xxs: CGFloat = 4

  /// 6pt - Extra small spacing
  static let xxxs: CGFloat = 6

  /// 8pt - Base unit, compact spacing
  static let xs: CGFloat = 8

  /// 10pt - Between xs and sm
  static let xsm: CGFloat = 10

  /// 12pt - 1.5 units, standard small spacing
  static let sm: CGFloat = 12

  /// 14pt - Between sm and md
  static let msm: CGFloat = 14

  /// 16pt - 2 units, standard content spacing
  static let md: CGFloat = 16

  /// 20pt - 2.5 units, card inset spacing
  static let mlg: CGFloat = 20

  /// 24pt - 3 units, large spacing (section gaps)
  static let lg: CGFloat = 24

  /// 32pt - 4 units, extra large spacing
  static let xl: CGFloat = 32

  /// 40pt - 5 units, major section spacing
  static let xxl: CGFloat = 40

  /// 48pt - 6 units
  static let xxxl: CGFloat = 48

  /// 56pt - 7 units
  static let huge: CGFloat = 56

  // MARK: - Component Heights

  /// Standard button height (48pt)
  static let buttonHeight: CGFloat = 48

  /// Standard icon size (24pt)
  static let iconSize: CGFloat = 24

  /// Small icon size (16pt)
  static let iconSizeSmall: CGFloat = 16

  /// Large icon size (32pt)
  static let iconSizeLarge: CGFloat = 32

  // MARK: - Layout Constants

  /// Standard horizontal content padding
  static let contentHorizontal: CGFloat = 16

  /// Standard vertical content padding
  static let contentVertical: CGFloat = 16

  /// Card internal padding
  static let cardPadding: CGFloat = 24

  /// Bottom scroll margin (for floating elements)
  static let bottomScrollMargin: CGFloat = 80
}
