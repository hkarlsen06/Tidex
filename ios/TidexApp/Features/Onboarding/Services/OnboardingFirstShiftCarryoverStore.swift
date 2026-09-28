import Foundation

/// Keeps the shift built in the pre-auth simulator so the first real Add screen can start from it.
internal enum OnboardingFirstShiftCarryoverStore {
  private static let key: String = "preAuthSimulatorShift"

  /// Saves the simulator shift. Call when the user taps Add in the simulator.
  internal static func write(
    dates: Set<String>,
    startTime: Date?,
    endTime: Date?,
    defaults: UserDefaults = .standard
  ) {
    let draft = ShiftDraft(
      mode: .single,
      startTime: startTime?.toHourMinuteString(),
      endTime: endTime?.toHourMinuteString(),
      jobId: nil,
      selectedDates: dates.sorted(),
      selectedDays: [:],
      repeatInterval: 1,
      endCondition: nil,
      eventNote: "",
      isEventAllDay: false,
      eventDate: nil,
      eventStartDate: nil,
      eventEndDate: nil,
      eventReminderMinutes: [],
      eventReminderAnchorTime: nil,
      lastModified: Date()
    )
    guard let data = try? JSONEncoder().encode(draft) else { return }
    defaults.set(data, forKey: key)
  }

  /// Turns the simulator shift into the Add screen draft so the Add screen opens pre-filled.
  /// Dates outside the current month are dropped because the simulator only showed the month
  /// the user was in. Returns false when there was nothing to carry over.
  @discardableResult
  internal static func moveToAddShiftDraft(
    now: Date = Date(),
    defaults: UserDefaults = .standard
  ) -> Bool {
    defer { clear(defaults: defaults) }

    guard let data = defaults.data(forKey: key),
      var draft = try? JSONDecoder().decode(ShiftDraft.self, from: data)
    else {
      return false
    }

    let monthPrefix = String(now.toISODateString().prefix(7))
    draft.selectedDates = draft.selectedDates.filter { $0.hasPrefix(monthPrefix) }
    draft.lastModified = now

    guard draft.hasContent, let updated = try? JSONEncoder().encode(draft) else {
      return false
    }

    defaults.set(updated, forKey: ShiftDraft.userDefaultsKey)
    return true
  }

  internal static func clear(defaults: UserDefaults = .standard) {
    defaults.removeObject(forKey: key)
  }
}
