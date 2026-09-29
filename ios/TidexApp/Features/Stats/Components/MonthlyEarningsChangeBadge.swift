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

  /// Picks the primary currency the way Stats does, after dropping conflicting shifts, so a
  /// conflict can't make Home compare in a different currency than Stats.
  static func percent(  // swiftlint:disable:this explicit_acl function_parameter_count
    monthShifts: [ShiftWithComputations],
    previousMonthShifts: [ShiftWithComputations],
    jobs: [Job],
    fallbackCurrency: String,
    halfTaxMonth: Int?,
    currentMonth: Int,
    previousMonth: Int,
    now: Date
  ) -> Double? {
    let current = ConflictExclusion.partition(shifts: monthShifts).includedShifts  // swiftlint:disable:this explicit_type_interface line_length
    let previous = ConflictExclusion.partition(shifts: previousMonthShifts).includedShifts  // swiftlint:disable:this explicit_type_interface line_length
    let currency = JobCurrencyAggregateResolver.resolve(  // swiftlint:disable:this explicit_type_interface
      shifts: current,
      jobs: jobs,
      fallbackCurrency: fallbackCurrency,
      referenceDate: now
    ).primary.currency
    return percent(
      currentShifts: JobCurrencyAggregateResolver.shifts(
        in: current, currency: currency, jobs: jobs, fallbackCurrency: fallbackCurrency),
      previousShifts: JobCurrencyAggregateResolver.shifts(
        in: previous, currency: currency, jobs: jobs, fallbackCurrency: fallbackCurrency),
      halfTaxMonth: halfTaxMonth,
      currentMonth: currentMonth,
      previousMonth: previousMonth,
      now: now
    )
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

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize  // swiftlint:disable:this explicit_type_interface

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
        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
        .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.8)  // swiftlint:disable:this no_magic_numbers
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
