import Foundation

/// Earnings in the main currency, the way Home's total card adds them up. Siri uses the same
/// totals, so both say the same amount.
struct EarningsTotals {
  /// Which currency is the main one, and the shift counts per currency.
  let aggregate: JobCurrencyAggregateResolution
  let totals: ShiftTotals

  var taxEnabled: Bool { aggregate.primary.hasTaxEnabled }
  var currency: String { aggregate.primary.currency }

  /// `shiftsByMonth` holds each month's computed shifts. Half-tax applies per payout month, so
  /// each month is summed on its own.
  static func compute(
    shiftsByMonth: [(month: Int, shifts: [ShiftWithComputations])],
    jobs: [Job],
    fallbackCurrency: String,
    halfTaxMonth: Int?,
    now: Date
  ) -> Self {
    let aggregate = JobCurrencyAggregateResolver.resolve(
      shifts: shiftsByMonth.flatMap(\.shifts),
      jobs: jobs,
      fallbackCurrency: fallbackCurrency,
      referenceDate: now
    )
    let totals = shiftsByMonth.reduce(ShiftTotals.zero) { sum, month in
      let monthTotals = PayrollEngine.summarizeShiftTotals(
        shifts: JobCurrencyAggregateResolver.shifts(
          matching: aggregate.primary, in: month.shifts, jobs: jobs,
          fallbackCurrency: fallbackCurrency),
        halfTaxMonth: halfTaxMonth,
        earningsMonth: month.month,
        now: now
      )
      return ShiftTotals(
        gross: sum.gross + monthTotals.gross,
        net: sum.net + monthTotals.net,
        supplement: sum.supplement + monthTotals.supplement,
        completedGross: sum.completedGross + monthTotals.completedGross,
        completedNet: sum.completedNet + monthTotals.completedNet
      )
    }
    return Self(aggregate: aggregate, totals: totals)
  }
}
