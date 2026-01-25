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

    /// 72pt bold - Extra large currency displays
    static let tidexDisplay = Font.system(size: 72, weight: .bold)

    /// 48pt bold - Dashboard stat values
    static let tidexStat = Font.system(size: 48, weight: .bold)

    /// 40pt bold - Secondary stat values
    static let tidexStatSecondary = Font.system(size: 40, weight: .bold)

    /// 32pt bold rounded - Large amounts (e.g., paycheck preview)
    static let tidexAmountLarge = Font.system(size: 32, weight: .bold, design: .rounded)

    // MARK: - Headings

    /// 24pt bold - Screen titles, primary headings
    static let tidexLargeTitle = Font.system(size: 24, weight: .bold)

    /// 22pt bold - Card headers, secondary titles
    static let tidexTitle = Font.system(size: 22, weight: .bold)

    /// 20pt bold - Tertiary titles
    static let tidexTitle2 = Font.system(size: 20, weight: .bold)

    /// 18pt semibold - Section headers, emphasis
    static let tidexHeadline = Font.system(size: 18, weight: .semibold)

    // MARK: - Body

    /// 16pt regular - Default body text
    static let tidexBody = Font.system(size: 16, weight: .regular)

    /// 16pt medium - Emphasized body text
    static let tidexBodyMedium = Font.system(size: 16, weight: .medium)

    /// 16pt semibold - Button text, strong emphasis
    static let tidexButton = Font.system(size: 16, weight: .semibold)

    // MARK: - Labels

    /// 14pt medium - Form labels, secondary emphasis
    static let tidexLabel = Font.system(size: 14, weight: .medium)

    /// 14pt regular - Secondary body text, descriptions
    static let tidexSubheadline = Font.system(size: 14, weight: .regular)

    /// 14pt semibold - Emphasized labels, action links
    static let tidexLabelStrong = Font.system(size: 14, weight: .semibold)

    // MARK: - Captions

    /// 12pt medium - Small labels, badges
    static let tidexCaption = Font.system(size: 12, weight: .medium)

    /// 12pt regular - Error messages, muted text
    static let tidexCaptionRegular = Font.system(size: 12, weight: .regular)

    /// 12pt semibold - Badge text, strong captions
    static let tidexCaptionStrong = Font.system(size: 12, weight: .semibold)

    // MARK: - Prices

    /// 22pt bold - Primary price display
    static let tidexPrice = Font.system(size: 22, weight: .bold)

    /// 12pt regular - Price period labels (e.g., "/month")
    static let tidexPricePeriod = Font.system(size: 12, weight: .regular)
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
