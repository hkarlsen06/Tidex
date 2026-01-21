import Foundation

// MARK: - Calendar Day Info

/// Represents a single day cell in a calendar grid
/// Shared across all calendar views (Shifts, Add Shift, Friends)
struct CalendarDayInfo: Identifiable, Equatable {
    let id: Int
    let dayNumber: Int
    let dateISO: String?
    let weekNumber: Int?  // ISO week number (only on Mondays)
    let isOutsideMonth: Bool

    /// Create a day info for a day within the current month
    static func inMonth(id: Int, dayNumber: Int, dateISO: String, weekNumber: Int?) -> CalendarDayInfo {
        CalendarDayInfo(
            id: id,
            dayNumber: dayNumber,
            dateISO: dateISO,
            weekNumber: weekNumber,
            isOutsideMonth: false
        )
    }

    /// Create a day info for a day outside the current month (prev/next month padding)
    static func outsideMonth(id: Int, dayNumber: Int, dateISO: String, weekNumber: Int?) -> CalendarDayInfo {
        CalendarDayInfo(
            id: id,
            dayNumber: dayNumber,
            dateISO: dateISO,
            weekNumber: weekNumber,
            isOutsideMonth: true
        )
    }
}

// MARK: - Hours Data

/// Time range data for displaying shift hours in a calendar cell
struct HoursData: Equatable {
    let start: String
    let end: String
    let crossesMidnight: Bool
}

// MARK: - Calendar View Mode

/// Mode for displaying data in calendar cells (hours or money)
enum CalendarViewMode: String, CaseIterable {
    case hours
    case money

    /// UserDefaults key for persisting view mode
    static let userDefaultsKey = "shifts_calendar_view_mode"

    /// Save the current mode to UserDefaults
    func save() {
        UserDefaults.standard.set(rawValue, forKey: Self.userDefaultsKey)
    }

    /// Load saved mode from UserDefaults (defaults to hours)
    static func load() -> CalendarViewMode {
        guard let rawValue = UserDefaults.standard.string(forKey: userDefaultsKey),
              let mode = CalendarViewMode(rawValue: rawValue) else {
            return .hours
        }
        return mode
    }
}
