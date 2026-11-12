import AppIntents
import Combine
import Foundation
import Observation
import SwiftUI
import os.log

extension AddShiftViewModel {

  // MARK: - Single Shift Actions

  /// Toggle selection of a date (single tap behavior)
  func toggleDate(_ dateISO: String) {
    // Toggle single date
    if selectedDates.contains(dateISO) {
      selectedDates.remove(dateISO)
      // Incremental update: remove from preview earnings
      cachedPreviewEarnings.removeValue(forKey: dateISO)
      // Update conflicts after removing date
      updateConflictsIncrementally(removedDate: dateISO)
    } else {
      selectedDates.insert(dateISO)
      // Incremental update: only compute earnings for this new date
      updatePreviewEarningsIncrementally(addedDate: dateISO)
      // Update conflicts after adding date
      updateConflictsIncrementally(addedDate: dateISO)
    }

    // Recompute from full current state so any in-flight async result with stale inputs
    // is invalidated and cannot overwrite the latest incremental updates.
    scheduleConflictsAndPreviewsRecompute()

    // Haptic feedback
    let generator = UIImpactFeedbackGenerator(style: .light)
    generator.impactOccurred()
  }

  /// Clear all selected dates
  func clearSelectedDates() {
    selectedDates.removeAll()
    cachedPreviewEarnings.removeAll()
    cachedConflictDatesForCalendar.removeAll()
  }

  func toggleEventCalendarDate(_ dateISO: String) {
    guard let tappedDate = Date.fromISODateString(dateISO) else {
      return
    }
    let calendar = Calendar.gregorianCurrent
    let normalizedDate = calendar.startOfDay(for: tappedDate)
    markEventCalendarSelectionEdited()

    if isEventAllDay {
      let currentStart = calendar.startOfDay(for: min(eventStartDate, eventEndDate))
      let currentEnd = calendar.startOfDay(for: max(eventStartDate, eventEndDate))
      let anchor = calendar.startOfDay(for: eventRangeAnchorDate ?? currentStart)
      let isExistingRange = currentStart < currentEnd
      let tappedInsideCurrentRange = normalizedDate >= currentStart && normalizedDate <= currentEnd

      if isExistingRange, tappedInsideCurrentRange, normalizedDate != anchor {
        eventStartDate = normalizedDate
        eventEndDate = normalizedDate
        eventRangeAnchorDate = normalizedDate
      } else if normalizedDate >= anchor {
        eventStartDate = anchor
        eventEndDate = normalizedDate
      } else {
        eventStartDate = normalizedDate
        eventEndDate = anchor
      }
    } else {
      eventDate = normalizedDate
      eventStartDate = normalizedDate
      eventEndDate = normalizedDate
      eventRangeAnchorDate = normalizedDate
    }

    let generator = UIImpactFeedbackGenerator(style: .light)
    generator.impactOccurred()
  }

  /// A single optional offer. Multi-date selections and repeating shifts remain shifts.
  var paymentSuggestionReason: LocalizedStringResource? {
    guard mode == .single, selectedDates.count == 1, startTime != nil, endTime != nil,
      let job = selectedJob
    else { return nil }
    if Self.hasPaymentLikeName(job.name) { return .addShiftPaymentNameReason }
    let conflicts = ShiftConflictDetector.detectConflicts(
      dates: Array(selectedDates), startTime: startTimeString, endTime: endTimeString,
      existingShifts: paymentConflictShifts, existingRecurringShifts: cachedRecurringShifts)
    if !conflicts.isEmpty { return .addShiftPaymentOverlapReason }
    let start = CalendarGridHelper.timeToMinutes(startTimeString)
    let end = CalendarGridHelper.timeToMinutes(endTimeString)
    let minutesPerDay = 24 * 60
    let longShiftMinutes = 16 * 60
    let duration = end > start ? end - start : end + minutesPerDay - start
    if duration >= longShiftMinutes { return .addShiftPaymentLongReason }
    let comparableGross = cachedShifts.filter { $0.job_id == job.id }.map { shift in
      PayrollCalculator.computeShift(
        shift,
        snapshot: snapshotForDate(shift.shift_date, jobId: job.id)
      ).gross
    }.filter { $0.isFinite && $0 > 0 }.sorted()
    let minimumComparableShifts = 5
    let unusualEarningsMultiplier = 4.0
    if comparableGross.count >= minimumComparableShifts,
      let date = selectedDates.first, let preview = computeEarningsForDate(date),
      preview.gross >= comparableGross[comparableGross.count / 2] * unusualEarningsMultiplier
    {
      return .addShiftPaymentLargeReason
    }
    return nil
  }

  private var paymentConflictShifts: [ShiftRow] {
    guard let owner = paymentDataOwnerId,
      owner == AppCoordinator.shared.getCurrentUserId(),
      let selected = selectedDates.first.flatMap({ Date.fromISODateString($0) }),
      let start = Calendar.gregorianCurrent.date(byAdding: .day, value: -1, to: selected),
      let end = Calendar.gregorianCurrent.date(byAdding: .day, value: 1, to: selected)
    else { return [] }
    return shiftsRepository.getShifts(for: owner, startDate: start, endDate: end)
  }

