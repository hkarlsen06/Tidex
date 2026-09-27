import Foundation

/// Centralized payroll computation service
/// Mirrors Next.js lib/services/shifts.ts
///
/// This service encapsulates the complete payroll computation workflow:
/// - Per-shift payout date calculation for accurate tax lookup
/// - Half-tax month application (Norwegian tax benefit)
/// - Conflict exclusion for overlapping shifts
/// - Monthly totals summarization
struct PayrollEngine {
  struct MonthComputationRequest {
    let year: Int
    let month: Int
    let shifts: [ShiftRow]
    let recurring: [RecurringShiftRow]
    let snapshots: [WageSnapshot]
    let settings: UserSettings?
    let visibleRange: (start: Date, end: Date)?
    let jobs: [Job]

    init(
      year: Int,
      month: Int,
      shifts: [ShiftRow],
      recurring: [RecurringShiftRow],
      snapshots: [WageSnapshot],
      settings: UserSettings?,
      visibleRange: (start: Date, end: Date)? = nil,
      jobs: [Job]
    ) {
      self.year = year
      self.month = month
      self.shifts = shifts
      self.recurring = recurring
      self.snapshots = snapshots
      self.settings = settings
      self.visibleRange = visibleRange
      self.jobs = jobs
    }
  }

  private struct ComputationContext {
    let fallbackPayrollDay: Int
    let fallbackHalfTaxMonth: Int?
    let jobsById: [String: Job]
    let defaultJobId: String?
    let snapshotsByJobId: [String?: [WageSnapshot]]
    let legacyNilJobSnapshots: [WageSnapshot]
  }

  // MARK: - Payout Date Calculation

  /// Calculate payout date for a shift (shift month + 1)
  /// Tax settings are based on when you receive the money (payout month)
  /// - Parameters:
  ///   - shiftDate: ISO date string (YYYY-MM-DD) of the shift
  ///   - payrollDay: Day of month for payroll (1-31)
  /// - Returns: ISO date string (YYYY-MM-DD) of the payout date
  static func calculatePayoutDate(shiftDate: String, payrollDay: Int) -> String {
    let components = shiftDate.split(separator: "-")
    guard components.count >= 2,
      let shiftYear = Int(components[0]),
      let shiftMonth = Int(components[1]),
      (1...12).contains(shiftMonth)
    else {
      // Fallback: return a default payout date
      return shiftDate
    }

    var payoutYear = shiftYear
    var payoutMonth = shiftMonth + 1

    if payoutMonth > 12 {
      payoutMonth = 1
      payoutYear += 1
    }

    // Handle edge case: payroll_day exceeds days in payout month
    let daysInPayoutMonth = Date.daysInMonth(year: payoutYear, month: payoutMonth)
    let effectivePayrollDay = min(max(payrollDay, 1), daysInPayoutMonth)

    return String(format: "%04d-%02d-%02d", payoutYear, payoutMonth, effectivePayrollDay)
  }

  /// Extract payout month (1-12) from a shift date
  /// Payout month = earnings month + 1
  static func payoutMonth(from shiftDate: String) -> Int {
    let components = shiftDate.split(separator: "-")
    guard components.count >= 2,
      let shiftMonth = Int(components[1]),
      (1...12).contains(shiftMonth)
    else {
      return 1
    }
    return shiftMonth >= 12 ? 1 : shiftMonth + 1
  }

  // MARK: - Shift Computation

