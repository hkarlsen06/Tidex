import AppIntents
import Combine
import Foundation
import Observation
import SwiftUI
import os.log

extension AddShiftViewModel {

  // MARK: - Month Navigation

  /// Navigate to the previous month
  /// Delegates to SharedMonthContext - data reload happens via subscription
  func goToPreviousMonth() {
    monthContext.goToPreviousMonth()
  }

  /// Navigate to the next month
  /// Delegates to SharedMonthContext - data reload happens via subscription
  func goToNextMonth() {
    monthContext.goToNextMonth()
  }

  /// Reset to current month
  /// Delegates to SharedMonthContext - data reload happens via subscription
  func goToCurrentMonth() {
    monthContext.goToCurrentMonth()
  }

  // MARK: - Computed Properties

  /// Whether the single shift form can be submitted
  var canSubmitSingle: Bool {
    !selectedDates.isEmpty
      && hasValidTimes
      && !activeJobs.isEmpty
      && effectiveSelectedJobId != nil
  }

  /// Whether the recurring shift form can be submitted
  var canSubmitRecurring: Bool {
    !selectedDays.isEmpty
      && hasValidTimes
      && !activeJobs.isEmpty
      && effectiveSelectedJobId != nil
  }

  var canSubmitEvent: Bool {
    hasEventNote
      && (isEventAllDay ? isEventDateRangeValid : hasValidEventTimes)
      && hasValidEventReminderConfiguration
  }

  var eventCalendarSelectedDates: Set<String> {
    if isEventAllDay {
      return contiguousDateSelection(from: eventStartDate, to: eventEndDate)
    }
    return [eventDate.toISODateString()]
  }

  /// Selected job object for display and contextual calculations.
  var selectedJob: Job? {
    guard let jobId = effectiveSelectedJobId else {
      return nil
    }
    return activeJobs.first(where: { $0.id == jobId })
  }

  var jobCreationInitialCurrency: String {
    activeJobs.first(where: \.is_default)?.currency ?? cachedSettings?.currency ?? currency
  }

  var jobCreationInitialPayrollDay: Int {
    activeJobs.first(where: \.is_default)?.payroll_day ?? cachedSettings?.effectivePayrollDay ?? 15
  }

  /// User must explicitly pick a job when multiple active jobs exist.
  var requiresExplicitJobSelection: Bool {
    activeJobs.count > 1
  }

  /// When explicit selection isn't required, use the only available job automatically.
  var effectiveSelectedJobId: String? {
    if requiresExplicitJobSelection {
      return selectedJobId
    }
    return selectedJobId ?? activeJobs.first?.id
  }

  var submissionJobs: [Job] {
    activeJobs
  }

  func selectJobForShiftCreation(_ jobId: String) {
    guard configuredJobIds.contains(jobId) else {
      requestPaySetup(for: jobId, action: .selectJob)
      return
    }

    selectedJobId = jobId
    showSubmitJobChooser = false
  }

  func requestPaySetup(for jobId: String, action: AddShiftPaySetupRequest.Action) {
    guard let job = activeJobs.first(where: { $0.id == jobId }) else {
      return
    }
    showSubmitJobChooser = false
    paySetupRequest = AddShiftPaySetupRequest(job: job, action: action)
  }

  func isJobConfigured(_ jobId: String) -> Bool {
    configuredJobIds.contains(jobId)
  }

  func createConfiguredJob(input: AddJobSetupInput) async -> Bool {
    guard let userId = AppCoordinator.shared.getCurrentUserId() else {
      error = String(localized: .settingsPayErrorNotAuthenticated)
      return false
    }

    do {
      let createdJob: Job
      if let existingJobSetup = input.existingJobSetup {
        guard
          try await jobsRepository.updateJob(
            userId: userId,
            jobId: existingJobSetup.id,
            name: input.name,
            color: input.color
          ) != nil
        else {
          throw JobsRepositoryError.jobNotFound
        }

        createdJob = try await jobsRepository.completePaySetup(
          userId: userId,
          jobId: existingJobSetup.id,
          currency: input.currency,
          payrollDay: input.payrollDay,
          halfTaxMonth: input.halfTaxMonth,
          monthlyGoal: activeJobs.first(where: { $0.id == existingJobSetup.id })?.monthly_goal,
          baselineSnapshot: input.baselineSnapshot
        )
      } else {
        createdJob = try await jobsRepository.createJobWithBaselineSnapshot(
          userId: userId,
          name: input.name,
          color: input.color,
          currency: input.currency,
          payrollDay: input.payrollDay,
          halfTaxMonth: input.halfTaxMonth,
          monthlyGoal: nil,
          baselineSnapshot: input.baselineSnapshot
        )
      }

      selectedJobId = createdJob.id
      await refreshData()
      Haptics.play(.success)
      return true
    } catch {
      addShiftViewModelLogger.error("Failed to create configured job from Add Shift: \(error.localizedDescription)")
      self.error = ErrorTranslations.translate(error)
      return false
    }
  }

