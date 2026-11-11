import AppIntents
import Combine
import Foundation
import Observation
import SwiftUI
import os.log

extension AddShiftViewModel {

  // MARK: - Private Helpers

  func reconcileSelectedJob() {
    guard !activeJobs.isEmpty else {
      selectedJobId = nil
      return
    }

    if let selectedJobId, activeJobs.contains(where: { $0.id == selectedJobId }) {
      return
    }

    selectedJobId =
      activeJobs.first(where: \.is_default)?.id
      ?? activeJobs.first?.id
  }

  func jobRequiringPaySetupForCurrentSelection() -> Job? {
    guard let jobId = effectiveSelectedJobId else {
      return nil
    }
    guard !configuredJobIds.contains(jobId) else {
      return nil
    }
    return activeJobs.first { $0.id == jobId }
  }

  private func snapshotsForJob(_ jobId: String?) -> [WageSnapshot] {
    guard let jobId else {
      return cachedSnapshots
    }

    let jobSnapshots = cachedSnapshots.filter { $0.job_id == jobId }
    if !jobSnapshots.isEmpty {
      return jobSnapshots
    }

    // Rollout fallback for legacy local rows that may not yet have job_id populated.
    // Nil job rows are treated as default-job rows only.
    // swiftlint:disable:next explicit_type_interface
    let defaultJobId = activeJobs.first(where: \.is_default)?.id
    if defaultJobId == jobId {
      return cachedSnapshots.filter { $0.job_id == nil }
    }

    return []
  }

  func snapshotForDate(_ dateISO: String, jobId: String?) -> WageSnapshot? {
    SnapshotsService.snapshotForDate(dateISO, from: snapshotsForJob(jobId))
  }

  private func payoutSchedule(for jobId: String?) -> PayoutSchedule {
    PayoutSchedule(
      job: jobId.flatMap { id in activeJobs.first { $0.id == id } },
      fallbackPayrollDay: cachedSettings?.effectivePayrollDay ?? 1
    )
  }

  /// Format Date to HH:mm string
  func formatTimeAsHHmm(_ date: Date) -> String {
    date.toHourMinuteString()
  }

  /// Compute earnings for a single date (net + gross)
  /// Uses wage snapshot from shift date, tax snapshot from payout date (shift month + 1)
  func computeEarningsForDate(_ dateISO: String) -> CalendarEarningsData? {
    // Multi-job users must choose a workplace before previews become job-scoped.
    // Until then, cells keep the checkmark-only selected style.
    if requiresExplicitJobSelection, selectedJobId == nil {
      return nil
    }

    let jobId = effectiveSelectedJobId
    guard let jobId, configuredJobIds.contains(jobId) else {
      return nil
    }

    // Wage/supplements from shift date
    let wageSnapshot = snapshotForDate(dateISO, jobId: jobId)

    // Tax settings from the payout date of the job's pay period
    let payoutDate = payoutSchedule(for: jobId).payoutDate(for: dateISO)
    let taxSnapshot = snapshotForDate(payoutDate, jobId: jobId)

    let shift = ShiftRow(
      id: "preview-\(dateISO)",
      user_id: nil,
      job_id: jobId,
      shift_date: dateISO,
      start_time: startTimeString,
      end_time: endTimeString,
      custom_supplements: nil
    )

    let computed = PayrollCalculator.computeShift(shift, snapshot: wageSnapshot)
    let gross = computed.gross
    let taxEnabled = taxSnapshot?.effectiveTaxEnabled ?? false
    let net = computed.netPay(
      taxEnabled: taxSnapshot?.effectiveTaxEnabled ?? false,
      taxPercentage: taxSnapshot?.effectiveTaxPercentage ?? 0
    )
    return CalendarEarningsData(net: net, gross: gross, hasTaxEnabled: taxEnabled)
  }

  nonisolated static func computeCalendarDisplayDataOffMain(
    _ input: CalendarDisplayComputationInput
  ) async -> CalendarDisplayData {
    await Task.detached(priority: .userInitiated) {
      Self.buildCalendarDisplayData(input)
    }.value
  }

