import AppIntents
import SwiftUI

// MARK: - Supplement Segment

/// A grouped supplement segment for display
struct SupplementSegment: Identifiable, Equatable {
  let fromMin: Double
  let toMin: Double
  let rate: Double
  let actualHours: Double
  var isOvertime: Bool = false

  var id: String { "\(fromMin)-\(toMin)-\(rate)-\(isOvertime)" }

  static func grouped(from periods: [WagePeriod]) -> [Self] {
    var result: [Self] = []
    for period in periods where period.durationMinutes > 0 && period.supplementRate > 0 {
      let isOvertime = period.isOvertime == true
      if let last = result.last, last.toMin == period.fromMin,
        last.rate == period.supplementRate, last.isOvertime == isOvertime
      {
        result[result.count - 1] = Self(
          fromMin: last.fromMin, toMin: period.toMin, rate: last.rate,
          actualHours: last.actualHours + period.durationHours, isOvertime: isOvertime
        )
      } else {
        result.append(
          Self(
            fromMin: period.fromMin, toMin: period.toMin, rate: period.supplementRate,
            actualHours: period.durationHours, isOvertime: isOvertime
          ))
      }
    }
    return result
  }

  /// Format minutes to display time (e.g., "21:00")
  func formatTime(_ minutes: Double) -> String {
    let dayOffset = Int(minutes / 1_440)  // swiftlint:disable:this explicit_type_interface no_magic_numbers
    let remainder = Int(minutes) % 1_440  // swiftlint:disable:this explicit_type_interface no_magic_numbers
    let normalizedMinutes = remainder < 0 ? remainder + 1_440 : remainder  // swiftlint:disable:this explicit_type_interface line_length no_magic_numbers
    let hours = normalizedMinutes / 60
    let mins = normalizedMinutes % 60
    let base = String(format: "%02d:%02d", hours, mins)
    if dayOffset > 0 {
      return "\(base) (+\(dayOffset))"
    }
    if dayOffset < 0 {
      return "\(base) (\(dayOffset))"
    }
    return base
  }

  /// Formatted time range string
  var timeRange: String {
    let from = formatTime(fromMin)
    let to = formatTime(toMin)
    return "\(from) – \(to)"
  }

  /// Total supplement amount for this segment
  var amount: Double {
    actualHours * rate
  }
}

struct BreakDeductionBreakdown: Equatable {
  let parts: [BreakDeductionPart]

  var totalAmount: Double {
    parts.reduce(0) { $0 + $1.amount }
  }

  static func basePay(for periods: [WagePeriod]) -> Double {
    PayrollCalculator.payTotals(for: periods).base
  }

  static func supplementPay(for periods: [WagePeriod]) -> Double {
    PayrollCalculator.payTotals(for: periods).supplement
  }

  static func make(
    originalPeriods: [WagePeriod],
    adjustedPeriods: [WagePeriod]
  ) -> Self? {
    var parts: [BreakDeductionPart] = []

    let baseAmount = roundedCurrency(
      max(0, basePay(for: originalPeriods) - basePay(for: adjustedPeriods)))
    let baseHours = deductedBaseHours(
      originalPeriods: originalPeriods,
      adjustedPeriods: adjustedPeriods
    )

    if isDisplayable(baseAmount) {
      parts.append(
        BreakDeductionPart(
          id: "base",
          kind: .base,
          supplementSegment: nil,
          hours: baseHours,
          rate: baseHours > 0 ? baseAmount / baseHours : nil,
          amount: baseAmount
        ))
    }

    parts.append(
      contentsOf: supplementParts(
        originalPeriods: originalPeriods,
        adjustedPeriods: adjustedPeriods
      )
    )

    guard !parts.isEmpty else {
      return nil
    }
    return Self(parts: parts)
  }

  private static func supplementParts(
    originalPeriods: [WagePeriod],
    adjustedPeriods: [WagePeriod]
  ) -> [BreakDeductionPart] {
    var parts: [BreakDeductionPart] = []
    var periodIndex = 0

    while periodIndex < originalPeriods.count {
      let period = originalPeriods[periodIndex]
      guard period.supplementRate > 0 else {
        periodIndex += 1
        continue
      }

      let groupStart = period.fromMin
      var groupEnd = period.toMin
      let rate = period.supplementRate
      var nextPeriodIndex = periodIndex + 1

      while nextPeriodIndex < originalPeriods.count,
        originalPeriods[nextPeriodIndex].supplementRate == rate
      {
        groupEnd = originalPeriods[nextPeriodIndex].toMin
        nextPeriodIndex += 1
      }

      if let part = supplementPart(
        originalPeriods: originalPeriods,
        adjustedPeriods: adjustedPeriods,
        groupStart: groupStart,
        groupEnd: groupEnd,
        rate: rate
      ) {
        parts.append(part)
      }

      periodIndex = nextPeriodIndex
    }

    return allocatingRemainder(
      to: parts, originalPeriods: originalPeriods, adjustedPeriods: adjustedPeriods)
  }