  func createBasicJobForSetup(input: AddJobBasicsInput) async -> Job? {
    guard let userId = AppCoordinator.shared.getCurrentUserId() else {
      error = String(localized: .settingsPayErrorNotAuthenticated)
      return nil
    }

    do {
      let createdJob = try await jobsRepository.createJob(
        userId: userId,
        name: input.name,
        color: input.color,
        currency: input.currency,
        payrollDay: input.payrollDay,
        halfTaxMonth: input.halfTaxMonth,
        monthlyGoal: nil
      )
      selectedJobId = createdJob.id
      await refreshData()
      return createdJob
    } catch {
      addShiftViewModelLogger.error("Failed to create basic job from Add Shift: \(error.localizedDescription)")
      self.error = ErrorTranslations.translate(error)
      return nil
    }
  }

  func completePaySetup(for job: Job, input: JobPaySetupInput) async -> Bool {
    guard let userId = AppCoordinator.shared.getCurrentUserId() else {
      error = String(localized: .settingsPayErrorNotAuthenticated)
      return false
    }

    let action = paySetupRequest?.action ?? .selectJob

    do {
      let configuredJob = try await jobsRepository.completePaySetup(
        userId: userId,
        jobId: job.id,
        currency: input.currency,
        payrollDay: input.payrollDay,
        halfTaxMonth: input.halfTaxMonth,
        monthlyGoal: job.monthly_goal,
        baselineSnapshot: input.baselineSnapshot
      )
      await refreshData()
      paySetupRequest = nil

      switch action {
      case .selectJob:
        selectedJobId = configuredJob.id

      case .submitSingle:
        selectedJobId = configuredJob.id
        Task { await submitSingleShifts() }

      case .showRecurringPreview:
        selectedJobId = configuredJob.id
        showPreview()

      case .submitRecurring:
        selectedJobId = configuredJob.id
        Task { await submitRecurringShift() }
      }

      Haptics.play(.success)
      return true
    } catch {
      addShiftViewModelLogger.error("Failed to complete Add Shift pay setup: \(error.localizedDescription)")
      self.error = ErrorTranslations.translate(error)
      return false
    }
  }

  func dismissJobSelection() {
    showSubmitJobChooser = false
  }

  func presentJobSelection() {
    guard !activeJobs.isEmpty else {
      return
    }
    showSubmitJobChooser = true
  }

  /// Whether both start and end times have been entered
  var hasValidTimes: Bool {
    startTime != nil && endTime != nil
  }

  private var hasValidEventTimes: Bool {
    guard startTime != nil, endTime != nil else {
      return false
    }
    return endTimeString > startTimeString
  }

  /// Both event times are set, but the end isn't after the start. Timed events can't run
  /// past midnight, so the form explains why it can't be saved.
  var eventTimesCrossMidnight: Bool {
    startTime != nil && endTime != nil && !hasValidEventTimes
  }

