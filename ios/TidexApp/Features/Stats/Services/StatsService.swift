import Combine
import Foundation
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "StatsService")

private struct FullYearCacheKey: Hashable {
  let userId: String
  let year: Int
  let jobId: String
  let settingsFingerprint: Int
  let snapshotsFingerprint: Int
  let recurringFingerprint: Int
  let jobsFingerprint: Int
  let shiftsFingerprint: Int
}

private struct FullYearComputedData {
  let shifts: [ShiftWithComputations]
  let includedShifts: [ShiftWithComputations]
}

private struct StatsComputationResult {
  let statsData: StatsData
  let currentShiftCount: Int
  let excludedShiftCount: Int
  let currentHours: Double
  let currentGross: Double
  let fullYearCacheData: FullYearComputedData?
}

// MARK: - Stats Service

/// Service for computing stats locally from on-device data
/// Uses the same PayrollEngine as the Dashboard for consistent calculations
@MainActor
final class StatsService: ObservableObject {
  static let shared = StatsService()

  // MARK: - Dependencies

  private let monthlyPayrollReadService: MonthlyPayrollReadService

  // MARK: - Published State

  @Published private(set) var stats: StatsData?
  @Published private(set) var isLoading = false
  @Published private(set) var error: Error?

  // MARK: - Private State

  private var cachedUserId: String?
  private var fullYearCache: [FullYearCacheKey: FullYearComputedData] = [:]

  // MARK: - Initialization

  init(
    shiftsRepository: ShiftsRepository? = nil,
    settingsRepository: SettingsRepository? = nil,
    snapshotsRepository: SnapshotsRepository? = nil,
    recurringShiftsRepository: RecurringShiftsRepository? = nil,
    jobsRepository: JobsRepository? = nil,
    monthlyPayrollReadService: MonthlyPayrollReadService? = nil
  ) {
    let resolvedShiftsRepository = shiftsRepository ?? ShiftsRepository.shared
    let resolvedSettingsRepository = settingsRepository ?? SettingsRepository.shared
    let resolvedSnapshotsRepository = snapshotsRepository ?? SnapshotsRepository.shared
    let resolvedRecurringShiftsRepository =
      recurringShiftsRepository ?? RecurringShiftsRepository.shared
    let resolvedJobsRepository = jobsRepository ?? JobsRepository.shared

    self.monthlyPayrollReadService =
      monthlyPayrollReadService
      ?? MonthlyPayrollReadService(
        shiftsRepository: resolvedShiftsRepository,
        settingsRepository: resolvedSettingsRepository,
        snapshotsRepository: resolvedSnapshotsRepository,
        recurringShiftsRepository: resolvedRecurringShiftsRepository,
        jobsRepository: resolvedJobsRepository
      )
  }

  // MARK: - Public API

