import Foundation

/// Projects future dates for a recurring shift pattern
/// Companion to RecurringShiftGenerator for use in the Add Shift form
struct RecurringShiftProjector {

  // MARK: - Public API

  /// Generate projected dates for a recurring pattern with optional limit
  /// - Parameters:
  ///   - selectedDays: Map of weekday ("0"-"6") to anchor ISO date
  ///   - repeatInterval: Repeat interval (0 = weekly, 1 = biweekly, etc.)
  ///   - endCondition: When the pattern should end
  ///   - limit: Maximum number of dates to generate (nil = no limit)
  /// - Returns: Sorted array of ISO date strings
  static func generateDates(
    selectedDays: [String: String],
    repeatInterval: Int,
    endCondition: EndCondition?,
    limit: Int? = nil
  ) -> [String] {
    guard !selectedDays.isEmpty else { return [] }
    guard repeatInterval >= 0 else { return [] }

    let calendar = Calendar.gregorianCurrent
    var dates: [String] = []

    // Find the earliest anchor
    let anchors = selectedDays.values.sorted()
    guard let earliestAnchor = anchors.first,
      let earliestDate = Date.fromISODateString(earliestAnchor)
    else {
      return []
    }

    // Calculate end date based on condition
    let endDate: Date
    switch endCondition {
    case .none:
      // Infinite: project 2 years ahead for preview
      endDate = calendar.date(byAdding: .year, value: 2, to: earliestDate) ?? earliestDate

    case .months(let value):
      endDate = calendar.date(byAdding: .month, value: value, to: earliestDate) ?? earliestDate

    case .years(let value):
      endDate = calendar.date(byAdding: .year, value: value, to: earliestDate) ?? earliestDate

    case .endDate(let dateString):
      endDate = Date.fromISODateString(dateString) ?? earliestDate
    }

    // Generate dates for each anchor
    for (_, anchorISO) in selectedDays {
      guard let anchorDate = Date.fromISODateString(anchorISO) else { continue }

      let intervalWeeks = repeatInterval + 1  // 0 = weekly (every 1 week), 1 = biweekly (every 2 weeks)
      var currentDate = anchorDate

      while currentDate <= endDate {
        dates.append(currentDate.toISODateString())

        // Move to next occurrence
        guard
          let nextDate = calendar.date(byAdding: .day, value: 7 * intervalWeeks, to: currentDate)
        else {
          break
        }
        currentDate = nextDate
      }
    }

    // Sort and deduplicate
    var result = Array(Set(dates)).sorted()

    // Apply limit if specified
    if let limit, result.count > limit {
      result = Array(result.prefix(limit))
    }

    return result
  }

  /// Generate projected dates for calendar display (limited to visible month + buffer)
  /// This is optimized for UI responsiveness - only generates dates needed for display
  /// - Parameters:
  ///   - selectedDays: Map of weekday ("0"-"6") to anchor ISO date
  ///   - repeatInterval: Repeat interval (0 = weekly, 1 = biweekly, etc.)
  ///   - displayMonth: The month currently being displayed
  ///   - endCondition: When the pattern should end (used to cap the projection)
  /// - Returns: Sorted array of ISO date strings for the visible month range
  static func generateDatesForCalendarDisplay(
    selectedDays: [String: String],
    repeatInterval: Int,
    displayMonth: Date,
    endCondition: EndCondition?
  ) -> [String] {
    guard !selectedDays.isEmpty else { return [] }
    guard repeatInterval >= 0 else { return [] }

    let calendar = Calendar.gregorianCurrent
    var dates: [String] = []

    // Get the display month range (with some buffer for edge cases)
    let components = calendar.dateComponents([.year, .month], from: displayMonth)
    guard let monthStart = calendar.date(from: components),
      let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart)
    else {
      return []
    }

    // Find the earliest anchor to determine the pattern's actual start
    let anchors = selectedDays.values.sorted()
    guard let earliestAnchor = anchors.first,
      let earliestDate = Date.fromISODateString(earliestAnchor)
    else {
      return []
    }

