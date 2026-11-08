import AppIntents
import Combine
import Foundation
import Observation
import SwiftUI
import os.log

extension AddShiftViewModel {

  // MARK: - Draft Persistence Methods

  /// Schedule a debounced draft save
  func scheduleDraftSave() {
    // Cancel any pending save
    draftSaveTask?.cancel()

    // Schedule new save with debounce delay
    draftSaveTask = Task { [weak self] in
      do {
        try await Task.sleep(for: .nanoseconds(Int64(Self.draftSaveDebounceDelay)))

        // Check if cancelled during sleep
        guard !Task.isCancelled else {
          return
        }

        await MainActor.run {
          self?.saveDraft()
        }
      } catch {
        // Task was cancelled - this is expected
      }
    }
  }

  /// Save the current form state as a draft
  func saveDraft() {
    let draft = ShiftDraft(
      mode: mode,
      startTime: startTime.map { formatTimeAsHHmm($0) },
      endTime: endTimeString.isEmpty ? nil : endTimeString,
      jobId: selectedJobId,
      selectedDates: Array(selectedDates),
      selectedDays: selectedDays,
      repeatInterval: repeatInterval,
      endCondition: endCondition,
      eventNote: eventNote,
      isEventAllDay: isEventAllDay,
      eventDate: eventDate.toISODateString(),
      eventStartDate: eventStartDate.toISODateString(),
      eventEndDate: eventEndDate.toISODateString(),
      eventReminderMinutes: eventReminderTimes,
      eventReminderAnchorTime: eventReminderAnchorTimeString,
      lastModified: Date()
    )

    // Only save if there's meaningful content
    guard draft.hasContent else {
      clearDraft()
      return
    }

    if let data = try? JSONEncoder().encode(draft) {
      draftDefaults.set(data, forKey: ShiftDraft.userDefaultsKey)
      addShiftViewModelLogger.debug("Saved draft: mode=\(draft.mode.rawValue), dates=\(draft.selectedDates.count)")
    }
  }

  /// Load a saved draft if it exists and hasn't expired
  func loadDraft() {
    guard let data = draftDefaults.data(forKey: ShiftDraft.userDefaultsKey),
      let draft = try? JSONDecoder().decode(ShiftDraft.self, from: data),
      !draft.isExpired,
      draft.hasContent
    else {
      return
    }

    // Restore form state from draft
    mode = draft.mode
    selectedJobId = draft.jobId

    // Restore times
    if let startTimeString = draft.startTime {
      startTime = parseTimeFromHHmm(startTimeString)
    }
    if let endTimeString = draft.endTime {
      endTime = parseTimeFromHHmm(endTimeString)
    }

    // Restore mode-specific data
    switch mode {
    case .single:
      selectedDates = Set(draft.selectedDates)

    case .recurring:
      selectedDays = draft.selectedDays
      repeatInterval = draft.repeatInterval
      endCondition = draft.endCondition

    case .events:
      eventNote = draft.eventNote
      isEventAllDay = draft.isEventAllDay
      if let eventDate = draft.eventDate.flatMap({ Date.fromISODateString($0) }) {
        self.eventDate = eventDate
      }
      if let eventStartDate = draft.eventStartDate.flatMap({ Date.fromISODateString($0) }) {
        self.eventStartDate = eventStartDate
      }
      if let eventEndDate = draft.eventEndDate.flatMap({ Date.fromISODateString($0) }) {
        self.eventEndDate = eventEndDate
      }
      eventReminderTimes = draft.eventReminderMinutes
      if let eventReminderAnchorTime = draft.eventReminderAnchorTime {
        self.eventReminderAnchorTime = parseTimeFromHHmm(eventReminderAnchorTime)
      }
      eventRangeAnchorDate = isEventAllDay ? self.eventStartDate : self.eventDate
    }

    addShiftViewModelLogger.info(
      """
      Loaded draft: mode=\(draft.mode.rawValue), dates=\(draft.selectedDates.count), \
      days=\(draft.selectedDays.count), jobSelected=\(draft.jobId != nil)
      """
    )
  }