  nonisolated static func makeImmediateCalendarDisplayData(
    _ input: CalendarDisplayComputationInput
  ) -> CalendarDisplayData {
    var existingDates = Set<String>()
    var shiftTimesByDate: [String: [(start: String, end: String)]] = [:]

    for shift in input.shifts {
      existingDates.insert(shift.shift_date)
      shiftTimesByDate[shift.shift_date, default: []].append(
        (start: shift.start_time, end: shift.end_time)
      )
    }

    for recurring in input.recurringShifts {
      let virtualShifts = RecurringShiftGenerator.generateVirtualShiftsForMonth(
        year: input.year,
        month: input.month,
        recurring: recurring
      )

      for virtualShift in virtualShifts {
        existingDates.insert(virtualShift.date)
        shiftTimesByDate[virtualShift.date, default: []].append(
          (start: recurring.cleanStartTime, end: recurring.cleanEndTime)
        )
      }
    }

    return CalendarDisplayData(
      existingShiftDates: existingDates,
      existingShiftEarnings: [:],
      existingShiftHours: buildExistingShiftHours(from: shiftTimesByDate),
      virtualShifts: [],
      year: input.year,
      month: input.month,
      timestamp: Date()
    )
  }

  private struct CalendarDisplayAccumulator {
    var existingDates = Set<String>()
    var netEarnings: [String: Double] = [:]
    var grossEarnings: [String: Double] = [:]
    var hasTax: [String: Bool] = [:]
    var shiftTimesByDate: [String: [(start: String, end: String)]] = [:]
    var virtualShiftsWithEarnings: [CalendarDisplayData.VirtualShiftWithEarnings] = []
  }

  private nonisolated static func buildCalendarDisplayData(
    _ input: CalendarDisplayComputationInput
  ) -> CalendarDisplayData {
    var accumulator = CalendarDisplayAccumulator()
    accumulateExistingShifts(input, into: &accumulator)
    accumulateVirtualShifts(input, into: &accumulator)

    var existingEarnings: [String: CalendarEarningsData] = [:]
    for (date, net) in accumulator.netEarnings {
      existingEarnings[date] = CalendarEarningsData(
        net: net,
        gross: accumulator.grossEarnings[date] ?? net,
        hasTaxEnabled: accumulator.hasTax[date] ?? false
      )
    }

    let existingHours = buildExistingShiftHours(from: accumulator.shiftTimesByDate)

    return CalendarDisplayData(
      existingShiftDates: accumulator.existingDates,
      existingShiftEarnings: existingEarnings,
      existingShiftHours: existingHours,
      virtualShifts: accumulator.virtualShiftsWithEarnings,
      year: input.year,
      month: input.month,
      timestamp: Date()
    )
  }

  private nonisolated static func accumulateExistingShifts(
    _ input: CalendarDisplayComputationInput,
    into accumulator: inout CalendarDisplayAccumulator
  ) {
    for shift in input.shifts {
      accumulator.existingDates.insert(shift.shift_date)

      let wageSnapshot = Self.snapshotForDate(
        shift.shift_date,
        jobId: shift.job_id,
        snapshots: input.snapshots,
        jobs: input.jobs
      )
      let computed = PayrollCalculator.computeShift(shift, snapshot: wageSnapshot)

      let payoutDate = Self.payoutSchedule(
        for: shift.job_id, jobs: input.jobs, settings: input.settings
      ).payoutDate(for: shift.shift_date)
      let taxSnapshot = Self.snapshotForDate(
        payoutDate,
        jobId: shift.job_id,
        snapshots: input.snapshots,
        jobs: input.jobs
      )

      let taxEnabled = taxSnapshot?.effectiveTaxEnabled ?? false
      accumulator.netEarnings[shift.shift_date, default: 0] += computed.netPay(
        taxEnabled: taxEnabled,
        taxPercentage: taxSnapshot?.effectiveTaxPercentage ?? 0
      )
      accumulator.grossEarnings[shift.shift_date, default: 0] += computed.gross
      accumulator.hasTax[shift.shift_date, default: false] =
        accumulator.hasTax[shift.shift_date, default: false] || taxEnabled
      accumulator.shiftTimesByDate[shift.shift_date, default: []].append(
        (start: shift.start_time, end: shift.end_time)
      )
    }
  }

