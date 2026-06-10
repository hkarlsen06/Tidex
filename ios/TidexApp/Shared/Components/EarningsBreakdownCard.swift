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

struct EarningsBreakdownDetailPrimaryRow: View {
  let title: String
  let value: String
  var valueColor: Color = .tidexTextPrimary

  var body: some View {
    HStack {
      Text(title)
        .font(.tidexLabelStrong)
        .foregroundColor(.tidexTextPrimary)

      Spacer()

      Text(value)
        .font(.tidexLabelStrong)
        .foregroundColor(valueColor)
    }
  }
}

struct EarningsBreakdownDetailSecondaryRow: View {
  let title: String
  let value: String?

  var body: some View {
    HStack {
      Text(title)
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextSecondary)

      Spacer()

      if let value {
        Text(value)
          .font(.tidexSubheadline)
          .foregroundColor(.tidexTextSecondary)
      }
    }
  }
}

struct EarningsSupplementBreakdownDetailCard: View {
  let timeRange: String?
  let hoursAndRate: String
  let amount: String

  var body: some View {
    EarningsBreakdownDetailCard {
      EarningsBreakdownDetailPrimaryRow(
        title: String(localized: .shiftsSupplementLabel),
        value: amount
      )

      if let timeRange {
        EarningsBreakdownDetailSecondaryRow(
          title: timeRange,
          value: hoursAndRate
        )
        .environment(\.layoutDirection, .leftToRight)
      } else {
        EarningsBreakdownDetailSecondaryRow(
          title: hoursAndRate,
          value: nil
        )
      }
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
    EarningsBreakdownDetailCard {
      EarningsBreakdownDetailPrimaryRow(
        title: title,
        value: amount,
        valueColor: valueColor
      )

      if forcesLeftToRight {
        EarningsBreakdownDetailSecondaryRow(
          title: detailTitle,
          value: detailValue
        )
        .environment(\.layoutDirection, .leftToRight)
      } else {
        EarningsBreakdownDetailSecondaryRow(
          title: detailTitle,
          value: detailValue
        )
      }
    }
  }
}
