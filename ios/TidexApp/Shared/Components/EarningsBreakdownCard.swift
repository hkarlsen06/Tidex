// swiftlint:disable:next blanket_disable_command
// swiftlint:disable line_length superfluous_disable_command
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable explicit_acl explicit_top_level_acl file_types_order no_grouping_extension
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable no_magic_numbers
import SwiftUI

struct EarningsBreakdownCard<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View {
    VStack(spacing: Spacing.sm) {
      content
    }
    .padding(Spacing.md)
    .background(
      RoundedRectangle(cornerRadius: CornerRadius.xxl)
        .fill(Color.tidexSurfacePrimary)
    )
  }
}

extension EarningsBreakdownCard {
  struct Row: View {
    let label: String
    let value: String
    var valueColor: Color = .tidexTextPrimary
    var isHighlighted: Bool = false

    var body: some View {
      HStack {
        Text(label)
          .font(isHighlighted ? .tidexLabel : .tidexSubheadline)
          .foregroundColor(isHighlighted ? .tidexTextPrimary : .tidexTextSecondary)

        Spacer()

        Text(value)
          .font(isHighlighted ? .tidexTitle2 : .tidexLabel)
          .foregroundColor(valueColor)
      }
    }
  }
}

struct EarningsBreakdownDetailCard<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View {
    VStack(spacing: Spacing.xxxs) {
      content
    }
    .padding(Spacing.sm)
    .background(
      RoundedRectangle(cornerRadius: CornerRadius.lg)
        .fill(Color.tidexSurfaceSecondary.opacity(0.4))
    )
  }
}

/// An indented two-line row under an expanded total: label and amount, then a muted detail line.
/// Kept flat, with no card, so a list of six segments reads as one column of amounts.
struct EarningsBreakdownDetailLine: View {
  let title: String
  let amount: String
  let detail: String?
  var valueColor: Color = .tidexTextPrimary
  var forcesLeftToRight: Bool = false

  @Environment(\.layoutDirection) private var layoutDirection

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
        Text(title)
          .font(.tidexSubheadline)
          .foregroundColor(.tidexTextSecondary)
          .environment(\.layoutDirection, forcesLeftToRight ? .leftToRight : layoutDirection)

        Spacer(minLength: Spacing.sm)

        Text(amount)
          .font(.tidexSubheadline)
          .monospacedDigit()
          .foregroundColor(valueColor)
      }

      if let detail {
        Text(detail)
          .font(.tidexFootnote)
          .monospacedDigit()
          .foregroundColor(.tidexTextMuted)
          .environment(\.layoutDirection, forcesLeftToRight ? .leftToRight : layoutDirection)
      }
    }
    .padding(.leading, Spacing.md)
    .accessibilityElement(children: .combine)
  }
}

struct EarningsSupplementBreakdownDetailCard: View {
  /// Shown only when it adds information, such as "Overtime". Plain supplements need no label.
  let title: String?
  let timeRange: String?
  let hoursAndRate: String
  let amount: String

  init(
    title: String? = nil,
    timeRange: String?,
    hoursAndRate: String,
    amount: String
  ) {
    self.title = title
    self.timeRange = timeRange
    self.hoursAndRate = hoursAndRate
    self.amount = amount
  }

  var body: some View {
    if let timeRange {
      EarningsBreakdownDetailLine(
        title: [title, timeRange].compactMap { $0 }.joined(separator: " · "),
        amount: amount,
        detail: hoursAndRate,
        forcesLeftToRight: true
      )
    } else {
      EarningsBreakdownDetailLine(
        title: title ?? hoursAndRate,
        amount: amount,
        detail: title == nil ? nil : hoursAndRate
      )
    }
  }
}

struct EarningsBreakDeductionDetailCard: View {
  let title: String
  let amount: String
  let detailTitle: String
  let detailValue: String?
  var valueColor: Color = .tidexError
  var forcesLeftToRight: Bool = false

  var body: some View {
    EarningsBreakdownDetailLine(
      title: title,
      amount: amount,
      detail: [detailTitle, detailValue].compactMap { $0 }.joined(separator: " · "),
      valueColor: valueColor,
      forcesLeftToRight: forcesLeftToRight
    )
  }
}
