import Foundation
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "WorkPatternAnalyzer")

/// Analyzes recent shift history to detect typical work patterns
@MainActor
struct WorkPatternAnalyzer {
  struct WorkPattern {
    let typicalWorkDays: [Int: DayPattern]  // weekday -> pattern (0=Sun)
    let computedAt: Date
    static let minimumWeeksRequired = 4
  }

  struct DayPattern {
    let weekday: Int
    let frequency: Double
    let medianStartMinutes: Int
    let medianEndMinutes: Int
  }

  private static let analysisWeeks = 12

  /// Analyze shift history for typical work patterns
  /// - Parameter userId: User ID
  /// - Returns: WorkPattern if sufficient data exists, otherwise nil
  static func analyze(for userId: String) -> WorkPattern? {
    let calendar = Calendar.current
    let now = Date()
    let endDate = calendar.startOfDay(for: now)
    guard let startDate = calendar.date(byAdding: .weekOfYear, value: -analysisWeeks, to: endDate)
    else {
      return nil
    }

    let combinedShifts = combinedShifts(for: userId, startDate: startDate, endDate: endDate)
    guard !combinedShifts.isEmpty else {
      logger.info("No shifts available for pattern analysis")
      return nil
    }

    // Compute weeks-with-data in the analysis window
    var weeksWithData = Set<String>()
    for shift in combinedShifts {
      guard let date = Date.fromISODateString(shift.dateISO) else { continue }
      let weekOfYear = calendar.component(.weekOfYear, from: date)
      let yearForWeek = calendar.component(.yearForWeekOfYear, from: date)
      weeksWithData.insert("\(yearForWeek)-\(weekOfYear)")
    }

    let weeksCount = weeksWithData.count
    guard weeksCount >= WorkPattern.minimumWeeksRequired else {
      logger.info("Insufficient weeks for pattern analysis: \(weeksCount)")
      return nil
    }

    // Group shifts by weekday
    var byWeekday: [Int: [ShiftTime]] = [:]
    for shift in combinedShifts {
      guard let date = Date.fromISODateString(shift.dateISO) else { continue }
      let weekday = calendar.component(.weekday, from: date) - 1  // 0=Sun
      byWeekday[weekday, default: []].append(shift)
    }

    var typicalWorkDays: [Int: DayPattern] = [:]
    for (weekday, shifts) in byWeekday {
      let frequency = Double(shifts.count) / Double(weeksCount)
      guard frequency >= 0.6 else { continue }

      let startMinutes = shifts.map { $0.startMinutes }.sorted()
      let endMinutes = shifts.map { $0.endMinutes }.sorted()

      guard let medianStart = median(of: startMinutes),
        let medianEnd = median(of: endMinutes)
      else {
        continue
      }

      typicalWorkDays[weekday] = DayPattern(
        weekday: weekday,
        frequency: frequency,
        medianStartMinutes: medianStart,
        medianEndMinutes: medianEnd
      )
    }

    if typicalWorkDays.isEmpty {
      logger.info("No typical work days detected")
      return nil
    }

    return WorkPattern(typicalWorkDays: typicalWorkDays, computedAt: now)
  }

  // MARK: - Combined Shifts

  private struct ShiftTime {
    let dateISO: String
    let startMinutes: Int
    let endMinutes: Int
  }

  private static func combinedShifts(
    for userId: String,
    startDate: Date,
    endDate: Date
  ) -> [ShiftTime] {
    let shiftsRepository = ShiftsRepository.shared
    let recurringRepository = RecurringShiftsRepository.shared

    let realShifts = shiftsRepository.getShifts(for: userId, startDate: startDate, endDate: endDate)
    let realDates = Set(realShifts.map { $0.shift_date })

    let recurringPatterns = recurringRepository.getRecurringShifts(for: userId)
    let monthsInRange = getMonthsInRange(startDate: startDate, endDate: endDate)

    var virtualShifts: [ShiftRow] = []
    for (year, month) in monthsInRange {
      for recurring in recurringPatterns {
        let generated = RecurringShiftGenerator.generateVirtualShiftsForMonth(
          year: year,
          month: month,
          recurring: recurring
        )

        for virtual in generated {
          guard let virtualDate = Date.fromISODateString(virtual.date),
            virtualDate >= startDate,
            virtualDate <= endDate
          else {
            continue
          }
          let virtualRow = ShiftRow(
            id: "virtual-\(recurring.id)-\(virtual.date)",
            user_id: recurring.user_id,
            shift_date: virtual.date,
            start_time: recurring.cleanStartTime,
            end_time: recurring.cleanEndTime,
            custom_supplements: recurring.date_specific_supplements?[virtual.date],
            created_at: nil
          )
          virtualShifts.append(virtualRow)
        }
      }
    }

    let dedupedVirtuals = virtualShifts.filter { !realDates.contains($0.shift_date) }
    let allShifts = realShifts + dedupedVirtuals

    var results: [ShiftTime] = []
    results.reserveCapacity(allShifts.count)

    for shift in allShifts {
      guard let startMinutes = parseMinutes(shift.start_time),
        let endMinutes = parseMinutes(shift.end_time)
      else {
        continue
      }
      let adjustedEnd = endMinutes < startMinutes ? endMinutes + (24 * 60) : endMinutes
      results.append(
        ShiftTime(
          dateISO: shift.shift_date,
          startMinutes: startMinutes,
          endMinutes: adjustedEnd
        ))
    }

    return results
  }

  private static func parseMinutes(_ time: String) -> Int? {
    let parts = time.split(separator: ":").compactMap { Int($0) }
    guard parts.count >= 2 else { return nil }
    return (parts[0] * 60) + parts[1]
  }

  private static func median(of values: [Int]) -> Int? {
    guard !values.isEmpty else { return nil }
    let count = values.count
    if count % 2 == 1 {
      return values[count / 2]
    }
    let lower = values[(count / 2) - 1]
    let upper = values[count / 2]
    return (lower + upper) / 2
  }

  private static func getMonthsInRange(startDate: Date, endDate: Date) -> [(Int, Int)] {
    var months: [(Int, Int)] = []
    let calendar = Calendar.current

    var current =
      calendar.date(from: calendar.dateComponents([.year, .month], from: startDate)) ?? startDate
    let endMonth =
      calendar.date(from: calendar.dateComponents([.year, .month], from: endDate)) ?? endDate

    while current <= endMonth {
      let year = calendar.component(.year, from: current)
      let month = calendar.component(.month, from: current)
      months.append((year, month))
      current = calendar.date(byAdding: .month, value: 1, to: current) ?? current
    }

    return months
  }
}