  /// Clear the saved draft
  func clearDraft() {
    draftSaveTask?.cancel()
    draftSaveTask = nil
    draftDefaults.removeObject(forKey: ShiftDraft.userDefaultsKey)
    addShiftViewModelLogger.debug("Cleared draft")
  }

  /// Start fresh - clear all form data and the draft
  func startFresh() {
    guard !isLoading else { return }
    clearDraft()
    clearSelectedDates()
    clearAnchors()
    startTime = nil
    endTime = nil
    repeatInterval = 1
    endCondition = nil
    eventNote = ""
    isEventAllDay = false
    let defaultEventDate = Self.defaultEventDate()
    eventDate = defaultEventDate
    eventStartDate = defaultEventDate
    eventEndDate = defaultEventDate
    eventReminderTimes = []
    eventReminderAnchorTime = nil
    eventRangeAnchorDate = defaultEventDate
    error = nil

    // Haptic feedback
    let generator = UIImpactFeedbackGenerator(style: .medium)
    generator.impactOccurred()
  }

  /// Parse HH:mm string to Date (supports "24:00" as midnight)
  private func parseTimeFromHHmm(_ timeString: String) -> Date? {
    // Handle "24:00" which DateFormatter can't parse
    let is24 = timeString == "24:00"
    let parseable = is24 ? "00:00" : timeString

    guard let time = FormatterCache.hourMinuteFormatter().date(from: parseable) else {
      return nil
    }

    // Transfer hour and minute to today's date
    let calendar = Calendar.gregorianCurrent
    var components = calendar.dateComponents([.year, .month, .day], from: Date())
    let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
    components.hour = timeComponents.hour
    components.minute = timeComponents.minute

    return calendar.date(from: components)
  }

  func syncCalendarSelectionForModeTransition(
    from previousMode: AddShiftMode,
    to newMode: AddShiftMode
  ) {
    switch (previousMode, newMode) {
    case (.single, .events):
      syncSingleSelectionIntoEvent()
      didEditEventCalendarSinceEnteringEvents = false

    case (.events, .single):
      if didEditEventCalendarSinceEnteringEvents || selectedDates.isEmpty {
        syncEventSelectionIntoSingle()
      }
      didEditEventCalendarSinceEnteringEvents = false

    default:
      if newMode != .events {
        didEditEventCalendarSinceEnteringEvents = false
      }
    }
  }

  private func syncSingleSelectionIntoEvent() {
    guard
      let earliestDate =
        selectedDates
        .compactMap({ Date.fromISODateString($0) })
        .map({ Calendar.gregorianCurrent.startOfDay(for: $0) })
        .min()
    else {
      return
    }

    withCalendarSelectionModeSync {
      if isEventAllDay {
        eventStartDate = earliestDate
        eventEndDate = earliestDate
      }
      eventDate = earliestDate
      eventRangeAnchorDate = earliestDate
    }
  }

  private func syncEventSelectionIntoSingle() {
    let carriedDates: Set<String>
    if isEventAllDay {
      carriedDates = contiguousDateSelection(from: eventStartDate, to: eventEndDate)
    } else {
      carriedDates = [eventDate.toISODateString()]
    }

    guard !carriedDates.isEmpty else {
      return
    }
    selectedDates = carriedDates
  }

  private func withCalendarSelectionModeSync(_ updates: () -> Void) {
    isSyncingCalendarSelectionAcrossModes = true
    updates()
    isSyncingCalendarSelectionAcrossModes = false
  }

  func markEventCalendarSelectionEdited() {
    guard mode == .events, !isSyncingCalendarSelectionAcrossModes else {
      return
    }
    didEditEventCalendarSinceEnteringEvents = true
  }

  func contiguousDateSelection(from start: Date, to end: Date) -> Set<String> {
    let calendar = Calendar.gregorianCurrent
    let normalizedStart = calendar.startOfDay(for: min(start, end))
    let normalizedEnd = calendar.startOfDay(for: max(start, end))

    var dates: Set<String> = []
    var current = normalizedStart
    while current <= normalizedEnd {
      dates.insert(current.toISODateString())
      guard let next = calendar.date(byAdding: .day, value: 1, to: current) else {
        break
      }
      current = next
    }
    return dates
  }
}
