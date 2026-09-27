import SwiftUI

/// Month-over-month change in gross shift pay. Home and Stats both use it, so they show the same number.
enum MonthlyEarningsChange {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  /// Percent change from the previous month, or nil when the previous month has no pay.
  /// Payroll adjustments stay out because they belong to a payout, not to the month the shifts were worked.
  static func percent(  // swiftlint:disable:this explicit_acl function_parameter_count
    currentShifts: [ShiftWithComputations],
    previousShifts: [ShiftWithComputations],
    halfTaxMonth: Int?,
    currentMonth: Int,
    previousMonth: Int,
    now: Date
  ) -> Double? {
    let current = PayrollEngine.summarizeShiftTotals(  // swiftlint:disable:this explicit_type_interface
      shifts: currentShifts,
      halfTaxMonth: halfTaxMonth,
      earningsMonth: currentMonth,
      now: now
    ).gross
    let previous = PayrollEngine.summarizeShiftTotals(  // swiftlint:disable:this explicit_type_interface
      shifts: previousShifts,
      halfTaxMonth: halfTaxMonth,
      earningsMonth: previousMonth,
      now: now
    ).gross
    guard previous > 0 else { return nil }  // swiftlint:disable:this conditional_returns_on_newline
    return (current - previous) / previous * 100  // swiftlint:disable:this no_magic_numbers
  }

  /// Whole-percent text with an explicit sign, for example "+17%" or "-8%".
  static func percentText(_ change: Double, locale: Locale = .appLocale) -> String {  // swiftlint:disable:this explicit_acl line_length
    let whole = change.rounded()  // swiftlint:disable:this explicit_type_interface
    // Avoid "-0%" when a small drop rounds to zero.
    return ((whole == 0 ? 0 : whole) / 100).formatted(  // swiftlint:disable:this no_magic_numbers
      .percent.precision(.fractionLength(0))
        .sign(strategy: .always(includingZero: false))
        .locale(locale)
    )
  }
}

/// Green or red pill that says how this month compares with the previous month.
struct MonthlyEarningsChangeBadge: View {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  let percentageChange: Double  // swiftlint:disable:this explicit_acl

  private var wholePercent: Double {
    percentageChange.rounded()
  }

  private var tint: Color {
    if wholePercent > 0 { return .tidexSuccess }  // swiftlint:disable:this conditional_returns_on_newline
    if wholePercent < 0 { return .tidexError }  // swiftlint:disable:this conditional_returns_on_newline
    return .tidexTextSecondary
  }

  private var symbolName: String {
    if wholePercent > 0 { return "chart.line.uptrend.xyaxis" }  // swiftlint:disable:this conditional_returns_on_newline
    if wholePercent < 0 { return "chart.line.downtrend.xyaxis" }  // swiftlint:disable:this conditional_returns_on_newline line_length
    return "chart.line.flattrend.xyaxis"
  }

  var body: some View {  // swiftlint:disable:this explicit_acl
    HStack(spacing: Spacing.xs) {
      Image(systemName: symbolName)
        .font(.tidexCaptionStrong)
        .accessibilityHidden(true)

      Text(.statsChangeVsPreviousMonth(MonthlyEarningsChange.percentText(percentageChange)))
        .font(.tidexFootnoteMedium)
        .lineLimit(1)
        .minimumScaleFactor(0.8)  // swiftlint:disable:this no_magic_numbers
    }
    .foregroundColor(tint)
    .padding(.horizontal, Spacing.xs)
    .padding(.vertical, Spacing.xxxs)
    .background(
      Capsule(style: .continuous)
        .fill(tint.opacity(0.12))  // swiftlint:disable:this no_magic_numbers
    )
    .accessibilityElement(children: .combine)
  }
}
