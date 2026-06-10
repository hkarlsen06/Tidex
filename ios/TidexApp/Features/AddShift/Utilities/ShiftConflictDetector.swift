import Foundation

/// Detects time conflicts between new shifts and existing shifts
/// Port of conflict detection logic from web app
struct ShiftConflictDetector {

  // MARK: - Public API

  /// Detect conflicts between new dates/times and existing shifts
  /// - Parameters:
  ///   - dates: Array of ISO date strings to check
  ///   - startTime: Start time (HH:mm)
  ///   - endTime: End time (HH:mm)
  ///   - existingShifts: Existing shift records
  ///   - existingRecurringShifts: Existing recurring shift patterns
  /// - Returns: Set of conflicting ISO date strings
  static func detectConflicts(
    dates: [String],
    startTime: String,
    endTime: String,
    existingShifts: [ShiftRow],
    existingRecurringShifts: [RecurringShiftRow] = []
  ) -> Set<String> {
    guard !dates.isEmpty else { return [] }
    guard isValidTime(startTime), isValidTime(endTime) else { return [] }

    var conflicts = Set<String>()

    // Build interval map from existing shifts
    // Include next day for cross-midnight check
    var expandedDates = dates
    for dateISO in dates {
      if let nextDay = addDays(to: dateISO, days: 1) {
        expandedDates.append(nextDay)
      }
    }

    let intervalMap = buildIntervalMap(
      existingShifts: existingShifts,
      existingRecurringShifts: existingRecurringShifts,
      datesToCheck: expandedDates
    )

    let startMinutes = toMinutes(startTime)
    let endMinutes = toMinutes(endTime)
    let isCrossMidnight = endMinutes <= startMinutes

    // Check each date for conflicts
    for dateISO in dates {
      let intervals = intervalMap[dateISO] ?? []
      let nextDayIntervals =
        isCrossMidnight ? (intervalMap[addDays(to: dateISO, days: 1) ?? ""] ?? []) : []

      if hasConflict(
        startMinutes: startMinutes,
        endMinutes: endMinutes,
        isCrossMidnight: isCrossMidnight,
        existingIntervals: intervals,
        nextDayIntervals: nextDayIntervals
      ) {
        conflicts.insert(dateISO)
      }
    }

    return conflicts
  }

  // MARK: - Private Helpers

  /// Build a map of date -> time intervals from existing shifts
  private static func buildIntervalMap(
    existingShifts: [ShiftRow],
    existingRecurringShifts: [RecurringShiftRow],
    datesToCheck: [String]
  ) -> [String: [(Int, Int)]] {
    var map: [String: [(Int, Int)]] = [:]

    // Add regular shifts
    for shift in existingShifts {
      addShiftToMap(
        &map,
        date: shift.shift_date,
        startTime: shift.start_time,
        endTime: shift.end_time
      )
    }

    // Add virtual shifts from recurring patterns
    let dateSet = Set(datesToCheck)
    for recurring in existingRecurringShifts {
      let virtualDates = getVirtualDatesForRecurring(recurring, nearDates: dateSet)
      for dateISO in virtualDates {
        addShiftToMap(
          &map,
          date: dateISO,
          startTime: recurring.start_time,
          endTime: recurring.end_time
        )
      }
    }

    return map
  }

  /// Add a shift's time interval to the map
  private static func addShiftToMap(
    _ map: inout [String: [(Int, Int)]],
    date: String,
    startTime: String,
    endTime: String
  ) {
    let sMin = toMinutes(startTime)
    let eMin = toMinutes(endTime)

    if eMin > sMin {
      // Same day shift
      map[date, default: []].append((sMin, eMin))
    } else {
      // Cross-midnight shift
      // First day: start to midnight
      map[date, default: []].append((sMin, 24 * 60))

      // Next day: midnight to end
      if let nextDate = addDays(to: date, days: 1) {
        map[nextDate, default: []].append((0, eMin))
      }
    }
  }

  /// Check if the new time slot conflicts with existing intervals
  private static func hasConflict(
    startMinutes: Int,
    endMinutes: Int,
    isCrossMidnight: Bool,
    existingIntervals: [(Int, Int)],
    nextDayIntervals: [(Int, Int)] = []
  ) -> Bool {
    if !isCrossMidnight {
      // Simple same-day check
      return existingIntervals.contains { interval in
        overlaps(startMinutes, endMinutes, interval.0, interval.1)
      }
    }
    // Cross-midnight: check both parts against correct day's intervals
    // swiftlint:disable:next explicit_type_interface
    let firstDayConflict = existingIntervals.contains { interval in
      // swiftlint:disable:next no_magic_numbers
      overlaps(startMinutes, 24 * 60, interval.0, interval.1)
    }

    // swiftlint:disable:next explicit_type_interface
    let nextDayConflict = nextDayIntervals.contains { interval in
      overlaps(0, endMinutes, interval.0, interval.1)
    }

    return firstDayConflict || nextDayConflict
  }

  /// Check if two intervals overlap
  private static func overlaps(_ aStart: Int, _ aEnd: Int, _ bStart: Int, _ bEnd: Int) -> Bool {
    return aStart < bEnd && bStart < aEnd
  }

  /// Convert HH:mm to minutes since midnight
  private static func toMinutes(_ hhmm: String) -> Int {
    let parts = hhmm.split(separator: ":").compactMap { Int($0) }
    guard parts.count >= 2 else { return 0 }
    return parts[0] * 60 + parts[1]
  }

  /// Validate HH:mm format
  private static func isValidTime(_ time: String) -> Bool {
    let pattern = #"^\d{2}:\d{2}$"#
    return time.range(of: pattern, options: .regularExpression) != nil
  }

  /// Add days to an ISO date string
  private static func addDays(to dateISO: String, days: Int) -> String? {
    guard let date = Date.fromISODateString(dateISO) else { return nil }
    let calendar = Calendar.current
    guard let newDate = calendar.date(byAdding: .day, value: days, to: date) else { return nil }
    return newDate.toISODateString()
  }

  /// Get virtual dates from a recurring pattern that might conflict with the given dates
  private static func getVirtualDatesForRecurring(
    _ recurring: RecurringShiftRow,
    nearDates: Set<String>
  ) -> [String] {
    // Get the month range of dates we're checking
    guard let minDate = nearDates.min(),
      let maxDate = nearDates.max()
    else {
      return []
    }

    guard let minDateObj = Date.fromISODateString(minDate),
      let maxDateObj = Date.fromISODateString(maxDate)
    else {
      return []
    }

    let calendar = Calendar.current
    var dates: [String] = []

    // Generate virtual shifts for months containing the dates
    var current = minDateObj
    while current <= maxDateObj {
      let year = calendar.component(.year, from: current)
      let month = calendar.component(.month, from: current)

      let virtualShifts = RecurringShiftGenerator.generateVirtualShiftsForMonth(
        year: year,
        month: month,
        recurring: recurring
      )

      dates.append(contentsOf: virtualShifts.map(\.date))

      // Move to next month
      guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: current) else {
        break
      }
      current = nextMonth
    }

    return dates
  }
}
