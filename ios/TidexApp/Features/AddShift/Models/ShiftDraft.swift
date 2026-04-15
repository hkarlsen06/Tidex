import Foundation

/// Persisted draft of an in-progress shift form
/// Used to restore form state when the Add Shift view is revisited
struct ShiftDraft: Codable {
  /// Current form mode (single or recurring)
  var mode: AddShiftMode

  /// Start time as ISO string (HH:mm)
  var startTime: String?

  /// End time as ISO string (HH:mm)
  var endTime: String?

  /// Selected job id for shift creation context
  var jobId: String?

  /// Selected dates for single mode (ISO format YYYY-MM-DD)
  var selectedDates: [String]

  /// Selected weekdays for recurring mode (weekday "0"-"6" -> anchor ISO date)
  var selectedDays: [String: String]

  /// Repeat interval for recurring mode (0 = weekly, 1 = biweekly, etc.)
  var repeatInterval: Int

  /// End condition for recurring mode
  var endCondition: EndCondition?

  /// Event note text.
  var eventNote: String

  /// Event all-day toggle.
  var isEventAllDay: Bool

  /// Timed event single date (ISO format YYYY-MM-DD).
  var eventDate: String?

  /// All-day event start date (ISO format YYYY-MM-DD).
  var eventStartDate: String?

  /// All-day event end date (ISO format YYYY-MM-DD).
  var eventEndDate: String?

  /// Event reminder offsets in minutes before the event.
  var eventReminderMinutes: [Int]

  /// All-day event reminder anchor time (HH:mm).
  var eventReminderAnchorTime: String?

  /// When the draft was last modified
  var lastModified: Date

  /// Default expiry duration (1 hour)
  static let expiryDuration: TimeInterval = 3600

  /// UserDefaults key for storing the draft
  static let userDefaultsKey = "shift_draft"

  /// Check if the draft has expired
  var isExpired: Bool {
    Date().timeIntervalSince(lastModified) > Self.expiryDuration
  }

  /// Check if the draft has any meaningful data worth restoring
  var hasContent: Bool {
    switch mode {
    case .single:
      return !selectedDates.isEmpty || startTime != nil || endTime != nil || jobId != nil
    case .recurring:
      return !selectedDays.isEmpty || startTime != nil || endTime != nil || jobId != nil
    case .events:
      let defaultEventDate = Date().toISODateString()
      return !eventNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || eventDate != defaultEventDate
        || eventStartDate != defaultEventDate
        || eventEndDate != defaultEventDate
        || isEventAllDay
        || startTime != nil || endTime != nil
        || !eventReminderMinutes.isEmpty
        || eventReminderAnchorTime != nil
    }
  }
}

extension ShiftDraft {
  private enum CodingKeys: String, CodingKey {
    case mode
    case startTime
    case endTime
    case jobId
    case selectedDates
    case selectedDays
    case repeatInterval
    case endCondition
    case eventNote
    case isEventAllDay
    case eventDate
    case eventStartDate
    case eventEndDate
    case eventReminderMinutes
    case eventReminderAnchorTime
    case lastModified
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    mode = try container.decode(AddShiftMode.self, forKey: .mode)
    startTime = try container.decodeIfPresent(String.self, forKey: .startTime)
    endTime = try container.decodeIfPresent(String.self, forKey: .endTime)
    jobId = try container.decodeIfPresent(String.self, forKey: .jobId)
    selectedDates = try container.decodeIfPresent([String].self, forKey: .selectedDates) ?? []
    selectedDays =
      try container.decodeIfPresent([String: String].self, forKey: .selectedDays) ?? [:]
    repeatInterval = try container.decodeIfPresent(Int.self, forKey: .repeatInterval) ?? 1
    endCondition = try container.decodeIfPresent(EndCondition.self, forKey: .endCondition)
    eventNote = try container.decodeIfPresent(String.self, forKey: .eventNote) ?? ""
    isEventAllDay = try container.decodeIfPresent(Bool.self, forKey: .isEventAllDay) ?? false
    eventDate = try container.decodeIfPresent(String.self, forKey: .eventDate)
    eventStartDate = try container.decodeIfPresent(String.self, forKey: .eventStartDate)
    eventEndDate = try container.decodeIfPresent(String.self, forKey: .eventEndDate)
    eventReminderMinutes =
      try container.decodeIfPresent([Int].self, forKey: .eventReminderMinutes) ?? []
    eventReminderAnchorTime =
      try container.decodeIfPresent(String.self, forKey: .eventReminderAnchorTime)
    lastModified = try container.decode(Date.self, forKey: .lastModified)
  }
}
