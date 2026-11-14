import Combine
import Foundation
import Observation
import UIKit
import os.log

extension ShiftsViewModel {

  // MARK: - Selection Actions

  /// Handle a tap on a day that has shifts or events.
  /// Outside selection mode a tap opens the day, so this returns `true` and leaves the
  /// selection alone. In selection mode it toggles the day and returns `false`.
  @discardableResult
  func handleDayTapped(dateISO: String, shiftsOnDay: [ShiftWithComputations]) -> Bool {
    // Reset delete confirmation on any tap
    confirmingDelete = false

    guard isSelectionModeEnabled else {
      return true
    }

    // If tapping a date with no shifts, ignore (don't clear selection)
    guard !shiftsOnDay.isEmpty else {
      return false
    }

    if selectedDates.contains(dateISO) {
      selectedDates.remove(dateISO)
    } else {
      selectedDates.insert(dateISO)
    }
    return false
  }

  /// Long press + drag on the calendar replaces the selection.
  func applyDragSelection(_ dates: Set<String>) {
    confirmingDelete = false
    selectedDates = dates
  }

  /// Clear all selection state
  func clearSelection() {
    selectedDates.removeAll()
    confirmingDelete = false
    // Also clear copy/move state
    isCopyMode = false
    isMoveMode = false
    copyTargetDates.removeAll()
    shiftForOperation = nil
  }

  /// Delete all shifts for selected dates. Throws so the screen can show the failure.
  func deleteSelectedShifts() async throws {
    let shiftsToDelete = shifts.filter { selectedDates.contains($0.shiftDate) }
    guard !shiftsToDelete.isEmpty else {
      return
    }

    isDeleting = true
    defer {
      isDeleting = false
    }

    do {
      let virtualExclusions = shiftsToDelete.compactMap {
        shift -> (recurringId: String, date: String)? in
        guard shift.isVirtual, let recurringId = shift.shift.recurring_id else {
          return nil
        }
        return (recurringId, shift.shiftDate)
      }
      let virtualExclusionsByRecurringId = Dictionary(
        grouping: virtualExclusions,
        by: { $0.recurringId }
      ).mapValues { exclusions in
        exclusions.map(\.date)
      }
      let regularShiftIds = shiftsToDelete.filter { !$0.isVirtual }.map(\.id)

      for (recurringId, dates) in virtualExclusionsByRecurringId {
        try await recurringShiftsRepository.addExclusions(
          id: recurringId,
          dates: dates
        )
      }

      if !regularShiftIds.isEmpty {
        try await shiftsRepository.deleteShifts(ids: regularShiftIds)
      }

      clearSelection()
      await reloadFromLocal()
      notifyShiftsDidChange(
        context: .affecting(
          isoDates: shiftsToDelete.map(\.shiftDate)
        ))

      // Play deletion feedback
      Haptics.playShiftDeleted()
      UIAccessibility.post(
        notification: .announcement, argument: String(localized: .shiftsAccessibilityShiftsDeleted))
    } catch {
      kScheduleLogger.error("Failed to delete shifts: \(error.localizedDescription)")
      throw error
    }
  }

  // MARK: - Copy/Move Actions

  func initiateCopy(of shift: ShiftWithComputations) {
    shiftForOperation = shift
    copyTargetDates.removeAll()
    isCopyMode = true
    isMoveMode = false
    confirmingDelete = false
  }

  func initiateMove(of shift: ShiftWithComputations) {
    shiftForOperation = shift
    copyTargetDates.removeAll()
    isCopyMode = false
    isMoveMode = true
    confirmingDelete = false
  }

  /// Cancel copy/move mode and return to normal selection
  func cancelCopyMoveMode() {
    isCopyMode = false
    isMoveMode = false
    copyTargetDates.removeAll()
    shiftForOperation = nil
    // Keep the original selection so user can try again
  }

  /// Toggle a target date while choosing where to copy the selected shift.
  /// - Parameter targetDateISO: The ISO date string to copy to.
  func toggleCopyTargetDate(_ targetDateISO: String) {
    guard isCopyMode, let sourceShift = shiftForOperation else {
      return
    }
    guard targetDateISO != sourceShift.shiftDate else {
      return
    }

    if copyTargetDates.contains(targetDateISO) {
      copyTargetDates.remove(targetDateISO)
    } else {
      copyTargetDates.insert(targetDateISO)
    }
  }

  /// Finish copy mode by copying the selected shift to all chosen target dates. Throws so the
  /// screen can show the failure, such as a shift whose job is archived.
  func finishCopyToSelectedDates() async throws {
    // Prevent duplicate taps
    guard !isCopying else {
      return
    }

    guard isCopyMode,
      let sourceShift = shiftForOperation,
      !copyTargetDates.isEmpty
    else { return }

    isCopying = true
    defer {
      isCopying = false
    }

    do {
      // Get current user ID - use cached value or fall back to AppCoordinator
      // This guards against race conditions if user signs out mid-operation
      let userId = cachedUserId ?? AppCoordinator.shared.getCurrentUserId()
      guard let userId else {
        throw ShiftsError.notAuthenticated
      }

      let sortedTargetDates = copyTargetDates.sorted()
      try await createCopies(of: sourceShift, on: sortedTargetDates, userId: userId)

      kScheduleLogger.info(
        "Copied shift from \(sourceShift.shiftDate) to \(self.copyTargetDates.count) target dates")

      // Exit copy mode and clear selection
      isCopyMode = false
      copyTargetDates.removeAll()
      shiftForOperation = nil
      clearSelection()

      // Reload to show the new shift
      await reloadFromLocal()
      notifyShiftsDidChange(context: .affecting(isoDates: sortedTargetDates))
      UIAccessibility.post(
        notification: .announcement, argument: String(localized: .shiftsAccessibilityShiftsCopied))

    } catch {
      kScheduleLogger.error("Failed to copy shift: \(error.localizedDescription)")
      throw error
    }
  }

