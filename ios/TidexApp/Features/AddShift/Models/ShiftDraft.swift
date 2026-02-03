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

    /// Selected dates for single mode (ISO format YYYY-MM-DD)
    var selectedDates: [String]

    /// Selected weekdays for recurring mode (weekday "0"-"6" -> anchor ISO date)
    var selectedDays: [String: String]

    /// Repeat interval for recurring mode (0 = weekly, 1 = biweekly, etc.)
    var repeatInterval: Int

    /// End condition for recurring mode
    var endCondition: EndCondition?

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
            return !selectedDates.isEmpty || startTime != nil || endTime != nil
        case .recurring:
            return !selectedDays.isEmpty || startTime != nil || endTime != nil
        }
    }
}
