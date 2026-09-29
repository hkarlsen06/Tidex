// swiftlint:disable:next blanket_disable_command
// swiftlint:disable line_length superfluous_disable_command
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable accessibility_label_for_image explicit_acl explicit_top_level_acl explicit_type_interface
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable no_magic_numbers sorted_enum_cases vertical_whitespace_between_cases
import SwiftUI

/// Totals shown in a calendar header.
/// `primary` is the net amount on the leading side. `secondary` is optional and shown on the
/// trailing side, as the before-tax amount, the change new shifts make, or the selection total.
struct CalendarHeaderTotals: Equatable {
  let primary: Double?
  let secondary: Double?
  /// Whether `primary` is after estimated tax. Labels the added amount in the delta style.
  var primaryIsAfterTax: Bool = false
}

/// "+1,600 kr after tax": an added amount written as a signed number with its tax basis,
/// so it doesn't look like an add button.
struct CalendarHeaderDeltaLabel<Amount: View>: View {
  let isAfterTax: Bool
  @ViewBuilder let amount: Amount

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: Spacing.xxxs) {
      HStack(alignment: .firstTextBaseline, spacing: 0) {
        Text(verbatim: "+")
        amount
      }
      .foregroundColor(.tidexSuccess)

      Text(isAfterTax ? .dashboardAfterTax : .dashboardBeforeTax)
        .foregroundColor(.tidexTextMuted)
    }
    .accessibilityElement(children: .combine)
  }
}

enum CalendarHeaderSecondaryStyle {
  case detail
  case delta
  /// Total for the selected dates, with the selection count.
  case selection
}

/// One-line totals header above a calendar. The month and year live in the month picker, so the
/// row shows the amount on the leading side and the before-tax amount, change, or selection
/// total on the trailing side. It keeps the same height whether or not the amounts are there, so selecting dates
/// never moves the calendar. It shows nothing when there are no totals, such as when earnings
/// are turned off.
struct CalendarHeaderRow: View {
  let totals: CalendarHeaderTotals?
  /// Number of selected dates, shown before the selection total in the `.selection` style.
  var selectionCount: Int?
  var secondaryStyle: CalendarHeaderSecondaryStyle = .detail
  /// Currency for the secondary amount when it differs from the row's currency.
  var secondaryCurrency: String?

  @Environment(\.userCurrency) private var userCurrency
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  @State private var lastDisplayedPrimary: Double = 0
  @State private var lastDisplayedSecondary: Double = 0

  var body: some View {
    if let totals {
      // At accessibility text sizes the two amounts stack, so neither truncates.
      let layout =
        dynamicTypeSize.isAccessibilitySize
        ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xxs))
        : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Spacing.xs))
      layout {
        // Holds the line height while no amount is shown.
        Text(verbatim: " ")
          .font(.tidexHeadline)
          .frame(width: 0)
          .hidden()
          .accessibilityHidden(true)

        primaryAmountText(totals.primary)

        if !dynamicTypeSize.isAccessibilitySize {
          Spacer(minLength: Spacing.xs)
        }

        if let secondary = totals.secondary {
          secondaryAmountText(secondary, isAfterTax: totals.primaryIsAfterTax)
            .userCurrency(secondaryCurrency ?? userCurrency)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
        }
      }
      .padding(.horizontal, Spacing.xxs)
      .padding(.bottom, Spacing.sm)
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
      .accessibilityLabel(
        Text(.commonAccessibilityTotalAmount(CurrencyConfig.format(amount, currency: userCurrency)))
      )
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
        .accessibilityHidden(true)
    }
  }

  @ViewBuilder
  private func secondaryAmountText(_ amount: Double, isAfterTax: Bool) -> some View {
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
      // The secondary amount is gross pay. The label keeps it from reading as "earned X of Y".
      HStack(alignment: .firstTextBaseline, spacing: Spacing.xxxs) {
        amountText
        Text(.dashboardBeforeTax)
      }
      .font(.tidexFootnote)
      .foregroundColor(.tidexTextMuted)
      .accessibilityElement(children: .combine)

    case .delta:
      CalendarHeaderDeltaLabel(isAfterTax: isAfterTax) {
        amountText
      }
      .font(.tidexFootnote)
      .transition(.opacity)

    case .selection:
      HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
        if let selectionCount {
          selectionCountText(selectionCount)
        }
        amountText
          .foregroundColor(.tidexBlueText)
      }
      .font(.tidexFootnote)
      .accessibilityElement(children: .combine)
    }
  }

  /// "(3)" on screen, "3 selected" for VoiceOver.
  private func selectionCountText(_ count: Int) -> some View {
    Text(verbatim: "(\(count))")
      .foregroundColor(.tidexTextMuted)
      .accessibilityLabel(Text(.commonAccessibilitySelectedCount(count)))
  }

  private func animatedAmount(_ amount: Double, animateFrom: Double?) -> some View {
    CurrencyCountUpText(
      amount: amount,
      animateOnAppear: false,
      animateFrom: animateFrom
    )
  }
}