  /// Compute all shifts with payroll for a given month
  /// - Parameters:
  ///   - year: Target year
  ///   - month: Target month (1-12)
  ///   - shifts: Regular shifts from database (may include out-of-month shifts for calendar display)
  ///   - recurring: Recurring shift patterns
  ///   - snapshots: Wage snapshots for lookup
  ///   - settings: User settings (for payroll_day)
  ///   - visibleRange: Optional visible date range for generating virtual shifts (includes out-of-month padding)
  /// - Returns: Array of computed shifts with correct tax settings
  static func computeShiftsForMonth(_ request: MonthComputationRequest) -> [ShiftWithComputations] {
    var result: [ShiftWithComputations] = []
    let fallbackPayrollDay = request.settings?.effectivePayrollDay ?? 1
    let snapshotsByJobId = Dictionary(grouping: request.snapshots, by: { $0.job_id })
    let context = ComputationContext(
      fallbackPayrollDay: fallbackPayrollDay,
      fallbackHalfTaxMonth: request.settings?.half_tax_month,
      jobsById: Dictionary(uniqueKeysWithValues: request.jobs.map { ($0.id, $0) }),
      defaultJobId: request.jobs.first(where: \.is_default)?.id,
      snapshotsByJobId: snapshotsByJobId,
      legacyNilJobSnapshots: snapshotsByJobId[nil] ?? []
    )

    // Use visible range if provided, otherwise just the target month
    let startDate =
      request.visibleRange?.start.toISODateString()
      ?? Date.firstDayOfMonth(year: request.year, month: request.month)
    let endDate =
      request.visibleRange?.end.toISODateString()
      ?? Date.lastDayOfMonth(year: request.year, month: request.month)

    // Process regular shifts
    for shift in request.shifts {
      let computed = computeShiftWithTax(
        shift: shift,
        allSnapshots: request.snapshots,
        context: context
      )
      result.append(computed)
    }

    // Recurring hours outside the visible dates still contribute to weekly overtime.
    let outputWindow =
      request.visibleRange.map {
        PayrollReadWindow(startDate: $0.start, endDate: $0.end)
      } ?? PayrollReadWindow.month(year: request.year, month: request.month)
    let overtimeWindow = outputWindow.expandedForOvertime
    let computationStartDate = overtimeWindow.startDate.toISODateString()
    let computationEndDate = overtimeWindow.endDate.toISODateString()
    let monthsToGenerate = getMonthsInRange(
      startDate: computationStartDate, endDate: computationEndDate)

    for recurringShift in request.recurring {
      for (genYear, genMonth) in monthsToGenerate {
        let virtualShifts = RecurringShiftGenerator.generateVirtualShiftsForMonth(
          year: genYear,
          month: genMonth,
          recurring: recurringShift
        )

        for virtual in virtualShifts {
          guard virtual.date >= computationStartDate, virtual.date <= computationEndDate else {
            continue
          }

          // Skip if we already added this virtual shift (from another month generation)
          let virtualId = "virtual-\(recurringShift.id)-\(virtual.date)"
          if result.contains(where: { $0.id == virtualId }) { continue }

          // Create virtual shift row
          let virtualRow = recurringShift.makeVirtualShift(
            date: virtual.date,
            weekday: virtual.weekday,
            id: virtualId
          )

          let computed = computeShiftWithTax(
            shift: virtualRow,
            allSnapshots: request.snapshots,
            context: context
          )
          result.append(computed)
        }
      }
    }

    // Conflict-excluded shifts are not paid, so their hours must not count toward overtime.
    // Decide exclusions in output order so later partitions keep the same shifts.
    let ordered = result.sorted(by: isInOutputOrder)
    let excludedIds = ConflictExclusion.buildExcludedShiftIds(shifts: ordered)
    let overtimeAdjusted =
      applyOvertime(
        to: ordered.filter { !excludedIds.contains($0.id) },
        allSnapshots: request.snapshots,
        context: context
      ) + ordered.filter { excludedIds.contains($0.id) }

    return
      overtimeAdjusted
      .filter { $0.shiftDate >= startDate && $0.shiftDate <= endDate }
      .sorted(by: isInOutputOrder)
  }

