import SwiftUI

/// Design system typography constants using SF Pro.
/// Provides semantic text styles for consistent hierarchy throughout the app.
///
/// Usage:
/// ```swift
/// Text("Welcome")
///     .font(.tidexTitle)
///
/// Text("24 380 kr")
///     .font(.tidexAmountLarge)
/// ```
extension Font {
  // MARK: - Display (Large Numbers)
  // These use scaled fonts to maintain visual impact while respecting Dynamic Type

  /// 56pt bold - Extra large currency displays (scales with Dynamic Type)
  static var tidexDisplay: Font {
    scaledFont(baseSize: 56, weight: .bold, relativeTo: .largeTitle)
  }

  /// 56pt bold - Dashboard stat values (scales with Dynamic Type)
  static var tidexStat: Font {
    scaledFont(baseSize: 56, weight: .bold, relativeTo: .largeTitle)
  }

  /// 40pt bold - Secondary stat values (scales with Dynamic Type)
  static var tidexStatSecondary: Font {
    scaledFont(baseSize: 40, weight: .bold, relativeTo: .title)
  }

  /// 88pt bold - Hero total card amount (scales with Dynamic Type)
  static var tidexHeroAmount: Font {
    scaledFont(baseSize: 88, weight: .bold, relativeTo: .largeTitle)
  }

  /// 32pt bold rounded - Large amounts (scales with Dynamic Type)
  static var tidexAmountLarge: Font {
    scaledFont(baseSize: 32, weight: .bold, relativeTo: .title2, design: .rounded)
  }

  // MARK: - Scaled Font Helper

  /// Creates a font that scales with Dynamic Type while maintaining a custom base size.
  private static func scaledFont(
    baseSize: CGFloat,
    weight: Font.Weight,
    relativeTo textStyle: Font.TextStyle,
    design: Font.Design = .default
  ) -> Font {
    let metrics = UIFontMetrics(forTextStyle: textStyle.uiKit)
    let scaledSize = metrics.scaledValue(for: baseSize)
    return Font.system(size: scaledSize, weight: weight, design: design)
  }

  // MARK: - Headings

  /// 24pt bold - Screen titles, primary headings
  static let tidexLargeTitle = Font.system(.title2, design: .default).weight(.bold)

  /// 22pt bold - Card headers, secondary titles
  static let tidexTitle = Font.system(.title3, design: .default).weight(.bold)

  /// 20pt bold - Tertiary titles
  static let tidexTitle2 = Font.system(.headline, design: .default).weight(.bold)

  /// 18pt semibold - Section headers, emphasis
  static let tidexHeadline = Font.system(.headline, design: .default)

  // MARK: - Body

  /// 16pt regular - Default body text
  static let tidexBody = Font.system(.body, design: .default)

  /// 16pt medium - Emphasized body text
  static let tidexBodyMedium = Font.system(.body, design: .default).weight(.medium)

  /// 16pt semibold - Button text, strong emphasis
  static let tidexButton = Font.system(.callout, design: .default).weight(.semibold)

  // MARK: - Labels

  /// 14pt medium - Form labels, secondary emphasis
  static let tidexLabel = Font.system(.subheadline, design: .default).weight(.medium)

  /// 14pt regular - Secondary body text, descriptions
  static let tidexSubheadline = Font.system(.subheadline, design: .default)

  /// 14pt semibold - Emphasized labels, action links
  static let tidexLabelStrong = Font.system(.subheadline, design: .default).weight(.semibold)

  // MARK: - Footnote

  /// 13pt regular - Footnote text, tertiary descriptions
  static let tidexFootnote = Font.system(.footnote, design: .default)

  /// 13pt medium - Emphasized footnote text
  static let tidexFootnoteMedium = Font.system(.footnote, design: .default).weight(.medium)

  /// 13pt semibold - Strong footnote labels
  static let tidexFootnoteStrong = Font.system(.footnote, design: .default).weight(.semibold)

  // MARK: - Captions

  /// 12pt medium - Small labels, badges
  static let tidexCaption = Font.system(.caption, design: .default).weight(.medium)

  /// 12pt regular - Error messages, muted text
  static let tidexCaptionRegular = Font.system(.caption, design: .default)

  /// 12pt semibold - Badge text, strong captions
  static let tidexCaptionStrong = Font.system(.caption, design: .default).weight(.semibold)

  // MARK: - Micro

  /// 11pt regular - Smallest readable text (caption2)
  static let tidexMicro = Font.system(.caption2, design: .default)

  // MARK: - Prices

  /// 22pt bold - Primary price display
  static let tidexPrice = Font.system(.title3, design: .default).weight(.bold)

  /// 12pt regular - Price period labels (e.g., "/month")
  static let tidexPricePeriod = Font.system(.caption, design: .default)
}

// MARK: - Text Style Modifiers

extension View {
  /// Applies the standard body text style
  func tidexBodyStyle() -> some View {
    self.font(.tidexBody)
      .foregroundColor(.tidexTextPrimary)
  }

  /// Applies the secondary text style
  func tidexSecondaryStyle() -> some View {
    self.font(.tidexSubheadline)
      .foregroundColor(.tidexTextSecondary)
  }

  /// Applies the muted caption style
  func tidexMutedStyle() -> some View {
    self.font(.tidexCaptionRegular)
      .foregroundColor(.tidexTextMuted)
  }
}

// MARK: - TextStyle UIKit Bridge

extension Font.TextStyle {
  /// Converts SwiftUI Font.TextStyle to UIKit UIFont.TextStyle for UIFontMetrics scaling.
  var uiKit: UIFont.TextStyle {
    switch self {
    case .largeTitle: return .largeTitle
    case .title: return .title1
    case .title2: return .title2
    case .title3: return .title3
    case .headline: return .headline
    case .subheadline: return .subheadline
    case .body: return .body
    case .callout: return .callout
    case .footnote: return .footnote
    case .caption: return .caption1
    case .caption2: return .caption2
    @unknown default: return .body
    }
  }
}
