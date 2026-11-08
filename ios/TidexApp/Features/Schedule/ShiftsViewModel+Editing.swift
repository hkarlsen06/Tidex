import Combine
import Foundation
import Observation
import UIKit
import os.log

extension ShiftsViewModel {

  // MARK: - Recurring Shift Editing

  /// Update a recurring shift pattern
  /// - Parameter editResult: The result from the recurring shift edit form
  func updateRecurringShift(_ editResult: RecurringShiftEditResult) async {
    // Prevent duplicate taps
    guard !isUpdatingRecurring else {
      return
    }

    isUpdatingRecurring = true
    kScheduleLogger.info("📝 Updating recurring shift \(editResult.recurringId)")

    do {
      _ = try await recurringShiftsRepository.updateRecurringShift(
        id: editResult.recurringId,
        startTime: editResult.startTime,
        endTime: editResult.endTime,
        repeatIntervalWeeks: editResult.repeatIntervalWeeks,
        selectedDays: editResult.selectedDays,
        endCondition: editResult.endCondition,
        exclusions: editResult.exclusions
      )

      kScheduleLogger.info("✅ Updated recurring shift \(editResult.recurringId)")

      // Clear recurring shifts cache so changes are picked up
      recurringShifts = []
      scheduleDependenciesLoaded = false

      // Reload to show the changes
      await reloadFromLocal()

      // Post notification for other views
      notifyShiftsDidChange(context: .fullReload)

    } catch {
      kScheduleLogger.error("❌ Failed to update recurring shift: \(error.localizedDescription)")
    }

    isUpdatingRecurring = false
  }

  func stopRecurringShiftAfterDate(recurringId: String, occurrenceDate: String) async throws {
    guard !isUpdatingRecurring else { throw ShiftSaveError.alreadyInProgress }

    isUpdatingRecurring = true
    defer { isUpdatingRecurring = false }
    kScheduleLogger.info("📝 Ending recurring shift \(recurringId) after \(occurrenceDate)")

    do {
      _ = try await recurringShiftsRepository.updateRecurringShift(
        id: recurringId,
        endCondition: .endDate(date: occurrenceDate)
      )

      recurringShifts = []
      scheduleDependenciesLoaded = false

      await reloadFromLocal()
      notifyShiftsDidChange(context: .fullReload)
    } catch {
      kScheduleLogger.error("❌ Failed to end recurring shift: \(error.localizedDescription)")
      throw error
    }
  }

  /// Delete a recurring shift pattern
  /// - Parameter recurringId: The ID of the recurring shift to delete
  func deleteRecurringShift(_ recurringId: String) async {
    // Prevent duplicate taps
    guard !isDeletingRecurring else {
      return
    }

    isDeletingRecurring = true
    kScheduleLogger.info("🗑️ Deleting recurring shift \(recurringId)")

    do {
      try await recurringShiftsRepository.deleteRecurringShift(id: recurringId)

      kScheduleLogger.info("✅ Deleted recurring shift \(recurringId)")

      // Clear recurring shifts cache so changes are picked up
      recurringShifts = []
      scheduleDependenciesLoaded = false

      // Reload to show the changes
      await reloadFromLocal()

      // Post notification for other views
      notifyShiftsDidChange(context: .fullReload)

    } catch {
      kScheduleLogger.error("❌ Failed to delete recurring shift: \(error.localizedDescription)")
    }

    isDeletingRecurring = false
  }

  /// Get a recurring shift by ID
  /// - Parameter id: The recurring shift ID
  /// - Returns: The recurring shift if found
  func getRecurringShift(id: String) -> RecurringShiftRow? {
    recurringShiftsRepository.getRecurringShift(id: id)
  }

  func getDisplayedShift(id: String) -> ShiftWithComputations? {
    shifts.first(where: { $0.id == id })
  }

  // MARK: - Event Editing

  func updateEvent(_ editResult: EventEditResult) async throws {
    guard !isUpdatingEvent else {
      return
    }

    isUpdatingEvent = true
    defer { isUpdatingEvent = false }
    kScheduleLogger.info("📝 Updating event \(editResult.eventId)")
    let existingEvent = events.first(where: { $0.id == editResult.eventId })

    guard
      let startDate = Date.fromISODateString(editResult.startDate),
      let endDate = Date.fromISODateString(editResult.endDate)
    else {
      kScheduleLogger.error(
        "Invalid event date range: \(editResult.startDate) - \(editResult.endDate)"
      )
      throw ShiftsError.invalidEventDateRange
    }

    do {
      guard
        try await eventsRepository.updateEvent(
          id: editResult.eventId,
          startDate: startDate,
          endDate: endDate,
          isAllDay: editResult.isAllDay,
          startTime: editResult.startTime,
          endTime: editResult.endTime,
          note: editResult.note,
          notificationMinutesArray: editResult.notificationMinutesArray,
          notificationAnchorTime: editResult.notificationAnchorTime
        ) != nil
      else {
        kScheduleLogger.error("❌ Event missing during update: \(editResult.eventId)")
        throw ShiftsError.eventNotFound
      }

      await reloadFromLocal()
      notifyShiftsDidChange(
        context: eventChangeContext(
          for: editResult,
          existingEvent: existingEvent
        ))
    } catch {
      kScheduleLogger.error("❌ Failed to update event: \(error.localizedDescription)")
      throw error
    }
  }