  private static func isInOutputOrder(
    _ lhs: ShiftWithComputations,
    _ rhs: ShiftWithComputations
  ) -> Bool {
    if lhs.shiftDate != rhs.shiftDate {
      return lhs.shiftDate < rhs.shiftDate
    }
    if lhs.startTime != rhs.startTime {
      return lhs.startTime < rhs.startTime
    }
    return lhs.id < rhs.id
  }

  /// Get all (year, month) pairs that fall within a date range
  private static func getMonthsInRange(startDate: String, endDate: String) -> [(Int, Int)] {
    let startComponents = startDate.split(separator: "-")
    let endComponents = endDate.split(separator: "-")

    guard startComponents.count >= 2, endComponents.count >= 2,
      let startYear = Int(startComponents[0]),
      let startMonth = Int(startComponents[1]),
      let endYear = Int(endComponents[0]),
      let endMonth = Int(endComponents[1])
    else {
      return []
    }

    var months: [(Int, Int)] = []
    var year = startYear
    var month = startMonth

    while year < endYear || (year == endYear && month <= endMonth) {
      months.append((year, month))
      month += 1
      if month > 12 {
        month = 1
        year += 1
      }
    }

    return months
  }

  /// Compute a single shift with correct tax settings based on payout date
  /// - Parameters:
  ///   - shift: The shift to compute
  ///   - allSnapshots: All wage snapshots for lookup
  ///   - payrollDay: User's payroll day
  /// - Returns: Shift with computations and correct tax settings
  private static func computeShiftWithTax(
    shift: ShiftRow,
    allSnapshots: [WageSnapshot],
    context: ComputationContext
  ) -> ShiftWithComputations {
    let effectiveJobId = shift.job_id ?? context.defaultJobId
    let payrollDay =
      effectiveJobId.flatMap { context.jobsById[$0]?.payroll_day } ?? context.fallbackPayrollDay

    let scopedSnapshots = snapshotsForJob(
      jobId: effectiveJobId,
      allSnapshots: allSnapshots,
      snapshotsByJobId: context.snapshotsByJobId,
      legacyNilJobSnapshots: context.legacyNilJobSnapshots,
      defaultJobId: context.defaultJobId
    )

    // 1. Calculate payout date for this specific shift
    let payoutDate = calculatePayoutDate(
      shiftDate: shift.shift_date,
      payrollDay: payrollDay
    )

    // 2. Look up wage/supplement snapshot for SHIFT date (determines wage rate & supplements)
    let wageSnapshot = SnapshotsService.snapshotForDate(shift.shift_date, from: scopedSnapshots)

    // 3. Look up tax snapshot for PAYOUT date (determines tax settings)
    let taxSnapshot = SnapshotsService.snapshotForDate(payoutDate, from: scopedSnapshots)

    // 4. Compute payroll with wage snapshot
    let computed = PayrollCalculator.computeShift(shift, snapshot: wageSnapshot)

    let job = effectiveJobId.flatMap { context.jobsById[$0] }
    let halfTaxMonth = job.map(\.half_tax_month) ?? context.fallbackHalfTaxMonth
    let month = payoutMonth(from: shift.shift_date)
    let taxSettings = PayoutTaxSettings(
      enabled: taxSnapshot?.effectiveTaxEnabled ?? false,
      percentage: taxSnapshot?.effectiveTaxPercentage ?? 0
    ).adjusted(payoutMonth: month, halfTaxMonth: halfTaxMonth)

    // 5. Return with tax settings from payout snapshot
    return ShiftWithComputations(
      shift: shift,
      computed: computed,
      taxEnabled: taxSnapshot?.effectiveTaxEnabled ?? false,
      taxPercentage: taxSnapshot?.effectiveTaxPercentage ?? 0,
      calculationContext: ShiftCalculationContext(
        wageSnapshotId: wageSnapshot?.id,
        taxSnapshotId: taxSnapshot?.id,
        scheduledPayoutDate: payoutDate,
        effectiveTaxPercentage: taxSettings.percentage,
        halfTaxApplied: taxSettings.enabled && halfTaxMonth == month
      )
    )
  }