  private static func supplementPart(
    originalPeriods: [WagePeriod],
    adjustedPeriods: [WagePeriod],
    groupStart: Double,
    groupEnd: Double,
    rate: Double
  ) -> BreakDeductionPart? {
    let originalMetrics = overlappingMetrics(
      periods: originalPeriods,
      from: groupStart,
      to: groupEnd,
      supplementRate: rate
    )
    let adjustedMetrics = overlappingMetrics(
      periods: adjustedPeriods,
      from: groupStart,
      to: groupEnd,
      supplementRate: rate
    )
    let deductedHours = max(0, originalMetrics.hours - adjustedMetrics.hours)
    let amount = roundedCurrency(max(0, originalMetrics.pay - adjustedMetrics.pay))

    guard deductedHours > 0 else { return nil }
    return BreakDeductionPart(
      id: "supplement-\(groupStart)-\(groupEnd)-\(rate)",
      kind: .supplement,
      supplementSegment: SupplementSegment(
        fromMin: groupStart,
        toMin: groupEnd,
        rate: rate,
        actualHours: deductedHours
      ),
      hours: deductedHours,
      rate: rate,
      amount: amount
    )
  }

  private static func allocatingRemainder(
    to parts: [BreakDeductionPart],
    originalPeriods: [WagePeriod],
    adjustedPeriods: [WagePeriod]
  ) -> [BreakDeductionPart] {
    // The visible deduction must equal the difference of the rounded pay components.
    // Allocate any fractional-cent remainder without inventing an extra deduction row.
    var remaining = roundedCurrency(
      max(
        0,
        supplementPay(for: originalPeriods) - supplementPay(for: adjustedPeriods)
      ))
    return parts.enumerated().compactMap { index, part in
      let amount = index == parts.count - 1 ? remaining : min(part.amount, remaining)
      remaining = roundedCurrency(remaining - amount)
      guard isDisplayable(amount) else { return nil }
      return BreakDeductionPart(
        id: part.id, kind: part.kind, supplementSegment: part.supplementSegment,
        hours: part.hours, rate: part.rate, amount: amount
      )
    }
  }

  private static func overlappingMetrics(
    periods: [WagePeriod],
    from: Double,
    to: Double,
    supplementRate: Double
  ) -> (hours: Double, pay: Double) {
    periods
      .filter { $0.supplementRate == supplementRate }
      .reduce((hours: 0, pay: 0)) { total, current in
        let overlapStart = max(current.fromMin, from)
        let overlapEnd = min(current.toMin, to)
        guard overlapEnd > overlapStart else {
          return total
        }
        let hours = (overlapEnd - overlapStart) / 60.0
        return (
          hours: total.hours + hours,
          pay: total.pay + payFor(hours: hours, rate: supplementRate)
        )
      }
  }

  private static func deductedBaseHours(
    originalPeriods: [WagePeriod],
    adjustedPeriods: [WagePeriod]
  ) -> Double {
    let originalHours = originalPeriods.reduce(0) { $0 + max(0, $1.durationHours) }
    let adjustedHours = adjustedPeriods.reduce(0) { $0 + max(0, $1.durationHours) }
    return max(0, originalHours - adjustedHours)
  }

  private static func roundedCurrency(_ amount: Double) -> Double {
    (amount * 100).rounded() / 100
  }

  private static func payFor(hours: Double, rate: Double) -> Double {
    hours * rate
  }

  private static func isDisplayable(_ amount: Double) -> Bool {
    roundedCurrency(amount) > 0
  }
}

struct BreakDeductionPart: Identifiable, Equatable {
  enum Kind: Equatable {
    case base
    case supplement
  }

  let id: String
  let kind: Kind
  let supplementSegment: SupplementSegment?
  let hours: Double
  let rate: Double?
  let amount: Double
}