  private var hasEventNote: Bool {
    !eventNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private var isEventDateRangeValid: Bool {
    eventEndDate >= eventStartDate
  }

  private var hasValidEventReminderConfiguration: Bool {
    guard isEventAllDay, !eventReminderTimes.isEmpty else {
      return true
    }
    return eventReminderAnchorTime != nil
  }

  var submitBlockers: [AddShiftSubmitBlocker] {
    var blockers: [AddShiftSubmitBlocker] = []

    switch mode {
    case .single:
      if activeJobs.isEmpty {
        blockers.append(.noAvailableJob)
      } else if effectiveSelectedJobId == nil {
        blockers.append(.noSelectedJob)
      }
      if selectedDates.isEmpty {
        blockers.append(.noSingleDates)
      }
      if !hasValidTimes {
        blockers.append(.missingTimes)
      }

    case .recurring:
      if activeJobs.isEmpty {
        blockers.append(.noAvailableJob)
      } else if effectiveSelectedJobId == nil {
        blockers.append(.noSelectedJob)
      }
      if selectedDays.isEmpty {
        blockers.append(.noRecurringDays)
      }
      if !hasValidTimes {
        blockers.append(.missingTimes)
      }

    case .events:
      if isEventAllDay {
        if !isEventDateRangeValid {
          blockers.append(.invalidEventDateRange)
        }
      } else {
        if eventTimesCrossMidnight {
          blockers.append(.eventCrossesMidnight)
        } else if !hasValidEventTimes {
          blockers.append(.missingTimes)
        }
      }

      if !hasEventNote {
        blockers.append(.missingEventNote)
      }
    }

    return blockers
  }

  /// Whether the form has any content that can be cleared
  /// Used to conditionally show the undo/clear button
  var hasContent: Bool {
    switch mode {
    case .single:
      return !selectedDates.isEmpty || startTime != nil || endTime != nil

    case .recurring:
      return !selectedDays.isEmpty || startTime != nil || endTime != nil

    case .events:
      return !eventNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || startTime != nil || endTime != nil
        || eventDate != Calendar.gregorianCurrent.startOfDay(for: Date())
        || eventStartDate != Calendar.gregorianCurrent.startOfDay(for: Date())
        || eventEndDate != Calendar.gregorianCurrent.startOfDay(for: Date())
        || isEventAllDay
        || !eventReminderTimes.isEmpty
        || eventReminderAnchorTime != nil
    }
  }

  /// Show hint until user has created at least 3 distinct start/end combinations.
  var shouldShowSingleTimeScopeHint: Bool {
    distinctShiftTimePairCount < 3
  }

  /// Start time as HH:mm string
  var startTimeString: String {
    guard let time = startTime else {
      return ""
    }
    return formatTimeAsHHmm(time)
  }

  /// End time as HH:mm string
  /// Returns "24:00" when end is midnight and start is not (end-of-day convention)
  var endTimeString: String {
    guard let time = endTime else {
      return ""
    }
    guard let start = startTime else {
      return formatTimeAsHHmm(time)
    }
    return ShiftSchedule.storedEndTime(formatTimeAsHHmm(time), start: formatTimeAsHHmm(start))
  }

  var eventReminderAnchorTimeString: String? {
    guard let eventReminderAnchorTime else {
      return nil
    }
    return formatTimeAsHHmm(eventReminderAnchorTime)
  }

  /// Set of dates that have existing shifts - uses cached data for performance
  var existingShiftDates: Set<String> {
    cachedDisplayData?.existingShiftDates ?? Set<String>()
  }

  /// Computed earnings for existing shifts by date - uses cached data for performance
  var existingShiftEarnings: [String: CalendarEarningsData] {
    cachedDisplayData?.existingShiftEarnings ?? [:]
  }

  /// Start/end hours for existing shifts by date - uses cached data for performance
  var existingShiftHours: [String: HoursData] {
    cachedDisplayData?.existingShiftHours ?? [:]
  }

  /// Start/end hours for currently entered times (used for add-calendar previews)
  var enteredHours: HoursData? {
    guard hasValidTimes else {
      return nil
    }

    let start = CalendarGridHelper.formatTime(startTimeString)
    let end = CalendarGridHelper.formatTime(endTimeString)
    let crossesMidnight =
      CalendarGridHelper.timeToMinutes(endTimeString)
      <= CalendarGridHelper.timeToMinutes(startTimeString)

    return HoursData(
      start: start,
      end: end,
      crossesMidnight: crossesMidnight
    )
  }

  /// Set of dates that would conflict with the current time selection - uses cached data
  var conflictDates: Set<String> {
    cachedConflictDatesForCalendar
  }

  /// Projected dates for the recurring pattern - uses cached data
  var projectedRecurringDates: [String] {
    cachedProjectedRecurringDates
  }

  /// Number of conflicts in the current selection
  var conflictCount: Int {
    cachedConflictDatesForCalendar.count
  }

  /// Preview earnings for selected dates (single mode) - uses cached data
  var previewEarnings: [String: CalendarEarningsData] {
    cachedPreviewEarnings
  }

  // MARK: - Toolbar Monthly Total

  /// Combined monthly total (existing shifts + preview earnings) for toolbar display.
  /// Uses `ConflictExclusion.combinedEarnings` so the "lowest gross wins" rule
  /// is applied consistently with the rest of the app.
  var toolbarTotals: CalendarHeaderTotals? {
    if mode == .events {
      return nil
    }

    let existingEarnings = cachedDisplayData?.existingShiftEarnings ?? [:]

    // Build preview earnings map for the current mode
    let previewByDate: [String: CalendarEarningsData] = {
      switch mode {
      case .single:
        return cachedPreviewEarnings

      case .recurring:
        var map: [String: CalendarEarningsData] = [:]
        for dateISO in cachedProjectedRecurringDates {
          let weekday = RecurringAnchorSelection.weekdayKey(for: dateISO)
          if let earnings = cachedAnchorEarnings[weekday] {
            map[dateISO] = earnings
          }
        }
        return map

      case .events:
        return [:]
      }
    }()

    let totals = ConflictExclusion.combinedEarnings(
      existingByDate: existingEarnings,
      previewByDate: previewByDate,
      conflictDates: cachedConflictDatesForCalendar
    )

    let baselineTotals = ConflictExclusion.combinedEarnings(
      existingByDate: existingEarnings,
      previewByDate: [:],
      conflictDates: []
    )

    let primaryAmount = totals.hasTaxEnabled ? totals.net : totals.gross
    let baselinePrimary = baselineTotals.hasTaxEnabled ? baselineTotals.net : baselineTotals.gross
    let secondaryAmount: Double? = {
      guard !previewByDate.isEmpty else {
        return nil
      }
      let delta = max(primaryAmount - baselinePrimary, 0)
      return delta > 0 ? delta : nil
    }()

    return CalendarHeaderTotals(
      primary: primaryAmount,
      secondary: secondaryAmount,
      primaryIsAfterTax: totals.hasTaxEnabled
    )
  }

  /// Get earnings for a recurring date by looking up its anchor's earnings
  /// All dates on the same weekday share the same earnings
  func earningsForRecurringDate(_ dateISO: String) -> CalendarEarningsData? {
    let weekday = RecurringAnchorSelection.weekdayKey(for: dateISO)
    return cachedAnchorEarnings[weekday]
  }
}
