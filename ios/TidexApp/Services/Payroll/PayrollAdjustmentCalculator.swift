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
        let contribution = netContribution(
          of: adjustment,
          settings: settings,
          halfTaxMonth: resolvedHalfTaxMonth,
          payoutMonth: payoutMonth
        )

        return PayrollAdjustmentTotals(
          gross: partial.gross + adjustment.amount,
          net: partial.net + contribution.net,
          taxEnabled: partial.taxEnabled || contribution.usesTaxEstimate
        )
      }
  }

  private static func netContribution(
    of adjustment: PayrollAdjustment,
    settings: PayoutTaxSettings,
    halfTaxMonth: Int?,
    payoutMonth: Int
  ) -> (net: Double, usesTaxEstimate: Bool) {
    switch adjustment.tax_treatment {
    case .grossTaxable:
      let net = netAmount(
        from: adjustment.amount,
        taxEnabled: settings.enabled,
        taxPercentage: settings.percentage,
        halfTaxMonth: halfTaxMonth,
        payoutMonth: payoutMonth
      )
      return (net, settings.enabled)

    case .netManual, .excludedFromTaxEstimate:
      return (adjustment.amount, false)
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
