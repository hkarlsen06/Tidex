import Foundation

/// Utility for formatting countdown text for shifts and payroll
/// Matches the behavior of useCountdown and usePayrollCountdown hooks in Next.js
struct CountdownFormatter {

    // MARK: - Shift Countdown

    /// Format countdown text for a shift
    /// - Parameters:
    ///   - shiftDate: ISO date string (YYYY-MM-DD)
    ///   - startTime: Start time (HH:mm)
    ///   - endTime: End time (HH:mm)
    ///   - isNorwegian: Whether to use Norwegian locale
    /// - Returns: Formatted countdown text and whether shift is active
    static func formatShiftCountdown(
        shiftDate: String,
        startTime: String,
        endTime: String,
        isNorwegian: Bool
    ) -> (text: String, isActive: Bool) {
        let now = Date()

        guard let shiftStart = parseShiftDateTime(date: shiftDate, time: startTime),
              let shiftEnd = parseShiftDateTime(date: shiftDate, time: endTime, crossesMidnight: endTime <= startTime) else {
            return ("---", false)
        }

        // Check if shift is active
        if now >= shiftStart && now < shiftEnd {
            return (isNorwegian ? "Pågår nå" : "In progress", true)
        }

        // Check if shift is in the past
        if now >= shiftEnd {
            return formatPastTime(from: shiftEnd, isNorwegian: isNorwegian)
        }

        // Shift is in the future
        return formatFutureTime(to: shiftStart, isNorwegian: isNorwegian)
    }

    // MARK: - Payroll Countdown

    /// Format countdown text for payroll date
    /// - Parameters:
    ///   - payrollDate: The payroll date
    ///   - isNorwegian: Whether to use Norwegian locale
    /// - Returns: Formatted countdown text and whether it's past
    static func formatPayrollCountdown(
        payrollDate: Date,
        isNorwegian: Bool
    ) -> (text: String, isPast: Bool, isToday: Bool) {
        let now = Date()
        let calendar = Calendar.current

        // Check if payroll is today
        if calendar.isDateInToday(payrollDate) {
            return (isNorwegian ? "I dag" : "Today", false, true)
        }

        // Check if payroll has passed
        if now > payrollDate {
            let (text, _) = formatPastTime(from: payrollDate, isNorwegian: isNorwegian)
            return (text, true, false)
        }

        // Payroll is in the future
        let (text, _) = formatFutureTime(to: payrollDate, isNorwegian: isNorwegian)
        return (text, false, false)
    }

    // MARK: - Private Helpers

    private static func parseShiftDateTime(date: String, time: String, crossesMidnight: Bool = false) -> Date? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = Date.localTimeZone

        let dateTimeString = "\(date) \(time)"
        guard var result = dateFormatter.date(from: dateTimeString) else { return nil }

        // If shift crosses midnight, add one day to the end time
        if crossesMidnight {
            result = Calendar.current.date(byAdding: .day, value: 1, to: result) ?? result
        }

        return result
    }

    private static func formatFutureTime(to targetDate: Date, isNorwegian: Bool) -> (String, Bool) {
        let now = Date()
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day, .hour, .minute, .second], from: now, to: targetDate)

        let days = components.day ?? 0
        let hours = components.hour ?? 0
        let minutes = components.minute ?? 0

        // Tomorrow
        if calendar.isDateInTomorrow(targetDate) {
            return (isNorwegian ? "I morgen" : "Tomorrow", false)
        }

        // Multiple days
        if days > 1 {
            let dayWord = days == 1 ? (isNorwegian ? "dag" : "day") : (isNorwegian ? "dager" : "days")
            return (isNorwegian ? "om \(days) \(dayWord)" : "in \(days) \(dayWord)", false)
        }

        // Same day or within 24 hours
        if days == 1 || hours >= 24 {
            let totalHours = days * 24 + hours
            let hourWord = isNorwegian ? "t" : "h"
            let minWord = isNorwegian ? "min" : "min"
            return (isNorwegian ? "om \(totalHours)\(hourWord) \(minutes)\(minWord)" : "in \(totalHours)\(hourWord) \(minutes)\(minWord)", false)
        }

        // Less than a day
        if hours > 0 {
            let hourWord = isNorwegian ? "t" : "h"
            let minWord = isNorwegian ? "min" : "min"
            return (isNorwegian ? "om \(hours)\(hourWord) \(minutes)\(minWord)" : "in \(hours)\(hourWord) \(minutes)\(minWord)", false)
        }

        // Less than an hour
        if minutes > 0 {
            let minWord = isNorwegian ? "min" : "min"
            return (isNorwegian ? "om \(minutes) \(minWord)" : "in \(minutes) \(minWord)", false)
        }

        // Less than a minute
        return (isNorwegian ? "snart" : "soon", false)
    }

    private static func formatPastTime(from pastDate: Date, isNorwegian: Bool) -> (String, Bool) {
        let now = Date()
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day, .hour, .minute], from: pastDate, to: now)

        let days = components.day ?? 0
        let hours = components.hour ?? 0
        let minutes = components.minute ?? 0

        // Yesterday
        if calendar.isDateInYesterday(pastDate) {
            return (isNorwegian ? "I går" : "Yesterday", false)
        }

        // Multiple days ago
        if days > 1 {
            let dayWord = days == 1 ? (isNorwegian ? "dag" : "day") : (isNorwegian ? "dager" : "days")
            return (isNorwegian ? "\(days) \(dayWord) siden" : "\(days) \(dayWord) ago", false)
        }

        // Within the last day
        if days == 1 || hours >= 24 {
            let totalHours = days * 24 + hours
            let hourWord = isNorwegian ? "t" : "h"
            return (isNorwegian ? "\(totalHours)\(hourWord) siden" : "\(totalHours)\(hourWord) ago", false)
        }

        // Less than a day ago
        if hours > 0 {
            let hourWord = isNorwegian ? "t" : "h"
            let minWord = isNorwegian ? "min" : "min"
            return (isNorwegian ? "\(hours)\(hourWord) \(minutes)\(minWord) siden" : "\(hours)\(hourWord) \(minutes)\(minWord) ago", false)
        }

        // Less than an hour ago
        if minutes > 0 {
            let minWord = isNorwegian ? "min" : "min"
            return (isNorwegian ? "\(minutes) \(minWord) siden" : "\(minutes) \(minWord) ago", false)
        }

        // Just now
        return (isNorwegian ? "akkurat nå" : "just now", false)
    }
}