  /// Compute stats for a specific month from local data
  /// - Parameters:
  ///   - year: Year to compute stats for (defaults to current year)
  ///   - month: Month to compute stats for (defaults to current month)
  ///   - jobId: Optional job filter. Nil aggregates all jobs.
  /// - Returns: Computed stats data
  func computeStats(
    year: Int? = nil,
    month: Int? = nil,
    jobId: String? = nil
  ) async throws -> StatsData {
    let calendar = Calendar.current
    let now = Date()
    let targetYear = year ?? calendar.component(.year, from: now)
    let targetMonth = month ?? calendar.component(.month, from: now)

    isLoading = true
    error = nil
    defer { isLoading = false }

    do {
      // Get user ID (using AuthSessionManager to prevent concurrent refresh race conditions)
      if cachedUserId == nil {
        let session = try await AuthSessionManager.shared.getSession()
        cachedUserId = session.normalizedUserId
      }

      guard let userId = cachedUserId else {
        throw StatsServiceError.notAuthenticated
      }

      // Load shared payroll inputs through the DAL-backed read service
      let readContext = monthlyPayrollReadService.loadContext(for: userId, jobId: jobId)

      guard let settings = readContext.settings else {
        throw StatsServiceError.noLocalData
      }

      let snapshots = readContext.snapshots
      let recurringShifts = readContext.recurringShifts
      let jobs = readContext.jobs

      // Calculate date ranges
      let currentYM = (year: targetYear, month: targetMonth)
      let previousYM = Date.previousYearMonth(from: currentYM)

      let currentStartDate = Date.firstDayOfMonthDate(year: currentYM.year, month: currentYM.month)
      let currentEndDate = Date.lastDayOfMonthDate(year: currentYM.year, month: currentYM.month)
      let previousStartDate = Date.firstDayOfMonthDate(
        year: previousYM.year, month: previousYM.month)
      let previousEndDate = Date.lastDayOfMonthDate(year: previousYM.year, month: previousYM.month)

      let yearStartDate = Date.firstDayOfMonthDate(year: targetYear, month: 1)
      let yearEndDate = Date.lastDayOfMonthDate(year: targetYear, month: 12)

      // Load shifts from local repositories
      async let currentMonthShiftsRaw = monthlyPayrollReadService.loadShiftRows(
        for: userId,
        startDate: currentStartDate,
        endDate: currentEndDate,
        jobId: jobId
      )
      async let previousMonthShiftsRaw = monthlyPayrollReadService.loadShiftRows(
        for: userId,
        startDate: previousStartDate,
        endDate: previousEndDate,
        jobId: jobId
      )
      async let yearShiftsRaw = monthlyPayrollReadService.loadShiftRows(
        for: userId,
        startDate: yearStartDate,
        endDate: yearEndDate,
        jobId: jobId
      )

      let (resolvedCurrentMonthShiftsRaw, resolvedPreviousMonthShiftsRaw, resolvedYearShiftsRaw) =
        await (currentMonthShiftsRaw, previousMonthShiftsRaw, yearShiftsRaw)

      // Build a deterministic fingerprint so we only recompute full-year data when inputs changed.
      let cacheKey = FullYearCacheKey(
        userId: userId,
        year: targetYear,
        jobId: jobId ?? "__all__",
        settingsFingerprint: Self.fingerprintSettingsForCaching(settings),
        snapshotsFingerprint: Self.fingerprintSnapshotsForCaching(snapshots),
        recurringFingerprint: Self.fingerprintRecurringShiftsForCaching(recurringShifts),
        jobsFingerprint: Self.fingerprintJobsForCaching(jobs),
        shiftsFingerprint: Self.fingerprintShiftsForCaching(resolvedYearShiftsRaw)
      )
      let cachedFullYearData = fullYearCache[cacheKey]

      try Task.checkCancellation()

      let computeTask = Task.detached(priority: .userInitiated) {
        try Task.checkCancellation()

        let currentMonthShifts = PayrollEngine.computeShiftsForMonth(
          .init(
            year: currentYM.year,
            month: currentYM.month,
            shifts: resolvedCurrentMonthShiftsRaw,
            recurring: recurringShifts,
            snapshots: snapshots,
            settings: settings,
            jobs: jobs
          )
        )

        let previousMonthShifts = PayrollEngine.computeShiftsForMonth(
          .init(
            year: previousYM.year,
            month: previousYM.month,
            shifts: resolvedPreviousMonthShiftsRaw,
            recurring: recurringShifts,
            snapshots: snapshots,
            settings: settings,
            jobs: jobs
          )
        )

        let currentMonthPartition = ConflictExclusion.partition(shifts: currentMonthShifts)
        let previousMonthPartition = ConflictExclusion.partition(shifts: previousMonthShifts)
        let currentMonthIncluded = currentMonthPartition.includedShifts
        let previousMonthIncluded = previousMonthPartition.includedShifts

        let fullYearData: FullYearComputedData
        let newFullYearCacheData: FullYearComputedData?
        if let cachedFullYearData {
          fullYearData = cachedFullYearData
          newFullYearCacheData = nil
        } else {
          let shiftsByMonth = Dictionary(grouping: resolvedYearShiftsRaw) { shift in
            Self.monthNumber(fromISODate: shift.shift_date)
          }

          var fullYearShifts: [ShiftWithComputations] = []
          fullYearShifts.reserveCapacity(max(resolvedYearShiftsRaw.count, 64))

          for month in 1...12 {
            try Task.checkCancellation()
            let monthShiftsRaw = shiftsByMonth[month] ?? []
            let computedShifts = PayrollEngine.computeShiftsForMonth(
              .init(
                year: targetYear,
                month: month,
                shifts: monthShiftsRaw,
                recurring: recurringShifts,
                snapshots: snapshots,
                settings: settings,
                jobs: jobs
              )
            )
            fullYearShifts.append(contentsOf: computedShifts)
          }

          let fullYearIncluded = ConflictExclusion.partition(shifts: fullYearShifts).includedShifts
          let computedData = FullYearComputedData(
            shifts: fullYearShifts,
            includedShifts: fullYearIncluded
          )
          fullYearData = computedData
          newFullYearCacheData = computedData
        }

        let fallbackCurrency = settings.currency ?? "kr"
        let currentMonthAggregate = JobCurrencyAggregateResolver.resolve(
          shifts: currentMonthIncluded,
          jobs: jobs,
          fallbackCurrency: fallbackCurrency,
          referenceDate: now
        )
        let primaryCurrentMonthShifts = JobCurrencyAggregateResolver.shifts(
          matching: currentMonthAggregate.primary,
          in: currentMonthIncluded,
          jobs: jobs,
          fallbackCurrency: fallbackCurrency
        )

        // Get totals using PayrollEngine with centralized exclusion IDs
        let halfTaxMonth = settings.half_tax_month
        let currentTotals = PayrollEngine.summarizeShiftTotals(
          shifts: primaryCurrentMonthShifts,
          halfTaxMonth: halfTaxMonth,
          earningsMonth: currentYM.month,
          now: now
        )
        let previousTotals = PayrollEngine.summarizeShiftTotals(
          shifts: previousMonthShifts,
          excludedShiftIds: previousMonthPartition.analysis.excludedIds,
          halfTaxMonth: halfTaxMonth,
          earningsMonth: previousYM.month,
          now: now
        )

        let previousComparisonGross: Double
        if currentMonthAggregate.hasMixedCurrency {
          let previousPrimaryShifts = JobCurrencyAggregateResolver.shifts(
            matching: currentMonthAggregate.primary,
            in: previousMonthIncluded,
            jobs: jobs,
            fallbackCurrency: fallbackCurrency
          )
          previousComparisonGross =
            PayrollEngine.summarizeShiftTotals(
              shifts: previousPrimaryShifts,
              halfTaxMonth: halfTaxMonth,
              earningsMonth: previousYM.month,
              now: now
            ).gross
        } else {
          previousComparisonGross = previousTotals.gross
        }

        // Calculate total hours (using filtered shifts that exclude conflicts)
        let currentHours = currentMonthIncluded.reduce(0) { $0 + $1.paidHours }
        let previousHours = previousMonthIncluded.reduce(0) { $0 + $1.paidHours }

        // Get tax settings from the primary aggregate bucket.
        let taxEnabled = currentMonthAggregate.primary.hasTaxEnabled
        let taxPercentage =
          primaryCurrentMonthShifts.first?.taxPercentage
          ?? currentMonthShifts.first?.taxPercentage
          ?? 0

        // Calculate percentage change
        let percentageChange: Double?
        if previousComparisonGross > 0 {
          percentageChange =
            ((currentTotals.gross - previousComparisonGross) / previousComparisonGross) * 100
        } else if currentTotals.gross > 0 {
          percentageChange = nil  // Can't compute meaningful change from zero
        } else {
          percentageChange = nil
        }

        // Build monthly goal
        let monthlyGoal: MonthlyGoal
        if let goalTarget = settings.effectiveMonthlyGoal(year: targetYear, month: targetMonth),
          goalTarget > 0
        {
          let progress = currentTotals.net
          let percentage = (progress / Double(goalTarget)) * 100
          let remaining = max(Double(goalTarget) - progress, 0)
          monthlyGoal = MonthlyGoal(
            enabled: true,
            target: Double(goalTarget),
            progress: progress,
            percentage: percentage,
            remaining: remaining
          )
        } else {
          monthlyGoal = MonthlyGoal(
            enabled: false,
            target: 0,
            progress: 0,
            percentage: 0,
            remaining: 0
          )
        }

        // Build cumulative data for progress chart (using filtered shifts for earnings)
        let cumulativeData = Self.buildCumulativeData(
          currentMonthShifts: currentMonthIncluded,
          previousMonthShifts: previousMonthIncluded,
          targetYear: targetYear,
          targetMonth: targetMonth,
          previousYear: previousYM.year,
          previousMonth: previousYM.month,
          now: now
        )

        // Determine if viewing current month
        let isCurrentMonth =
          targetYear == calendar.component(.year, from: now)
          && targetMonth == calendar.component(.month, from: now)

        // Build weekly data (using filtered shifts for earnings)
        let thisWeek: [DailyData]?
        let bestWeek: BestWeekData?

        if isCurrentMonth {
          thisWeek = Self.buildThisWeekData(
            shifts: currentMonthIncluded,
            now: now
          )
          bestWeek = nil
        } else {
          thisWeek = nil
          bestWeek = Self.buildBestWeekData(
            shifts: currentMonthIncluded,
            focusYear: targetYear,
            focusMonth: targetMonth
          )
        }

        // Build employment data for the focus year (uses all shifts for hours worked)
        let employmentData = Self.buildEmploymentData(
          focusYear: targetYear,
          shifts: fullYearData.shifts,
          snapshots: snapshots
        )

        let yearlyIncomeData = Self.buildYearlyIncomeData(
          focusYear: targetYear,
          shifts: fullYearData.includedShifts
        )

        let statsData = StatsData(
          focusMonth: FocusMonth(year: targetYear, month: targetMonth),
          tax: TaxSettings(enabled: taxEnabled, percentage: taxPercentage),
          currentMonth: MonthStats(
            totalEarnings: currentTotals.gross,
            totalEarningsNet: currentTotals.net,
            totalHours: currentHours,
            shiftCount: currentMonthShifts.count
          ),
          currentMonthCurrencyAggregate: currentMonthAggregate,
          lastMonth: MonthStats(
            totalEarnings: previousTotals.gross,
            totalEarningsNet: previousTotals.net,
            totalHours: previousHours,
            shiftCount: previousMonthShifts.count
          ),
          percentageChange: percentageChange,
          monthlyGoal: monthlyGoal,
          thisMonthCumulative: cumulativeData,
          thisWeek: thisWeek,
          bestWeek: bestWeek,
          employment: employmentData,
          yearlyIncome: yearlyIncomeData
        )

        return StatsComputationResult(
          statsData: statsData,
          currentShiftCount: currentMonthShifts.count,
          excludedShiftCount: currentMonthPartition.analysis.excludedIds.count,
          currentHours: currentHours,
          currentGross: currentTotals.gross,
          fullYearCacheData: newFullYearCacheData
        )
      }

      let result: StatsComputationResult
      do {
        result = try await computeTask.value
      } catch {
        computeTask.cancel()
        throw error
      }

      try Task.checkCancellation()

      if let fullYearCacheData = result.fullYearCacheData {
        fullYearCache[cacheKey] = fullYearCacheData
        if fullYearCache.count > 8 {
          fullYearCache.removeAll(keepingCapacity: true)
        }
      }

      stats = result.statsData
      logger.info(
        "Computed stats: \(result.currentShiftCount) shifts (\(result.excludedShiftCount) excluded), \(Int(result.currentHours))h, \(Int(result.currentGross)) gross"
      )

      return result.statsData
    } catch is CancellationError {
      throw CancellationError()
    } catch let error as StatsServiceError {
      self.error = error
      throw error
    } catch {
      let wrappedError = StatsServiceError.computationFailed(underlying: error)
      self.error = wrappedError
      throw wrappedError
    }
  }

