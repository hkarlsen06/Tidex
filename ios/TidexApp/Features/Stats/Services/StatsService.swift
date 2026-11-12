import Foundation
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "StatsService")  // swiftlint:disable:this explicit_type_interface line_length prefixed_toplevel_constant

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

struct FullYearComputedData {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  let year: Int  // swiftlint:disable:this explicit_acl
  let shiftsByMonth: [Int: [ShiftWithComputations]]  // swiftlint:disable:this explicit_acl
  let shifts: [ShiftWithComputations]
  let includedShifts: [ShiftWithComputations]

  /// Reuse payroll already computed for the year, including empty months.
  /// January still computes the previous December from its separate row read.
  func shifts(for request: PayrollEngine.MonthComputationRequest) -> [ShiftWithComputations] {  // swiftlint:disable:this explicit_acl line_length
    if request.year == year {
      return shiftsByMonth[request.month] ?? []
    }
    return PayrollEngine.computeShiftsForMonth(request)
  }
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
final class StatsService {  // swiftlint:disable:this explicit_acl explicit_top_level_acl file_types_order line_length required_deinit type_body_length
  static let shared = StatsService()  // swiftlint:disable:this explicit_acl explicit_type_interface

  // MARK: - Dependencies

  private let monthlyPayrollReadService: MonthlyPayrollReadService
  private let userIdProvider: @MainActor () async throws -> String

  // MARK: - State

  private(set) var stats: StatsData?  // swiftlint:disable:this explicit_acl
  private(set) var statsUserId: String?
  private(set) var statsJobId: String?
  private(set) var isLoading = false  // swiftlint:disable:this explicit_acl explicit_type_interface
  private(set) var error: Error?  // swiftlint:disable:this explicit_acl

  // MARK: - Private State

  private var computationGeneration: Int = 0
  private var fullYearCache: [FullYearCacheKey: FullYearComputedData] = [:]

  // MARK: - Initialization

