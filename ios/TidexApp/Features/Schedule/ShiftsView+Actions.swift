import Observation
import SwiftUI
import os.log

extension ShiftsView {

  // MARK: - Calendar Share

  func startCalendarShare() {
    Haptics.play(.medium)
    if coordinator.getCurrentUserId() != nil {
      showingShareDestinationPicker = true
    } else {
      showingShareOptions = true
    }
  }

  private func makeShareableCalendar(includeEarnings: Bool) -> ShareableCalendarView {
    ShareableCalendarView(
      shifts: viewModel.shifts,
      year: viewModel.committedYear,
      month: viewModel.committedMonth,
      currency: viewModel.currency,
      includeEarnings: includeEarnings,
      excludedFromTotalIds: viewModel.excludedFromTotalIds,
      colorScheme: colorScheme
    )
  }

  func renderCalendarImage(includeEarnings: Bool) -> UIImage? {
    makeShareableCalendar(includeEarnings: includeEarnings).renderAsImage()
  }

  func makeCalendarImageDraft(for recipient: ShareRecipient) throws
    -> FriendsComposerAttachmentDraft
  {
    guard let image = renderCalendarImage(includeEarnings: recipient.canSeeOwnerEarnings),
      let compressed = ImageCompressor.compress(image)
    else {
      throw CalendarSharePreparationError.unableToPrepareImage
    }

    return .image(ImageAttachment(data: compressed.data, mediaType: compressed.mediaType))
  }

  private enum CalendarSharePreparationError: LocalizedError {
    case unableToPrepareImage

    var errorDescription: String? {
      String(localized: .friendsChatSendToChatPrepareImageFailed)
    }
  }

  // MARK: - Deep Link Handling

  /// Handle pending deep link from widget or notification
  func handleDeepLink(_ deepLink: AppCoordinator.DeepLink?) {
    guard selectedTab == .shifts,
      case .shifts(let dates, let shiftIds, let action) = deepLink
    else {
      return
    }

    let sortedDates = dates?.sorted() ?? []
    let targetShiftIds = Set(shiftIds ?? [])
    let dateISO =
      sortedDates.first
      ?? viewModel.shifts.first(where: { targetShiftIds.contains($0.id) })?.shiftDate
    guard let dateISO else {
      return
    }

    // Avoid processing the same deep link twice
    if highlightedDateISO == dateISO {
      scheduleViewLogger.debug(" Deep link already being processed for: \(dateISO)")
      coordinator.clearPendingDeepLink()
      return
    }

    scheduleViewLogger.debug(" Handling deep link for date: \(dateISO), action: \(action.rawValue)")

    // Store the action to use when selecting the shift
    deepLinkAction = action
    highlightedShiftIds = targetShiftIds
    if action == .highlight {
      showDeepLinkHighlights(for: Set(sortedDates), shiftIds: targetShiftIds)
    }

    // Parse the date to extract year and month
    guard let date = Date.fromISODateString(dateISO) else {
      scheduleViewLogger.debug(" Failed to parse date: \(dateISO)")
      highlightedShiftIds = []
      coordinator.clearPendingDeepLink()
      return
    }

    let calendar = Calendar.gregorianCurrent
    let targetYear = calendar.component(.year, from: date)
    let targetMonth = calendar.component(.month, from: date)

    // Store the date to highlight/select once shifts are loaded
    // This persists across async operations until we successfully show the shift
    highlightedDateISO = dateISO

    // Clear the deep link immediately to prevent MainTabView from re-processing
    coordinator.clearPendingDeepLink()

    navigateToDeepLinkMonth(
      dateISO: dateISO, year: targetYear, month: targetMonth, shiftIds: targetShiftIds)
  }

  private func navigateToDeepLinkMonth(
    dateISO: String,
    year targetYear: Int,
    month targetMonth: Int,
    shiftIds targetShiftIds: Set<String>
  ) {
    // Navigate to the correct month if not already there
    if viewModel.displayYear != targetYear || viewModel.displayMonth != targetMonth {
      scheduleViewLogger.debug(" Navigating to \(targetYear)-\(targetMonth)")
      SharedMonthContext.shared.navigateTo(year: targetYear, month: targetMonth)
      // Shifts will load via the month change subscription
      // The onChange(of: viewModel.shifts) will then call selectShiftFromDeepLink
    } else if !viewModel.shifts.isEmpty {
      // Already on the correct month and shifts are loaded - select immediately
      selectShiftFromDeepLink(dateISO: dateISO, shiftIds: targetShiftIds, shifts: viewModel.shifts)
    }
    // If shifts are empty, the onChange(of: viewModel.shifts) will handle it when they load
  }

