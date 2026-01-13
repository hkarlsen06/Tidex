import Foundation

/// Result of break deduction including adjusted periods and audit trail
struct BreakDeductionResult {
    let periods: [WagePeriod]
    let audit: BreakAudit
}

/// Break deduction logic
/// Port of lib/payroll/breaks.ts
struct BreakDeduction {

    /// Apply automatic break deduction to wage periods
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
        let totalMinutes = periods.reduce(0) { $0 + $1.durationMinutes }
        let totalHours = Double(totalMinutes) / 60.0

        // Only deduct if shift exceeds threshold
        let toDeduct = totalHours > thresholdHours ? deductionHours : 0

        var adjusted = periods
        var notes: [String] = []

        if toDeduct > 0 && method != .none {
            var remainingMinutes = Int((toDeduct * 60).rounded())

            switch method {
            case .endOfShift:
                // Subtract from tail (last periods first)
                for i in stride(from: adjusted.count - 1, through: 0, by: -1) {
                    guard remainingMinutes > 0 else { break }
                    let span = adjusted[i].durationMinutes
                    let cut = min(span, remainingMinutes)

                    adjusted[i] = WagePeriod(
                        fromMin: adjusted[i].fromMin,
                        toMin: adjusted[i].toMin - cut,
                        baseRate: adjusted[i].baseRate,
                        supplementRate: adjusted[i].supplementRate
                    )
                    remainingMinutes -= cut
                }
                notes.append("Deducted at end of shift")

            case .proportional:
                // Deduct proportionally across all periods
                let totalMin = Double(totalMinutes)
                var newPeriods: [WagePeriod] = []

                for period in adjusted {
                    let span = Double(period.durationMinutes)
                    let proportion = span / totalMin
                    let cutMinutes = Int((proportion * toDeduct * 60).rounded())

                    newPeriods.append(WagePeriod(
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
                let indexedPeriods = adjusted.enumerated()
                    .sorted { $0.element.supplementRate < $1.element.supplementRate }

                for (idx, _) in indexedPeriods {
                    guard remainingMinutes > 0 else { break }
                    let span = adjusted[idx].durationMinutes
                    let cut = min(span, remainingMinutes)

                    adjusted[idx] = WagePeriod(
                        fromMin: adjusted[idx].fromMin,
                        toMin: adjusted[idx].toMin - cut,
                        baseRate: adjusted[idx].baseRate,
                        supplementRate: adjusted[idx].supplementRate
                    )
                    remainingMinutes -= cut
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
                notes: notes
            )
        )
    }
}
