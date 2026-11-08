import AppIntents
import Combine
import Foundation
import Observation
import SwiftUI
import os.log

extension AddShiftViewModel {

  // MARK: - Data Loading

  /// Load initial data from repositories
  func loadData() async {
    if hasLoadedInitialData {
      await refreshData()
      applyPreselectedDate()
      applyPendingDeepLinkMode()
      return
    }

    guard let userId = AppCoordinator.shared.getCurrentUserId() else {
      addShiftViewModelLogger.warning("Cannot load data: no user ID")
      return
    }

    paymentDataOwnerId = userId

    // Load any saved draft first (before other data to set mode correctly)
    loadDraft()

    // Load settings
    cachedSettings = settingsRepository.getSettings(for: userId)
    currency = cachedSettings?.currency ?? "kr"

    // Load active jobs before snapshots/preview computations.
    activeJobs = jobsRepository.getActiveJobs(for: userId)
    configuredJobIds = jobPaySetupStatusService.configuredJobIds(for: userId)
    reconcileSelectedJob()

    // Load snapshots
    cachedSnapshots = snapshotsRepository.getSnapshots(for: userId)

    // Load existing shifts for displayed month (for conflict detection)
    reloadShiftsForDisplayedMonth()
    refreshDistinctShiftTimePairCount(for: userId)

    // Load recurring shifts
    cachedRecurringShifts = recurringRepository.getRecurringShifts(for: userId)

    // Build cached display data for the current month
    scheduleCalendarDisplayRebuild()
    scheduleConflictsAndPreviewsRecompute()

    // Check for pre-selected date from SharedMonthContext (e.g., tapping empty day in Shifts tab)
    applyPreselectedDate()
    hasLoadedInitialData = true
    applyPendingDeepLinkMode()

    publishStateToCoordinator()

    let shiftCount = cachedShifts.count
    let recurringCount = cachedRecurringShifts.count
    let snapshotCount = cachedSnapshots.count
    let jobCount = activeJobs.count
    addShiftViewModelLogger.info(
      "Loaded data: \(shiftCount) shifts, \(recurringCount) recurring, \(snapshotCount) snapshots, \(jobCount) jobs"
    )
  }

  /// Refresh cached repository data while preserving current in-progress form state.
  func refreshData() async {  // swiftlint:disable:this async_without_await
    guard let userId = AppCoordinator.shared.getCurrentUserId() else {
      addShiftViewModelLogger.warning("Cannot refresh data: no user ID")
      return
    }

    // Reload cache sources without touching draft-driven UI state.
    cachedSettings = settingsRepository.getSettings(for: userId)
    currency = cachedSettings?.currency ?? "kr"
    activeJobs = jobsRepository.getActiveJobs(for: userId)
    configuredJobIds = jobPaySetupStatusService.configuredJobIds(for: userId)
    reconcileSelectedJob()
    cachedSnapshots = snapshotsRepository.getSnapshots(for: userId)
    cachedRecurringShifts = recurringRepository.getRecurringShifts(for: userId)
    reloadShiftsForDisplayedMonth()
    refreshDistinctShiftTimePairCount(for: userId)

    publishStateToCoordinator()

    let shifts = cachedShifts.count
    let recurring = cachedRecurringShifts.count
    let snapshots = cachedSnapshots.count
    let jobs = activeJobs.count
    addShiftViewModelLogger.info(
      "Refreshed add tab data: \(shifts) shifts, \(recurring) recurring, \(snapshots) snapshots, \(jobs) jobs"
    )
  }

  /// Check and apply any pre-selected date from SharedMonthContext
  /// Called from onAppear when tab becomes visible
  func checkPreselectedDate() {
    // On first add-tab load, loadData() must restore the draft before consuming the
    // preselected date. Otherwise the restored draft can overwrite the tapped date.
    guard hasLoadedInitialData else {
      return
    }
    applyPreselectedDate()
  }

  /// Apply a mode requested by external navigation.
  /// If initial load is still restoring a draft, defer until loadData() completes so
  /// draft restoration cannot overwrite the requested mode.
  func applyDeepLinkMode(_ mode: AddShiftMode) {
    pendingDeepLinkMode = mode
    applyPendingDeepLinkMode()
  }

  private func applyPendingDeepLinkMode() {
    guard hasLoadedInitialData, let pendingDeepLinkMode else {
      return
    }
    self.pendingDeepLinkMode = nil
    mode = pendingDeepLinkMode
  }

  /// Apply and consume the pre-selected date from SharedMonthContext
  /// Called when the user taps an empty day in the Shifts calendar
  private func applyPreselectedDate() {
    guard let dateISO = monthContext.preselectedDate else {
      return
    }

    // Consume the pre-selected date (one-time use)
    monthContext.preselectedDate = nil

    // Ensure we're in single mode for date selection
    mode = .single

    // External navigation to Add should focus the tapped date, not merge it into any
    // previous manual selection left in the form.
    cachedPreviewEarnings.removeAll()
    cachedConflictDatesForCalendar.removeAll()
    selectedDates = [dateISO]
    scheduleConflictsAndPreviewsRecompute()

    // Navigate to the month containing the pre-selected date
    if let date = Date.fromISODateString(dateISO) {
      let calendar = Calendar.gregorianCurrent
      let components = calendar.dateComponents([.year, .month], from: date)
      if let year = components.year, let month = components.month {
        monthContext.navigateTo(year: year, month: month)
      }
    }

    addShiftViewModelLogger.info("Applied pre-selected date: \(dateISO)")
  }

  /// Reload shifts for the currently displayed month
  /// Call this when navigating to a new month
  func reloadShiftsForDisplayedMonth() {
    guard let userId = AppCoordinator.shared.getCurrentUserId() else {
      return
    }

    let calendar = Calendar.gregorianCurrent
    let components = calendar.dateComponents([.year, .month], from: displayMonth)
    guard let year = components.year, let month = components.month else {
      return
    }

    let startDate = Date.firstDayOfMonthDate(year: year, month: month)
    let endDate = Date.lastDayOfMonthDate(year: year, month: month)

    cachedShifts = shiftsRepository.getShifts(for: userId, startDate: startDate, endDate: endDate)

    let displayInput = CalendarDisplayComputationInput(
      year: year,
      month: month,
      shifts: cachedShifts,
      recurringShifts: cachedRecurringShifts,
      snapshots: cachedSnapshots,
      jobs: activeJobs,
      settings: cachedSettings
    )
    cachedDisplayData = Self.makeImmediateCalendarDisplayData(displayInput)

    // Rebuild full display data and previews asynchronously to avoid blocking UI
    scheduleCalendarDisplayRebuild()
    scheduleConflictsAndPreviewsRecompute()
  }

  /// Refresh number of distinct start/end pairs used in historical shifts.
  func refreshDistinctShiftTimePairCount(for userId: String) {
    let allShifts = shiftsRepository.getAllShifts(for: userId)
    let distinctPairs = Set(
      allShifts.compactMap { shift -> String? in
        let start = shift.start_time.trimmingCharacters(in: .whitespacesAndNewlines)
        let end = shift.end_time.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !start.isEmpty, !end.isEmpty else {
          return nil
        }
        return "\(start)|\(end)"
      })
    distinctShiftTimePairCount = distinctPairs.count
  }
}