  /// Clear cached data
  func clearCache() {
    stats = nil
    cachedUserId = nil
    fullYearCache.removeAll(keepingCapacity: true)
  }

  nonisolated static func fingerprintSettingsForCaching(_ settings: UserSettings) -> Int {
    var hasher = Hasher()
    hasher.combine(settings.updated_at ?? "")
    hasher.combine(settings.monthly_goal ?? -1)
    hasher.combine(settings.half_tax_month ?? -1)
    hasher.combine(settings.currency ?? "")

    let monthlyGoals = (settings.monthly_goals_by_month ?? [:]).sorted(by: { $0.key < $1.key })
    for entry in monthlyGoals {
      hasher.combine(entry.key)
      hasher.combine(entry.value)
    }
    return hasher.finalize()
  }

  nonisolated static func fingerprintSnapshotsForCaching(_ snapshots: [WageSnapshot]) -> Int {
    var hasher = Hasher()
    for snapshot in snapshots.sorted(by: { $0.id < $1.id }) {
      hasher.combine(snapshot.id)
      hasher.combine(snapshot.job_id ?? "")
      hasher.combine(snapshot.from_date ?? "")
      hasher.combine(snapshot.hourly_wage)
      hasher.combine(snapshot.wage_level ?? -1)
      hasher.combine(snapshot.tariff_type_id ?? "")
      hasher.combine(snapshot.tax_enabled ?? false)
      hasher.combine(snapshot.tax_percentage ?? 0)
      hasher.combine(snapshot.break_enabled ?? true)
      hasher.combine(snapshot.break_method ?? "")
      hasher.combine(snapshot.break_threshold_hours ?? 0)
      hasher.combine(snapshot.break_deduction_minutes ?? 0)
      hasher.combine(String(describing: snapshot.supplements.rules))
    }
    return hasher.finalize()
  }

