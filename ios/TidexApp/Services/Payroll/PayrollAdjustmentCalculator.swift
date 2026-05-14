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
    payoutMonth: Int
  ) -> PayrollAdjustmentTotals {
    adjustments
      .filter { !$0.isDeleted }
      .reduce(.zero) { partial, adjustment in
        let settings = taxSettings(adjustment)
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
            halfTaxMonth: halfTaxMonth,
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
    guard taxEnabled else { return gross }

    var effectiveTaxRate = min(max(taxPercentage, 0), 100)
    if let halfTaxMonth, halfTaxMonth == payoutMonth {
      effectiveTaxRate /= 2
    }

    return gross * (1 - effectiveTaxRate / 100)
  }
}
