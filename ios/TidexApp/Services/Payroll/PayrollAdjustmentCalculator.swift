import Foundation

enum PayrollAdjustmentCalculator {
  static func totals(
    adjustments: [PayrollAdjustment],
    taxEnabled: Bool,
    taxPercentage: Double,
    halfTaxMonth: Int?,
    payoutMonth: Int
  ) -> PayrollAdjustmentTotals {
    totals(
      adjustments: adjustments,
      taxSettings: { _ in PayoutTaxSettings(enabled: taxEnabled, percentage: taxPercentage) },
      halfTaxMonth: halfTaxMonth,
      payoutMonth: payoutMonth
    )
  }

  static func totals(
    adjustments: [PayrollAdjustment],
    taxSettings: (PayrollAdjustment) -> PayoutTaxSettings,
    halfTaxMonth: Int?,
    payoutMonth: Int,
    jobs: [Job] = []
  ) -> PayrollAdjustmentTotals {
    adjustments
      .filter { !$0.isDeleted }
      .reduce(.zero) { partial, adjustment in
        let settings = taxSettings(adjustment)
        let job =
          adjustment.job_id.flatMap { jobId in jobs.first { $0.id == jobId } }
          ?? (adjustment.job_id == nil ? jobs.first(where: \.is_default) : nil)
        let resolvedHalfTaxMonth = job.map(\.half_tax_month) ?? halfTaxMonth
        let grossContribution: Double
        let netContribution: Double
        let usesTaxEstimate: Bool

        switch adjustment.tax_treatment {
        case .grossTaxable:
          grossContribution = adjustment.amount
          netContribution = netAmount(
            from: adjustment.amount,
            taxEnabled: settings.enabled,
            taxPercentage: settings.percentage,
            halfTaxMonth: resolvedHalfTaxMonth,
            payoutMonth: payoutMonth
          )
          usesTaxEstimate = settings.enabled

        case .netManual:
          grossContribution = adjustment.amount
          netContribution = adjustment.amount
          usesTaxEstimate = false

        case .excludedFromTaxEstimate:
          grossContribution = adjustment.amount
          netContribution = adjustment.amount
          usesTaxEstimate = false
        }

        return PayrollAdjustmentTotals(
          gross: partial.gross + grossContribution,
          net: partial.net + netContribution,
          taxEnabled: partial.taxEnabled || usesTaxEstimate
        )
      }
  }

  private static func netAmount(
    from gross: Double,
    taxEnabled: Bool,
    taxPercentage: Double,
    halfTaxMonth: Int?,
    payoutMonth: Int
  ) -> Double {
    PayoutTaxSettings(enabled: taxEnabled, percentage: taxPercentage)
      .adjusted(payoutMonth: payoutMonth, halfTaxMonth: halfTaxMonth)
      .netAmount(from: gross)
  }
}