  nonisolated static func fingerprintRecurringShiftsForCaching(
    _ recurringShifts: [RecurringShiftRow]
  ) -> Int {
    var hasher = Hasher()
    for shift in recurringShifts.sorted(by: { $0.id < $1.id }) {
      hasher.combine(shift.id)
      hasher.combine(shift.job_id ?? "")
      hasher.combine(shift.start_time)
      hasher.combine(shift.end_time)
      hasher.combine(shift.repeat_interval_weeks)
      for entry in shift.selected_days.sorted(by: { $0.key < $1.key }) {
        hasher.combine(entry.key)
        hasher.combine(entry.value)
      }
      hasher.combine(String(describing: shift.end_condition))
      for exclusion in (shift.exclusions ?? []).sorted() {
        hasher.combine(exclusion)
      }
      for entry in (shift.date_specific_supplements ?? [:]).sorted(by: { $0.key < $1.key }) {
        hasher.combine(entry.key)
        hasher.combine(String(describing: entry.value))
      }
    }
    return hasher.finalize()
  }

  nonisolated static func fingerprintJobsForCaching(_ jobs: [Job]) -> Int {
    var hasher = Hasher()
    for job in jobs.sorted(by: { $0.id < $1.id }) {
      hasher.combine(job.id)
      hasher.combine(job.name)
      hasher.combine(job.color ?? "")
      hasher.combine(job.is_default)
      hasher.combine(job.sort_order)
      hasher.combine(job.payroll_day ?? -1)
      hasher.combine(job.half_tax_month ?? -1)
      hasher.combine(job.monthly_goal ?? -1)
      hasher.combine(job.currency)
      hasher.combine(job.archived_at ?? "")
      hasher.combine(job.deleted_at ?? "")
      hasher.combine(job.updated_at ?? "")
    }
    return hasher.finalize()
  }

  nonisolated static func fingerprintShiftsForCaching(_ shifts: [ShiftRow]) -> Int {
    var hasher = Hasher()
    for shift in shifts.sorted(by: { $0.id < $1.id }) {
      hasher.combine(shift.id)
      hasher.combine(shift.job_id ?? "")
      hasher.combine(shift.shift_date)
      hasher.combine(shift.start_time)
      hasher.combine(shift.end_time)
      hasher.combine(shift.updated_at?.timeIntervalSince1970 ?? -1)
      hasher.combine(String(describing: shift.custom_supplements))
    }
    return hasher.finalize()
  }