  private nonisolated static func accumulateVirtualShifts(
    _ input: CalendarDisplayComputationInput,
    into accumulator: inout CalendarDisplayAccumulator
  ) {
    for recurring in input.recurringShifts {
      let virtualShifts = RecurringShiftGenerator.generateVirtualShiftsForMonth(
        year: input.year,
        month: input.month,
        recurring: recurring
      )

      for virtualShift in virtualShifts {
        accumulator.existingDates.insert(virtualShift.date)

        let shift = recurring.makeVirtualShift(
          date: virtualShift.date,
          weekday: virtualShift.weekday,
          id: "virtual-\(virtualShift.date)",
          userId: nil
        )

        let earnings = Self.virtualShiftEarnings(
          shift, on: virtualShift.date, recurring: recurring, input: input)

        accumulator.virtualShiftsWithEarnings.append(
          CalendarDisplayData.VirtualShiftWithEarnings(date: virtualShift.date, earnings: earnings)
        )

        accumulator.netEarnings[virtualShift.date, default: 0] += earnings.net
        accumulator.grossEarnings[virtualShift.date, default: 0] += earnings.gross
        accumulator.hasTax[virtualShift.date, default: false] =
          accumulator.hasTax[virtualShift.date, default: false] || earnings.hasTaxEnabled
        accumulator.shiftTimesByDate[virtualShift.date, default: []].append(
          (start: recurring.cleanStartTime, end: recurring.cleanEndTime)
        )
      }
    }
  }

  private nonisolated static func virtualShiftEarnings(
    _ shift: ShiftRow,
    on date: String,
    recurring: RecurringShiftRow,
    input: CalendarDisplayComputationInput
  ) -> CalendarEarningsData {
    let wageSnapshot = Self.snapshotForDate(
      date,
      jobId: recurring.job_id,
      snapshots: input.snapshots,
      jobs: input.jobs
    )
    let computed = PayrollCalculator.computeShift(shift, snapshot: wageSnapshot)

    let payoutDate = Self.payoutSchedule(
      for: recurring.job_id,
      jobs: input.jobs,
      settings: input.settings
    ).payoutDate(for: date)
    let taxSnapshot = Self.snapshotForDate(
      payoutDate,
      jobId: recurring.job_id,
      snapshots: input.snapshots,
      jobs: input.jobs
    )

    let taxEnabled = taxSnapshot?.effectiveTaxEnabled ?? false
    let netEarnings = computed.netPay(
      taxEnabled: taxEnabled,
      taxPercentage: taxSnapshot?.effectiveTaxPercentage ?? 0
    )
    return CalendarEarningsData(
      net: netEarnings,
      gross: computed.gross,
      hasTaxEnabled: taxEnabled
    )
  }

  private nonisolated static func buildExistingShiftHours(
    from shiftTimesByDate: [String: [(start: String, end: String)]]
  ) -> [String: HoursData] {
    shiftTimesByDate.compactMapValues(HoursData.init(spanning:))
  }

  nonisolated static func computeConflictsAndPreviewsOffMain(
    _ input: ConflictsAndPreviewsComputationInput
  ) async -> ConflictsAndPreviewsComputationResult {
    await Task.detached(priority: .userInitiated) {
      Self.buildConflictsAndPreviews(input)
    }.value
  }

  private struct RecurringProjection {
    let projectedRecurringDates: [String]?
    let anchorEarnings: [String: CalendarEarningsData]?
    let datesToCheck: [String]
  }

  /// Earnings for each selected weekday anchor, or nil when the times are not valid yet.
  nonisolated static func anchorEarnings(
    for input: ConflictsAndPreviewsComputationInput,
    earningsContext: EarningsComputationContext
  ) -> [String: CalendarEarningsData]? {
    guard input.hasValidTimes else { return nil }

    var computedByAnchor: [String: CalendarEarningsData] = [:]
    for (weekday, anchorISO) in input.selectedDays {
      if let earnings = Self.computeEarningsForDate(
        anchorISO,
        startTime: input.startTime,
        endTime: input.endTime,
        context: earningsContext
      ) {
        computedByAnchor[weekday] = earnings
      }
    }
    return computedByAnchor
  }

