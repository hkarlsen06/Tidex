import Foundation

struct ShiftCardDateParts {
    let dayName: String
    let dayNumber: String
    let monthName: String
}

/// Shared formatting helpers for shift cards to avoid duplicated logic.
@MainActor
enum ShiftCardFormatter {
    private static let formatterCache = ShiftCardFormatterCache()

    static func dateParts(for isoDate: String, locale: Locale) -> ShiftCardDateParts {
        guard let date = Date.fromISODateString(isoDate) else {
            return ShiftCardDateParts(dayName: "", dayNumber: "", monthName: "")
        }

        let dayNameFormatter = formatterCache.formatter(locale: locale, format: "EEEE")
        let dayName = dayNameFormatter.string(from: date).capitalized

        let dayNumberFormatter = formatterCache.formatter(locale: locale, format: "d")
        let dayNumber = dayNumberFormatter.string(from: date) + String(localized: .commonDaySuffix)

        let monthFormatter = formatterCache.formatter(locale: locale, format: "MMM")
        let monthName = monthFormatter.string(from: date).lowercased()

        return ShiftCardDateParts(dayName: dayName, dayNumber: dayNumber, monthName: monthName)
    }

    static func formattedHours(_ hours: Double, locale: Locale) -> String {
        let hoursLabel = String(localized: .commonHoursShort)
        return String(format: "%.2f %@", hours, hoursLabel)
    }
}

private final class ShiftCardFormatterCache {
    private var formatters: [String: DateFormatter] = [:]
    private let lock = NSLock()

    func formatter(locale: Locale, format: String) -> DateFormatter {
        let key = "\(locale.identifier)|\(format)"

        lock.lock()
        defer { lock.unlock() }

        if let cached = formatters[key] {
            return cached
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: locale.identifier)
        formatter.dateFormat = format
        formatters[key] = formatter
        return formatter
    }
}
