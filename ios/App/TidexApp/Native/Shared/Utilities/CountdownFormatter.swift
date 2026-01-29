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
    /// - Returns: Formatted countdown text, whether shift is active, and progress (0-100) if active
    static func formatShiftCountdown(
        shiftDate: String,
        startTime: String,
        endTime: String,
        isNorwegian: Bool
    ) -> (text: String, isActive: Bool, progress: Double) {
        let now = Date()

        guard let shiftStart = parseShiftDateTime(date: shiftDate, time: startTime),
              let shiftEnd = parseShiftDateTime(date: shiftDate, time: endTime, crossesMidnight: endTime <= startTime) else {
            return ("---", false, 0)
        }

        // Check if shift is active
        if now >= shiftStart && now < shiftEnd {
            // Calculate progress through the shift (0-100)
            let totalDuration = shiftEnd.timeIntervalSince(shiftStart)
            let elapsed = now.timeIntervalSince(shiftStart)
            let progress = totalDuration > 0 ? min(100, max(0, (elapsed / totalDuration) * 100)) : 0
            return (isNorwegian ? "Pågår nå" : "In progress", true, progress)
        }

        // Check if shift is in the past
        if now >= shiftEnd {
            let (text, _) = formatPastTime(from: shiftEnd, isNorwegian: isNorwegian)
            return (text, false, 0)
        }

        // Shift is in the future
        let (text, _) = formatFutureTime(to: shiftStart, isNorwegian: isNorwegian)
        return (text, false, 0)
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

    /// Count midnight boundaries crossed between two dates (matching Next.js behavior)
    /// Users perceive "1 day" as "tomorrow", not "24 hours from now"
    private static func countMidnightCrossings(from: Date, to: Date) -> Int {
        let calendar = Calendar.current
        let fromMidnight = calendar.startOfDay(for: from)
        let toMidnight = calendar.startOfDay(for: to)
        let days = calendar.dateComponents([.day], from: fromMidnight, to: toMidnight).day ?? 0
        return abs(days)
    }

    private static func formatFutureTime(to targetDate: Date, isNorwegian: Bool) -> (String, Bool) {
        let now = Date()
        let calendar = Calendar.current
        let midnightDays = countMidnightCrossings(from: now, to: targetDate)

        // 1 midnight crossing = tomorrow
        if midnightDays == 1 {
            return (isNorwegian ? "I morgen" : "Tomorrow", false)
        }

        // 2+ midnight crossings = "In X days"
        if midnightDays > 1 {
            let dayWord = isNorwegian ? "dager" : "days"
            return (isNorwegian ? "Om \(midnightDays) \(dayWord)" : "In \(midnightDays) \(dayWord)", false)
        }

        // Same calendar day (0 midnight crossings) - show hours/minutes/seconds
        let components = calendar.dateComponents([.hour, .minute, .second], from: now, to: targetDate)
        let hours = components.hour ?? 0
        let minutes = components.minute ?? 0
        let seconds = components.second ?? 0
        let totalSeconds = Int(targetDate.timeIntervalSince(now))
        let totalHours = totalSeconds / 3600

        // Within 6 hours - show high precision with seconds
        if totalHours < 6 {
            let secWord = isNorwegian ? "sek" : "sec"

            // Less than 1 minute - show only seconds
            if hours == 0 && minutes == 0 {
                return (isNorwegian ? "Om \(seconds)\(secWord)" : "In \(seconds)\(secWord)", false)
            }

            // Less than 1 hour - show minutes and seconds
            if hours == 0 {
                return (isNorwegian ? "Om \(minutes)min \(seconds)\(secWord)" : "In \(minutes)min \(seconds)\(secWord)", false)
            }

            // Less than 6 hours - show hours, minutes and seconds
            let hourWord = isNorwegian ? "t" : "h"
            return (isNorwegian ? "Om \(hours)\(hourWord) \(minutes)min \(seconds)\(secWord)" : "In \(hours)\(hourWord) \(minutes)min \(seconds)\(secWord)", false)
        }

        // 6+ hours on same day - show hours and minutes only
        let hourWord = isNorwegian ? "t" : "h"
        if minutes == 0 {
            return (isNorwegian ? "Om \(hours)\(hourWord)" : "In \(hours)\(hourWord)", false)
        }
        return (isNorwegian ? "Om \(hours)\(hourWord) \(minutes)min" : "In \(hours)\(hourWord) \(minutes)min", false)
    }

    private static func formatPastTime(from pastDate: Date, isNorwegian: Bool) -> (String, Bool) {
        let now = Date()
        let calendar = Calendar.current
        let midnightDays = countMidnightCrossings(from: pastDate, to: now)

        // 1 midnight crossing = yesterday
        if midnightDays == 1 {
            return (isNorwegian ? "I går" : "Yesterday", false)
        }

        // 2+ midnight crossings = "X days ago"
        if midnightDays > 1 {
            let dayWord = isNorwegian ? "dager" : "days"
            return (isNorwegian ? "\(midnightDays) \(dayWord) siden" : "\(midnightDays) \(dayWord) ago", false)
        }

        // Same calendar day (0 midnight crossings) - show hours/minutes/seconds
        let components = calendar.dateComponents([.hour, .minute, .second], from: pastDate, to: now)
        let hours = components.hour ?? 0
        let minutes = components.minute ?? 0
        let seconds = components.second ?? 0
        let totalSeconds = Int(now.timeIntervalSince(pastDate))
        let totalHours = totalSeconds / 3600

        // Within 6 hours - show high precision with seconds
        if totalHours < 6 {
            let secWord = isNorwegian ? "sek" : "sec"

            // Less than 1 minute - show only seconds
            if hours == 0 && minutes == 0 {
                return (isNorwegian ? "\(seconds)\(secWord) siden" : "\(seconds)\(secWord) ago", false)
            }

            // Less than 1 hour - show minutes and seconds
            if hours == 0 {
                return (isNorwegian ? "\(minutes)min \(seconds)\(secWord) siden" : "\(minutes)min \(seconds)\(secWord) ago", false)
            }

            // Less than 6 hours - show hours, minutes and seconds
            let hourWord = isNorwegian ? "t" : "h"
            return (isNorwegian ? "\(hours)\(hourWord) \(minutes)min \(seconds)\(secWord) siden" : "\(hours)\(hourWord) \(minutes)min \(seconds)\(secWord) ago", false)
        }

        // 6+ hours on same day - show hours and minutes only
        let hourWord = isNorwegian ? "t" : "h"
        if minutes == 0 {
            return (isNorwegian ? "\(hours)\(hourWord) siden" : "\(hours)\(hourWord) ago", false)
        }
        return (isNorwegian ? "\(hours)\(hourWord) \(minutes)min siden" : "\(hours)\(hourWord) \(minutes)min ago", false)
    }
}