  private struct OvertimeSegment {
    let shift: ShiftWithComputations
    let period: WagePeriod
    let absoluteStart: Date
    let absoluteEnd: Date
    let shiftDayStart: Date
    let jobId: String?
    let snapshot: WageSnapshot?
    let config: OvertimeConfig?
  }

  private struct OvertimePiece {
    let shiftId: String
    let start: Date
    let period: WagePeriod
    let overtimeMinutes: Double
  }

  private struct OvertimeGroupKey: Hashable {
    let jobId: String
    let weekStart: String
  }

  private static func applyOvertime(
    to shifts: [ShiftWithComputations],
    allSnapshots: [WageSnapshot],
    context: ComputationContext
  ) -> [ShiftWithComputations] {
    guard !shifts.isEmpty else { return shifts }

    var grouped: [OvertimeGroupKey: [OvertimeSegment]] = [:]
    var fallbackPiecesByShift: [String: [OvertimePiece]] = [:]

    for shift in shifts {
      let effectiveJobId = shift.shift.job_id ?? context.defaultJobId
      let scopedSnapshots = snapshotsForJob(
        jobId: effectiveJobId,
        allSnapshots: allSnapshots,
        snapshotsByJobId: context.snapshotsByJobId,
        legacyNilJobSnapshots: context.legacyNilJobSnapshots,
        defaultJobId: context.defaultJobId
      )
      let snapshot = SnapshotsService.snapshotForDate(shift.shiftDate, from: scopedSnapshots)
      let config = snapshot?.overtime.runtimeEnabledConfig

      guard let shiftDayStart = Date.fromISODateString(shift.shiftDate) else {
        continue
      }

      for period in shift.computed.wagePeriods {
        let absoluteStart = shiftDayStart.addingTimeInterval(period.fromMin * 60)
        let absoluteEnd = shiftDayStart.addingTimeInterval(period.toMin * 60)
        guard absoluteEnd > absoluteStart else { continue }

        for (partStart, partEnd) in splitByISOWeek(start: absoluteStart, end: absoluteEnd) {
          let key = OvertimeGroupKey(
            jobId: effectiveJobId ?? "__nil__",
            weekStart: isoWeekStart(for: partStart).toISODateString()
          )
          let partPeriod = WagePeriod(
            fromMin: minutesBetween(shiftDayStart, partStart),
            toMin: minutesBetween(shiftDayStart, partEnd),
            baseRate: period.baseRate,
            supplementRate: period.supplementRate
          )
          let segment = OvertimeSegment(
            shift: shift,
            period: partPeriod,
            absoluteStart: partStart,
            absoluteEnd: partEnd,
            shiftDayStart: shiftDayStart,
            jobId: effectiveJobId,
            snapshot: snapshot,
            config: config
          )
          grouped[key, default: []].append(segment)
          fallbackPiecesByShift[shift.id, default: []].append(
            OvertimePiece(
              shiftId: shift.id,
              start: partStart,
              period: partPeriod,
              overtimeMinutes: 0
            ))
        }
      }
    }

    var piecesByShift: [String: [OvertimePiece]] = [:]

    for key in grouped.keys {
      var cumulativeMinutes: Double = 0
      let segments = (grouped[key] ?? []).sorted {
        if $0.absoluteStart != $1.absoluteStart {
          return $0.absoluteStart < $1.absoluteStart
        }
        return $0.shift.id < $1.shift.id
      }

      for segment in segments {
        let result = applyOvertime(to: segment, cumulativeMinutes: cumulativeMinutes)
        cumulativeMinutes += segment.period.durationMinutes
        for piece in result {
          piecesByShift[piece.shiftId, default: []].append(piece)
        }
      }
    }

    return shifts.map { shift in
      let pieces = piecesByShift[shift.id] ?? fallbackPiecesByShift[shift.id] ?? []
      guard !pieces.isEmpty else { return shift }

      let sortedPieces = pieces.sorted {
        if $0.start != $1.start {
          return $0.start < $1.start
        }
        return $0.period.fromMin < $1.period.fromMin
      }
      let periods = mergeAdjacentPeriods(sortedPieces.map(\.period))
      let overtimeMinutes = sortedPieces.reduce(0.0) { $0 + $1.overtimeMinutes }
      var computed = PayrollCalculator.replacingWagePeriods(
        in: shift.computed,
        with: periods,
        overtimeMinutes: overtimeMinutes
      )
      if overtimeMinutes > 0 {
        computed.preOvertimeGross = shift.computed.gross
      }
      return ShiftWithComputations(
        shift: shift.shift,
        computed: computed,
        taxEnabled: shift.taxEnabled,
        taxPercentage: shift.taxPercentage,
        calculationContext: shift.calculationContext
      )
    }
  }