  nonisolated private static func monthNumber(fromISODate date: String) -> Int {
    guard date.count >= 7 else { return -1 }
    let monthStart = date.index(date.startIndex, offsetBy: 5)
    let monthEnd = date.index(monthStart, offsetBy: 2)
    return Int(date[monthStart..<monthEnd]) ?? -1
  }

  // MARK: - Private Helpers

  /// Build cumulative earnings data for the progress chart
  /// - Parameters:
  ///   - currentMonthShifts: Computed shifts for the target month
  ///   - previousMonthShifts: Computed shifts for the previous month
  ///   - targetYear: Year of target month
  ///   - targetMonth: Month number (1-12) of target month
  ///   - previousYear: Year of previous month
  ///   - previousMonth: Month number (1-12) of previous month
  ///   - now: Current date for determining today/future
  /// - Returns: Array of cumulative data for each day of the month
  nonisolated private static func buildCumulativeData(  // swiftlint:disable:this function_parameter_count
    currentMonthShifts: [ShiftWithComputations],
    previousMonthShifts: [ShiftWithComputations],
    targetYear: Int,
    targetMonth: Int,
    previousYear: Int,
    previousMonth: Int,
    now: Date
  ) -> [DailyCumulativeData] {
    let calendar = Calendar.current

    // Get days in target month
    guard
      let targetMonthDate = calendar.date(
        from: DateComponents(year: targetYear, month: targetMonth, day: 1)),
      let range = calendar.range(of: .day, in: .month, for: targetMonthDate)
    else {
      return []
    }
    let daysInCurrentMonth = range.count

    // Get days in previous month
    guard
      let prevMonthDate = calendar.date(
        from: DateComponents(year: previousYear, month: previousMonth, day: 1)),
      let prevRange = calendar.range(of: .day, in: .month, for: prevMonthDate)
    else {
      return []
    }
    let daysInPreviousMonth = prevRange.count

    // Determine if we're viewing the current real month
    let currentYear = calendar.component(.year, from: now)
    let currentMonth = calendar.component(.month, from: now)
    let isCurrentSelection = targetYear == currentYear && targetMonth == currentMonth

    // Today's day number (or end of month if viewing a past month)
    let todayDayNumber =
      isCurrentSelection ? calendar.component(.day, from: now) : daysInCurrentMonth

    // Build earnings per day maps
    var currentMonthEarningsPerDay: [Int: Double] = [:]
    var previousMonthEarningsPerDay: [Int: Double] = [:]

    for shift in currentMonthShifts {
      // Parse day from shift_date string (YYYY-MM-DD)
      let components = shift.shiftDate.split(separator: "-")
      if components.count >= 3, let day = Int(components[2]) {
        currentMonthEarningsPerDay[day, default: 0] += shift.grossPay
      }
    }

    for shift in previousMonthShifts {
      // Parse day from shift_date string (YYYY-MM-DD)
      let components = shift.shiftDate.split(separator: "-")
      if components.count >= 3, let day = Int(components[2]) {
        previousMonthEarningsPerDay[day, default: 0] += shift.grossPay
      }
    }

    // Build cumulative data
    var cumulativeData: [DailyCumulativeData] = []
    var currentCumulative: Double = 0
    var previousCumulative: Double = 0

    for day in 1...daysInCurrentMonth {
      // Add current month's earnings for this day
      currentCumulative += currentMonthEarningsPerDay[day] ?? 0

      // Add previous month's earnings for this day (if it exists in previous month)
      if day <= daysInPreviousMonth {
        previousCumulative += previousMonthEarningsPerDay[day] ?? 0
      }

      let dataPoint = DailyCumulativeData(
        day: day,
        currentMonth: currentCumulative,
        lastMonth: previousCumulative,
        isToday: isCurrentSelection && day == todayDayNumber,
        isFuture: day > todayDayNumber
      )
      cumulativeData.append(dataPoint)
    }

    return cumulativeData
  }

