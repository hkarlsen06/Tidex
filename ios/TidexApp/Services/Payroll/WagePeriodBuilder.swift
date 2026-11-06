import Foundation

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
    rules: [SupplementRule],
    shiftDate: String? = nil
  ) -> [WagePeriod] {
    guard let (start, end) = shiftMinutes(startTime: startTime, endTime: endTime) else {
      return []
    }
    let windows = ruleWindows(
      weekday: weekday, rules: rules, shiftDate: shiftDate, shiftStartTime: startTime
    )
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

      var groups: [String: Double] = [:]

      for window in windows where a >= window.from && b <= window.to {
        let group = window.rule.stackingGroup ?? ""
        groups[group] = max(
          groups[group] ?? 0, resolveSupplementRate(rule: window.rule, baseRate: baseRate))
      }

      // Convert Int to Double for WagePeriod (supports fractional break deductions)
      result.append(
        WagePeriod(
          fromMin: Double(a),
          toMin: Double(b),
          baseRate: baseRate,
          supplementRate: groups.values.reduce(0, +)
        ))
    }

    return result
  }

  static func shiftMinutes(startTime: String, endTime: String) -> (Int, Int)? {
    guard let start = toMinutes(startTime), let end = toMinutes(endTime) else { return nil }
    return (start, end <= start ? end + 24 * 60 : end)
  }

  /// Weekdays identify the day a rule starts. Include overnight rules carried from yesterday.
  static func ruleWindows(
    weekday: Int, rules: [SupplementRule], shiftDate: String? = nil,
    shiftStartTime: String? = nil
  ) -> [RuleWindow] {
    guard (1...7).contains(weekday) else { return [] }
    return rules.flatMap { rule -> [RuleWindow] in
      if let limit = rule.shiftStartBefore {
        guard let shiftStartTime, let start = toMinutes(shiftStartTime),
          let before = toMinutes(limit), start < before
        else { return [] }
      }
      guard let from = toMinutes(rule.from), let to = toMinutes(rule.to), from != to else {
        return []
      }
      return (-1...1).compactMap { dayOffset in
        let ruleWeekday = (weekday - 1 + dayOffset + 7) % 7 + 1
        guard rule.days.contains(ruleWeekday),
          ruleMatchesDate(rule, shiftDate: shiftDate, dayOffset: dayOffset)
        else { return nil }
        let offset = dayOffset * 24 * 60
        return RuleWindow(
          from: from + offset,
          to: to + offset + (to < from ? 24 * 60 : 0),
          rule: rule
        )
      }
    }
  }

  private static func ruleMatchesDate(
    _ rule: SupplementRule, shiftDate: String?, dayOffset: Int
  ) -> Bool {
    if let required = rule.shiftStartDates, !required.contains(shiftDate ?? "") { return false }
    if let shiftDate, rule.excludedShiftStartDates?.contains(shiftDate) == true { return false }
    guard let shiftDate, let date = Date.fromISODateStringUTC(shiftDate) else {
      return rule.dates == nil
    }
    let shifted = date.addingTimeInterval(Double(dayOffset * 24 * 60 * 60))
    let iso = String(shifted.ISO8601Format().prefix(10))
    if let dates = rule.dates, !dates.contains(iso) { return false }
    return !(rule.excludedDates?.contains(iso) ?? false)
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
      let basis = rule.percentageBaseRate ?? baseRate
      let minimum = rule.minimumRate ?? 0
      guard basis.isFinite, basis >= 0, minimum.isFinite, minimum >= 0 else { return 0 }
      return max(minimum, (basis * percent) / 100.0)
    }
    return 0
  }
}
