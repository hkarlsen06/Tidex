/// Result of break deduction including adjusted periods and audit trail
struct BreakDeductionResult {
  let periods: [WagePeriod]
  let audit: BreakAudit
}

/// Break deduction logic
/// Port of lib/payroll/breaks.ts
struct BreakDeduction {

  /// Apply automatic break deduction to wage periods
  /// Port of lib/payroll/breaks.ts - matches Next.js behavior exactly
  /// - Parameters:
  ///   - periods: Original wage periods
  ///   - method: Break deduction method
  ///   - thresholdHours: Minimum shift duration to trigger break deduction
  ///   - deductionHours: Hours to deduct as break
  /// - Returns: Adjusted periods and audit trail
  static func applyBreakDeduction(
    periods: [WagePeriod],
    method: BreakMethod,
    thresholdHours: Double,
    deductionHours: Double
  ) -> BreakDeductionResult {
    let totalMinutes = periods.reduce(0.0) { $0 + $1.durationMinutes }
    let totalHours = totalMinutes / 60.0

    // Only deduct if shift exceeds threshold (strict >)
    let toDeduct = totalHours > thresholdHours ? deductionHours : 0

    var adjusted = periods
    var notes: [String] = []

    if toDeduct > 0 && method != .none {
      // For end_of_shift and base_only, use rounded minutes like Next.js
      var remaining = (toDeduct * 60).rounded()

      switch method {
      case .endOfShift:
        // Subtract from tail (last periods first)
        for i in stride(from: adjusted.count - 1, through: 0, by: -1) {
          guard remaining > 0 else { break }
          let span = adjusted[i].durationMinutes
          let cut = min(span, remaining)

          adjusted[i] = WagePeriod(
            fromMin: adjusted[i].fromMin,
            toMin: adjusted[i].toMin - cut,
            baseRate: adjusted[i].baseRate,
            supplementRate: adjusted[i].supplementRate
          )
          remaining -= cut
        }
        notes.append("Deducted at end of shift")

      case .proportional:
        // Deduct exact proportional fractions (NOT rounded to minutes)
        // This matches Next.js lib/payroll/breaks.ts exactly
        var newPeriods: [WagePeriod] = []

        for period in adjusted {
          let span = period.durationMinutes
          let proportion = span / totalMinutes
          let cutMinutes = proportion * toDeduct * 60  // Exact, no rounding

          newPeriods.append(
            WagePeriod(
              fromMin: period.fromMin,
              toMin: period.toMin - cutMinutes,
              baseRate: period.baseRate,
              supplementRate: period.supplementRate
            ))
        }
        adjusted = newPeriods
        notes.append("Deducted proportionally across periods")

      case .baseOnly:
        // Prefer periods with lowest supplement rate
        // Get sorted indices by supplement rate
        let sortedIndices = adjusted.indices
          .sorted { adjusted[$0].supplementRate < adjusted[$1].supplementRate }

        for idx in sortedIndices {
          guard remaining > 0 else { break }
          let span = adjusted[idx].durationMinutes
          let cut = min(span, remaining)

          adjusted[idx] = WagePeriod(
            fromMin: adjusted[idx].fromMin,
            toMin: adjusted[idx].toMin - cut,
            baseRate: adjusted[idx].baseRate,
            supplementRate: adjusted[idx].supplementRate
          )
          remaining -= cut
        }
        notes.append("Deducted from base/lowest supplement periods first")

      case .none:
        break
      }

      // Remove empty periods (where toMin <= fromMin)
      adjusted = adjusted.filter { $0.toMin > $0.fromMin }
    }

    return BreakDeductionResult(
      periods: adjusted,
      audit: BreakAudit(
        method: method,
        thresholdHours: thresholdHours,
        deductedHours: toDeduct,
        source: .automaticBreak,
        notes: notes
      )
    )
  }
}
