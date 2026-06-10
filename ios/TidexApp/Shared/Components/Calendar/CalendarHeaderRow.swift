// swiftlint:disable:next blanket_disable_command
// swiftlint:disable line_length superfluous_disable_command
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable accessibility_label_for_image explicit_acl explicit_top_level_acl explicit_type_interface
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable no_magic_numbers sorted_enum_cases vertical_whitespace_between_cases
import SwiftUI

/// Totals shown on the trailing side of a calendar header.
/// `primary` is rendered on the month/year line. `secondary` is optional and shown below.
struct CalendarHeaderTotals: Equatable {
  let primary: Double?
  let secondary: Double?
}

enum CalendarHeaderSecondaryStyle {
  case detail
  case delta
}

/// Shared month/year header used by calendar-based screens.
/// Supports optional trailing totals.
struct CalendarHeaderRow: View {
  let monthName: String
  let year: Int
  let selectionCount: Int?
  let phase: MonthTransitionPhase?
  let totals: CalendarHeaderTotals?
  let trailingAccessory: AnyView?
  var secondaryStyle: CalendarHeaderSecondaryStyle = .detail

  @State private var lastDisplayedPrimary: Double = 0
  @State private var lastDisplayedSecondary: Double = 0

  var body: some View {
    if let totals, totals.secondary != nil {
      HStack(alignment: .center) {
        monthYearLabel

        Spacer()

        trailingContent(totals: totals, alignment: .center)
      }
      .padding(.horizontal, Spacing.xxs)
      .padding(.bottom, Spacing.sm)
    } else {
      HStack(alignment: .firstTextBaseline) {
        monthYearLabel

        Spacer()

        if let totals {
          trailingContent(totals: totals, alignment: .firstTextBaseline)
        } else if let trailingAccessory {
          trailingAccessory
        }
      }
      .padding(.horizontal, Spacing.xxs)
      .padding(.bottom, Spacing.sm)
    }
  }

  @ViewBuilder
  private var monthYearLabel: some View {
    HStack(spacing: Spacing.xxxs) {
      Text(monthName)
        .font(.tidexTitle2)
        .foregroundColor(.tidexTextPrimary)

      if let selectionCount {
        Text("(\(selectionCount))")
          .font(.tidexBodyLarge)
          .foregroundColor(.tidexTextMuted)
      } else {
        Text(String(year))
          .font(.tidexBodyLarge)
          .foregroundColor(.tidexTextMuted)
      }
    }
  }

  @ViewBuilder
  private func trailingContent(totals: CalendarHeaderTotals, alignment: VerticalAlignment)
    -> some View
  {
    HStack(alignment: alignment, spacing: Spacing.xs) {
      if let trailingAccessory {
        trailingAccessory
      }
      totalsView(totals: totals)
    }
  }

  @ViewBuilder
  private func totalsView(totals: CalendarHeaderTotals) -> some View {
    if let secondary = totals.secondary {
      VStack(alignment: .trailing, spacing: Spacing.micro) {
        primaryAmountText(totals.primary)
        secondaryAmountText(secondary)
      }
    } else {
      primaryAmountText(totals.primary)
    }
  }

  @ViewBuilder
  private func primaryAmountText(_ amount: Double?) -> some View {
    if let amount, amount > 0 {
      animatedAmount(
        amount,
        animateFrom: lastDisplayedPrimary > 0 ? lastDisplayedPrimary : nil
      )
      .font(.tidexHeadline)
      .foregroundColor(.tidexTextPrimary)
      .onChange(of: amount) { _, newValue in
        lastDisplayedPrimary = newValue
      }
      .onAppear {
        if lastDisplayedPrimary == 0 {
          lastDisplayedPrimary = amount
        }
      }
    } else {
      Text("—")
        .font(.tidexHeadline)
        .foregroundColor(.tidexTextPrimary)
    }
  }

  @ViewBuilder
  private func secondaryAmountText(_ amount: Double) -> some View {
    let amountText = animatedAmount(
      amount,
      animateFrom: lastDisplayedSecondary > 0 ? lastDisplayedSecondary : nil
    )
    .font(.tidexFootnote)
    .onChange(of: amount) { _, newValue in
      lastDisplayedSecondary = newValue
    }
    .onAppear {
      if lastDisplayedSecondary == 0 {
        lastDisplayedSecondary = amount
      }
    }

    switch secondaryStyle {
    case .detail:
      amountText
        .foregroundColor(.tidexTextMuted)

    case .delta:
      HStack(alignment: .center, spacing: Spacing.xxxs) {
        Image(systemName: "plus")
          .font(.caption2.weight(.bold))
        amountText
      }
      .foregroundColor(.tidexBlue)
      .transition(.offset(y: -4).combined(with: .opacity))
    }
  }

  private func animatedAmount(_ amount: Double, animateFrom: Double?) -> some View {
    CurrencyCountUpText(
      amount: amount,
      animateOnAppear: false,
      animateFrom: animateFrom
    )
  }
}
