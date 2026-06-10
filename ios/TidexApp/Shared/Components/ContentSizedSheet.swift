// swiftlint:disable:next blanket_disable_command
// swiftlint:disable line_length superfluous_disable_command
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable conditional_returns_on_newline explicit_acl explicit_top_level_acl explicit_type_interface
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable file_name no_magic_numbers type_contents_order
import SwiftUI
import UIKit

private struct SheetContentHeightPreferenceKey: PreferenceKey {
  static var defaultValue: CGFloat = 0

  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = max(value, nextValue())
  }
}

enum ContentSizedSheetMetrics {
  static let navigationChromeHeight: CGFloat = 76
  static let minDetentHeight: CGFloat = 180
  static let maxScreenCoverage: CGFloat = 0.82
  static let defaultContentHeight: CGFloat = 220
  static let estimatedSummaryHeaderHeight: CGFloat = 104

  static func detentHeight(for contentHeight: CGFloat) -> CGFloat {
    let maxHeight = currentWindowHeight * maxScreenCoverage
    let resolvedContentHeight = max(contentHeight, defaultContentHeight)
    let totalHeight = resolvedContentHeight + navigationChromeHeight
    return min(max(totalHeight, minDetentHeight), maxHeight)
  }

  static func estimatedCardListContentHeight(
    cardCount: Int,
    includesSummaryHeader: Bool
  ) -> CGFloat {
    let cardCount = max(cardCount, 0)
    let cardsHeight = CGFloat(cardCount) * ShiftCardMetrics.regularCardMinHeight
    let cardsSpacing = CGFloat(max(cardCount - 1, 0)) * Spacing.sm
    let summaryHeight = includesSummaryHeader ? estimatedSummaryHeaderHeight : 0
    let summarySpacing = includesSummaryHeader && cardCount > 0 ? Spacing.md : 0

    return (Spacing.mlg * 2) + summaryHeight + summarySpacing + cardsHeight + cardsSpacing
  }

  private static var currentWindowHeight: CGFloat {
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .first(where: \.isKeyWindow)?
      .bounds.height ?? 800
  }
}

extension View {
  func measureSheetContentHeight(_ onChange: @escaping (CGFloat) -> Void) -> some View {
    background(
      GeometryReader { proxy in
        Color.clear
          .preference(
            key: SheetContentHeightPreferenceKey.self,
            value: proxy.size.height
          )
      }
    )
    .onPreferenceChange(SheetContentHeightPreferenceKey.self) { height in
      guard height > 0 else { return }
      onChange(ceil(height))
    }
  }
}