  private nonisolated static func recurringProjection(
    for input: ConflictsAndPreviewsComputationInput,
    earningsContext: EarningsComputationContext
  ) -> RecurringProjection {
    let projectedRecurringDates: [String]?
    let anchorEarnings: [String: CalendarEarningsData]?
    let datesToCheck: [String]

    switch input.mode {
    case .single:
      projectedRecurringDates = nil
      anchorEarnings = nil
      datesToCheck = input.selectedDates

    case .recurring:
      if !input.selectedDays.isEmpty {
        let generated = RecurringShiftProjector.generateDatesForCalendarDisplay(
          selectedDays: input.selectedDays,
          repeatInterval: input.repeatInterval,
          displayMonth: input.displayMonth,
          endCondition: input.endCondition
        )
        projectedRecurringDates = generated
        datesToCheck = generated

        anchorEarnings = Self.anchorEarnings(for: input, earningsContext: earningsContext)
      } else {
        projectedRecurringDates = []
        anchorEarnings = [:]
        datesToCheck = []
      }

    case .events:
      projectedRecurringDates = nil
      anchorEarnings = nil
      datesToCheck = []
    }

    return RecurringProjection(
      projectedRecurringDates: projectedRecurringDates,
      anchorEarnings: anchorEarnings,
      datesToCheck: datesToCheck
    )
  }

  private nonisolated static func singleModePreviewEarnings(
    for input: ConflictsAndPreviewsComputationInput,
    earningsContext: EarningsComputationContext
  ) -> [String: CalendarEarningsData] {
    var previewEarnings: [String: CalendarEarningsData] = [:]
    if input.mode == .single {
      for dateISO in input.selectedDates {
        if let earnings = Self.computeEarningsForDate(
          dateISO,
          startTime: input.startTime,
          endTime: input.endTime,
          context: earningsContext
        ) {
          previewEarnings[dateISO] = earnings
        }
      }
    }
    return previewEarnings
  }

  private nonisolated static func buildConflictsAndPreviews(
    _ input: ConflictsAndPreviewsComputationInput
  ) -> ConflictsAndPreviewsComputationResult {
    let earningsContext = EarningsComputationContext(
      requiresExplicitJobSelection: input.requiresExplicitJobSelection,
      selectedJobId: input.selectedJobId,
      effectiveJobId: input.effectiveJobId,
      snapshots: input.snapshots,
      jobs: input.jobs,
      configuredJobIds: input.configuredJobIds,
      settings: input.settings
    )

    let projection = Self.recurringProjection(for: input, earningsContext: earningsContext)
    let projectedRecurringDates = projection.projectedRecurringDates
    let anchorEarnings = projection.anchorEarnings
    let datesToCheck = projection.datesToCheck

    guard input.hasValidTimes, !datesToCheck.isEmpty else {
      return ConflictsAndPreviewsComputationResult(
        projectedRecurringDates: projectedRecurringDates,
        anchorEarnings: anchorEarnings,
        conflictDates: [],
        previewEarnings: [:]
      )
    }

    let conflicts = ShiftConflictDetector.detectConflicts(
      dates: datesToCheck,
      startTime: input.startTime,
      endTime: input.endTime,
      existingShifts: input.existingShifts,
      existingRecurringShifts: input.existingRecurringShifts
    )

    let previewEarnings = Self.singleModePreviewEarnings(
      for: input, earningsContext: earningsContext)

    return ConflictsAndPreviewsComputationResult(
      projectedRecurringDates: projectedRecurringDates,
      anchorEarnings: anchorEarnings,
      conflictDates: conflicts,
      previewEarnings: previewEarnings
    )
  }

