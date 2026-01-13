import Foundation

// MARK: - Date + Tidex Extensions

extension Date {
    // MARK: - Timezone

    /// Europe/Oslo timezone (Norwegian timezone)
    static let osloTimeZone = TimeZone(identifier: "Europe/Oslo")!

    // MARK: - ISO Date Formatting

    /// Format date as ISO date string (YYYY-MM-DD)
    func toISODateString(in timeZone: TimeZone = Date.osloTimeZone) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: self)
    }

    /// Parse ISO date string (YYYY-MM-DD) to Date
    static func fromISODateString(_ string: String, in timeZone: TimeZone = Date.osloTimeZone) -> Date? {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: string)
    }

    /// Parse ISO date string as UTC
    static func fromISODateStringUTC(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: string)
    }

    // MARK: - Year/Month Components

    /// Get year and month components
    func yearMonth(in timeZone: TimeZone = Date.osloTimeZone) -> (year: Int, month: Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month], from: self)
        return (year: components.year ?? 1970, month: components.month ?? 1)
    }

    /// Get current year and month
    static func currentYearMonth(in timeZone: TimeZone = Date.osloTimeZone) -> (year: Int, month: Int) {
        Date().yearMonth(in: timeZone)
    }

    /// Get previous month (handles year rollover)
    static func previousYearMonth(from current: (year: Int, month: Int)) -> (year: Int, month: Int) {
        if current.month == 1 {
            return (year: current.year - 1, month: 12)
        }
        return (year: current.year, month: current.month - 1)
    }

    // MARK: - Month Boundaries

    /// Get first day of month as ISO date string
    static func firstDayOfMonth(year: Int, month: Int) -> String {
        String(format: "%04d-%02d-01", year, month)
    }

    /// Get last day of month as ISO date string
    static func lastDayOfMonth(year: Int, month: Int) -> String {
        let lastDay = daysInMonth(year: year, month: month)
        return String(format: "%04d-%02d-%02d", year, month, lastDay)
    }

    /// Get number of days in a month
    static func daysInMonth(year: Int, month: Int) -> Int {
        var components = DateComponents()
        components.year = year
        components.month = month + 1
        components.day = 0
        let calendar = Calendar(identifier: .gregorian)
        guard let date = calendar.date(from: components) else { return 30 }
        return calendar.component(.day, from: date)
    }

    /// Get Date object for first day of month
    static func firstDayOfMonthDate(year: Int, month: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        return Calendar(identifier: .gregorian).date(from: components) ?? Date()
    }

    /// Get Date object for last day of month
    static func lastDayOfMonthDate(year: Int, month: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month + 1
        components.day = 0
        return Calendar(identifier: .gregorian).date(from: components) ?? Date()
    }

    // MARK: - Weekday

    /// Get weekday (1-7 where 1=Monday, 7=Sunday) matching TypeScript conventions
    var tidexWeekday: Int {
        let calendar = Calendar(identifier: .gregorian)
        let weekday = calendar.component(.weekday, from: self)
        // Calendar: 1=Sunday, 2=Monday, ..., 7=Saturday
        // Tidex: 1=Monday, ..., 7=Sunday
        return weekday == 1 ? 7 : weekday - 1
    }

    /// Get weekday from ISO date string (1-7 where 1=Monday, 7=Sunday)
    static func weekdayFromISO(_ dateString: String) -> Int {
        guard let date = fromISODateStringUTC(dateString) else { return 1 }
        return date.tidexWeekday
    }

    /// Get weekday key (0-6 where 0=Sunday) for recurring shift selected_days
    var recurringWeekdayKey: Int {
        let calendar = Calendar(identifier: .gregorian)
        return calendar.component(.weekday, from: self) - 1
    }

    // MARK: - Comparison

    /// Check if this date is today (in Oslo timezone)
    var isToday: Bool {
        let todayString = Date().toISODateString()
        return toISODateString() == todayString
    }

    /// Check if this date is in the past (before today)
    var isPast: Bool {
        let todayString = Date().toISODateString()
        return toISODateString() < todayString
    }

    /// Check if this date is in the future (after today)
    var isFuture: Bool {
        let todayString = Date().toISODateString()
        return toISODateString() > todayString
    }

    // MARK: - Days Between

    /// Calculate days between two ISO date strings
    static func daysBetween(_ from: String, _ to: String) -> Int {
        guard let fromDate = fromISODateStringUTC(from),
              let toDate = fromISODateStringUTC(to) else {
            return 0
        }
        let seconds = toDate.timeIntervalSince(fromDate)
        return Int(seconds / 86400)
    }
}

// MARK: - Today ISO Helper

/// Get today's date as ISO string in Oslo timezone
func todayISO() -> String {
    Date().toISODateString()
}
