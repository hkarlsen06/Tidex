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
      let shiftMonth = Int(components[1])
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
    let effectivePayrollDay = min(payrollDay, daysInPayoutMonth)

    return String(format: "%04d-%02d-%02d", payoutYear, payoutMonth, effectivePayrollDay)
  }

  /// Extract payout month (1-12) from a shift date
  /// Payout month = earnings month + 1
  static func payoutMonth(from shiftDate: String) -> Int {
    let components = shiftDate.split(separator: "-")
    guard components.count >= 2,
      let shiftMonth = Int(components[1])
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
      jobsById: Dictionary(uniqueKeysWithValues: request.jobs.map { ($0.id, $0) }),
      defaultJobId: request.jobs.first(where: { $0.is_default })?.id,
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

    // Generate and process virtual shifts from recurring patterns
    // Need to generate for all months that might have visible dates
    let monthsToGenerate = getMonthsInRange(startDate: startDate, endDate: endDate)

    for recurringShift in request.recurring {
      for (genYear, genMonth) in monthsToGenerate {
        let virtualShifts = RecurringShiftGenerator.generateVirtualShiftsForMonth(
          year: genYear,
          month: genMonth,
          recurring: recurringShift
        )

        for virtual in virtualShifts {
          // Filter to visible date range
          guard virtual.date >= startDate && virtual.date <= endDate else { continue }

          // Skip if we already added this virtual shift (from another month generation)
          let virtualId = "virtual-\(recurringShift.id)-\(virtual.date)"
          if result.contains(where: { $0.id == virtualId }) { continue }

          // Create virtual shift row
          let virtualRow = ShiftRow(
            id: virtualId,
            user_id: recurringShift.user_id,
            job_id: recurringShift.job_id,
            shift_date: virtual.date,
            start_time: recurringShift.cleanStartTime,
            end_time: recurringShift.cleanEndTime,
            custom_pause_windows: recurringShift.date_specific_pause_windows?[virtual.date],
            custom_supplements: recurringShift.date_specific_supplements?[virtual.date],
            created_at: nil,
            recurring_id: recurringShift.id,
            recurring_anchor_weekday: virtual.weekday
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

    // Sort by date
    return result.sorted { $0.shiftDate < $1.shiftDate }
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

    // 5. Return with tax settings from payout snapshot
    return ShiftWithComputations(
      shift: shift,
      computed: computed,
      taxEnabled: taxSnapshot?.effectiveTaxEnabled ?? false,
      taxPercentage: taxSnapshot?.effectiveTaxPercentage ?? 0
    )
  }

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
    let gross = shift.grossPay

    guard shift.taxEnabled else {
      return gross
    }

    var effectiveTaxRate = shift.taxPercentage

    // Apply half-tax if payout month matches the configured half tax month
    if let halfTax = halfTaxMonth, payoutMonth == halfTax {
      effectiveTaxRate /= 2
    }

    let netMultiplier = 1 - effectiveTaxRate / 100
    return gross * netMultiplier
  }
}
