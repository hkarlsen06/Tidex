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
    let totalMinutes = periods.reduce(0.0) { $0 + max(0, $1.durationMinutes) }
    let totalHours = totalMinutes / 60.0
    let thresholdHours = thresholdHours.isFinite ? max(0, thresholdHours) : totalHours

    // Only deduct if shift exceeds threshold (strict >)
    let sanitizedDeductionHours =
      deductionHours.isFinite ? min(max(deductionHours, 0), totalHours) : 0
    let toDeduct = method != .none && totalHours > thresholdHours ? sanitizedDeductionHours : 0

    var adjusted = periods
    var notes: [String] = []

    if totalMinutes > 0, toDeduct > 0, method != .none {
      // For end_of_shift and base_only, use rounded minutes like Next.js
      let remaining = (toDeduct * 60).rounded()

      switch method {
      case .endOfShift:
        adjusted = deductFromEnd(adjusted, minutes: remaining)
        notes.append("Deducted at end of shift")

      case .proportional:
        adjusted = deductProportionally(adjusted, totalMinutes: totalMinutes, toDeduct: toDeduct)
        notes.append("Deducted proportionally across periods")

      case .baseOnly:
        adjusted = deductFromLowestSupplement(adjusted, minutes: remaining)
        notes.append("Deducted from base/lowest supplement periods first")

      case .none:
        break
      }

      // Remove empty periods (where toMin <= fromMin)
      adjusted = adjusted.filter { $0.toMin > $0.fromMin }
    }

    let paidMinutes = adjusted.reduce(0.0) { $0 + max(0, $1.durationMinutes) }
    let deductedHours = max(0, totalMinutes - paidMinutes) / 60
    return BreakDeductionResult(
      periods: adjusted,
      audit: BreakAudit(
        method: method,
        thresholdHours: thresholdHours,
        deductedHours: deductedHours,
        source: deductedHours > 0 ? .automaticBreak : .none,
        notes: notes
      )
    )
  }

  /// Subtract from tail (last periods first)
  private static func deductFromEnd(_ periods: [WagePeriod], minutes: Double) -> [WagePeriod] {
    var adjusted = periods
    var remaining = minutes
    for index in stride(from: adjusted.count - 1, through: 0, by: -1) {
      guard remaining > 0 else { break }
      let span = adjusted[index].durationMinutes
      let cut = min(span, remaining)

      adjusted[index] = WagePeriod(
        fromMin: adjusted[index].fromMin,
        toMin: adjusted[index].toMin - cut,
        baseRate: adjusted[index].baseRate,
        supplementRate: adjusted[index].supplementRate
      )
      remaining -= cut
    }
    return adjusted
  }

  /// Deduct exact proportional fractions (NOT rounded to minutes)
  /// This matches Next.js lib/payroll/breaks.ts exactly
  private static func deductProportionally(
    _ periods: [WagePeriod],
    totalMinutes: Double,
    toDeduct: Double
  ) -> [WagePeriod] {
    var newPeriods: [WagePeriod] = []

    for period in periods {
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
    return newPeriods
  }

  /// Prefer periods with lowest supplement rate
  private static func deductFromLowestSupplement(
    _ periods: [WagePeriod],
    minutes: Double
  ) -> [WagePeriod] {
    var adjusted = periods
    var remaining = minutes
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
    return adjusted
  }
}