  /// The job to preview earnings for, or nil when no configured job is selected.
  private nonisolated static func previewableJobId(in context: EarningsComputationContext)
    -> String?
  {
    if context.requiresExplicitJobSelection, context.selectedJobId == nil {
      return nil
    }
    guard let effectiveJobId = context.effectiveJobId,
      context.configuredJobIds.contains(effectiveJobId)
    else {
      return nil
    }
    return effectiveJobId
  }

  nonisolated static func computeEarningsForDate(
    _ dateISO: String,
    startTime: String,
    endTime: String,
    context: EarningsComputationContext
  ) -> CalendarEarningsData? {
    guard let effectiveJobId = Self.previewableJobId(in: context) else {
      return nil
    }

    let wageSnapshot = Self.snapshotForDate(
      dateISO,
      jobId: effectiveJobId,
      snapshots: context.snapshots,
      jobs: context.jobs
    )

    let payoutDate = Self.payoutSchedule(
      for: effectiveJobId,
      jobs: context.jobs,
      settings: context.settings
    ).payoutDate(for: dateISO)
    let taxSnapshot = Self.snapshotForDate(
      payoutDate,
      jobId: effectiveJobId,
      snapshots: context.snapshots,
      jobs: context.jobs
    )

    let shift = ShiftRow(
      id: "preview-\(dateISO)",
      user_id: nil,
      job_id: effectiveJobId,
      shift_date: dateISO,
      start_time: startTime,
      end_time: endTime,
      custom_supplements: nil
    )

    let computed = PayrollCalculator.computeShift(shift, snapshot: wageSnapshot)
    let job = context.jobs.first { $0.id == effectiveJobId }
    let taxSettings = PayoutTaxSettings(
      enabled: taxSnapshot?.effectiveTaxEnabled ?? false,
      percentage: taxSnapshot?.effectiveTaxPercentage ?? 0
    ).adjusted(
      payoutMonth: PayPeriodCalendar.components(payoutDate)?.month ?? 1,
      halfTaxMonth: job.map(\.half_tax_month) ?? context.settings?.half_tax_month)

    return CalendarEarningsData(
      net: taxSettings.netAmount(from: computed.gross), gross: computed.gross,
      hasTaxEnabled: taxSettings.enabled)
  }

  private nonisolated static func snapshotsForJob(
    _ jobId: String?,
    snapshots: [WageSnapshot],
    jobs: [Job]
  ) -> [WageSnapshot] {
    guard let jobId else {
      return snapshots
    }

    let jobSnapshots = snapshots.filter { $0.job_id == jobId }
    if !jobSnapshots.isEmpty {
      return jobSnapshots
    }

    // swiftlint:disable:next explicit_type_interface
    let defaultJobId = jobs.first(where: \.is_default)?.id
    if defaultJobId == jobId {
      return snapshots.filter { $0.job_id == nil }
    }

    return []
  }

  nonisolated static func snapshotForDate(
    _ dateISO: String,
    jobId: String?,
    snapshots: [WageSnapshot],
    jobs: [Job]
  ) -> WageSnapshot? {
    SnapshotsService.snapshotForDate(
      dateISO,
      from: snapshotsForJob(jobId, snapshots: snapshots, jobs: jobs)
    )
  }

  private nonisolated static func payoutSchedule(
    for jobId: String?,
    jobs: [Job],
    settings: UserSettings?
  ) -> PayoutSchedule {
    PayoutSchedule(
      job: jobId.flatMap { id in jobs.first { $0.id == id } },
      fallbackPayrollDay: settings?.effectivePayrollDay ?? 1
    )
  }

  /// Virtual shift with computed earnings
  struct VirtualShiftWithEarnings {
    let date: String
    let earnings: CalendarEarningsData
  }

  /// Generate virtual shift dates from recurring patterns for display
  private func generateVirtualShiftDatesForDisplay() -> Set<String> {
    Set(generateVirtualShiftsForDisplay().map(\.date))
  }