  /// Select or highlight shift for the given date once shifts are loaded
  func selectShiftFromDeepLink(
    dateISO: String,
    shiftIds: Set<String>,
    shifts: [ShiftWithComputations]
  ) {
    // Parse target date to verify we're looking at the correct month
    guard let targetDate = Date.fromISODateString(dateISO) else {
      scheduleViewLogger.debug(" Invalid date format: \(dateISO)")
      highlightedDateISO = nil
      highlightedShiftIds = []
      return
    }

    let calendar = Calendar.gregorianCurrent
    let targetYear = calendar.component(.year, from: targetDate)
    let targetMonth = calendar.component(.month, from: targetDate)

    // Make sure we're on the correct committed month before trying to find the shift
    // (committed values indicate data is ready to display)
    guard viewModel.committedYear == targetYear, viewModel.committedMonth == targetMonth else {
      scheduleViewLogger.debug(
        " Not on target month yet (committed: \(viewModel.committedYear)-\(viewModel.committedMonth), target: \(targetYear)-\(targetMonth))"
      )
      // Keep highlightedDateISO - month navigation is still in progress
      return
    }

    let shiftsOnDate = shifts.filter { shift in
      shift.shiftDate == dateISO && (shiftIds.isEmpty || shiftIds.contains(shift.id))
    }

    guard !shiftsOnDate.isEmpty else {
      scheduleViewLogger.debug(" No shifts found for date: \(dateISO) (shifts loaded: \(shifts.count))")
      // Clear highlighted date - we're on the right month but there's no shift
      // This handles the case where the shift was deleted
      highlightedDateISO = nil
      highlightedShiftIds = []
      return
    }

    scheduleViewLogger.debug(
      " Found \(shiftsOnDate.count) shift(s) on \(dateISO), action: \(deepLinkAction.rawValue)")

    // Capture the action before clearing state
    let action = deepLinkAction

    // Clear the highlighted date and reset action since we're handling it now
    highlightedDateISO = nil
    highlightedShiftIds = []
    deepLinkAction = .open  // Reset to default

    Haptics.play(.selection)

    // Only open sheets when action is .open (default behavior from notifications)
    // When action is .highlight (from widgets), show visual highlight instead
    if action == .highlight {
      scheduleViewLogger.debug(" Highlight-only mode - showing visual highlight for \(dateISO)")
      showDeepLinkHighlights(for: [dateISO], shiftIds: shiftIds)
      return
    }

    if shiftsOnDate.count == 1, let shift = shiftsOnDate.first {
      // Single shift - open shift details directly
      selectedShift = shift
    } else {
      // Multiple shifts - open day sheet
      presentDaySheet(
        dateISO: dateISO,
        items: shiftsOnDate.map { DayPresentationItem.shift($0) }
      )
    }
  }

  private func showDeepLinkHighlights(for dates: Set<String>, shiftIds: Set<String>) {
    guard !dates.isEmpty || !shiftIds.isEmpty else {
      return
    }
    deepLinkHighlightClearTask?.cancel()

    MotionTokens.animate(.subtle, reduceMotion: reduceMotion) {
      deepLinkHighlightDates = dates
      highlightedShiftIds = shiftIds
    }

    deepLinkHighlightClearTask = Task { @MainActor in
      do {
        try await Task.sleep(for: .seconds(8))
      } catch {
        return
      }

      MotionTokens.animate(.subtle, reduceMotion: reduceMotion) {
        deepLinkHighlightDates.subtract(dates)
        highlightedShiftIds.subtract(shiftIds)
      }
      deepLinkHighlightClearTask = nil
    }
  }

  // MARK: - Delete Shift

  func deleteShift(_ shift: ShiftWithComputations) async {
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
      AccessibilityNotification.Announcement(String(localized: .shiftsAccessibilityShiftsDeleted))
        .post()

      shiftToDelete = nil
    } catch {
      scheduleViewLogger.error("Failed to delete shift: \(error.localizedDescription)")
      operationErrorMessage = ErrorTranslations.translate(error)
      shiftToDelete = nil
    }
  }

  func deleteEvent(_ event: EventRow) async {
    Haptics.play(.medium)

    do {
      try await viewModel.deleteEvent(event)
      eventToDelete = nil
    } catch {
      scheduleViewLogger.error("Failed to delete event: \(error.localizedDescription)")
      operationErrorMessage = ErrorTranslations.translate(error)
      eventToDelete = nil
    }
  }

  // MARK: - Tap Handlers

  /// Handle shift card tap - simply set the item to present
  /// Using .sheet(item:) guarantees the data is available when sheet shows
  func handleShiftTapped(_ shift: ShiftWithComputations) {
    selectedShift = shift
  }

  func handleEventTapped(_ event: EventRow, startInEditMode: Bool = false) {
    selectedEvent = EventSheetSelection(event: event, startInEditMode: startInEditMode)
  }

  /// Present the items attached to a calendar day without changing selection.
  func presentDayItems(dateISO: String, shifts: [ShiftWithComputations]) {
    let items = viewModel.mixedItems(for: dateISO)

    if items.count == 1, let singleItem = items.first {
      switch singleItem {
      case .shift(let shift):
        selectedShift = shift

      case .event(let event):
        handleEventTapped(event.event)
      }
    } else if !items.isEmpty {
      presentDaySheet(dateISO: dateISO, items: items)
    } else if !shifts.isEmpty {
      presentDaySheet(
        dateISO: dateISO,
        items: shifts.map { DayPresentationItem.shift($0) }
      )
    }
  }

  private func presentDaySheet(dateISO: String, items: [DayPresentationItem]) {
    selectedDaySheetContentHeight = ContentSizedSheetMetrics.estimatedCardListContentHeight(
      cardCount: items.count,
      includesSummaryHeader: false
    )
    selectedDayForSheet = DayItemSelection(dateISO: dateISO, items: items)
  }

  /// Open the selected day's details from the calendar action bar.
  func handleSelectedDayDetails() {
    guard let dateISO = viewModel.selectedDates.first else {
      return
    }
    presentDayItems(dateISO: dateISO, shifts: viewModel.selectedDateShifts)
  }
}
