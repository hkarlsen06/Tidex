import Foundation
import SwiftUI

// MARK: - Calendar Grid Helper

/// Static helper functions for calendar grid computations
/// Centralizes the date calculation logic shared across all calendar views
enum CalendarGridHelper {
    private static let calendar = Calendar.current

    // MARK: - Days in Month

    /// Generate day info array for a given month
    /// - Parameters:
    ///   - year: The year (e.g., 2025)
    ///   - month: The month number (1-12)
    ///   - selectedDates: Optional set of selected date ISO strings (for marking selection state)
    /// - Returns: Array of CalendarDayInfo for the grid (includes padding days from prev/next months)
    static func daysInMonth(
        year: Int,
        month: Int,
        selectedDates: Set<String>? = nil
    ) -> [CalendarDayInfo] {
        var days: [CalendarDayInfo] = []

        // Get first day of month
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        guard let firstOfMonth = calendar.date(from: components) else { return days }

        // Get weekday of first day (1 = Sunday, 7 = Saturday)
        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)

        // Convert to Monday-start (0 = Monday, 6 = Sunday)
        let startOffset = (firstWeekday + 5) % 7

        // Get number of days in month
        guard let range = calendar.range(of: .day, in: .month, for: firstOfMonth) else { return days }

        // Get last day of previous month for "outside days"
        guard let previousMonth = calendar.date(byAdding: .month, value: -1, to: firstOfMonth),
              let previousMonthRange = calendar.range(of: .day, in: .month, for: previousMonth)
        else { return days }
        let daysInPreviousMonth = previousMonthRange.count

        // Add days from previous month (outside days)
        for i in 0..<startOffset {
            let day = daysInPreviousMonth - startOffset + i + 1
            guard let date = calendar.date(byAdding: .day, value: i - startOffset, to: firstOfMonth) else { continue }
            let dateISO = date.toISODateString()
            let weekNum = calendar.component(.weekday, from: date) == 2 ? getIsoWeek(from: date) : nil

            days.append(.outsideMonth(
                id: -1000 + i,
                dayNumber: day,
                dateISO: dateISO,
                weekNumber: weekNum
            ))
        }

        // Add cells for each day in current month
        for day in range {
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth) else { continue }
            let dateISO = date.toISODateString()
            let isMonday = calendar.component(.weekday, from: date) == 2
            let weekNum = isMonday ? getIsoWeek(from: date) : nil

            days.append(.inMonth(
                id: day,
                dayNumber: day,
                dateISO: dateISO,
                weekNumber: weekNum
            ))
        }

        // Add days from next month to fill the last row
        let totalDays = days.count
        let remainder = totalDays % 7
        if remainder > 0 {
            let daysToAdd = 7 - remainder
            for i in 0..<daysToAdd {
                guard let date = calendar.date(byAdding: .day, value: range.count + i, to: firstOfMonth) else { continue }
                let dateISO = date.toISODateString()
                let weekNum = calendar.component(.weekday, from: date) == 2 ? getIsoWeek(from: date) : nil

                days.append(.outsideMonth(
                    id: 1000 + i,
                    dayNumber: i + 1,
                    dateISO: dateISO,
                    weekNumber: weekNum
                ))
            }
        }

        return days
    }

    /// Generate day info array for a given Date (extracts year/month automatically)
    static func daysInMonth(for date: Date, selectedDates: Set<String>? = nil) -> [CalendarDayInfo] {
        let components = calendar.dateComponents([.year, .month], from: date)
        guard let year = components.year, let month = components.month else { return [] }
        return daysInMonth(year: year, month: month, selectedDates: selectedDates)
    }

    // MARK: - ISO Week Number

    /// Get ISO week number from a date
    static func getIsoWeek(from date: Date) -> Int {
        var isoCalendar = Calendar(identifier: .iso8601)
        isoCalendar.firstWeekday = 2  // Monday
        isoCalendar.minimumDaysInFirstWeek = 4
        return isoCalendar.component(.weekOfYear, from: date)
    }

    // MARK: - Weekday Symbols

    /// Get localized weekday symbols (Monday-start)
    static func weekdaySymbols(isNorwegian: Bool) -> [String] {
        if isNorwegian {
            return ["MA", "TI", "ON", "TO", "FR", "LØ", "SØ"]
        } else {
            return ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]
        }
    }

    // MARK: - Grid Columns

    /// Standard 7-column grid for calendar
    static let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    // MARK: - Formatting

    /// Format currency amount for calendar cells (compact, no symbol)
    static func formatCompactCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.groupingSeparator = " "
        return formatter.string(from: NSNumber(value: amount)) ?? "\(Int(amount))"
    }

    /// Format time string for display (removes seconds, optional leading zero)
    /// e.g., "08:30:00" -> "8:30"
    static func formatTime(_ time: String) -> String {
        let hhmm = String(time.prefix(5))
        return hhmm.hasPrefix("0") ? String(hhmm.dropFirst()) : hhmm
    }

    /// Convert time string to minutes since midnight
    static func timeToMinutes(_ time: String) -> Int {
        let parts = time.split(separator: ":")
        guard parts.count >= 2,
              let hours = Int(parts[0]),
              let minutes = Int(parts[1]) else { return 0 }
        return hours * 60 + minutes
    }

    // MARK: - Month Name

    /// Get localized month name from Date
    static func monthName(from date: Date, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        formatter.locale = locale
        return formatter.string(from: date).capitalized
    }

    /// Get localized month name from year/month components
    static func monthName(year: Int, month: Int, locale: Locale) -> String {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1

        if let date = calendar.date(from: components) {
            return monthName(from: date, locale: locale)
        }
        return ""
    }
}