  static func hasPaymentLikeName(_ name: String) -> Bool {
    let words = name.folding(
      options: [.caseInsensitive, .diacriticInsensitive], locale: .appLocale
    )
    .split { !$0.isLetter && !$0.isNumber }
    let paymentWords: Set<String> = [
      "nav", "benefit", "benefits", "bonus", "bonuses", "trygd", "trygdeytelse", "dagpenger",
      "utbetaling",
    ]
    return words.contains { paymentWords.contains(String($0)) }
  }

  func proposePaymentAdjustment() {
    guard paymentSuggestionReason != nil, let job = selectedJob,
      let dateISO = selectedDates.first, let date = Date.fromISODateString(dateISO),
      let owner = try? AppCoordinator.shared.requireUserId(),
      owner == paymentDataOwnerId
    else { return }
    // Compute from the current inputs rather than a potentially stale debounced preview.
    let preview = Self.computeEarningsForDate(
      dateISO, startTime: startTimeString, endTime: endTimeString,
      context: .init(
        requiresExplicitJobSelection: requiresExplicitJobSelection,
        selectedJobId: selectedJobId, effectiveJobId: effectiveSelectedJobId,
        snapshots: cachedSnapshots, jobs: activeJobs, configuredJobIds: configuredJobIds,
        settings: cachedSettings))
    guard let preview, preview.gross.isFinite else { return }
    paymentOwnerId = owner
    paymentSaved = false
    paymentFormContext = PayrollAdjustmentFormContext(
      prefill: PayrollAdjustmentDraft(
        jobId: job.id, amount: preview.gross, currency: job.currency, category: .correction,
        taxTreatment: .grossTaxable, description: job.name, note: nil,
        earnedFromDate: nil, earnedToDate: nil, payoutDate: date), taxEnabled: true)
  }

  func savePaymentAdjustment(_ draft: PayrollAdjustmentDraft) async throws {
    let owner = try AppCoordinator.shared.requireUserId()
    guard owner == paymentOwnerId, let context = paymentFormContext,
      draft.jobId == context.jobId, draft.currency == context.currency,
      draft.amount.isFinite, draft.amount != 0
    else { throw ShiftSaveError.invalidDate }
    _ = try await PayrollAdjustmentsRepository.shared.createAdjustment(
      userId: owner, jobId: draft.jobId, amount: draft.amount, currency: draft.currency,
      category: draft.category, taxTreatment: draft.taxTreatment, description: draft.description,
      note: draft.note, earnedFromDate: draft.earnedFromDate, earnedToDate: draft.earnedToDate,
      payoutDate: draft.payoutDate)
    guard (try? AppCoordinator.shared.requireUserId()) == owner else { return }
    clearDraft()
    paymentSaved = true
  }

  func paymentEditorDismissed() {
    paymentOwnerId = nil
    if paymentSaved {
      paymentSaved = false
      onShiftsCreated?(.payment)
    }
  }

  /// Submit single shifts
  func submitSingleShifts() async {  // swiftlint:disable:this function_body_length
    guard canSubmitSingle, !isLoading else {
      return
    }

    if let job = jobRequiringPaySetupForCurrentSelection() {
      paySetupRequest = AddShiftPaySetupRequest(job: job, action: .submitSingle)
      return
    }

    guard let userId = resolveSubmitUserId() else {
      return
    }

    isLoading = true
    error = nil
    let isFirstShift = CelebrationManager.shared.isFirstShiftSave(for: userId)
    var createdDates: Set<String> = []
    defer {
      endSingleSubmission(createdDates: createdDates, userId: userId)
    }

    do {
      let jobId = effectiveSelectedJobId
      let submittedStartTime = startTimeString
      let submittedEndTime = endTimeString

      try await saveSelectedSingleShifts { shiftDate in
        _ = try await shiftsRepository.createShift(
          userId: userId,
          jobId: jobId,
          shiftDate: shiftDate,
          startTime: submittedStartTime,
          endTime: submittedEndTime
        )
        createdDates.insert(shiftDate.toISODateString())
      }

      donateAddShift(jobId: jobId, dates: createdDates)
      finishSingleSubmission(createdDates: createdDates, userId: userId, isFirstShift: isFirstShift)
    } catch {
      addShiftViewModelLogger.error("Failed to create shifts: \(error.localizedDescription)")
      self.error = ErrorTranslations.translate(error).map { message in
        createdDates.isEmpty
          ? message
          : String(localized: .addShiftSinglePartialSave) + "\n" + message
      }
      Haptics.play(.error)
    }
  }

  /// Lets Siri suggest adding a shift like this one.
  private func donateAddShift(jobId: String?, dates: Set<String>) {
    guard
      let day = dates.min().flatMap({ Date.fromISODateString($0) }),
      let startTime,
      let endTime
    else {
      return
    }
    let job = activeJobs.first { $0.id == jobId }.map(JobEntity.init)
    _ = AddShiftIntent(job: job, date: day, start: startTime, end: endTime).donate()
  }