  private static func applyOvertime(
    to segment: OvertimeSegment,
    cumulativeMinutes: Double
  ) -> [OvertimePiece] {
    guard let config = segment.config else {
      return [
        OvertimePiece(
          shiftId: segment.shift.id,
          start: segment.absoluteStart,
          period: segment.period,
          overtimeMinutes: 0,
        )
      ]
    }

    let thresholdMinutes = config.weeklyThresholdHours * 60
    var cursor = segment.absoluteStart
    var cursorCumulative = cumulativeMinutes
    var pieces: [OvertimePiece] = []

    while cursor < segment.absoluteEnd {
      let next = nextOvertimeBoundary(
        after: cursor,
        segmentEnd: segment.absoluteEnd,
        config: config,
        cumulativeMinutes: cursorCumulative,
        thresholdMinutes: thresholdMinutes
      )
      let durationMinutes = max(0, next.timeIntervalSince(cursor) / 60)
      guard durationMinutes > 0 else { break }

      let isOvertime = cursorCumulative >= thresholdMinutes
      let supplementRate: Double
      let overtimeMinutes: Double
      if isOvertime,
        let percent = overtimePercent(config: config, at: cursor)
      {
        supplementRate = segment.period.baseRate * percent / 100
        overtimeMinutes = durationMinutes
      } else {
        supplementRate = segment.period.supplementRate
        overtimeMinutes = 0
      }

      pieces.append(
        OvertimePiece(
          shiftId: segment.shift.id,
          start: cursor,
          period: WagePeriod(
            fromMin: minutesBetween(segment.shiftDayStart, cursor),
            toMin: minutesBetween(segment.shiftDayStart, next),
            baseRate: segment.period.baseRate,
            supplementRate: supplementRate,
            isOvertime: overtimeMinutes > 0
          ),
          overtimeMinutes: overtimeMinutes
        ))

      cursorCumulative += durationMinutes
      cursor = next
    }

    return pieces
  }

  private static func nextOvertimeBoundary(
    after date: Date,
    segmentEnd: Date,
    config: OvertimeConfig,
    cumulativeMinutes: Double,
    thresholdMinutes: Double
  ) -> Date {
    var boundary = segmentEnd
    let dayStart = startOfDay(for: date)

    if let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart), nextDay > date {
      boundary = min(boundary, nextDay)
    }

    if cumulativeMinutes < thresholdMinutes {
      let minutesUntilThreshold = thresholdMinutes - cumulativeMinutes
      let thresholdDate = date.addingTimeInterval(minutesUntilThreshold * 60)
      if thresholdDate > date {
        boundary = min(boundary, thresholdDate)
      }
    }

    let minuteOfDay = minutesBetween(dayStart, date)
    for rule in config.rules where overtimeRuleCanMatch(rule, at: date) {
      guard let from = OvertimeConfig.timeToMinutes(rule.from),
        let to = OvertimeConfig.timeToMinutes(rule.to)
      else {
        continue
      }
      for value in [Double(from), Double(to)] where value > minuteOfDay {
        let candidate = dayStart.addingTimeInterval(value * 60)
        if candidate > date {
          boundary = min(boundary, candidate)
        }
      }
    }