  /// Generate virtual shifts with computed earnings from recurring patterns (net after tax)
  /// Uses wage snapshot from shift date, tax snapshot from payout date (shift month + 1)
  private func generateVirtualShiftsForDisplay() -> [VirtualShiftWithEarnings] {
    var results: [VirtualShiftWithEarnings] = []

    // Only generate for the currently displayed month
    let year = displayYear
    let month = displayMonthNumber

    for recurring in cachedRecurringShifts {
      let virtualShifts = RecurringShiftGenerator.generateVirtualShiftsForMonth(
        year: year,
        month: month,
        recurring: recurring
      )

      for virtualShift in virtualShifts {
        // Create a temporary shift to compute earnings
        let shift = recurring.makeVirtualShift(
          date: virtualShift.date,
          weekday: virtualShift.weekday,
          id: "virtual-\(virtualShift.date)",
          userId: nil
        )

        // Wage/supplements from shift date
        let wageSnapshot = snapshotForDate(virtualShift.date, jobId: recurring.job_id)
        let computed = PayrollCalculator.computeShift(shift, snapshot: wageSnapshot)

        // Tax settings from the payout date of the job's pay period
        let payoutDate = payoutSchedule(for: recurring.job_id).payoutDate(for: virtualShift.date)
        let taxSnapshot = snapshotForDate(payoutDate, jobId: recurring.job_id)

        let taxEnabled = taxSnapshot?.effectiveTaxEnabled ?? false
        let net = computed.netPay(
          taxEnabled: taxEnabled,
          taxPercentage: taxSnapshot?.effectiveTaxPercentage ?? 0
        )

        results.append(
          VirtualShiftWithEarnings(
            date: virtualShift.date,
            earnings: CalendarEarningsData(
              net: net,
              gross: computed.gross,
              hasTaxEnabled: taxEnabled
            )
          ))
      }
    }

    return results
  }

  /// Clear the form after successful submission
  func clearForm() {
    // Clear the saved draft since submission was successful
    clearDraft()

    // Clear date selections
    selectedDates.removeAll()
    selectedDays.removeAll()

    // Clear cached computation data
    cachedPreviewEarnings.removeAll()
    cachedConflictDatesForCalendar.removeAll()
    cachedProjectedRecurringDates.removeAll()
    cachedAnchorEarnings.removeAll()

    // Cancel any pending preview update before clearing times
    previewUpdateTask?.cancel()
    previewUpdateTask = nil

    // Clear times so user can start fresh
    startTime = nil
    endTime = nil

    // Reset recurring options to defaults (biweekly, indefinite)
    repeatInterval = 1
    endCondition = nil

    // Reset event-specific fields.
    eventNote = ""
    isEventAllDay = false
    let defaultEventDate = Self.defaultEventDate()
    eventDate = defaultEventDate
    eventStartDate = defaultEventDate
    eventEndDate = defaultEventDate
    eventReminderTimes = []
    eventReminderAnchorTime = nil
    eventRangeAnchorDate = defaultEventDate

    // NOTE: Do NOT reset the month context here!
    // The user should stay on the month where they just added shifts
    // so that when they're navigated to the Shifts tab, they see their new shifts.

    // Clear error state
    error = nil
  }

  /// Default start time (09:00)
  private static func defaultStartTime() -> Date {
    let calendar = Calendar.gregorianCurrent
    var components = calendar.dateComponents([.year, .month, .day], from: Date())
    components.hour = Self.defaultStartHour
    components.minute = 0
    return calendar.date(from: components) ?? Date()
  }

  /// Default end time (17:00)
  private static func defaultEndTime() -> Date {
    let calendar = Calendar.gregorianCurrent
    var components = calendar.dateComponents([.year, .month, .day], from: Date())
    components.hour = Self.defaultEndHour
    components.minute = 0
    return calendar.date(from: components) ?? Date()
  }

  static func defaultEventDate() -> Date {
    Calendar.gregorianCurrent.startOfDay(for: Date())
  }

  static func defaultEventReminderAnchorTime() -> Date {
    let calendar = Calendar.gregorianCurrent
    let baseDate = Date()
    return calendar.date(
      bySettingHour: Self.defaultStartHour,
      minute: 0,
      second: 0,
      of: baseDate
    ) ?? baseDate
  }
}