  func deleteEvent(_ event: EventRow) async throws {
    guard !isDeletingEvent else {
      return
    }

    isDeletingEvent = true
    defer { isDeletingEvent = false }

    kScheduleLogger.info("🗑️ Deleting event \(event.id)")

    try await eventsRepository.deleteEvent(id: event.id)
    await reloadFromLocal()
    notifyShiftsDidChange(
      context: .affecting(
        isoDateRangeStart: event.start_date,
        end: event.end_date
      ))
  }

  // MARK: - Shift Editing

  /// Update a shift with new date/time values
  /// - Parameter editResult: The result from the shift edit form
  func updateShift(_ editResult: ShiftEditResult) async throws {
    // Prevent duplicate taps
    guard !isUpdatingShift else { throw ShiftSaveError.alreadyInProgress }

    isUpdatingShift = true
    defer { isUpdatingShift = false }
    kScheduleLogger.info("📝 Updating shift \(editResult.shiftId)")

    do {
      // Parse the new date
      guard let newDate = Date.fromISODateString(editResult.shiftDate) else {
        kScheduleLogger.error("Invalid date format: \(editResult.shiftDate)")
        throw ShiftSaveError.invalidDate
      }

      let currentShift = shifts.first(where: { $0.id == editResult.shiftId })?.shift
      let hasTimeOrDateChanges =
        editResult.shiftDate != currentShift?.shift_date
        || editResult.startTime != currentShift.map { String($0.start_time.prefix(5)) }
        || editResult.endTime != currentShift.map { String($0.end_time.prefix(5)) }
      let resolvedNote = editResult.noteWasEdited ? editResult.note : currentShift?.note

      if editResult.isVirtualShiftConversion {
        try await convertVirtualShift(
          editResult,
          newDate: newDate,
          hasTimeOrDateChanges: hasTimeOrDateChanges,
          resolvedNote: resolvedNote
        )

      } else {
        try await updateRegularShift(editResult, newDate: newDate)
      }

      // Reload to show the changes
      await reloadFromLocal()

      // Post notification for other views
      notifyShiftsDidChange(
        context: shiftChangeContext(
          for: editResult,
          existingShift: currentShift
        ))

    } catch {
      kScheduleLogger.error("❌ Failed to update shift: \(error.localizedDescription)")
      throw error
    }
  }

  /// Regular shift update - just update the existing shift
  private func updateRegularShift(_ editResult: ShiftEditResult, newDate: Date) async throws {
    _ = try await shiftsRepository.updateShift(
      id: editResult.shiftId,
      shiftDate: newDate,
      startTime: editResult.startTime,
      endTime: editResult.endTime,
      note: editResult.note,
      noteWasEdited: editResult.noteWasEdited,
      customSupplements: editResult.customSupplements
    )
    kScheduleLogger.info("✅ Updated shift \(editResult.shiftId)")
  }

