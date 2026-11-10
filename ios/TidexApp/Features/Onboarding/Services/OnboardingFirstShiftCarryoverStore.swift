import Foundation

/// The shift a user built in the pre-auth simulator. It stays a what-if until the user saves it.
internal struct CarriedDemoShift: Equatable {
  /// Sorted `yyyy-MM-dd` dates.
  internal let dates: [String]
  /// `HH:mm`.
  internal let startTime: String
  /// `HH:mm`. An end at or before the start ends the next day.
  internal let endTime: String
}

/// Keeps the shift built in the pre-auth simulator until the user saves it, declines it or signs out.
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

  /// The carried shift, or nil when there is none or it lacks dates or times.
  internal static func read(defaults: UserDefaults = .standard) -> CarriedDemoShift? {
    guard let draft = storedDraft(defaults: defaults),
      let startTime = draft.startTime,
      let endTime = draft.endTime,
      !draft.selectedDates.isEmpty
    else {
      return nil
    }
    return CarriedDemoShift(
      dates: draft.selectedDates.sorted(), startTime: startTime, endTime: endTime)
  }

  /// Turns the simulator shift into the Add screen draft so the Add screen opens pre-filled
  /// with every carried date. Returns false when there was nothing to carry over.
  @discardableResult
  internal static func moveToAddShiftDraft(
    now: Date = Date(),
    defaults: UserDefaults = .standard
  ) -> Bool {
    defer { clear(defaults: defaults) }

    guard var draft = storedDraft(defaults: defaults) else {
      return false
    }
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

  private static func storedDraft(defaults: UserDefaults) -> ShiftDraft? {
    defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(ShiftDraft.self, from: $0) }
  }
}