  /// Build "This Week" data showing current calendar week (Mon-Sun)
  /// - Parameters:
  ///   - shifts: Computed shifts for the current month
  ///   - now: Current date
  /// - Returns: Array of daily data for Mon-Sun of current week
  nonisolated private static func buildThisWeekData(
    shifts: [ShiftWithComputations],
    now: Date
  ) -> [DailyData] {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = Date.localTimeZone
    calendar.firstWeekday = 2  // Monday

    // Find Monday of current week
    let weekday = calendar.component(.weekday, from: now)
    // weekday: 1=Sun, 2=Mon, ..., 7=Sat
    // Days back to Monday: Sun(1)->6, Mon(2)->0, Tue(3)->1, etc.
    let daysBackToMonday = weekday == 1 ? 6 : weekday - 2
    guard let monday = calendar.date(byAdding: .day, value: -daysBackToMonday, to: now) else {
      return []
    }

    // Build earnings map for shifts
    var earningsMap: [String: (earnings: Double, hours: Double, shifts: Int)] = [:]
    for shift in shifts {
      let key = shift.shiftDate
      let existing = earningsMap[key] ?? (0, 0, 0)
      earningsMap[key] = (
        existing.earnings + shift.grossPay,
        existing.hours + shift.paidHours,
        existing.shifts + 1
      )
    }

    // Build data for each day of the week (Mon-Sun)
    var weekData: [DailyData] = []

    for dayOffset in 0..<7 {
      guard let date = calendar.date(byAdding: .day, value: dayOffset, to: monday) else {
        continue
      }

      let isoDate = date.toISODateString()
      let data = earningsMap[isoDate] ?? (0, 0, 0)

      // Get localized day names
      let shortName = Self.shortWeekdayName(for: date, calendar: calendar)
      let fullName = Self.fullWeekdayName(for: date, calendar: calendar)

      weekData.append(
        DailyData(
          date: shortName,
          fullDay: fullName,
          earnings: data.earnings,
          hours: data.hours,
          shifts: data.shifts,
          fullDate: isoDate
        ))
    }

    return weekData
  }

  /// Build "Best Week" data showing the week with highest earnings in a past month
  /// - Parameters:
  ///   - shifts: Computed shifts for the focus month
  ///   - focusYear: Year of focus month
  ///   - focusMonth: Month number (1-12) of focus month
  /// - Returns: Best week data or nil if no shifts
  nonisolated private static func buildBestWeekData(
    shifts: [ShiftWithComputations],
    focusYear: Int,
    focusMonth: Int
  ) -> BestWeekData? {
    guard !shifts.isEmpty else { return nil }

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = Date.localTimeZone
    calendar.firstWeekday = 2  // Monday

    // Group shifts by ISO week number
    var weeklyEarnings: [Int: (earnings: Double, hours: Double, shifts: [ShiftWithComputations])] =
      [:]

    for shift in shifts {
      guard let date = Date.fromISODateString(shift.shiftDate) else { continue }
      let weekNumber = calendar.component(.weekOfYear, from: date)

      let existing = weeklyEarnings[weekNumber] ?? (0, 0, [])
      weeklyEarnings[weekNumber] = (
        existing.earnings + shift.grossPay,
        existing.hours + shift.paidHours,
        existing.shifts + [shift]
      )
    }

    // Find week with highest earnings
    guard let bestWeekEntry = weeklyEarnings.max(by: { $0.value.earnings < $1.value.earnings })
    else {
      return nil
    }

    let bestWeekNumber = bestWeekEntry.key
    let bestWeekShifts = bestWeekEntry.value.shifts

    // Find Monday of the best week
    // Get any date from that week and find its Monday
    guard let sampleShift = bestWeekShifts.first,
      let sampleDate = Date.fromISODateString(sampleShift.shiftDate)
    else {
      return nil
    }

    let weekday = calendar.component(.weekday, from: sampleDate)
    let daysBackToMonday = weekday == 1 ? 6 : weekday - 2
    guard let monday = calendar.date(byAdding: .day, value: -daysBackToMonday, to: sampleDate)
    else {
      return nil
    }

    // Build earnings map
    var earningsMap: [String: (earnings: Double, hours: Double, shifts: Int)] = [:]
    for shift in bestWeekShifts {
      let key = shift.shiftDate
      let existing = earningsMap[key] ?? (0, 0, 0)
      earningsMap[key] = (
        existing.earnings + shift.grossPay,
        existing.hours + shift.paidHours,
        existing.shifts + 1
      )
    }

    // Build data for each day of the week (Mon-Sun)
    // Use date numbers for best week (e.g., "15.") instead of day names
    var weekData: [DailyData] = []

    for dayOffset in 0..<7 {
      guard let date = calendar.date(byAdding: .day, value: dayOffset, to: monday) else {
        continue
      }

      let isoDate = date.toISODateString()
      let dayComponents = isoDate.split(separator: "-")

      // Only include days that are in the focus month
      let dateMonth = dayComponents.count >= 2 ? Int(dayComponents[1]) ?? 0 : 0
      let dayNumber = dayComponents.count >= 3 ? Int(dayComponents[2]) ?? 0 : 0

      let data: (earnings: Double, hours: Double, shifts: Int)
      if dateMonth == focusMonth {
        data = earningsMap[isoDate] ?? (0, 0, 0)
      } else {
        // Day is outside focus month - show 0
        data = (0, 0, 0)
      }

      // Show date number instead of day name for best week (e.g., "15.")
      let dateLabel = "\(dayNumber)."
      let fullName = Self.fullWeekdayName(for: date, calendar: calendar)

      weekData.append(
        DailyData(
          date: dateLabel,
          fullDay: fullName,
          earnings: data.earnings,
          hours: data.hours,
          shifts: data.shifts,
          fullDate: isoDate
        ))
    }

    return BestWeekData(
      weekData: weekData,
      weekNumber: bestWeekNumber,
      totalEarnings: bestWeekEntry.value.earnings,
      totalHours: bestWeekEntry.value.hours
    )
  }