    return boundary
  }

  private static func overtimePercent(config: OvertimeConfig, at date: Date) -> Double? {
    let minute = minutesBetween(startOfDay(for: date), date)
    return config.rules.compactMap { rule -> Double? in
      guard overtimeRuleCanMatch(rule, at: date),
        let from = OvertimeConfig.timeToMinutes(rule.from),
        let to = OvertimeConfig.timeToMinutes(rule.to),
        minute >= Double(from),
        minute < Double(to)
      else {
        return nil
      }
      return rule.percent
    }.max()
  }

  private static func overtimeRuleCanMatch(_ rule: OvertimeRule, at date: Date) -> Bool {
    let day = date.tidexWeekday
    guard rule.days.contains(day) else { return false }

    if NorwegianHolidays.isPublicHoliday(date) {
      return rule.appliesOnHolidays
    }

    let holidayOnly = rule.appliesOnHolidays && Set(rule.days) == Set(1...7)
    return !holidayOnly
  }

  private static func splitByISOWeek(start: Date, end: Date) -> [(Date, Date)] {
    var result: [(Date, Date)] = []
    var cursor = start

    while cursor < end {
      let weekStart = isoWeekStart(for: cursor)
      let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? end
      let partEnd = min(end, weekEnd)
      result.append((cursor, partEnd))
      cursor = partEnd
    }

    return result
  }

  private static func isoWeekStart(for date: Date) -> Date {
    isoCalendar.dateInterval(of: .weekOfYear, for: date)?.start ?? startOfDay(for: date)
  }

  private static func startOfDay(for date: Date) -> Date {
    calendar.startOfDay(for: date)
  }

  private static func minutesBetween(_ start: Date, _ end: Date) -> Double {
    end.timeIntervalSince(start) / 60
  }

  private static func mergeAdjacentPeriods(_ periods: [WagePeriod]) -> [WagePeriod] {
    var merged: [WagePeriod] = []

    for period in periods where period.toMin > period.fromMin {
      if let last = merged.last,
        abs(last.toMin - period.fromMin) < 0.0001,
        last.baseRate == period.baseRate,
        last.supplementRate == period.supplementRate,
        last.isOvertime == period.isOvertime
      {
        merged[merged.count - 1] = WagePeriod(
          fromMin: last.fromMin,
          toMin: period.toMin,
          baseRate: last.baseRate,
          supplementRate: last.supplementRate,
          isOvertime: last.isOvertime
        )
      } else {
        merged.append(period)
      }
    }

    return merged
  }

  private static let calendar: Calendar = {
    var value = Calendar(identifier: .gregorian)
    value.timeZone = Date.localTimeZone
    return value
  }()

  private static let isoCalendar: Calendar = {
    var value = Calendar(identifier: .iso8601)
    value.timeZone = Date.localTimeZone
    return value
  }()

  /// Resolve snapshot scope for a shift's job.
  /// During rollout, nil-job snapshots are treated as default-job snapshots only.
  private static func snapshotsForJob(
    jobId: String?,
    allSnapshots: [WageSnapshot],
    snapshotsByJobId: [String?: [WageSnapshot]],
    legacyNilJobSnapshots: [WageSnapshot],
    defaultJobId: String?
  ) -> [WageSnapshot] {
    guard let jobId else {
      return legacyNilJobSnapshots.isEmpty ? allSnapshots : legacyNilJobSnapshots
    }

    if let scoped = snapshotsByJobId[jobId], !scoped.isEmpty {
      return scoped
    }

    if let defaultJobId, let defaultScoped = snapshotsByJobId[defaultJobId], !defaultScoped.isEmpty
    {
      return defaultScoped
    }

    return legacyNilJobSnapshots.isEmpty ? allSnapshots : legacyNilJobSnapshots
  }

  // MARK: - Monthly Totals

  /// Summarize shift totals with half-tax support and conflict exclusion
  /// - Parameters:
  ///   - shifts: All computed shifts for the month
  ///   - excludedShiftIds: Optional precomputed excluded IDs from ConflictExclusion.analyze.
  ///     When nil, exclusions are computed automatically.
  ///   - halfTaxMonth: User's half-tax month setting (11=November, 12=December)
  ///   - earningsMonth: The month these shifts are worked in (1-12)
  ///   - now: Current date for determining completed shifts
  /// - Returns: Aggregated totals with half-tax applied
  static func summarizeShiftTotals(
    shifts: [ShiftWithComputations],
    excludedShiftIds: Set<String>? = nil,
    halfTaxMonth: Int?,
    earningsMonth: Int,
    now: Date = Date()
  ) -> ShiftTotals {
    // Payout month = earnings month + 1 (used for half-tax detection)
    let payoutMonth = earningsMonth >= 12 ? 1 : earningsMonth + 1

    // Automatically compute excluded shifts (higher-earning conflicting shifts)
    let excludedIds = excludedShiftIds ?? ConflictExclusion.buildExcludedShiftIds(shifts: shifts)

    // Filter out excluded shifts for totals calculation
    let includedShifts =
      excludedIds.isEmpty
      ? shifts
      : shifts.filter { !excludedIds.contains($0.id) }

    // Calculate gross totals
    let gross = includedShifts.reduce(0) { $0 + $1.grossPay }
    let supplement = includedShifts.reduce(0) { $0 + $1.computed.supplementPay }

    // Calculate completed shifts
    let completedShifts = includedShifts.filter { shift in
      Date.hasShiftEnded(
        shiftDate: shift.shiftDate,
        startTime: shift.startTime,
        endTime: shift.endTime,
        referenceDate: now
      )
    }
    let completedGross = completedShifts.reduce(0) { $0 + $1.grossPay }

    // Calculate net with half-tax support
    let net = calculateNetTotal(
      shifts: includedShifts,
      payoutMonth: payoutMonth,
      halfTaxMonth: halfTaxMonth
    )
    let completedNet = calculateNetTotal(
      shifts: completedShifts,
      payoutMonth: payoutMonth,
      halfTaxMonth: halfTaxMonth
    )

    return ShiftTotals(
      gross: gross,
      net: net,
      supplement: supplement,
      completedGross: completedGross,
      completedNet: completedNet
    )
  }

  /// Calculate net total with half-tax support
  private static func calculateNetTotal(
    shifts: [ShiftWithComputations],
    payoutMonth: Int,
    halfTaxMonth: Int?
  ) -> Double {
    return shifts.reduce(0) { total, shift in
      total
        + calculateShiftNet(
          shift: shift,
          payoutMonth: payoutMonth,
          halfTaxMonth: halfTaxMonth
        )
    }
  }

  /// Calculate net for a single shift with half-tax support
  /// - Parameters:
  ///   - shift: The shift to calculate net for
  ///   - payoutMonth: The payout month (1-12)
  ///   - halfTaxMonth: User's half-tax month setting
  /// - Returns: Net pay after tax
  private static func calculateShiftNet(
    shift: ShiftWithComputations,
    payoutMonth: Int,
    halfTaxMonth: Int?
  ) -> Double {
    if shift.calculationContext != nil {
      return shift.netPay
    }
    let gross = shift.grossPay

    guard shift.taxEnabled else {
      return gross
    }

    var effectiveTaxRate = min(max(shift.taxPercentage, 0), 100)

    // Apply half-tax if payout month matches the configured half tax month
    if let halfTax = halfTaxMonth, payoutMonth == halfTax {
      effectiveTaxRate /= 2
    }

    let netMultiplier = 1 - effectiveTaxRate / 100
    return gross * netMultiplier
  }
}