  /// Convert a virtual (recurring) shift into a regular shift, or store only a per-date note.
  private func convertVirtualShift(
    _ editResult: ShiftEditResult,
    newDate: Date,
    hasTimeOrDateChanges: Bool,
    resolvedNote: String?
  ) async throws {
    // Virtual shift conversion:
    // 1. Add exclusion to the recurring shift for the original date
    // 2. Create a new regular shift with the edited values
    kScheduleLogger.info("🔄 Converting virtual shift to regular shift")

    // Get user ID - use cached value or fall back to AppCoordinator
    // This guards against race conditions if user signs out mid-operation
    let userId = cachedUserId ?? AppCoordinator.shared.getCurrentUserId()
    guard let recurringId = editResult.recurringId,
      let userId
    else {
      kScheduleLogger.error("Missing recurringId or userId for virtual shift conversion")
      throw ShiftSaveError.missingRecurringInfo
    }

    let recurringShift =
      recurringShifts.first(where: { $0.id == recurringId })
      ?? recurringShiftsRepository.getRecurringShift(id: recurringId)

    if !hasTimeOrDateChanges, editResult.customSupplements == nil, editResult.noteWasEdited {
      var updatedNotes = recurringShift?.date_specific_notes ?? [:]
      if let resolvedNote {
        updatedNotes[editResult.originalDate] = resolvedNote
      } else {
        updatedNotes.removeValue(forKey: editResult.originalDate)
      }

      _ = try await recurringShiftsRepository.updateDateSpecificNotes(
        id: recurringId,
        dateSpecificNotes: updatedNotes
      )
      kScheduleLogger.info("✅ Updated recurring note for \(editResult.originalDate)")
    } else {
      try await clearDateSpecificNote(
        on: editResult.originalDate, recurringId: recurringId, recurringShift: recurringShift)

      // Step 1: Add exclusion for the original date
      try await RecurringShiftsRepository.shared.addExclusion(
        id: recurringId,
        date: editResult.originalDate
      )
      kScheduleLogger.info("✅ Added exclusion for \(editResult.originalDate)")

      // Step 2: Create a new regular shift with the edited values
      try await createRegularShift(
        from: editResult, recurringId: recurringId, userId: userId,
        newDate: newDate, note: resolvedNote)

      try await clearDateSpecificNote(
        on: editResult.originalDate, recurringId: recurringId, recurringShift: recurringShift)
    }
  }

  private func createRegularShift(
    from editResult: ShiftEditResult,
    recurringId: String,
    userId: String,
    newDate: Date,
    note: String?
  ) async throws {
    let sourceJobId =
      shifts.first(where: { $0.id == editResult.shiftId })?.shift.job_id
      ?? recurringShifts.first(where: { $0.id == recurringId })?.job_id

    _ = try await shiftsRepository.createShift(
      userId: userId,
      jobId: sourceJobId,
      shiftDate: newDate,
      startTime: editResult.startTime,
      endTime: editResult.endTime,
      note: note,
      customSupplements: editResult.customSupplements
    )
    kScheduleLogger.info("✅ Created new shift on \(editResult.shiftDate)")
  }

  private func clearDateSpecificNote(
    on date: String,
    recurringId: String,
    recurringShift: RecurringShiftRow?
  ) async throws {
    guard var updatedNotes = recurringShift?.date_specific_notes else { return }
    updatedNotes.removeValue(forKey: date)
    _ = try await recurringShiftsRepository.updateDateSpecificNotes(
      id: recurringId,
      dateSpecificNotes: updatedNotes
    )
  }

  func updateShiftPause(_ editResult: ShiftPauseEditResult) async {
    guard !isUpdatingShift else {
      return
    }

    isUpdatingShift = true
    defer { isUpdatingShift = false }

    kScheduleLogger.info("⏸️ Updating shift pause windows")
    let changeContext: ShiftChangeContext

    switch editResult.target {
    case .standalone(let shiftId):
      if let shift = shifts.first(where: { $0.id == shiftId }) {
        changeContext = .affecting(isoDate: shift.shiftDate)
      } else {
        changeContext = .fullReload
      }

    case .recurringOccurrence(_, let date):
      changeContext = .affecting(isoDate: date)
    }

    do {
      switch editResult.target {
      case .standalone(let shiftId):
        _ = try await shiftsRepository.updateCustomPauseWindows(
          id: shiftId,
          customPauseWindows: editResult.customPauseWindows
        )

      case .recurringOccurrence(let recurringId, let date):
        guard
          let recurringShift = recurringShifts.first(where: { $0.id == recurringId })
            ?? recurringShiftsRepository.getRecurringShift(id: recurringId)
        else {
          kScheduleLogger.error("Recurring shift not found for pause update: \(recurringId)")
          return
        }

        var updatedPauseWindows = recurringShift.date_specific_pause_windows ?? [:]
        if let normalized = PauseWindowSupport.normalize(editResult.customPauseWindows) {
          updatedPauseWindows[date] = normalized
        } else {
          updatedPauseWindows.removeValue(forKey: date)
        }

        _ = try await recurringShiftsRepository.updateDateSpecificPauseWindows(
          id: recurringId,
          dateSpecificPauseWindows: PauseWindowSupport.normalize(updatedPauseWindows)
        )
      }

      await reloadFromLocal()
      notifyShiftsDidChange(context: changeContext)
    } catch {
      kScheduleLogger.error("❌ Failed to update shift pause windows: \(error.localizedDescription)")
    }
  }