  /// Get short weekday name (e.g., "Man", "Tir")
  nonisolated private static func shortWeekdayName(for date: Date, calendar: Calendar) -> String {
    let formatter = FormatterCache.shortWeekdayFormatter(locale: Locale(identifier: "nb_NO"))
    formatter.calendar = calendar
    return formatter.string(from: date).sentenceCased()
  }

  /// Get full weekday name (e.g., "Mandag", "Tirsdag")
  nonisolated private static func fullWeekdayName(for date: Date, calendar: Calendar) -> String {
    let formatter = FormatterCache.weekdayFormatter(locale: Locale(identifier: "nb_NO"))
    formatter.calendar = calendar
    return formatter.string(from: date).sentenceCased()
  }

  // MARK: - Employment Percentage Calculation

  /// Build employment percentage data for the focus year
  /// Calculates average employment percentage per month based on hours worked
  /// Uses weighted distribution for weeks spanning multiple months
  /// - Parameters:
  ///   - focusYear: The year to calculate employment data for
  ///   - shifts: All computed shifts for the year
  ///   - snapshots: Wage snapshots to determine break deduction settings
  /// - Returns: Employment data with monthly breakdown and yearly average
  nonisolated private static func buildEmploymentData(
    focusYear: Int,
    shifts: [ShiftWithComputations],
    snapshots: [WageSnapshot]
  ) -> EmploymentData {
    // Full-time hours per week: 37.5h if break deduction enabled, 40h otherwise
    // Uses baseline snapshot's break setting (or first available snapshot)
    let baselineSnapshot = snapshots.first { $0.isBaseline } ?? snapshots.first
    let breakDeductionEnabled = baselineSnapshot?.effectiveBreakEnabled ?? true
    let fullTimeHoursPerWeek: Double = breakDeductionEnabled ? 37.5 : 40

    // Short and full month names (Norwegian)
    let shortMonthNames = [
      "jan.", "feb.", "mar.", "apr.", "mai", "jun.",
      "jul.", "aug.", "sep.", "okt.", "nov.", "des.",
    ]
    let fullMonthNames = [
      "Januar", "Februar", "Mars", "April", "Mai", "Juni",
      "Juli", "August", "September", "Oktober", "November", "Desember",
    ]

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = Date.localTimeZone
    calendar.firstWeekday = 2  // Monday

    // Build a map of date -> hours worked
    var hoursPerDay: [String: Double] = [:]
    for shift in shifts {
      let dateStr = shift.shiftDate
      hoursPerDay[dateStr, default: 0] += shift.paidHours
    }

    // Track which days have shifts for hasShifts flag
    var daysWithShiftsPerMonth: [Int: Set<Int>] = [:]
    for shift in shifts {
      let components = shift.shiftDate.split(separator: "-")
      if components.count >= 3,
        let month = Int(components[1]),
        let day = Int(components[2])
      {
        daysWithShiftsPerMonth[month, default: []].insert(day)
      }
    }

    // Accumulators for monthly employment percentages
    struct MonthAccumulator {
      var totalWeightedPercentage: Double = 0
      var totalWeight: Double = 0
    }
    var monthlyAccumulators: [Int: MonthAccumulator] = [:]
    for month in 1...12 {
      monthlyAccumulators[month] = MonthAccumulator()
    }

    // Find Monday of the first week of the year
    guard let yearStart = calendar.date(from: DateComponents(year: focusYear, month: 1, day: 1))
    else {
      return EmploymentData(
        monthlyData: [], yearlyAverage: nil, fullTimeHoursPerWeek: fullTimeHoursPerWeek)
    }
    let weekday = calendar.component(.weekday, from: yearStart)
    let daysBackToMonday = weekday == 1 ? 6 : weekday - 2
    guard var currentMonday = calendar.date(byAdding: .day, value: -daysBackToMonday, to: yearStart)
    else {
      return EmploymentData(
        monthlyData: [], yearlyAverage: nil, fullTimeHoursPerWeek: fullTimeHoursPerWeek)
    }

    // End of the focus year
    guard let yearEnd = calendar.date(from: DateComponents(year: focusYear, month: 12, day: 31))
    else {
      return EmploymentData(
        monthlyData: [], yearlyAverage: nil, fullTimeHoursPerWeek: fullTimeHoursPerWeek)
    }

    // Process all weeks until we pass the end of the year
    while currentMonday <= yearEnd {
      // Build the 7 days of this week
      var weekDays: [Date] = []
      for i in 0..<7 {
        if let day = calendar.date(byAdding: .day, value: i, to: currentMonday) {
          weekDays.append(day)
        }
      }

      // Calculate hours worked per month within this week
      // Only count hours towards the month they were actually worked in
      var hoursPerMonthInWeek: [Int: Double] = [:]
      var daysPerMonth: [Int: Int] = [:]

      for day in weekDays {
        let month = calendar.component(.month, from: day)
        let year = calendar.component(.year, from: day)

        // Only count days in the focus year
        if year == focusYear {
          daysPerMonth[month, default: 0] += 1

          // Add hours worked on this day to the appropriate month
          let dateStr = day.toISODateString()
          let hoursOnDay = hoursPerDay[dateStr] ?? 0
          hoursPerMonthInWeek[month, default: 0] += hoursOnDay
        }
      }

      // Add weighted contribution to each month based on hours worked IN that month
      for (month, dayCount) in daysPerMonth {
        let weight = Double(dayCount) / 7.0
        let hoursInMonth = hoursPerMonthInWeek[month] ?? 0

        // Calculate employment percentage based only on hours worked in this month's portion
        let monthEmploymentPct = (hoursInMonth / fullTimeHoursPerWeek) * 100

        monthlyAccumulators[month]?.totalWeightedPercentage += monthEmploymentPct * weight
        monthlyAccumulators[month]?.totalWeight += weight
      }

      // Move to next week
      currentMonday = calendar.date(byAdding: .day, value: 7, to: currentMonday) ?? currentMonday
    }

    // Build monthly data
    var monthlyData: [EmploymentMonthlyData] = []
    var yearlySum: Double = 0
    var monthsWithShifts = 0

    for month in 1...12 {
      let accumulator = monthlyAccumulators[month] ?? MonthAccumulator()
      let averagePercentage: Double
      if accumulator.totalWeight > 0 {
        averagePercentage = accumulator.totalWeightedPercentage / accumulator.totalWeight
      } else {
        averagePercentage = 0
      }

      let hasShifts = !(daysWithShiftsPerMonth[month]?.isEmpty ?? true)

      // Round to 1 decimal place
      let roundedPercentage = (averagePercentage * 10).rounded() / 10

      monthlyData.append(
        EmploymentMonthlyData(
          month: shortMonthNames[month - 1],
          fullMonth: fullMonthNames[month - 1],
          year: focusYear,
          monthNumber: month,
          averagePercentage: roundedPercentage,
          hasShifts: hasShifts
        ))

      // Add to yearly sum if month has shifts
      if hasShifts && accumulator.totalWeight > 0 {
        yearlySum += averagePercentage
        monthsWithShifts += 1
      }
    }

    // Calculate yearly average
    let yearlyAverage: Double?
    if monthsWithShifts > 0 {
      yearlyAverage = (yearlySum / Double(monthsWithShifts) * 10).rounded() / 10
    } else {
      yearlyAverage = nil
    }

    return EmploymentData(
      monthlyData: monthlyData,
      yearlyAverage: yearlyAverage,
      fullTimeHoursPerWeek: fullTimeHoursPerWeek
    )
  }

