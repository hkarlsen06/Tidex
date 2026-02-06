import Foundation

/// Builds wage periods by splitting shift time according to supplement rule boundaries
/// Port of lib/payroll/periods.ts
struct WagePeriodBuilder {

  // MARK: - Public API

  /// Build wage periods from shift times and supplement rules
  /// - Parameters:
  ///   - startTime: Start time in HH:mm format
  ///   - endTime: End time in HH:mm format (can be less than start for cross-midnight)
  ///   - weekday: Weekday (1-7 where 1=Monday, 7=Sunday)
  ///   - baseRate: Base hourly wage rate
  ///   - rules: Supplement rules to apply
  /// - Returns: Array of wage periods split by supplement boundaries
  static func buildWagePeriods(
    startTime: String,
    endTime: String,
    weekday: Int,
    baseRate: Double,
    rules: [SupplementRule]
  ) -> [WagePeriod] {
    let start = toMinutes(startTime)
    var end = toMinutes(endTime)

    // Handle cross-midnight: when end <= start, treat as next day
    if end <= start {
      end += 24 * 60
    }

    // Collect boundary points
    var points = Set<Int>([start, end])

    for rule in rules {
      guard rule.days.contains(weekday) else { continue }

      let ruleFrom = toMinutes(rule.from)
      var ruleTo = toMinutes(rule.to)

      // Handle cross-midnight rules
      if ruleTo < ruleFrom {
        ruleTo += 24 * 60
      }

      // Consider both same-day and next-day windows
      for base in [0, 24 * 60] {
        let a = ruleFrom + base
        let b = ruleTo + base

        // Skip if rule window doesn't overlap with shift
        if b < start || a > end { continue }

        // Add boundary points within shift range
        if a > start && a < end { points.insert(a) }
        if b > start && b < end { points.insert(b) }
      }
    }

    let sorted = points.sorted()
    var result: [WagePeriod] = []

    // Build periods between consecutive boundary points
    for i in 0..<(sorted.count - 1) {
      let a = sorted[i]
      let b = sorted[i + 1]

      // Find highest matching supplement for this period
      var supplement: Double = 0

      for rule in rules {
        guard rule.days.contains(weekday) else { continue }

        for base in [0, 24 * 60] {
          let ruleFrom = toMinutes(rule.from) + base
          var ruleTo = toMinutes(rule.to) + base

          // Handle cross-midnight rules
          if toMinutes(rule.to) < toMinutes(rule.from) {
            ruleTo += 24 * 60
          }

          // Check if period [a,b) is fully within rule [ruleFrom, ruleTo]
          // Period [a,b) means from minute a (inclusive) to minute b (exclusive)
          // So we need: a >= ruleFrom (period starts at or after rule starts)
          //         and b-1 <= ruleTo (period ends at or before rule ends, since b is exclusive)
          if a >= ruleFrom && (b - 1) <= ruleTo {
            let supplementValue = resolveSupplementRate(rule: rule, baseRate: baseRate)
            supplement = max(supplement, supplementValue)
          }
        }
      }

      // Convert Int to Double for WagePeriod (supports fractional break deductions)
      result.append(
        WagePeriod(
          fromMin: Double(a),
          toMin: Double(b),
          baseRate: baseRate,
          supplementRate: supplement
        ))
    }

    return result
  }

  // MARK: - Private Helpers

  /// Convert HH:mm string to minutes since midnight
  private static func toMinutes(_ hhmm: String) -> Int {
    let parts = hhmm.split(separator: ":").compactMap { Int($0) }
    guard parts.count >= 2 else { return 0 }
    let hours = parts[0]
    let minutes = parts[1]
    // Normalize 24:00 to 1440 minutes (end of day)
    return hours * 60 + minutes
  }

  /// Resolve supplement rate (fixed NOK or percentage of base)
  private static func resolveSupplementRate(rule: SupplementRule, baseRate: Double) -> Double {
    // If 'rate' is specified, use it as fixed NOK per hour
    if let rate = rule.rate, !rate.isNaN {
      return rate
    }
    // If 'percent' is specified, calculate as percentage of base rate
    if let percent = rule.percent, !percent.isNaN {
      return (baseRate * percent) / 100.0
    }
    return 0
  }
}
