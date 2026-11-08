import AppIntents
import Combine
import Foundation
import Observation
import SwiftUI
import os.log

extension AddShiftViewModel {

  // MARK: - Performance Optimization Methods

  /// Schedule a debounced preview update after time input changes
  /// Uses adaptive delays: instant feedback when form is complete, debounced during typing
  func schedulePreviewUpdate() {
    // Cancel any pending update
    previewUpdateTask?.cancel()

    // Use shorter delay when both times are set (user editing complete form = instant feedback)
    // Use longer delay when partially filled (user actively typing = debounce to reduce thrashing)
    let delay = hasValidTimes ? Self.completedFormDelay : Self.activeTypingDelay

    // Schedule new update with adaptive delay
    previewUpdateTask = Task { [weak self] in
      do {
        try await Task.sleep(for: .nanoseconds(Int64(delay)))

        // Check if cancelled during sleep
        guard !Task.isCancelled else {
          return
        }

        self?.scheduleConflictsAndPreviewsRecompute()
      } catch {
        // Task was cancelled - this is expected
      }
    }
  }

  func scheduleCalendarDisplayRebuild() {
    displayComputationVersion &+= 1
    let computationVersion = displayComputationVersion
    let input = CalendarDisplayComputationInput(
      year: displayYear,
      month: displayMonthNumber,
      shifts: cachedShifts,
      recurringShifts: cachedRecurringShifts,
      snapshots: cachedSnapshots,
      jobs: activeJobs,
      settings: cachedSettings
    )

    Task { [weak self] in
      guard let self else {
        return
      }
      let displayData = await Self.computeCalendarDisplayDataOffMain(input)
      guard !Task.isCancelled else {
        return
      }
      guard displayComputationVersion == computationVersion else {
        return
      }

      cachedDisplayData = displayData
      addShiftViewModelLogger.info(
        """
        Rebuilt calendar display data: \(displayData.existingShiftDates.count) dates, \
        \(displayData.virtualShifts.count) virtual shifts
        """
      )
    }
  }

  func scheduleConflictsAndPreviewsRecompute() {
    previewComputationVersion &+= 1
    let computationVersion = previewComputationVersion

    Task { [weak self] in
      await self?.computeConflictsAndPreviews(computationVersion: computationVersion)
    }
  }

  /// Update conflicts and preview earnings (called after time changes or initial load)
  private func updateConflictsAndPreviews() {
    scheduleConflictsAndPreviewsRecompute()
  }

  private func computeConflictsAndPreviews(computationVersion: UInt64) async {
    let input = ConflictsAndPreviewsComputationInput(
      mode: mode,
      selectedDates: Array(selectedDates),
      selectedDays: selectedDays,
      repeatInterval: repeatInterval,
      displayMonth: displayMonth,
      endCondition: endCondition,
      hasValidTimes: hasValidTimes,
      startTime: startTimeString,
      endTime: endTimeString,
      requiresExplicitJobSelection: requiresExplicitJobSelection,
      selectedJobId: selectedJobId,
      effectiveJobId: effectiveSelectedJobId,
      existingShifts: cachedShifts,
      existingRecurringShifts: cachedRecurringShifts,
      snapshots: cachedSnapshots,
      jobs: activeJobs,
      configuredJobIds: configuredJobIds,
      settings: cachedSettings
    )

    let result = await Self.computeConflictsAndPreviewsOffMain(input)
    guard !Task.isCancelled else {
      return
    }
    guard previewComputationVersion == computationVersion else {
      return
    }

    if let projectedDates = result.projectedRecurringDates {
      cachedProjectedRecurringDates = projectedDates
    }
    if let anchorEarnings = result.anchorEarnings {
      cachedAnchorEarnings = anchorEarnings
    }
    cachedConflictDatesForCalendar = result.conflictDates
    cachedPreviewEarnings = result.previewEarnings
  }

  /// Incrementally update preview earnings when a single date is added
  func updatePreviewEarningsIncrementally(addedDate: String) {
    guard hasValidTimes else {
      return
    }

    if let earnings = computeEarningsForDate(addedDate) {
      cachedPreviewEarnings[addedDate] = earnings
    }
  }

  /// Incrementally update conflicts when a date is added
  func updateConflictsIncrementally(addedDate: String) {
    guard hasValidTimes else {
      return
    }

    // Check if the added date conflicts with existing shifts
    let conflicts = ShiftConflictDetector.detectConflicts(
      dates: [addedDate],
      startTime: startTimeString,
      endTime: endTimeString,
      existingShifts: cachedShifts,
      existingRecurringShifts: cachedRecurringShifts
    )

    // Add any conflicts found
    cachedConflictDatesForCalendar.formUnion(conflicts)
  }

  /// Incrementally update conflicts when a date is removed
  func updateConflictsIncrementally(removedDate: String) {
    // Simply remove the date from conflicts (it can't conflict if it's not selected)
    cachedConflictDatesForCalendar.remove(removedDate)
  }

  /// Update projected recurring dates when recurring settings change
  func updateProjectedRecurringDates() {
    guard !selectedDays.isEmpty else {
      cachedProjectedRecurringDates = []
      cachedAnchorEarnings = [:]
      return
    }

    // Only generate dates for calendar display (current month)
    cachedProjectedRecurringDates = RecurringShiftProjector.generateDatesForCalendarDisplay(
      selectedDays: selectedDays,
      repeatInterval: repeatInterval,
      displayMonth: displayMonth,
      endCondition: endCondition
    )

    // Compute earnings once per anchor
    if hasValidTimes {
      var anchorEarnings: [String: CalendarEarningsData] = [:]
      for (weekday, anchorISO) in selectedDays {
        if let earnings = computeEarningsForDate(anchorISO) {
          anchorEarnings[weekday] = earnings
        }
      }
      cachedAnchorEarnings = anchorEarnings

      // Update conflicts for the projected dates
      cachedConflictDatesForCalendar = ShiftConflictDetector.detectConflicts(
        dates: cachedProjectedRecurringDates,
        startTime: startTimeString,
        endTime: endTimeString,
        existingShifts: cachedShifts,
        existingRecurringShifts: cachedRecurringShifts
      )
    }
  }
}