  // MARK: - Yearly Income Data

  /// Build monthly income breakdown for the focus year
  /// - Parameters:
  ///   - focusYear: The year to calculate income data for
  ///   - shifts: All computed shifts for the year
  /// - Returns: Array of monthly income data for all 12 months
  nonisolated private static func buildYearlyIncomeData(
    focusYear: Int,
    shifts: [ShiftWithComputations]
  ) -> [MonthlyIncomeData] {
    // Short and full month names (Norwegian)
    let shortMonthNames = [
      "jan.", "feb.", "mar.", "apr.", "mai", "jun.",
      "jul.", "aug.", "sep.", "okt.", "nov.", "des.",
    ]
    let fullMonthNames = [
      "Januar", "Februar", "Mars", "April", "Mai", "Juni",
      "Juli", "August", "September", "Oktober", "November", "Desember",
    ]

    // Group shifts by month
    var monthlyEarnings: [Int: Double] = [:]
    var monthlyHours: [Int: Double] = [:]
    var monthlyShiftCounts: [Int: Int] = [:]

    for shift in shifts {
      // Parse month from shift_date string (YYYY-MM-DD)
      let components = shift.shiftDate.split(separator: "-")
      guard components.count >= 2,
        let month = Int(components[1]),
        month >= 1, month <= 12
      else {
        continue
      }

      monthlyEarnings[month, default: 0] += shift.grossPay
      monthlyHours[month, default: 0] += shift.paidHours
      monthlyShiftCounts[month, default: 0] += 1
    }

    // Build monthly data for all 12 months
    return (1...12).map { month in
      MonthlyIncomeData(
        month: shortMonthNames[month - 1],
        fullMonth: fullMonthNames[month - 1],
        year: focusYear,
        monthNumber: month,
        earnings: monthlyEarnings[month] ?? 0,
        hours: monthlyHours[month] ?? 0,
        shifts: monthlyShiftCounts[month] ?? 0
      )
    }
  }
}

// MARK: - Errors

enum StatsServiceError: Error, LocalizedError {
  case notAuthenticated
  case noLocalData
  case computationFailed(underlying: Error)

  var errorDescription: String? {
    switch self {
    case .notAuthenticated:
      return "Not authenticated"
    case .noLocalData:
      return "No local data available. Please wait for sync to complete."
    case .computationFailed(let error):
      return "Failed to compute stats: \(error.localizedDescription)"
    }
  }
}
