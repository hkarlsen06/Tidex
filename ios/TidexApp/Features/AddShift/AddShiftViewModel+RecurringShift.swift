import AppIntents
import Combine
import Foundation
import Observation
import SwiftUI
import os.log

extension AddShiftViewModel {

  // MARK: - Recurring Shift Actions

  /// Toggle anchor date for a weekday
  func toggleAnchorDate(_ dateISO: String) {
    let weekday = RecurringAnchorSelection.weekdayKey(for: dateISO)
    let updatedSelectedDays = RecurringAnchorSelection.toggledSelectedDays(
      selectedDays,
      dateISO: dateISO,
      requiresAtLeastOneAnchor: false
    )

    if selectedDays[weekday] == dateISO, updatedSelectedDays[weekday] == nil {
      cachedAnchorEarnings.removeValue(forKey: weekday)
    }
    selectedDays = updatedSelectedDays

    // Update projected dates for the new anchor configuration
    updateProjectedRecurringDates()

    // Haptic feedback
    let generator = UIImpactFeedbackGenerator(style: .light)
    generator.impactOccurred()
  }

  /// Remove anchor for a specific weekday
  func removeAnchor(weekday: String) {
    selectedDays.removeValue(forKey: weekday)
    cachedAnchorEarnings.removeValue(forKey: weekday)

    // Update projected dates
    updateProjectedRecurringDates()

    // Haptic feedback
    let generator = UIImpactFeedbackGenerator(style: .light)
    generator.impactOccurred()
  }

  /// Clear all anchors
  func clearAnchors() {
    selectedDays.removeAll()
    cachedAnchorEarnings.removeAll()
    cachedProjectedRecurringDates.removeAll()
    cachedConflictDatesForCalendar.removeAll()
  }

  /// Show the preview sheet - computes projected dates once
  func showPreview() {
    guard canSubmitRecurring else {
      return
    }

    if let job = jobRequiringPaySetupForCurrentSelection() {
      paySetupRequest = AddShiftPaySetupRequest(job: job, action: .showRecurringPreview)
      return
    }

    // Compute projected dates once when showing preview
    cachedProjectedDates = RecurringShiftProjector.generateDates(
      selectedDays: selectedDays,
      repeatInterval: repeatInterval,
      endCondition: endCondition
    )

    // Compute conflicts once
    cachedConflictDates = ShiftConflictDetector.detectConflicts(
      dates: cachedProjectedDates,
      startTime: startTimeString,
      endTime: endTimeString,
      existingShifts: cachedShifts,
      existingRecurringShifts: cachedRecurringShifts
    )

    showPreviewSheet = true
  }

  /// Submit recurring shift
  func submitRecurringShift() async {
    guard canSubmitRecurring, !isLoading else {
      return
    }

    if let job = jobRequiringPaySetupForCurrentSelection() {
      paySetupRequest = AddShiftPaySetupRequest(job: job, action: .submitRecurring)
      return
    }

    guard let userId = resolveSubmitUserId() else {
      return
    }

    isLoading = true
    error = nil
    let isFirstShift = CelebrationManager.shared.isFirstShiftSave(for: userId)

    do {
      // Use cached conflicts from preview
      let conflicts = cachedConflictDates

      _ = try await recurringRepository.createRecurringShift(
        userId: userId,
        jobId: effectiveSelectedJobId,
        startTime: startTimeString,
        endTime: endTimeString,
        repeatIntervalWeeks: repeatInterval,
        selectedDays: selectedDays,
        endCondition: endCondition,
        exclusions: Array(conflicts),
        dateSpecificSupplements: nil
      )

      finishRecurringSubmission(conflicts: conflicts, userId: userId, isFirstShift: isFirstShift)
    } catch {
      addShiftViewModelLogger.error("Failed to create recurring shift: \(error.localizedDescription)")
      self.error = ErrorTranslations.translate(error)
      Haptics.play(.error)
    }

    isLoading = false
  }

  private func finishRecurringSubmission(
    conflicts: Set<String>, userId: String, isFirstShift: Bool
  ) {
    addShiftViewModelLogger.info(
      "Created recurring shift with \(self.cachedProjectedDates.count) projected dates, \(conflicts.count) exclusions"
    )

    // Get non-excluded dates for celebration (the ones actually created)
    let createdDates = Set(cachedProjectedDates).subtracting(conflicts)

    // Highlight the created dates in the Shifts tab
    CelebrationManager.shared.celebrate(dates: createdDates)
    if isFirstShift {
      CelebrationManager.shared.celebrateFirstShift()
    }

    refreshDistinctShiftTimePairCount(for: userId)

    // Clear form
    clearForm()

    // Dismiss preview sheet
    showPreviewSheet = false

    // Success haptic
    Haptics.playShiftCreationSuccess()
    AccessibilityNotification.Announcement(String(localized: .shiftsAccessibilitySaved)).post()

    // Notify that shifts changed (for dashboard refresh)
    NotificationCenter.default.postShiftsDidChange(context: .fullReload)

    // Notify completion
    onShiftsCreated?(.recurring)
    requestShiftReminderPermission(for: userId, afterFirstShift: isFirstShift)
  }
}