  /// Create a shift with the same times and supplements on each target date.
  private func createCopies(
    of sourceShift: ShiftWithComputations,
    on targetDatesISO: [String],
    userId: String
  ) async throws {
    for targetDateISO in targetDatesISO {
      guard let targetDate = Date.fromISODateString(targetDateISO) else {
        kScheduleLogger.error("Invalid target date: \(targetDateISO)")
        continue
      }

      // Create a new shift with the same times at the target date
      _ = try await shiftsRepository.createShift(
        userId: userId,
        jobId: sourceShift.shift.job_id,
        shiftDate: targetDate,
        startTime: sourceShift.startTime,
        endTime: sourceShift.endTime,
        customSupplements: sourceShift.shift.custom_supplements
      )
    }
  }

  func computeCopyPreviewEarnings(
    for dateISO: String,
    sourceShift: ShiftWithComputations
  ) -> CalendarEarningsData? {
    let jobId = sourceShift.shift.job_id
    let scopedSnapshots = snapshotsForJob(jobId)

    let wageSnapshot = SnapshotsService.snapshotForDate(dateISO, from: scopedSnapshots)
    let payoutDate = payoutSchedule(for: jobId).payoutDate(for: dateISO)
    let taxSnapshot = SnapshotsService.snapshotForDate(payoutDate, from: scopedSnapshots)

    let shift = ShiftRow(
      id: "copy-preview-\(dateISO)",
      user_id: sourceShift.shift.user_id,
      job_id: jobId,
      shift_date: dateISO,
      start_time: sourceShift.startTime,
      end_time: sourceShift.endTime,
      custom_supplements: sourceShift.shift.custom_supplements
    )

    let computed = PayrollCalculator.computeShift(shift, snapshot: wageSnapshot)
    let taxEnabled = taxSnapshot?.effectiveTaxEnabled ?? false
    let net = computed.netPay(
      taxEnabled: taxEnabled,
      taxPercentage: taxSnapshot?.effectiveTaxPercentage ?? 0
    )

    return CalendarEarningsData(net: net, gross: computed.gross, hasTaxEnabled: taxEnabled)
  }

  private func snapshotsForJob(_ jobId: String?) -> [WageSnapshot] {
    let jobSnapshots = snapshots.filter { $0.job_id == jobId }
    if !jobSnapshots.isEmpty {
      return jobSnapshots
    }

    let defaultJobId = activeJobs.first(where: \.is_default)?.id  // swiftlint:disable:this explicit_type_interface
    if defaultJobId == jobId {
      return snapshots.filter { $0.job_id == nil }
    }

    return []
  }

  private func payoutSchedule(for jobId: String?) -> PayoutSchedule {
    PayoutSchedule(
      job: jobId.flatMap { id in activeJobs.first { $0.id == id } },
      fallbackPayrollDay: settings?.effectivePayrollDay ?? 1
    )
  }

  /// Handle date tap when in move mode - move shift to the tapped date
  /// - Parameter targetDateISO: The ISO date string to move to
  func handleMoveToDate(_ targetDateISO: String) async throws {
    // Prevent duplicate taps
    guard !isMoving else {
      return
    }

    guard isMoveMode,
      let sourceShift = shiftForOperation
    else { return }

    // Don't move to the same date
    guard targetDateISO != sourceShift.shiftDate else {
      cancelCopyMoveMode()
      return
    }

    // Virtual shifts (from recurring patterns) cannot be moved
    if sourceShift.isVirtual {
      kScheduleLogger.warning("Cannot move virtual shift - must move the recurring pattern")
      cancelCopyMoveMode()
      return
    }

    isMoving = true

    do {
      // Parse the target date
      guard let targetDate = Date.fromISODateString(targetDateISO) else {
        kScheduleLogger.error("Invalid target date: \(targetDateISO)")
        isMoving = false
        cancelCopyMoveMode()
        return
      }

      // Update the shift's date
      _ = try await shiftsRepository.updateShift(
        id: sourceShift.id,
        shiftDate: targetDate
      )

      kScheduleLogger.info("Moved shift from \(sourceShift.shiftDate) to \(targetDateISO)")

      // Exit move mode and clear selection
      isMoveMode = false
      shiftForOperation = nil
      clearSelection()

      // Reload to show the moved shift
      await reloadFromLocal()
      notifyShiftsDidChange(
        context: .affecting(
          isoDates: [sourceShift.shiftDate, targetDateISO]
        ))
      UIAccessibility.post(
        notification: .announcement, argument: String(localized: .shiftsAccessibilityShiftsMoved))

    } catch {
      kScheduleLogger.error("Failed to move shift: \(error.localizedDescription)")
      isMoving = false
      throw error
    }

    isMoving = false
  }
}