  func resolveSubmitUserId() -> String? {
    do {
      return try AppCoordinator.shared.requireUserId()
    } catch {
      self.error = ErrorTranslations.translate(error)
      return nil
    }
  }

  /// Reloads what changed and clears the loading state, also after a partial save.
  private func endSingleSubmission(createdDates: Set<String>, userId: String) {
    if !createdDates.isEmpty {
      reloadShiftsForDisplayedMonth()
      refreshDistinctShiftTimePairCount(for: userId)
      NotificationCenter.default.postShiftsDidChange(
        context: .affecting(isoDates: Array(createdDates))
      )
    }
    isLoading = false
  }

  private func finishSingleSubmission(
    createdDates: Set<String>, userId: String, isFirstShift: Bool
  ) {
    addShiftViewModelLogger.info("Created \(createdDates.count) shifts")

    // Highlight the added dates in the Shifts tab
    CelebrationManager.shared.celebrate(dates: createdDates)
    if isFirstShift, !createdDates.isEmpty {
      CelebrationManager.shared.celebrateFirstShift()
    }

    // Saving leaves the screen, so the form keeps its values while it slides away.
    clearDraft()

    // Success haptic
    Haptics.playShiftCreationSuccess()
    AccessibilityNotification.Announcement(String(localized: .shiftsAccessibilityShiftsAdded))
      .post()

    // Notify completion
    onShiftsCreated?(.single(dates: createdDates))
    requestShiftReminderPermission(for: userId, afterFirstShift: isFirstShift)
  }

  /// Runs in its own task, so the save finishes and Home reloads before the prompt is answered.
  func requestShiftReminderPermission(for userId: String, afterFirstShift isFirstShift: Bool) {
    let preferences = NotificationPreferencesRepository.shared.getOrCreatePreferences(for: userId)
    guard preferences.shiftRemindersEnabled, !preferences.shiftReminderMinutesArray.isEmpty else {
      return
    }
    Task {
      if isFirstShift {
        await FirstShiftConfetti.waitUntilFinished()
      }
      await NotificationService.shared.requestPermissionAndRegister(for: userId)
    }
  }

  /// Check all dates before writing, then retire each saved date from the retryable draft.
  /// A failure leaves only the failed and unattempted dates selected, including after relaunch.
  /// The calendar keeps the whole selection until the save ends, so days don't clear one by one.
  func saveSelectedSingleShifts(
    createShift: (Date) async throws -> Void
  ) async throws {
    let dates = try selectedDates.sorted().map { dateISO in
      guard let date = Date.fromISODateString(dateISO) else {
        throw ShiftSaveError.invalidDate
      }
      return (iso: dateISO, date: date)
    }
    var unsavedDates = selectedDates
    defer { selectedDates = unsavedDates }
    for selection in dates {
      try await createShift(selection.date)
      unsavedDates.remove(selection.iso)
      saveDraft(selectedDates: unsavedDates)
    }
  }

  /// Submit a private event.
  func submitEvent() async {
    guard canSubmitEvent, !isLoading else {
      return
    }

    guard let userId = resolveSubmitUserId() else {
      return
    }

    isLoading = true
    error = nil

    do {
      let trimmedNote = eventNote.trimmingCharacters(in: .whitespacesAndNewlines)
      let startDate = isEventAllDay ? eventStartDate : eventDate
      let endDate = isEventAllDay ? eventEndDate : eventDate
      let startTime = isEventAllDay ? nil : startTimeString
      let endTime = isEventAllDay ? nil : endTimeString
      let notificationMinutesArray = eventReminderTimes.isEmpty ? nil : eventReminderTimes
      let notificationAnchorTime =
        isEventAllDay && !eventReminderTimes.isEmpty ? eventReminderAnchorTimeString : nil

      _ = try await eventsRepository.createEvent(
        userId: userId,
        startDate: startDate,
        endDate: endDate,
        isAllDay: isEventAllDay,
        startTime: startTime,
        endTime: endTime,
        note: trimmedNote,
        notificationMinutesArray: notificationMinutesArray,
        notificationAnchorTime: notificationAnchorTime
      )

      await finishEventSubmission(
        startDate: startDate, endDate: endDate,
        hasReminders: notificationMinutesArray != nil, userId: userId)
    } catch {
      addShiftViewModelLogger.error("Failed to create event: \(error.localizedDescription)")
      self.error = ErrorTranslations.translate(error)
      Haptics.play(.error)
    }

    isLoading = false
  }

  private func finishEventSubmission(
    startDate: Date, endDate: Date, hasReminders: Bool, userId: String
  ) async {
    addShiftViewModelLogger.info("Created private event")

    clearDraft()
    Haptics.playShiftCreationSuccess()
    AccessibilityNotification.Announcement(String(localized: .shiftsAccessibilitySaved)).post()
    NotificationCenter.default.postShiftsDidChange(
      context: .affecting(dateRangeStart: startDate, end: endDate)
    )
    onShiftsCreated?(.event)
    if hasReminders {
      await NotificationService.shared.requestPermissionAndRegister(for: userId)
    }
  }
}
