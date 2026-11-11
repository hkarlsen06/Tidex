import SwiftUI

/// The break, tax and payday settings a job's pay uses, in words. Setup no longer asks about
/// them, so the setup result states them under the save.
internal struct PayAssumptions: Equatable {
  private static let lastPayrollDay = 31

  internal let summary: String

  internal init(job: Job, snapshot: WageSnapshot) {
    self.init(snapshot: snapshot, payPeriod: job.pay_period, payrollDay: job.payroll_day)
  }

  /// `payPeriod` nil is a calendar month, paid on `payrollDay`.
  internal init(snapshot: WageSnapshot, payPeriod: PayPeriod?, payrollDay: Int?) {
    var clauses: [String] = []

    if snapshot.effectiveBreakEnabled {
      let threshold = snapshot.effectiveBreakThresholdHours.formatted(
        .number.precision(.fractionLength(0...1)).locale(.appLocale))
      clauses.append(
        String(
          localized: .dashboardPayAssumptionsBreak(
            snapshot.effectiveBreakDeductionMinutes, threshold)))
    } else {
      clauses.append(String(localized: .dashboardPayAssumptionsNoBreak))
    }

    if snapshot.effectiveTaxEnabled {
      let percent = (snapshot.effectiveTaxPercentage / 100).formatted(
        .percent.precision(.fractionLength(0...1)).locale(.appLocale))
      clauses.append(String(localized: .dashboardPayAssumptionsTax(percent)))
    } else {
      clauses.append(String(localized: .dashboardPayAssumptionsNoTax))
    }

    if let payday = Self.paydayClause(payPeriod: payPeriod, payrollDay: payrollDay) {
      clauses.append(payday)
    }

    summary = String(
      localized: .dashboardPayAssumptionsSummary(
        clauses.formatted(.list(type: .and).locale(.appLocale))))
  }

  /// Biweekly pay has no fixed day of the month, so it gets no payday clause.
  private static func paydayClause(payPeriod: PayPeriod?, payrollDay: Int?) -> String? {
    if case .biweekly = payPeriod {
      return nil
    }
    guard let day = payrollDay else {
      return nil
    }
    if day >= lastPayrollDay {
      return String(localized: .dashboardPayAssumptionsPaydayLast)
    }
    let formatter = NumberFormatter()
    formatter.numberStyle = .ordinal
    formatter.locale = .appLocale
    let ordinal = formatter.string(from: NSNumber(value: day)) ?? "\(day)"
    return String(localized: .dashboardPayAssumptionsPayday(ordinal))
  }
}
