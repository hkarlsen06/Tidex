/// Builds wage periods by splitting shift time according to supplement rule boundaries
/// Port of lib/payroll/periods.ts
struct WagePeriodBuilder {
  struct RuleWindow {
    let from: Int
    let to: Int
    let rule: SupplementRule
  }

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
    guard let (start, end) = shiftMinutes(startTime: startTime, endTime: endTime) else {
      return []
    }
    let windows = ruleWindows(weekday: weekday, rules: rules)
      .filter { $0.to > start && $0.from < end }

    // Collect boundary points
    var points = Set<Int>([start, end])

    for window in windows {
      points.insert(max(start, window.from))
      points.insert(min(end, window.to))
    }

    let sorted = points.sorted()
    guard sorted.count >= 2 else {
      return []
    }
    var result: [WagePeriod] = []

    // Build periods between consecutive boundary points
    for i in 0..<(sorted.count - 1) {
      let a = sorted[i]
      let b = sorted[i + 1]

      // Find highest matching supplement for this period
      var supplement: Double = 0

      for window in windows where a >= window.from && b <= window.to {
        supplement = max(supplement, resolveSupplementRate(rule: window.rule, baseRate: baseRate))
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

  static func shiftMinutes(startTime: String, endTime: String) -> (Int, Int)? {
    guard let start = toMinutes(startTime), let end = toMinutes(endTime) else { return nil }
    return (start, end <= start ? end + 24 * 60 : end)
  }

  /// Weekdays identify the day a rule starts. Include overnight rules carried from yesterday.
  static func ruleWindows(weekday: Int, rules: [SupplementRule]) -> [RuleWindow] {
    guard (1...7).contains(weekday) else { return [] }
    return rules.flatMap { rule -> [RuleWindow] in
      guard let from = toMinutes(rule.from), let to = toMinutes(rule.to), from != to else {
        return []
      }
      return (-1...1).compactMap { dayOffset in
        let ruleWeekday = (weekday - 1 + dayOffset + 7) % 7 + 1
        guard rule.days.contains(ruleWeekday) else { return nil }
        let offset = dayOffset * 24 * 60
        return RuleWindow(
          from: from + offset,
          to: to + offset + (to < from ? 24 * 60 : 0),
          rule: rule
        )
      }
    }
  }

  // MARK: - Private Helpers

  /// Convert HH:mm string to minutes since midnight
  private static func toMinutes(_ hhmm: String) -> Int? {
    let parts = hhmm.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count == 2,
      let hours = Int(parts[0]),
      let minutes = Int(parts[1]),
      minutes >= 0,
      minutes < 60,
      hours >= 0,
      hours <= 24,
      hours < 24 || minutes == 0
    else {
      return nil
    }
    return hours * 60 + minutes
  }

  /// Resolve supplement rate (fixed NOK or percentage of base)
  private static func resolveSupplementRate(rule: SupplementRule, baseRate: Double) -> Double {
    // If 'rate' is specified, use it as fixed NOK per hour
    if let rate = rule.rate, rate.isFinite, rate >= 0 {
      return rate
    }
    // If 'percent' is specified, calculate as percentage of base rate
    if let percent = rule.percent, percent.isFinite, percent >= 0 {
      return (baseRate * percent) / 100.0
    }
    return 0
  }
}
