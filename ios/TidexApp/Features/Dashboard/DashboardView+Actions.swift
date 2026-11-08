import SwiftUI

extension DashboardView {

  // MARK: - Shift Operations

  /// Delete a shift (or exclude a virtual shift)
  func deleteShift(_ shift: ShiftWithComputations) async {  // swiftlint:disable:this type_contents_order
    Haptics.play(.medium)

    do {
      if shift.isVirtual {
        // Virtual shift: add date to exclusions of parent recurring shift
        guard let recurringId = shift.shift.recurring_id else {
          return
        }
        try await RecurringShiftsRepository.shared.addExclusion(
          id: recurringId,
          date: shift.shiftDate
        )
      } else {
        // Regular shift: mark for deletion
        try await ShiftsRepository.shared.deleteShift(id: shift.id)
      }

      // Post notification for other views
      NotificationCenter.default.postShiftsDidChange(
        context: .affecting(isoDate: shift.shiftDate)
      )

    } catch {
      operationErrorMessage = ErrorTranslations.translate(error)
    }

    shiftToDelete = nil
  }

  func deleteEvent(_ event: EventRow) async {  // swiftlint:disable:this type_contents_order
    Haptics.play(.medium)

    do {
      try await viewModel.deleteEvent(event)
      eventToDelete = nil
    } catch {
      operationErrorMessage = ErrorTranslations.translate(error)
      eventToDelete = nil
    }
  }

  /// Update a recurring shift pattern
  func updateRecurringShift(_ editResult: RecurringShiftEditResult) async {  // swiftlint:disable:this line_length type_contents_order
    do {
      _ = try await RecurringShiftsRepository.shared.updateRecurringShift(
        id: editResult.recurringId,
        startTime: editResult.startTime,
        endTime: editResult.endTime,
        repeatIntervalWeeks: editResult.repeatIntervalWeeks,
        selectedDays: editResult.selectedDays,
        endCondition: editResult.endCondition,
        exclusions: editResult.exclusions
      )

      // Post notification for other views
      NotificationCenter.default.postShiftsDidChange(context: .fullReload)

    } catch {
      operationErrorMessage = ErrorTranslations.translate(error)
    }
  }

  /// Delete a recurring shift pattern
  func deleteRecurringShift(_ recurringId: String) async {  // swiftlint:disable:this type_contents_order
    do {
      try await RecurringShiftsRepository.shared.deleteRecurringShift(id: recurringId)

      // Post notification for other views
      NotificationCenter.default.postShiftsDidChange(context: .fullReload)

    } catch {
      operationErrorMessage = ErrorTranslations.translate(error)
    }
  }
}
