import Combine
import Foundation
import Observation
import UIKit
import os.log  // swiftlint:disable:this sorted_imports

extension DashboardViewModel {

  /// Get tariff supplement rules for a specific shift date
  /// Used by ShiftDetailsSheet to show applicable tariff rules
  /// - Parameter shiftDate: ISO date string (YYYY-MM-DD)
  /// - Returns: Array of supplement rules from the applicable snapshot
  func getTariffRules(for shiftDate: String) -> [SupplementRule] {  // swiftlint:disable:this explicit_acl line_length type_contents_order
    guard let snapshot = SnapshotsService.snapshotForDate(shiftDate, from: snapshots) else {
      return []
    }
    return snapshot.effectiveSupplements
  }

  /// Get a recurring shift by ID
  /// - Parameter id: The recurring shift ID
  /// - Returns: The recurring shift if found
  func getRecurringShift(id: String) -> RecurringShiftRow? {  // swiftlint:disable:this explicit_acl type_contents_order
    recurringShiftsRepository.getRecurringShift(id: id)
  }

  func stopRecurringShiftAfterDate(recurringId: String, occurrenceDate: String) async throws {  // swiftlint:disable:this explicit_acl line_length type_contents_order
    guard !isUpdatingRecurringShift else { throw ShiftSaveError.alreadyInProgress }

    isUpdatingRecurringShift = true
    defer { isUpdatingRecurringShift = false }

    _ = try await recurringShiftsRepository.updateRecurringShift(
      id: recurringId,
      endCondition: .endDate(date: occurrenceDate)
    )

    resetDashboardDependencies(preservingDisplayJobs: true)
    await reloadFromLocal()
    notifyShiftsDidChange(context: .fullReload)
  }

  func getDisplayedShift(id: String) -> ShiftWithComputations? {  // swiftlint:disable:this explicit_acl line_length type_contents_order
    displayedMonthShifts.first(where: { $0.id == id })
  }

  // MARK: - Event Operations

  func updateEvent(_ editResult: EventEditResult) async throws {  // swiftlint:disable:this explicit_acl line_length type_contents_order
    guard !isUpdatingEvent else { return }  // swiftlint:disable:this conditional_returns_on_newline

    isUpdatingEvent = true
    defer { isUpdatingEvent = false }
    let existingEvent = displayedMonthEvents.first(where: { $0.id == editResult.eventId })  // swiftlint:disable:this explicit_type_interface line_length

    guard
      let startDate = Date.fromISODateString(editResult.startDate),
      let endDate = Date.fromISODateString(editResult.endDate)
    else {
      throw ShiftsError.invalidEventDateRange
    }

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
      throw ShiftsError.eventNotFound
    }

