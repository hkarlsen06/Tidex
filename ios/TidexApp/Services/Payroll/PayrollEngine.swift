import Foundation

/// Maps app models to the shared payroll engine and summarizes monthly totals.
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

  /// The shared Foundation-only core owns pay math for the app and extensions.
  static func computeShiftsForMonth(_ request: MonthComputationRequest) -> [ShiftWithComputations] {
    let ownerId = request.settings?.user_id ?? ""
    let payload = SharingRPCPayloadInput(
      ownerId: ownerId, showEarnings: true,
      settings: SharingRPCUserSettings(
        userId: ownerId, monthlyGoal: nil, monthlyGoalsByMonth: nil, defaultShiftsView: nil,
        profilePictureUrl: nil, payrollDay: request.settings?.payroll_day, theme: nil,
        calendarAnimationStyle: nil, halfTaxMonth: request.settings?.half_tax_month, currency: nil),
      shifts: request.shifts.map(sharingShift),
      recurringShifts: request.recurring.map(sharingRecurring),
      snapshots: request.snapshots.map(sharingSnapshot), jobs: request.jobs.map(sharingJob))
    let computed = SharingComputeCore.computeShiftsInRange(
      payload: payload,
      startDate: request.visibleRange?.start.toISODateString()
        ?? SharingComputeCore.monthStart(year: request.year, month: request.month),
      endDate: request.visibleRange?.end.toISODateString()
        ?? SharingComputeCore.monthEnd(year: request.year, month: request.month),
      mode: .visible)
    let originals = Dictionary(request.shifts.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
    let recurringById = Dictionary(
      request.recurring.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
    return computed.map { value in
      let row = originals[value.id]
        ?? value.recurringId.flatMap { recurringById[$0] }?.makeVirtualShift(
          date: value.shiftDate, weekday: value.recurringAnchorWeekday ?? 0, id: value.id)
        ?? ShiftRow(
          id: value.id, user_id: value.userId, job_id: value.jobId,
          shift_date: value.shiftDate, start_time: value.startTime, end_time: value.endTime,
          custom_pause_windows: value.customPauseWindows, custom_supplements: nil)
      return ShiftWithComputations(
        shift: row, computed: appComputed(value.computed, id: value.id),
        taxEnabled: value.taxEnabled,
        taxPercentage: value.calculationContext?.savedTaxPercentage ?? value.taxPercentage,
        calculationContext: value.calculationContext.map {
          ShiftCalculationContext(
            wageSnapshotId: $0.wageSnapshotId, taxSnapshotId: $0.taxSnapshotId,
            scheduledPayoutDate: $0.scheduledPayoutDate, effectiveTaxPercentage: value.taxPercentage,
            halfTaxApplied: $0.halfTaxApplied)
        })
    }
  }

  static func sharingShift(_ shift: ShiftRow) -> SharingRPCShiftRow {
    SharingRPCShiftRow(
      id: shift.id, userId: shift.user_id ?? "", jobId: shift.job_id,
      shiftDate: shift.shift_date, startTime: shift.start_time, endTime: shift.end_time,
      customPauseWindows: shift.custom_pause_windows,
      customSupplements: shift.custom_supplements.map(sharingCustomSupplements),
      recurringId: shift.recurring_id, recurringAnchorWeekday: shift.recurring_anchor_weekday)
  }

  private static func sharingCustomSupplements(_ custom: CustomSupplementsData)
    -> SharingRPCCustomSupplements
  {
    SharingRPCCustomSupplements(rules: custom.rules.map {
      SharingRPCCustomSupplementRule(
        stackingGroup: $0.stackingGroup, dates: $0.dates, excludedDates: $0.excludedDates,
        shiftStartDates: $0.shiftStartDates, excludedShiftStartDates: $0.excludedShiftStartDates,
        shiftStartBefore: $0.shiftStartBefore, minimumRate: $0.minimumRate,
        percentageBaseRate: $0.percentageBaseRate,
        from: $0.from, to: $0.to, rate: $0.rate, percent: $0.percent, isCustom: $0.isCustom)
    })
  }

  static func sharingRule(_ rule: SupplementRule) -> SharingRPCSupplementRule {
    SharingRPCSupplementRule(
      stackingGroup: rule.stackingGroup, dates: rule.dates, excludedDates: rule.excludedDates,
      shiftStartDates: rule.shiftStartDates, excludedShiftStartDates: rule.excludedShiftStartDates,
      shiftStartBefore: rule.shiftStartBefore, minimumRate: rule.minimumRate,
      percentageBaseRate: rule.percentageBaseRate,
      days: rule.days, from: rule.from, to: rule.to, rate: rule.rate, percent: rule.percent)
  }

  static func sharingOvertime(_ config: OvertimeConfig) -> SharingRPCOvertimeConfig {
    SharingRPCOvertimeConfig(
      enabled: config.enabled, weeklyThresholdHours: config.weeklyThresholdHours,
      rules: config.rules.map {
        SharingRPCOvertimeRule(
          days: $0.days, appliesOnHolidays: $0.appliesOnHolidays, from: $0.from, to: $0.to,
          percent: $0.percent, dates: $0.dates, excludedDates: $0.excludedDates)
      }, retainSupplements: config.retainSupplements, premiumBaseMultiplier: config.premiumBaseMultiplier,
      baseRate: config.baseRate, retainedSupplements: config.retainedSupplements?.map(sharingRule))
  }

  static func sharingSnapshot(_ snapshot: WageSnapshot) -> SharingRPCWageSnapshot {
    SharingRPCWageSnapshot(
      id: snapshot.id, userId: snapshot.user_id, jobId: snapshot.job_id,
      fromDate: snapshot.from_date, hourlyWage: snapshot.hourly_wage,
      wageLevel: snapshot.wage_level, tariffTypeId: snapshot.tariff_type_id,
      supplements: SharingRPCSupplementRulesSnapshot(rules: snapshot.supplements.rules.map(sharingRule)),
      overtime: sharingOvertime(snapshot.overtime),
      taxEnabled: snapshot.tax_enabled, taxPercentage: snapshot.tax_percentage,
      breakEnabled: snapshot.break_enabled, breakMethod: snapshot.break_method,
      breakThresholdHours: snapshot.break_threshold_hours,
      breakDeductionMinutes: snapshot.break_deduction_minutes)
  }

  private static func sharingJob(_ job: Job) -> SharingRPCJobRow {
    SharingRPCJobRow(
      id: job.id, userId: job.user_id, name: job.name, color: job.color,
      currency: job.currency, isDefault: job.is_default, sortOrder: job.sort_order,
      payrollDay: job.payroll_day, payPeriod: job.pay_period, halfTaxMonth: job.half_tax_month,
      monthlyGoal: job.monthly_goal.map(Double.init), archivedAt: job.archived_at,
      deletedAt: job.deleted_at, createdAt: job.created_at, updatedAt: job.updated_at)
  }

  static func sharingRecurring(_ recurring: RecurringShiftRow) -> SharingRPCRecurringShiftRow {
    SharingRPCRecurringShiftRow(
      id: recurring.id, userId: recurring.user_id, jobId: recurring.job_id,
      startTime: recurring.start_time, endTime: recurring.end_time,
      repeatIntervalWeeks: recurring.repeat_interval_weeks, selectedDays: recurring.selected_days,
      endCondition: recurring.end_condition.map {
        switch $0 {
        case .months(let value): .months(value: value)
        case .years(let value): .years(value: value)
        case .endDate(let date): .endDate(date: date)
        }
      }, exclusions: recurring.exclusions,
      dateSpecificPauseWindows: recurring.date_specific_pause_windows,
      dateSpecificSupplements: recurring.date_specific_supplements?.mapValues(sharingCustomSupplements))
  }

  static func appComputed(_ computed: SharingComputedShiftComputed, id: String) -> ShiftComputed {
    ShiftComputed(
      id: id, durationHours: computed.durationHours, paidHours: computed.paidHours,
      basePay: computed.basePay, supplementPay: computed.supplementPay, gross: computed.gross,
      wagePeriods: computed.wagePeriods, originalWagePeriods: computed.originalWagePeriods,
      breakAudit: computed.breakAudit, overtimeApplied: computed.overtimeApplied,
      overtimeMinutes: computed.overtimeMinutes, preOvertimeGross: computed.preOvertimeGross)
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