  /// Non-blocking month data loader
  /// Uses cache for instant display, fetches in background if needed
  /// IMPORTANT: Commits display state (year/month) atomically with shift data
  func applyCommittedMonthSnapshot(
    shifts computedShifts: [ShiftWithComputations],
    events displayEvents: [EventRow],
    year: Int,
    month: Int
  ) {
    let visibleRange = Date.visibleCalendarRange(year: year, month: month)
    let currentMonth = Date.currentYearMonth()
    let nextUpcomingShift =
      currentMonth.year == year && currentMonth.month == month
      ? findNextUpcomingShift(in: computedShifts)
      : nil

    updateConflictDetection(for: computedShifts)
    self.shifts = computedShifts
    self.events = displayEvents
    self.eventCoverageByDate = Self.buildEventCoverageByDate(
      events: displayEvents,
      visibleRange: visibleRange
    )
    self.calendarPresentation = ShiftsCalendarPresentation.build(
      shifts: computedShifts,
      year: year,
      month: month,
      jobs: activeJobs,
      currency: currency,
      excludedFromTotalIds: excludedFromTotalIds
    )
    self.committedYear = year
    self.committedMonth = month
    self.nextUpcomingShift = nextUpcomingShift
    if !selectedDates.isEmpty {
      updateSelectionSummary()
    }
  }

  func notifyShiftsDidChange(context: ShiftChangeContext = .fullReload) {
    NotificationCenter.default.postShiftsDidChange(object: self, context: context)
  }

  func shiftChangeContext(
    for editResult: ShiftEditResult,
    existingShift: ShiftRow?
  ) -> ShiftChangeContext {
    var dates = [editResult.shiftDate, editResult.originalDate]

    if let existingShift {
      dates.append(existingShift.shift_date)
    }

    return .affecting(isoDates: dates)
  }

  private func eventChangeContext(
    for editResult: EventEditResult,
    existingEvent: EventRow?
  ) -> ShiftChangeContext {
    var context = ShiftChangeContext.affecting(
      isoDateRangeStart: editResult.startDate,
      end: editResult.endDate
    )

    if let existingEvent {
      context = context.merging(
        .affecting(
          isoDateRangeStart: existingEvent.start_date,
          end: existingEvent.end_date
        ))
    }

    return context
  }

  @discardableResult
  func applyCachedDisplayedMonthIfValid(year: Int, month: Int) -> Bool {
    let displayKey = "\(year)-\(month)"

    guard var displayCache = monthCache[displayKey], displayCache.isValid else {
      return false
    }

    kScheduleLogger.info("📦 Using cached computed data for \(displayKey)")

    // ATOMIC UPDATE: Set shifts and committed state together
    // This ensures the calendar structure and event data update in the same render pass.
    applyCommittedMonthSnapshot(
      shifts: displayCache.shifts,
      events: displayCache.events,
      year: year,
      month: month
    )

    // Update last accessed time for LRU tracking
    displayCache.lastAccessed = Date()
    monthCache[displayKey] = displayCache

    return true
  }

  func loadShiftsForDisplayedMonthNonBlocking() {
    guard isActiveTabVisible else {
      displayedMonthLoadPending = true
      kScheduleLogger.info("⏸️ Deferring schedule month load while Schedule tab is hidden")
      return
    }

    let targetYear = displayYear
    let targetMonth = displayMonth
    let displayKey = "\(targetYear)-\(targetMonth)"

    // Check if we have valid computed cache for displayed month
    if applyCachedDisplayedMonthIfValid(year: targetYear, month: targetMonth) {
      // Still prefetch neighbors in background
      prefetchNeighboringMonths()
      return
    }

    // Cache miss - fetch from local in background
    // DON'T clear shifts array or update committed state - keep showing previous month until new data is ready
    // This prevents the "flash of empty state" during local SQLite reads
    kScheduleLogger.info("🔄 Cache miss for \(displayKey), fetching from local...")
    self.isLoading = true

    // Cancel any previous navigation task
    activeNavigationTask?.cancel()

    // Start background fetch
    activeNavigationTask = Task { [weak self] in
      guard let self else {
        return
      }

      // Check if this task is still relevant
      guard !Task.isCancelled,
        displayYear == targetYear,
        displayMonth == targetMonth
      else {
        kScheduleLogger.info("⏭️ Skipping stale fetch for \(displayKey)")
        return
      }

      await loadShiftsForDisplayedMonth(
        showLoadingState: false, targetYear: targetYear, targetMonth: targetMonth)

      // Check again after fetch
      guard !Task.isCancelled,
        displayYear == targetYear,
        displayMonth == targetMonth
      else {
        kScheduleLogger.info("⏭️ Skipping prefetch - user navigated during fetch")
        return
      }

      // Prefetch neighbors after successful load
      prefetchNeighboringMonths()
    }
  }
}
