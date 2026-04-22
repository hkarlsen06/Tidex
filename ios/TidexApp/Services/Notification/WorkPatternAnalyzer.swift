import Foundation
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "WorkPatternAnalyzer")

/// Analyzes recent shift history to detect typical work days
/// For each weekday, checks if the user has worked that day regularly over the analysis window
struct WorkPatternAnalyzer {
  struct WorkPattern {
    let typicalWorkDays: [Int: DayPattern]  // weekday -> pattern (0=Sun)
    let computedAt: Date
    static let minimumWeeksRequired = 6
  }

  /// Detailed analysis result including diagnostics
  enum AnalysisResult {
    case success(WorkPattern)
    case insufficientData(weeksFound: Int)
    case noShifts
    case noPatternDetected
  }

  struct DayPattern {
    let weekday: Int
    let frequency: Double
    let medianStartMinutes: Int
    let medianEndMinutes: Int
  }

  private static let analysisWeeks = 26
  private static let frequencyThreshold = 0.45

  /// Analyze shift history for typical work patterns
  /// - Parameter userId: User ID
  /// - Returns: WorkPattern if sufficient data exists, otherwise nil
  @MainActor
  static func analyze(for userId: String) -> WorkPattern? {
    switch analyzeDetailed(for: userId) {
    case .success(let pattern):
      return pattern
    default:
      return nil
    }
  }

  /// Async variant that runs heavy analysis work off the main actor.
  @MainActor
  static func analyzeAsync(for userId: String) async -> WorkPattern? {
    switch await analyzeDetailedAsync(for: userId) {
    case .success(let pattern):
      return pattern
    default:
      return nil
    }
  }

  /// Analyze shift history with detailed result including diagnostics
  /// For each weekday (Mon-Sun), computes how often the user works that day
  /// across the analysis window. Any weekday above the frequency threshold
  /// is considered a typical work day.
  @MainActor
  static func analyzeDetailed(for userId: String) -> AnalysisResult {
    let calendar = Calendar.current
    let now = Date()
    let endDate = calendar.startOfDay(for: now)
    guard let startDate = calendar.date(byAdding: .weekOfYear, value: -analysisWeeks, to: endDate)
    else {
      return .noShifts
    }

    let shifts = combinedShifts(for: userId, startDate: startDate, endDate: endDate)
    guard !shifts.isEmpty else {
      logger.info("No shifts available for pattern analysis")
      return .noShifts
    }

    return analyzeShiftTimes(shifts, now: now)
  }

  /// Async variant that keeps repository reads on main actor but runs loop-heavy analysis off-main.
  @MainActor
  static func analyzeDetailedAsync(for userId: String) async -> AnalysisResult {
    let calendar = Calendar.current
    let now = Date()
    let endDate = calendar.startOfDay(for: now)
    guard let startDate = calendar.date(byAdding: .weekOfYear, value: -analysisWeeks, to: endDate)
    else {
      return .noShifts
    }

    let realShifts = ShiftsRepository.shared.getShifts(
      for: userId,
      startDate: startDate,
      endDate: endDate
    )
    let recurringPatterns = RecurringShiftsRepository.shared.getRecurringShifts(for: userId)

    let shifts = await combinedShiftsOffMain(
      realShifts: realShifts,
      recurringPatterns: recurringPatterns,
      startDate: startDate,
      endDate: endDate
    )
    guard !shifts.isEmpty else {
      logger.info("No shifts available for pattern analysis")
      return .noShifts
    }

    return await Task.detached(priority: .utility) {
      analyzeShiftTimes(shifts, now: now)
    }.value
  }

  // MARK: - Combined Shifts

  private struct ShiftTime {
    let dateISO: String
    let startMinutes: Int
    let endMinutes: Int
  }

  @MainActor
  private static func combinedShifts(
    for userId: String,
    startDate: Date,
    endDate: Date
  ) -> [ShiftTime] {
    let realShifts = ShiftsRepository.shared.getShifts(
      for: userId, startDate: startDate, endDate: endDate)
    let recurringPatterns = RecurringShiftsRepository.shared.getRecurringShifts(for: userId)
    return combinedShifts(
      realShifts: realShifts,
      recurringPatterns: recurringPatterns,
      startDate: startDate,
      endDate: endDate
    )
  }

  private nonisolated static func combinedShiftsOffMain(
    realShifts: [ShiftRow],
    recurringPatterns: [RecurringShiftRow],
    startDate: Date,
    endDate: Date
  ) async -> [ShiftTime] {
    await Task.detached(priority: .utility) {
      combinedShifts(
        realShifts: realShifts,
        recurringPatterns: recurringPatterns,
        startDate: startDate,
        endDate: endDate
      )
    }.value
  }

  private nonisolated static func combinedShifts(
    realShifts: [ShiftRow],
    recurringPatterns: [RecurringShiftRow],
    startDate: Date,
    endDate: Date
  ) -> [ShiftTime] {
    let realDates = Set(realShifts.map { $0.shift_date })
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
            custom_pause_windows: recurring.date_specific_pause_windows?[virtual.date],
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

  private nonisolated static func analyzeShiftTimes(
    _ shifts: [ShiftTime],
    now: Date
  ) -> AnalysisResult {
    let calendar = Calendar.current

    var weeksWithData = Set<String>()
    for shift in shifts {
      guard let date = Date.fromISODateString(shift.dateISO) else { continue }
      let weekOfYear = calendar.component(.weekOfYear, from: date)
      let yearForWeek = calendar.component(.yearForWeekOfYear, from: date)
      weeksWithData.insert("\(yearForWeek)-\(weekOfYear)")
    }

    let weeksCount = weeksWithData.count
    guard weeksCount >= WorkPattern.minimumWeeksRequired else {
      logger.info("Insufficient weeks for pattern analysis: \(weeksCount)")
      return .insufficientData(weeksFound: weeksCount)
    }

    var byWeekday: [Int: [ShiftTime]] = [:]
    for shift in shifts {
      guard let date = Date.fromISODateString(shift.dateISO) else { continue }
      let weekday = calendar.component(.weekday, from: date) - 1
      byWeekday[weekday, default: []].append(shift)
    }

    var typicalWorkDays: [Int: DayPattern] = [:]
    for (weekday, dayShifts) in byWeekday {
      let frequency = Double(dayShifts.count) / Double(weeksCount)
      guard frequency >= frequencyThreshold else { continue }

      let startMinutes = dayShifts.map { $0.startMinutes }.sorted()
      let endMinutes = dayShifts.map { $0.endMinutes }.sorted()

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
      return .noPatternDetected
    }

    logger.info(
      "Detected \(typicalWorkDays.count) typical work days (threshold: \(self.frequencyThreshold))")
    return .success(WorkPattern(typicalWorkDays: typicalWorkDays, computedAt: now))
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