    await reloadFromLocal()
    notifyShiftsDidChange(
      context: eventChangeContext(
        for: editResult,
        existingEvent: existingEvent
      ))  // swiftlint:disable:this multiline_arguments_brackets
  }

  func deleteEvent(_ event: EventRow) async throws {  // swiftlint:disable:this explicit_acl type_contents_order
    guard !isDeletingEvent else { return }  // swiftlint:disable:this conditional_returns_on_newline

    isDeletingEvent = true
    defer { isDeletingEvent = false }

    try await eventsRepository.deleteEvent(id: event.id)
    await reloadFromLocal()
    notifyShiftsDidChange(
      context: .affecting(
        isoDateRangeStart: event.start_date,
        end: event.end_date
      ))  // swiftlint:disable:this multiline_arguments_brackets
  }

  /// End an active shift immediately using the current local device time.
  /// Uses the existing update pipeline so sync/reload behavior stays consistent.
  /// - Parameters:
  ///   - shift: The shift to end now
  ///   - now: Optional reference time for testing
  func endShiftNow(_ shift: ShiftWithComputations, at now: Date = Date()) async {  // swiftlint:disable:this explicit_acl line_length type_contents_order
    guard !isUpdatingShift else { return }  // swiftlint:disable:this conditional_returns_on_newline

    ((UIApplication.shared.delegate as? AppDelegate) ?? AppDelegate.shared)?.endLiveActivity(
      for: shift.id)  // swiftlint:disable:this multiline_arguments_brackets

    let editResult = ShiftEditResult(  // swiftlint:disable:this explicit_type_interface
      shiftId: shift.id,
      shiftDate: shift.shiftDate,
      startTime: String(shift.startTime.prefix(5)),  // swiftlint:disable:this no_magic_numbers
      endTime: Self.timeString(from: now),
      isVirtualShiftConversion: shift.isVirtual,
      recurringId: shift.shift.recurring_id,
      originalDate: shift.shiftDate,
      customSupplements: nil
    )

    do {
      try await updateShift(editResult)
    } catch {
      dashboardViewModelLogger.error("❌ Failed to end active shift: \(error.localizedDescription)")
    }
  }

  /// End a persisted (non-virtual) shift immediately.
  /// This is used by dashboard clock actions when an ongoing normal shift exists.
  func endShiftNow(_ shift: ShiftRow, at now: Date = Date()) async {  // swiftlint:disable:this explicit_acl line_length type_contents_order
    guard !isUpdatingShift else { return }  // swiftlint:disable:this conditional_returns_on_newline

    ((UIApplication.shared.delegate as? AppDelegate) ?? AppDelegate.shared)?.endLiveActivity(
      for: shift.id)  // swiftlint:disable:this multiline_arguments_brackets

    let editResult = ShiftEditResult(  // swiftlint:disable:this explicit_type_interface
      shiftId: shift.id,
      shiftDate: shift.shift_date,
      startTime: String(shift.start_time.prefix(5)),  // swiftlint:disable:this no_magic_numbers
      endTime: Self.timeString(from: now),
      isVirtualShiftConversion: false,
      recurringId: nil,
      originalDate: shift.shift_date,
      customSupplements: nil
    )

    do {
      try await updateShift(editResult)
    } catch {
      dashboardViewModelLogger.error("❌ Failed to end persisted shift: \(error.localizedDescription)")
    }
  }

  /// Update a shift with new date/time values
  /// - Parameter editResult: The result from the shift edit form
  func updateShift(_ editResult: ShiftEditResult) async throws {  // swiftlint:disable:this cyclomatic_complexity explicit_acl function_body_length line_length type_contents_order
    // Prevent duplicate taps
    guard !isUpdatingShift else { throw ShiftSaveError.alreadyInProgress }

    isUpdatingShift = true
    defer { isUpdatingShift = false }
    dashboardViewModelLogger.info("📝 Updating shift \(editResult.shiftId)")

    do {
      // Parse the new date
      guard let newDate = Date.fromISODateString(editResult.shiftDate) else {
        dashboardViewModelLogger.error("Invalid date format: \(editResult.shiftDate)")
        throw ShiftSaveError.invalidDate
      }

      let currentShift = displayedMonthShifts.first(where: { $0.id == editResult.shiftId })?.shift  // swiftlint:disable:this explicit_type_interface line_length
      let hasTimeOrDateChanges =  // swiftlint:disable:this explicit_type_interface
        editResult.shiftDate != currentShift?.shift_date
        || editResult.startTime != currentShift.map { String($0.start_time.prefix(5)) }  // swiftlint:disable:this line_length no_magic_numbers
        || editResult.endTime != currentShift.map { String($0.end_time.prefix(5)) }  // swiftlint:disable:this line_length no_magic_numbers
      let resolvedNote = editResult.noteWasEdited ? editResult.note : currentShift?.note  // swiftlint:disable:this explicit_type_interface line_length

      if editResult.isVirtualShiftConversion {
        // Virtual shift conversion:
        // 1. Add exclusion to the recurring shift for the original date
        // 2. Create a new regular shift with the edited values
        dashboardViewModelLogger.info("🔄 Converting virtual shift to regular shift")

        // Get user ID
        guard let recurringId = editResult.recurringId,
          let userId = cachedUserId
        else {
          dashboardViewModelLogger.error("Missing recurringId or userId for virtual shift conversion")
          throw ShiftSaveError.missingRecurringInfo
        }

        let recurringShift =  // swiftlint:disable:this explicit_type_interface
          recurringShifts.first(where: { $0.id == recurringId })
          ?? recurringShiftsRepository.getRecurringShift(id: recurringId)

        if !hasTimeOrDateChanges, editResult.customSupplements == nil, editResult.noteWasEdited {
          var updatedNotes = recurringShift?.date_specific_notes ?? [:]  // swiftlint:disable:this explicit_type_interface line_length
          if let resolvedNote {
            updatedNotes[editResult.originalDate] = resolvedNote
          } else {
            updatedNotes.removeValue(forKey: editResult.originalDate)
          }

          _ = try await recurringShiftsRepository.updateDateSpecificNotes(
            id: recurringId,
            dateSpecificNotes: updatedNotes
          )
          dashboardViewModelLogger.info("✅ Updated recurring note for \(editResult.originalDate)")
        } else {
          if var updatedNotes = recurringShift?.date_specific_notes {
            updatedNotes.removeValue(forKey: editResult.originalDate)
            _ = try await recurringShiftsRepository.updateDateSpecificNotes(
              id: recurringId,
              dateSpecificNotes: updatedNotes
            )
          }

          // Step 1: Add exclusion for the original date
          try await RecurringShiftsRepository.shared.addExclusion(
            id: recurringId,
            date: editResult.originalDate
          )
          dashboardViewModelLogger.info("✅ Added exclusion for \(editResult.originalDate)")

          let sourceJobId =  // swiftlint:disable:this explicit_type_interface
            displayedMonthShifts.first(where: { $0.id == editResult.shiftId })?.shift.job_id
            ?? recurringShifts.first(where: { $0.id == recurringId })?.job_id

          // Step 2: Create a new regular shift with the edited values
          _ = try await shiftsRepository.createShift(
            userId: userId,
            jobId: sourceJobId,
            shiftDate: newDate,
            startTime: editResult.startTime,
            endTime: editResult.endTime,
            note: resolvedNote,
            customSupplements: editResult.customSupplements
          )
          dashboardViewModelLogger.info("✅ Created new shift on \(editResult.shiftDate)")

          if var updatedNotes = recurringShift?.date_specific_notes {
            updatedNotes.removeValue(forKey: editResult.originalDate)
            _ = try await recurringShiftsRepository.updateDateSpecificNotes(
              id: recurringId,
              dateSpecificNotes: updatedNotes
            )
          }
        }

      } else {
        // Regular shift update - just update the existing shift
        _ = try await shiftsRepository.updateShift(
          id: editResult.shiftId,
          shiftDate: newDate,
          startTime: editResult.startTime,
          endTime: editResult.endTime,
          note: editResult.note,
          noteWasEdited: editResult.noteWasEdited,
          customSupplements: editResult.customSupplements
        )
        dashboardViewModelLogger.info("✅ Updated shift \(editResult.shiftId)")
      }

      // Reload to show the changes
      await reloadFromLocal()

      // Post notification for other views
      notifyShiftsDidChange(
        context: shiftChangeContext(
          for: editResult,
          existingShift: currentShift
        ))  // swiftlint:disable:this multiline_arguments_brackets

    } catch {
      dashboardViewModelLogger.error("❌ Failed to update shift: \(error.localizedDescription)")
      throw error
    }
  }

  func updateShiftPause(_ editResult: ShiftPauseEditResult) async {  // swiftlint:disable:this cyclomatic_complexity explicit_acl function_body_length line_length type_contents_order
    guard !isUpdatingShift else { return }  // swiftlint:disable:this conditional_returns_on_newline

    isUpdatingShift = true
    defer { isUpdatingShift = false }

    dashboardViewModelLogger.info("⏸️ Updating shift pause windows")
    let changeContext: ShiftChangeContext

    switch editResult.target {
    case .standalone(let shiftId):
      if let shift = displayedMonthShifts.first(where: { $0.id == shiftId }) {
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

      case .recurringOccurrence(let recurringId, let date):  // swiftlint:disable:this pattern_matching_keywords
        guard
          let recurringShift = recurringShifts.first(where: { $0.id == recurringId })
            ?? recurringShiftsRepository.getRecurringShift(id: recurringId)
        else {
          dashboardViewModelLogger.error("Recurring shift not found for pause update: \(recurringId)")
          return
        }

        var updatedPauseWindows = recurringShift.date_specific_pause_windows ?? [:]  // swiftlint:disable:this explicit_type_interface line_length
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
      dashboardViewModelLogger.error("❌ Failed to update shift pause windows: \(error.localizedDescription)")
    }
  }

  func ensureCachedUserId() async -> String? {  // swiftlint:disable:this type_contents_order
    if let cachedUserId, !cachedUserId.isEmpty {
      return cachedUserId
    }

    // Use session-derived user ID for clock actions to avoid stale settings/coordinator
    // values during reload/account-context transitions.
    cachedUserId = try? await getCurrentUserId()
    return cachedUserId
  }

  func defaultJobId(for userId: String) -> String? {  // swiftlint:disable:this type_contents_order
    if displayJobs.isEmpty {
      displayJobs = jobsRepository.getNonDeletedJobs(for: userId)
    }
    let activeJobs = displayJobs.filter { $0.archived_at == nil && $0.deleted_at == nil }  // swiftlint:disable:this explicit_type_interface line_length
    return activeJobs.first(where: \.is_default)?.id ?? activeJobs.first?.id
  }
}
