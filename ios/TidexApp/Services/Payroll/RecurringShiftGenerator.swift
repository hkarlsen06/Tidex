import Foundation

/// Generates virtual shift occurrences from recurring patterns
/// Port of lib/recurring/utils.ts
struct RecurringShiftGenerator {

  // MARK: - Public API

  /// Check if a date is in phase with an anchor date given an interval
  /// - Parameters:
  ///   - dateISO: ISO date to check (YYYY-MM-DD)
  ///   - anchorISO: Anchor date (YYYY-MM-DD)
  ///   - interval: Repetition interval (0 = every week, 1 = every 2 weeks, etc.)
  /// - Returns: true if date is in phase with anchor
  ///
  /// Example:
  /// - isInPhase("2025-11-03", "2025-10-27", 0) → true (every week)
  /// - isInPhase("2025-11-03", "2025-10-27", 1) → true (every 2 weeks, 1 week apart)
  /// - isInPhase("2025-11-10", "2025-10-27", 1) → false (2 weeks apart, wrong phase)
  static func isInPhase(dateISO: String, anchorISO: String, interval: Int) -> Bool {
    // interval 0 means every week, always in phase
    if interval == 0 { return true }

    let daysDiff = Date.daysBetween(anchorISO, dateISO)
    let weeksDiff = daysDiff / 7

    // Check if week difference is divisible by (interval + 1)
    // interval 1 = every 2 weeks, interval 2 = every 3 weeks, etc.
    return weeksDiff.isMultiple(of: interval + 1)
  }

  /// Generate virtual shift occurrences for a specific month
  /// - Parameters:
  ///   - year: Target year
  ///   - month: Target month (1-12)
  ///   - recurring: Recurring shift pattern
  /// - Returns: Array of virtual shift occurrences in the target month
  static func generateVirtualShiftsForMonth(
    year: Int,
    month: Int,
    recurring: RecurringShiftRow
  ) -> [RecurringVirtualShift] {
    guard !recurring.selected_days.isEmpty else { return [] }

    let monthStartISO = Date.firstDayOfMonth(year: year, month: month)
    let monthEndISO = Date.lastDayOfMonth(year: year, month: month)

    var virtualShifts: [RecurringVirtualShift] = []
    let exclusionSet = Set(recurring.effectiveExclusions)

    // Use local calendar for user-facing date iteration
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = Date.localTimeZone

    // Create month start/end dates in UTC
    var startComponents = DateComponents()
    startComponents.year = year
    startComponents.month = month
    startComponents.day = 1
    startComponents.hour = 12  // Noon to avoid any timezone edge cases
    guard let monthStartDate = calendar.date(from: startComponents) else { return [] }

    var endComponents = DateComponents()
    endComponents.year = year
    endComponents.month = month
    endComponents.day = Date.daysInMonth(year: year, month: month)
    endComponents.hour = 12
    guard let monthEndDate = calendar.date(from: endComponents) else { return [] }

    // For each selected weekday anchor
    for (weekdayKey, anchorISO) in recurring.selected_days {
      guard let weekday = Int(weekdayKey) else { continue }

      // Find first occurrence of this weekday in target month
      var current = monthStartDate
      let currentWeekday = calendar.component(.weekday, from: current) - 1  // 0=Sun, 6=Sat

      let daysUntilTarget = (weekday - currentWeekday + 7) % 7
      current = calendar.date(byAdding: .day, value: daysUntilTarget, to: current) ?? current

      // Generate occurrences throughout the month
      while current <= monthEndDate {
        let currentISO = toISODateLocal(current)

        // Check date range
        guard currentISO >= monthStartISO, currentISO <= monthEndISO else {
          current = calendar.date(byAdding: .weekOfYear, value: 1, to: current) ?? current
          continue
        }

        // Only generate forwards from anchor date
        guard currentISO >= anchorISO else {
          current = calendar.date(byAdding: .weekOfYear, value: 1, to: current) ?? current
          continue
        }

        // Check if in phase with anchor
        let inPhase = isInPhase(
          dateISO: currentISO,
          anchorISO: anchorISO,
          interval: recurring.repeat_interval_weeks
        )

        // Check if within recurring shift window (end condition)
        let withinWindow = checkEndCondition(
          currentISO: currentISO,
          endCondition: recurring.end_condition,
          selectedDays: recurring.selected_days
        )

        // Check if not excluded
        let notExcluded = !exclusionSet.contains(currentISO)

        if inPhase, withinWindow, notExcluded {
          virtualShifts.append(
            RecurringVirtualShift(
              date: currentISO,
              weekday: weekday
            ))
        }

        // Move to next week
        current = calendar.date(byAdding: .weekOfYear, value: 1, to: current) ?? current
      }
    }

    // Sort by date
    return virtualShifts.sorted { $0.date < $1.date }
  }

  // MARK: - Private Helpers

  /// Convert Date to ISO date string (YYYY-MM-DD) in local time
  private static func toISODateLocal(_ date: Date) -> String {
    FormatterCache.isoDateFormatter().string(from: date)
  }

  /// Check if date is within the recurring shift's end condition window
  private static func checkEndCondition(
    currentISO: String,
    endCondition: EndCondition?,
    selectedDays: SelectedDays
  ) -> Bool {
    // No end condition = always valid (infinite recurrence)
    guard let endCondition else {
      return true
    }

    // Find earliest anchor date for window calculation
    let anchorDates = selectedDays.values.sorted()
    guard let earliestAnchor = anchorDates.first,
      let anchorDate = Date.fromISODateString(earliestAnchor)
    else {
      return true
    }

    // Use local calendar for consistent date calculations
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = Date.localTimeZone

    switch endCondition {
    case .months(let value):
      // End date is anchor + N months
      guard let endDate = calendar.date(byAdding: .month, value: value, to: anchorDate) else {
        return true
      }
      // Compare calendar days: occurrences sit at noon while the anchor parses to midnight.
      return currentISO <= endDate.toISODateString()

    case .years(let value):
      // End date is anchor + N years
      guard let endDate = calendar.date(byAdding: .year, value: value, to: anchorDate) else {
        return true
      }
      return currentISO <= endDate.toISODateString()

    case .endDate(let dateString):
      // Specific end date
      return currentISO <= dateString
    }
  }
}