    // Calculate end date based on condition (to know when pattern stops)
    let patternEndDate: Date
    switch endCondition {
    case .none:
      // Infinite: use a far future date
      patternEndDate = calendar.date(byAdding: .year, value: 10, to: earliestDate) ?? earliestDate

    case .months(let value):
      patternEndDate =
        calendar.date(byAdding: .month, value: value, to: earliestDate) ?? earliestDate

    case .years(let value):
      patternEndDate =
        calendar.date(byAdding: .year, value: value, to: earliestDate) ?? earliestDate

    case .endDate(let dateString):
      patternEndDate = Date.fromISODateString(dateString) ?? earliestDate
    }

    // Generate dates for each anchor, but only within the display month
    for (_, anchorISO) in selectedDays {
      guard let anchorDate = Date.fromISODateString(anchorISO) else { continue }

      let intervalWeeks = repeatInterval + 1
      let intervalDays = 7 * intervalWeeks

      // Find the first occurrence in or before the display month
      var currentDate = anchorDate

      // If anchor is after display month, skip this anchor
      if currentDate >= monthEnd {
        continue
      }

      // If anchor is before display month, fast-forward to display month
      if currentDate < monthStart {
        let daysBetween =
          calendar.dateComponents([.day], from: currentDate, to: monthStart).day ?? 0
        let intervalsToSkip = daysBetween / intervalDays
        if let fastForwarded = calendar.date(
          byAdding: .day, value: intervalsToSkip * intervalDays, to: currentDate)
        {
          currentDate = fastForwarded
        }
      }

      // Generate dates within the display month
      while currentDate < monthEnd, currentDate <= patternEndDate {
        if currentDate >= monthStart {
          dates.append(currentDate.toISODateString())
        }

        guard let nextDate = calendar.date(byAdding: .day, value: intervalDays, to: currentDate)
        else {
          break
        }
        currentDate = nextDate
      }
    }

    return Array(Set(dates)).sorted()
  }

  /// Get the date window for a recurring pattern (for calendar navigation)
  /// - Parameters:
  ///   - selectedDays: Map of weekday to anchor date
  ///   - endCondition: End condition
  /// - Returns: Tuple of (minMonth, maxMonth) dates, or nil if no valid window
  static func getDateWindow(
    selectedDays: [String: String],
    endCondition: EndCondition?
  ) -> (minMonth: Date, maxMonth: Date?)? {
    guard !selectedDays.isEmpty else { return nil }

    let calendar = Calendar.gregorianCurrent

    // Find earliest anchor
    let anchors = selectedDays.values.sorted()
    guard let earliestAnchor = anchors.first,
      let earliestDate = Date.fromISODateString(earliestAnchor)
    else {
      return nil
    }

    // Get start of month for min
    let minMonth =
      calendar.date(from: calendar.dateComponents([.year, .month], from: earliestDate))
      ?? earliestDate

    // Calculate max based on end condition
    let maxMonth: Date?
    switch endCondition {
    case .none:
      // Infinite: no max
      maxMonth = nil

    case .months(let value):
      if let endDate = calendar.date(byAdding: .month, value: value, to: earliestDate) {
        maxMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: endDate))
      } else {
        maxMonth = nil
      }

    case .years(let value):
      if let endDate = calendar.date(byAdding: .year, value: value, to: earliestDate) {
        maxMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: endDate))
      } else {
        maxMonth = nil
      }

    case .endDate(let dateString):
      if let endDate = Date.fromISODateString(dateString) {
        maxMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: endDate))
      } else {
        maxMonth = nil
      }
    }

    return (minMonth, maxMonth)
  }

  /// Check if navigating to a previous month is allowed
  static func canNavigateToPrevious(
    from currentMonth: Date,
    selectedDays: [String: String]
  ) -> Bool {
    guard let window = getDateWindow(selectedDays: selectedDays, endCondition: nil) else {
      return true
    }

    let calendar = Calendar.gregorianCurrent
    guard let prevMonth = calendar.date(byAdding: .month, value: -1, to: currentMonth) else {
      return false
    }

    return prevMonth >= window.minMonth
  }

  /// Check if navigating to a next month is allowed
  static func canNavigateToNext(
    from currentMonth: Date,
    selectedDays: [String: String],
    endCondition: EndCondition?
  ) -> Bool {
    guard let window = getDateWindow(selectedDays: selectedDays, endCondition: endCondition),
      let maxMonth = window.maxMonth
    else {
      return true  // No max = always can go forward
    }

    let calendar = Calendar.gregorianCurrent
    guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth) else {
      return false
    }

    return nextMonth <= maxMonth
  }
}