  init(  // swiftlint:disable:this explicit_acl
    shiftsRepository: ShiftsRepository? = nil,
    settingsRepository: SettingsRepository? = nil,
    snapshotsRepository: SnapshotsRepository? = nil,
    recurringShiftsRepository: RecurringShiftsRepository? = nil,
    jobsRepository: JobsRepository? = nil,
    monthlyPayrollReadService: MonthlyPayrollReadService? = nil,
    userIdProvider: (@MainActor () async throws -> String)? = nil
  ) {
    self.userIdProvider = userIdProvider ?? Self.resolveUserIdForLocalStats
    let resolvedShiftsRepository = shiftsRepository ?? ShiftsRepository.shared  // swiftlint:disable:this explicit_type_interface line_length
    let resolvedSettingsRepository = settingsRepository ?? SettingsRepository.shared  // swiftlint:disable:this explicit_type_interface line_length
    let resolvedSnapshotsRepository = snapshotsRepository ?? SnapshotsRepository.shared  // swiftlint:disable:this explicit_type_interface line_length
    let resolvedRecurringShiftsRepository =  // swiftlint:disable:this explicit_type_interface
      recurringShiftsRepository ?? RecurringShiftsRepository.shared
    let resolvedJobsRepository = jobsRepository ?? JobsRepository.shared  // swiftlint:disable:this explicit_type_interface line_length

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
  func computeStats(  // swiftlint:disable:this cyclomatic_complexity explicit_acl function_body_length line_length type_contents_order
    year: Int? = nil,
    month: Int? = nil,
    jobId: String? = nil
  ) async throws -> StatsData {
    let calendar = Calendar.gregorianCurrent  // swiftlint:disable:this explicit_type_interface
    let now = Date()  // swiftlint:disable:this explicit_type_interface
    let targetYear = year ?? calendar.component(.year, from: now)  // swiftlint:disable:this explicit_type_interface
    let targetMonth = month ?? calendar.component(.month, from: now)  // swiftlint:disable:this explicit_type_interface

    computationGeneration += 1
    let generation = computationGeneration
    isLoading = true
    error = nil
    defer {
      if generation == computationGeneration {
        isLoading = false
      }
    }

    do {
      let userId = try await userIdProvider()  // swiftlint:disable:this explicit_type_interface
      try checkCurrentComputation(generation)

      // Load shared payroll inputs through the DAL-backed read service
      let readContext: PayrollReadContext =
        await monthlyPayrollReadService.loadContextUsingStoreActor(
          for: userId,
          jobId: jobId
        )
      try checkCurrentComputation(generation)

      guard let settings = readContext.settings else {
        throw StatsServiceError.noLocalData
      }

      let snapshots = readContext.snapshots  // swiftlint:disable:this explicit_type_interface
      let recurringShifts = readContext.recurringShifts  // swiftlint:disable:this explicit_type_interface
      let jobs = readContext.jobs  // swiftlint:disable:this explicit_type_interface

      // Calculate date ranges
      let currentYM = (year: targetYear, month: targetMonth)  // swiftlint:disable:this explicit_type_interface
      let previousYM = Date.previousYearMonth(from: currentYM)  // swiftlint:disable:this explicit_type_interface

      let previousStartDate = Date.firstDayOfMonthDate(  // swiftlint:disable:this explicit_type_interface
        year: previousYM.year, month: previousYM.month)  // swiftlint:disable:this multiline_arguments_brackets
      let previousEndDate = Date.lastDayOfMonthDate(year: previousYM.year, month: previousYM.month)  // swiftlint:disable:this explicit_type_interface line_length

      let yearStartDate = Date.firstDayOfMonthDate(year: targetYear, month: 1)  // swiftlint:disable:this explicit_type_interface line_length
      let yearEndDate = Date.lastDayOfMonthDate(year: targetYear, month: 12)  // swiftlint:disable:this explicit_type_interface line_length no_magic_numbers

      // The annual read already contains the current and previous months, except in January.
      async let yearShiftsRaw = monthlyPayrollReadService.loadShiftRows(  // swiftlint:disable:this explicit_type_interface line_length
        for: userId,
        startDate: yearStartDate,
        endDate: yearEndDate,
        jobId: jobId
      )

      let resolvedPreviousYearShiftsRaw: [ShiftRow]
      if previousYM.year != targetYear {
        resolvedPreviousYearShiftsRaw = await monthlyPayrollReadService.loadShiftRows(
          for: userId,
          startDate: previousStartDate,
          endDate: previousEndDate,
          jobId: jobId
        )
      } else {
        resolvedPreviousYearShiftsRaw = []
      }
      let resolvedYearShiftsRaw = await yearShiftsRaw  // swiftlint:disable:this explicit_type_interface
      try checkCurrentComputation(generation)

      // Build a deterministic fingerprint so we only recompute full-year data when inputs changed.
      let cacheKey = FullYearCacheKey(  // swiftlint:disable:this explicit_type_interface
        userId: userId,
        year: targetYear,
        jobId: jobId ?? "__all__",
        settingsFingerprint: Self.fingerprintSettingsForCaching(settings),
        snapshotsFingerprint: Self.fingerprintSnapshotsForCaching(snapshots),
        recurringFingerprint: Self.fingerprintRecurringShiftsForCaching(recurringShifts),
        jobsFingerprint: Self.fingerprintJobsForCaching(jobs),
        shiftsFingerprint: Self.fingerprintShiftsForCaching(resolvedYearShiftsRaw)
      )
      let cachedFullYearData = fullYearCache[cacheKey]  // swiftlint:disable:this explicit_type_interface

      try Task.checkCancellation()

      let computeTask = Task.detached(priority: .userInitiated) {  // swiftlint:disable:this closure_body_length explicit_type_interface line_length
        try Task.checkCancellation()

        let fullYearData: FullYearComputedData
        let newFullYearCacheData: FullYearComputedData?
        if let cachedFullYearData {
          fullYearData = cachedFullYearData
          newFullYearCacheData = nil
        } else {
          let computedData = try Self.computeFullYearPayrollData(  // swiftlint:disable:this explicit_type_interface
            year: targetYear,
            shifts: resolvedYearShiftsRaw,
            recurring: recurringShifts,
            snapshots: snapshots,
            settings: settings,
            jobs: jobs
          )
          fullYearData = computedData
          newFullYearCacheData = computedData
        }

        let currentMonthShifts = fullYearData.shiftsByMonth[currentYM.month] ?? []  // swiftlint:disable:this explicit_type_interface line_length
        let previousMonthShifts = fullYearData.shifts(  // swiftlint:disable:this explicit_type_interface
          for: .init(
            year: previousYM.year,
            month: previousYM.month,
            shifts: resolvedPreviousYearShiftsRaw,
            recurring: recurringShifts,
            snapshots: snapshots,
            settings: settings,
            jobs: jobs
          )
        )
        // Keep monthly conflict decisions separate from annual conflict exclusions.
        let currentMonthPartition = ConflictExclusion.partition(shifts: currentMonthShifts)  // swiftlint:disable:this explicit_type_interface line_length
        let previousMonthPartition = ConflictExclusion.partition(shifts: previousMonthShifts)  // swiftlint:disable:this explicit_type_interface line_length
        let currentMonthIncluded = currentMonthPartition.includedShifts  // swiftlint:disable:this explicit_type_interface line_length
        let previousMonthIncluded = previousMonthPartition.includedShifts  // swiftlint:disable:this explicit_type_interface line_length

        let fallbackCurrency = settings.currency ?? "kr"  // swiftlint:disable:this explicit_type_interface
        let aggregateJobs = jobId.map { selectedId in jobs.filter { $0.id == selectedId } } ?? jobs
        let currentMonthAggregate = JobCurrencyAggregateResolver.resolve(  // swiftlint:disable:this explicit_type_interface line_length
          shifts: currentMonthIncluded,
          jobs: aggregateJobs,
          fallbackCurrency: fallbackCurrency,
          referenceDate: now
        )
        let primaryCurrentMonthShifts = JobCurrencyAggregateResolver.shifts(  // swiftlint:disable:this explicit_type_interface line_length
          in: currentMonthIncluded,
          currency: currentMonthAggregate.primary.currency,
          jobs: jobs,
          fallbackCurrency: fallbackCurrency
        )
        let primaryPreviousMonthShifts = JobCurrencyAggregateResolver.shifts(
          in: previousMonthIncluded,
          currency: currentMonthAggregate.primary.currency,
          jobs: jobs,
          fallbackCurrency: fallbackCurrency
        )

        // Get totals using PayrollEngine with centralized exclusion IDs
        let halfTaxMonth = settings.half_tax_month  // swiftlint:disable:this explicit_type_interface
        let currentTotals = PayrollEngine.summarizeShiftTotals(  // swiftlint:disable:this explicit_type_interface
          shifts: primaryCurrentMonthShifts,
          halfTaxMonth: halfTaxMonth,
          earningsMonth: currentYM.month,
          now: now
        )
        let previousTotals = PayrollEngine.summarizeShiftTotals(  // swiftlint:disable:this explicit_type_interface
          shifts: primaryPreviousMonthShifts,
          halfTaxMonth: halfTaxMonth,
          earningsMonth: previousYM.month,
          now: now
        )

        // Calculate total hours (using filtered shifts that exclude conflicts)
        let currentHours = currentMonthIncluded.reduce(0) { $0 + $1.paidHours }  // swiftlint:disable:this explicit_type_interface line_length
        let previousHours = previousMonthIncluded.reduce(0) { $0 + $1.paidHours }  // swiftlint:disable:this explicit_type_interface line_length

        // Get tax settings from the primary aggregate bucket.
        let taxEnabled = currentMonthAggregate.primary.hasTaxEnabled  // swiftlint:disable:this explicit_type_interface
        let taxPercentage =  // swiftlint:disable:this explicit_type_interface
          primaryCurrentMonthShifts.first?.taxPercentage
          ?? currentMonthShifts.first?.taxPercentage
          ?? 0

        // Same computation as Home, so both screens show the same percentage.
        let percentageChange = MonthlyEarningsChange.percent(  // swiftlint:disable:this explicit_type_interface
          currentShifts: primaryCurrentMonthShifts,
          previousShifts: primaryPreviousMonthShifts,
          halfTaxMonth: halfTaxMonth,
          currentMonth: currentYM.month,
          previousMonth: previousYM.month,
          now: now
        )

        // Build cumulative data for progress chart (using filtered shifts for earnings)
        let cumulativeData = Self.buildCumulativeData(  // swiftlint:disable:this explicit_type_interface
          currentMonthShifts: primaryCurrentMonthShifts,
          previousMonthShifts: primaryPreviousMonthShifts,
          targetYear: targetYear,
          targetMonth: targetMonth,
          previousYear: previousYM.year,
          previousMonth: previousYM.month,
          now: now
        )

        let dayStats = Self.buildDayStats(  // swiftlint:disable:this explicit_type_interface
          primaryShifts: primaryCurrentMonthShifts,
          includedShifts: currentMonthIncluded,
          year: targetYear,
          month: targetMonth
        )

        // Build employment data for the focus year from shifts that count toward totals
        let employmentData = Self.buildEmploymentData(  // swiftlint:disable:this explicit_type_interface
          focusYear: targetYear,
          shifts: fullYearData.includedShifts,
          snapshots: snapshots
        )

        let yearlyIncomeData = Self.buildYearlyIncomeData(  // swiftlint:disable:this explicit_type_interface
          focusYear: targetYear,
          shifts: JobCurrencyAggregateResolver.shifts(
            in: fullYearData.includedShifts,
            currency: currentMonthAggregate.primary.currency,
            jobs: jobs,
            fallbackCurrency: fallbackCurrency
          )
        )

        let statsData = StatsData(  // swiftlint:disable:this explicit_type_interface
          focusMonth: FocusMonth(year: targetYear, month: targetMonth),
          tax: TaxSettings(enabled: taxEnabled, percentage: taxPercentage),
          currentMonth: MonthStats(
            totalEarnings: currentTotals.gross,
            totalEarningsNet: currentTotals.net,
            totalHours: currentHours,
            shiftCount: currentMonthIncluded.count
          ),
          currentMonthCurrencyAggregate: currentMonthAggregate,
          lastMonth: MonthStats(
            totalEarnings: previousTotals.gross,
            totalEarningsNet: previousTotals.net,
            totalHours: previousHours,
            shiftCount: previousMonthIncluded.count
          ),
          percentageChange: percentageChange,
          thisMonthCumulative: cumulativeData,
          days: dayStats,
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

      let result = try await withTaskCancellationHandler {  // swiftlint:disable:this explicit_type_interface
        try await computeTask.value
      } onCancel: {
        computeTask.cancel()
      }

      try checkCurrentComputation(generation)

      if let fullYearCacheData = result.fullYearCacheData {
        fullYearCache[cacheKey] = fullYearCacheData
        if fullYearCache.count > 8 {  // swiftlint:disable:this no_magic_numbers
          fullYearCache.removeAll(keepingCapacity: true)
        }
      }

      statsUserId = userId
      statsJobId = jobId
      stats = result.statsData
      logger.info(
        "Computed stats: \(result.currentShiftCount) shifts (\(result.excludedShiftCount) excluded), \(Int(result.currentHours))h, \(Int(result.currentGross)) gross"  // swiftlint:disable:this line_length
      )

      return result.statsData
    } catch is CancellationError {
      throw CancellationError()
    } catch let error as StatsServiceError {
      try checkCurrentComputation(generation)
      self.error = error
      throw error
    } catch {
      try checkCurrentComputation(generation)
      let wrappedError = StatsServiceError.computationFailed(underlying: error)  // swiftlint:disable:this explicit_type_interface line_length
      self.error = wrappedError
      throw wrappedError
    }
  }

  /// Clear cached data
  func clearCache() {  // swiftlint:disable:this explicit_acl type_contents_order
    computationGeneration += 1
    stats = nil
    statsUserId = nil
    statsJobId = nil
    isLoading = false
    error = nil
    fullYearCache.removeAll(keepingCapacity: true)
  }

  private func checkCurrentComputation(_ generation: Int) throws {
    try Task.checkCancellation()
    guard generation == computationGeneration else {
      throw CancellationError()
    }
  }

  nonisolated static func computeFullYearPayrollData(  // swiftlint:disable:this explicit_acl function_parameter_count
    year: Int,
    shifts: [ShiftRow],
    recurring: [RecurringShiftRow],
    snapshots: [WageSnapshot],
    settings: UserSettings,
    jobs: [Job]
  ) throws -> FullYearComputedData {
    var shiftsByMonth: [Int: [ShiftWithComputations]] = [:]
    var fullYearShifts: [ShiftWithComputations] = []
    fullYearShifts.reserveCapacity(max(shifts.count, 64))  // swiftlint:disable:this no_magic_numbers

    for month in 1...12 {  // swiftlint:disable:this no_magic_numbers
      try Task.checkCancellation()
      // Match the monthly DAL read, including overnight hours carried into the first ISO week.
      let window = PayrollReadWindow.month(year: year, month: month).expandedForOvertime  // swiftlint:disable:this explicit_type_interface line_length
      let startISO = window.startDate.toISODateString()  // swiftlint:disable:this explicit_type_interface
      let endISO = window.endDate.toISODateString()  // swiftlint:disable:this explicit_type_interface
      let monthRows = shifts.filter { $0.shift_date >= startISO && $0.shift_date <= endISO }  // swiftlint:disable:this explicit_type_interface line_length
      let computedShifts = PayrollEngine.computeShiftsForMonth(  // swiftlint:disable:this explicit_type_interface
        .init(
          year: year,
          month: month,
          shifts: monthRows,
          recurring: recurring,
          snapshots: snapshots,
          settings: settings,
          jobs: jobs
        )
      )
      shiftsByMonth[month] = computedShifts
      fullYearShifts.append(contentsOf: computedShifts)
    }

    return FullYearComputedData(
      year: year,
      shiftsByMonth: shiftsByMonth,
      shifts: fullYearShifts,
      includedShifts: ConflictExclusion.partition(shifts: fullYearShifts).includedShifts
    )
  }

  // swiftlint:disable:next type_contents_order
  private static func resolveUserIdForLocalStats() async throws -> String {
    do {
      let session = try await AuthSessionManager.shared.getSession()  // swiftlint:disable:this explicit_type_interface
      return session.normalizedUserId
    } catch {
      guard AuthSessionManager.shared.isTransientSessionResolutionError(error),
        let offlineUserId = AuthSessionManager.shared.offlineUserIdFallback()
      else {
        throw error
      }

      logger.info("Using offline user id fallback for local stats")
      return offlineUserId
    }
  }

  nonisolated static func fingerprintSettingsForCaching(_ settings: UserSettings) -> Int {  // swiftlint:disable:this explicit_acl line_length
    var hasher = Hasher()  // swiftlint:disable:this explicit_type_interface
    hasher.combine(settings.updated_at ?? "")
    hasher.combine(settings.effectivePayrollDay)
    hasher.combine(settings.half_tax_month ?? -1)
    hasher.combine(settings.currency ?? "")
    return hasher.finalize()
  }

  nonisolated static func fingerprintSnapshotsForCaching(_ snapshots: [WageSnapshot]) -> Int {  // swiftlint:disable:this explicit_acl line_length
    var hasher = Hasher()  // swiftlint:disable:this explicit_type_interface
    // Snapshot lookup uses input order to break ties for identical effective dates.
    for snapshot in snapshots {
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
      hasher.combine(snapshot.effectiveBreakThresholdHours)
      hasher.combine(snapshot.effectiveBreakDeductionMinutes)
      hasher.combine(String(describing: snapshot.supplements.rules))
      hasher.combine(snapshot.overtime.enabled)
      hasher.combine(snapshot.overtime.weeklyThresholdHours)
      hasher.combine(String(describing: snapshot.overtime.rules))
    }
    return hasher.finalize()
  }

  nonisolated static func fingerprintRecurringShiftsForCaching(  // swiftlint:disable:this explicit_acl
    _ recurringShifts: [RecurringShiftRow]
  ) -> Int {
    var hasher = Hasher()  // swiftlint:disable:this explicit_type_interface
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
      for entry in (shift.date_specific_pause_windows ?? [:]).sorted(by: { $0.key < $1.key }) {
        hasher.combine(entry.key)
        hasher.combine(String(describing: entry.value))
      }
      for entry in (shift.date_specific_supplements ?? [:]).sorted(by: { $0.key < $1.key }) {
        hasher.combine(entry.key)
        hasher.combine(String(describing: entry.value))
      }
    }
    return hasher.finalize()
  }

  nonisolated static func fingerprintJobsForCaching(_ jobs: [Job]) -> Int {  // swiftlint:disable:this explicit_acl
    var hasher = Hasher()  // swiftlint:disable:this explicit_type_interface
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

  nonisolated static func fingerprintShiftsForCaching(_ shifts: [ShiftRow]) -> Int {  // swiftlint:disable:this explicit_acl line_length
    var hasher = Hasher()  // swiftlint:disable:this explicit_type_interface
    for shift in shifts.sorted(by: { $0.id < $1.id }) {
      hasher.combine(shift.id)
      hasher.combine(shift.job_id ?? "")
      hasher.combine(shift.shift_date)
      hasher.combine(shift.start_time)
      hasher.combine(shift.end_time)
      hasher.combine(shift.updated_at?.timeIntervalSince1970 ?? -1)
      hasher.combine(String(describing: shift.custom_pause_windows))
      hasher.combine(String(describing: shift.custom_supplements))
    }
    return hasher.finalize()
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
  nonisolated static func buildCumulativeData(  // swiftlint:disable:this cyclomatic_complexity explicit_acl function_body_length function_parameter_count line_length
    currentMonthShifts: [ShiftWithComputations],
    previousMonthShifts: [ShiftWithComputations],
    targetYear: Int,
    targetMonth: Int,
    previousYear: Int,
    previousMonth: Int,
    now: Date
  ) -> [DailyCumulativeData] {
    let calendar = Calendar.gregorianCurrent  // swiftlint:disable:this explicit_type_interface

    // Get days in target month
    guard
      let targetMonthDate = calendar.date(
        from: DateComponents(year: targetYear, month: targetMonth, day: 1)),  // swiftlint:disable:this line_length multiline_arguments_brackets
      let range = calendar.range(of: .day, in: .month, for: targetMonthDate)
    else {
      return []
    }
    let daysInCurrentMonth = range.count  // swiftlint:disable:this explicit_type_interface

    // Get days in previous month
    guard
      let prevMonthDate = calendar.date(
        from: DateComponents(year: previousYear, month: previousMonth, day: 1)),  // swiftlint:disable:this line_length multiline_arguments_brackets
      let prevRange = calendar.range(of: .day, in: .month, for: prevMonthDate)
    else {
      return []
    }
    let daysInPreviousMonth = prevRange.count  // swiftlint:disable:this explicit_type_interface

    // Determine if we're viewing the current real month
    let currentYear = calendar.component(.year, from: now)  // swiftlint:disable:this explicit_type_interface
    let currentMonth = calendar.component(.month, from: now)  // swiftlint:disable:this explicit_type_interface
    let isCurrentSelection = targetYear == currentYear && targetMonth == currentMonth  // swiftlint:disable:this explicit_type_interface line_length

    // Today's day number (or end of month if viewing a past month)
    let todayDayNumber =  // swiftlint:disable:this explicit_type_interface
      isCurrentSelection ? calendar.component(.day, from: now) : daysInCurrentMonth

    // Build earnings per day maps
    var currentMonthEarningsPerDay: [Int: Double] = [:]
    var previousMonthEarningsPerDay: [Int: Double] = [:]

    for shift in currentMonthShifts {
      // Parse day from shift_date string (YYYY-MM-DD)
      let components = shift.shiftDate.split(separator: "-")  // swiftlint:disable:this explicit_type_interface
      if components.count >= 3, let day = Int(components[2]) {  // swiftlint:disable:this no_magic_numbers
        currentMonthEarningsPerDay[day, default: 0] += shift.grossPay
      }
    }

    for shift in previousMonthShifts {
      // Parse day from shift_date string (YYYY-MM-DD)
      let components = shift.shiftDate.split(separator: "-")  // swiftlint:disable:this explicit_type_interface
      if components.count >= 3, let day = Int(components[2]) {  // swiftlint:disable:this no_magic_numbers
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
      // A longer previous month folds its remaining days into the last point.
      if day == daysInCurrentMonth, daysInPreviousMonth > daysInCurrentMonth {
        for extraDay in (day + 1)...daysInPreviousMonth {
          previousCumulative += previousMonthEarningsPerDay[extraDay] ?? 0
        }
      }

      let dataPoint = DailyCumulativeData(  // swiftlint:disable:this explicit_type_interface
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

  /// One entry per day of the month, days without shifts included.
  /// `includedShifts` holds every currency, so the shifts it has beyond `primaryShifts`
  /// are the ones paid in another currency.
  nonisolated static func buildDayStats(  // swiftlint:disable:this explicit_acl
    primaryShifts: [ShiftWithComputations],
    includedShifts: [ShiftWithComputations],
    year: Int,
    month: Int
  ) -> [DayStats] {
    let dayCount = Date.daysInMonth(year: year, month: month)  // swiftlint:disable:this explicit_type_interface
    var earnings = [Double](repeating: 0, count: dayCount)  // swiftlint:disable:this explicit_type_interface
    var hours = [Double](repeating: 0, count: dayCount)  // swiftlint:disable:this explicit_type_interface
    var primaryCounts = [Int](repeating: 0, count: dayCount)  // swiftlint:disable:this explicit_type_interface
    var allCounts = [Int](repeating: 0, count: dayCount)  // swiftlint:disable:this explicit_type_interface

    func dayIndex(of shift: ShiftWithComputations) -> Int? {
      let components = shift.shiftDate.split(separator: "-")  // swiftlint:disable:this explicit_type_interface
      guard components.count >= 3, let day = Int(components[2]) else { return nil }
      return (1...dayCount).contains(day) ? day - 1 : nil
    }

    for shift in primaryShifts {
      guard let index = dayIndex(of: shift) else { continue }
      earnings[index] += shift.grossPay
      hours[index] += shift.paidHours
      primaryCounts[index] += 1
    }
    for shift in includedShifts {
      guard let index = dayIndex(of: shift) else { continue }
      allCounts[index] += 1
    }

    return (0..<dayCount).map { index in
      DayStats(
        day: index + 1,
        earnings: earnings[index],
        hours: hours[index],
        shifts: primaryCounts[index],
        otherCurrencyShifts: max(allCounts[index] - primaryCounts[index], 0)
      )
    }
  }

  nonisolated static func monthNames(locale: Locale = .current) -> (short: [String], full: [String])
  {
    var calendar: Calendar = Calendar(identifier: .gregorian)
    calendar.locale = locale
    return (calendar.shortMonthSymbols, calendar.monthSymbols.map { $0.sentenceCased() })
  }

  // MARK: - Employment Percentage Calculation

  /// Build employment percentage data for the focus year
  /// Calculates average employment percentage per month based on hours worked
  /// Compares hours worked in each month with full-time hours for that month's weekdays
  /// - Parameters:
  ///   - focusYear: The year to calculate employment data for
  ///   - shifts: All computed shifts for the year
  ///   - snapshots: Wage snapshots to determine break deduction settings
  /// - Returns: Employment data with monthly breakdown and yearly average
  nonisolated static func buildEmploymentData(  // swiftlint:disable:this cyclomatic_complexity explicit_acl function_body_length line_length
    focusYear: Int,
    shifts: [ShiftWithComputations],
    snapshots: [WageSnapshot]
  ) -> EmploymentData {
    // Full-time hours per week: 37.5h if break deduction enabled, 40h otherwise
    // Uses baseline snapshot's break setting (or first available snapshot)
    let baselineSnapshot = snapshots.first(where: \.isBaseline) ?? snapshots.first  // swiftlint:disable:this explicit_type_interface line_length
    let breakDeductionEnabled = baselineSnapshot?.effectiveBreakEnabled ?? true  // swiftlint:disable:this explicit_type_interface line_length
    let fullTimeHoursPerWeek: Double = breakDeductionEnabled ? 37.5 : 40  // swiftlint:disable:this no_magic_numbers

    let (shortMonthNames, fullMonthNames) = Self.monthNames()

    var calendar = Calendar(identifier: .gregorian)  // swiftlint:disable:this explicit_type_interface
    calendar.timeZone = Date.localTimeZone
    calendar.firstWeekday = 2  // Monday // swiftlint:disable:this no_magic_numbers

    // Build a map of date -> hours worked
    var hoursPerDay: [String: Double] = [:]
    for shift in shifts {
      let dateStr = shift.shiftDate  // swiftlint:disable:this explicit_type_interface
      hoursPerDay[dateStr, default: 0] += shift.paidHours
    }

    // Track which days have shifts for hasShifts flag
    var daysWithShiftsPerMonth: [Int: Set<Int>] = [:]
    for shift in shifts {
      let components = shift.shiftDate.split(separator: "-")  // swiftlint:disable:this explicit_type_interface
      if components.count >= 3,  // swiftlint:disable:this no_magic_numbers
        let month = Int(components[1]),
        let day = Int(components[2])  // swiftlint:disable:this no_magic_numbers
      {
        daysWithShiftsPerMonth[month, default: []].insert(day)
      }
    }

    // A full-time month is its weekdays at a fifth of the weekly full-time hours,
    // so someone working every weekday shows 100% whether the month has 20 or 23 of them.
    var hoursPerMonth: [Int: Double] = [:]
    for (dateStr, hours) in hoursPerDay where dateStr.hasPrefix("\(focusYear)-") {
      if let month = Int(dateStr.split(separator: "-")[1]) {
        hoursPerMonth[month, default: 0] += hours
      }
    }
    var fullTimeHoursPerMonth: [Int: Double] = [:]
    for month in 1...12 {  // swiftlint:disable:this no_magic_numbers
      guard
        let monthStart = calendar.date(from: DateComponents(year: focusYear, month: month, day: 1)),
        let days = calendar.range(of: .day, in: .month, for: monthStart)
      else { continue }
      let weekdayCount = days.filter { day in  // swiftlint:disable:this explicit_type_interface
        guard let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) else {
          return false
        }
        return !calendar.isDateInWeekend(date)
      }.count
      // swiftlint:disable:next no_magic_numbers
      fullTimeHoursPerMonth[month] = Double(weekdayCount) * fullTimeHoursPerWeek / 5
    }

    // Build monthly data
    var monthlyData: [EmploymentMonthlyData] = []
    var yearlySum: Double = 0
    var monthsWithShifts = 0  // swiftlint:disable:this explicit_type_interface

    for month in 1...12 {  // swiftlint:disable:this no_magic_numbers
      let fullTimeHours = fullTimeHoursPerMonth[month] ?? 0  // swiftlint:disable:this explicit_type_interface
      let averagePercentage =
        fullTimeHours > 0 ? (hoursPerMonth[month] ?? 0) / fullTimeHours * 100 : 0  // swiftlint:disable:this explicit_type_interface line_length

      let hasShifts = !(daysWithShiftsPerMonth[month]?.isEmpty ?? true)  // swiftlint:disable:this explicit_type_interface line_length

      // Round to 1 decimal place
      let roundedPercentage = (averagePercentage * 10).rounded() / 10  // swiftlint:disable:this explicit_type_interface line_length no_magic_numbers

      monthlyData.append(
        EmploymentMonthlyData(
          month: shortMonthNames[month - 1],
          fullMonth: fullMonthNames[month - 1],
          year: focusYear,
          monthNumber: month,
          averagePercentage: roundedPercentage,
          hasShifts: hasShifts
        ))  // swiftlint:disable:this multiline_arguments_brackets

      // Add to yearly sum if month has shifts
      if hasShifts, fullTimeHours > 0 {
        yearlySum += averagePercentage
        monthsWithShifts += 1
      }
    }

    // Calculate yearly average
    let yearlyAverage: Double?
    if monthsWithShifts > 0 {
      yearlyAverage = (yearlySum / Double(monthsWithShifts) * 10).rounded() / 10  // swiftlint:disable:this line_length no_magic_numbers
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
    let (shortMonthNames, fullMonthNames) = Self.monthNames()

    // Group shifts by month
    var monthlyEarnings: [Int: Double] = [:]
    var monthlyHours: [Int: Double] = [:]
    var monthlyShiftCounts: [Int: Int] = [:]

    for shift in shifts {
      // Parse month from shift_date string (YYYY-MM-DD)
      let components = shift.shiftDate.split(separator: "-")  // swiftlint:disable:this explicit_type_interface
      guard components.count >= 2,  // swiftlint:disable:this no_magic_numbers
        let month = Int(components[1]),
        month >= 1, month <= 12  // swiftlint:disable:this no_magic_numbers
      else {
        continue
      }

      monthlyEarnings[month, default: 0] += shift.grossPay
      monthlyHours[month, default: 0] += shift.paidHours
      monthlyShiftCounts[month, default: 0] += 1
    }

    // Build monthly data for all 12 months
    return (1...12).map { month in  // swiftlint:disable:this no_magic_numbers
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

enum StatsServiceError: Error, LocalizedError {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  case notAuthenticated  // swiftlint:disable:this sorted_enum_cases
  case noLocalData
  case computationFailed(underlying: Error)  // swiftlint:disable:this sorted_enum_cases

  var errorDescription: String? {  // swiftlint:disable:this explicit_acl
    switch self {
    case .notAuthenticated:
      return String(localized: .commonErrorNotAuthenticated)

    case .noLocalData:
      return String(localized: .commonErrorNoLocalData)

    case .computationFailed:
      return String(localized: .statsErrorComputationFailed)
    }
  }
}  // swiftlint:disable:this file_length
