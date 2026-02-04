import EventKit
import Foundation
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "CalendarExportService")

/// Service for exporting shifts to the device calendar
final class CalendarExportService {
    static let shared = CalendarExportService()

    private let eventStore = EKEventStore()

    /// Calendar identifier key for UserDefaults
    private let calendarIdentifierKey = "tidex.calendar.identifier"

    private init() {}

    // MARK: - Public Methods

    /// Request calendar access permission
    /// - Returns: True if access was granted
    func requestAccess() async throws -> Bool {
        if #available(iOS 17.0, *) {
            return try await eventStore.requestFullAccessToEvents()
        } else {
            return try await eventStore.requestAccess(to: .event)
        }
    }

    /// Check if calendar access is authorized
    var isAuthorized: Bool {
        if #available(iOS 17.0, *) {
            return EKEventStore.authorizationStatus(for: .event) == .fullAccess
        } else {
            return EKEventStore.authorizationStatus(for: .event) == .authorized
        }
    }

    /// Export shifts to calendar
    /// - Parameters:
    ///   - shifts: Array of shifts to export
    ///   - calendarName: Name for the Tidex calendar
    ///   - eventTitle: Title for each calendar event
    /// - Returns: Number of events created
    func exportShifts(
        _ shifts: [ExportedShift],
        calendarName: String,
        eventTitle: String
    ) async throws -> Int {
        // Ensure we have permission
        if !isAuthorized {
            let granted = try await requestAccess()
            if !granted {
                throw CalendarExportError.permissionDenied
            }
        }

        // Get or create the Tidex calendar
        let calendar = try getOrCreateCalendar(name: calendarName)

        var createdCount = 0

        for shift in shifts {
            do {
                try createEvent(for: shift, in: calendar, title: eventTitle)
                createdCount += 1
            } catch {
                logger.error("Failed to create event for shift \(shift.id): \(error.localizedDescription)")
                // Continue with other shifts
            }
        }

        logger.info("Exported \(createdCount) shifts to calendar")
        return createdCount
    }

    // MARK: - Private Methods

    /// Get or create the Tidex calendar
    private func getOrCreateCalendar(name: String) throws -> EKCalendar {
        // Try to find existing Tidex calendar by stored identifier
        if let identifier = UserDefaults.standard.string(forKey: calendarIdentifierKey),
           let existingCalendar = eventStore.calendar(withIdentifier: identifier) {
            logger.debug("Found existing Tidex calendar")
            return existingCalendar
        }

        // Try to find by name (in case identifier was lost)
        if let existingCalendar = eventStore.calendars(for: .event).first(where: { $0.title == name }) {
            // Store the identifier for future use
            UserDefaults.standard.set(existingCalendar.calendarIdentifier, forKey: calendarIdentifierKey)
            logger.debug("Found Tidex calendar by name")
            return existingCalendar
        }

        // Create new calendar
        let calendar = EKCalendar(for: .event, eventStore: eventStore)
        calendar.title = name

        // Use the default calendar source for local calendars
        // Prefer local source, fall back to default
        if let localSource = eventStore.sources.first(where: { $0.sourceType == .local }) {
            calendar.source = localSource
        } else if let defaultSource = eventStore.defaultCalendarForNewEvents?.source {
            calendar.source = defaultSource
        } else if let anySource = eventStore.sources.first {
            calendar.source = anySource
        } else {
            throw CalendarExportError.noCalendarSource
        }

        // Set a nice color (Tidex blue)
        calendar.cgColor = CGColor(red: 0.2, green: 0.5, blue: 1.0, alpha: 1.0)

        try eventStore.saveCalendar(calendar, commit: true)

        // Store the identifier
        UserDefaults.standard.set(calendar.calendarIdentifier, forKey: calendarIdentifierKey)

        logger.info("Created new Tidex calendar")
        return calendar
    }

    /// Create a calendar event for a shift
    private func createEvent(for shift: ExportedShift, in calendar: EKCalendar, title: String) throws {
        // Parse dates
        guard let shiftDate = parseISODate(shift.date) else {
            throw CalendarExportError.invalidDate
        }

        guard let startDate = combineDateAndTime(date: shiftDate, time: shift.startTime),
              let endDate = calculateEndDate(date: shiftDate, startTime: shift.startTime, endTime: shift.endTime) else {
            throw CalendarExportError.invalidDate
        }

        // Check if event already exists (to avoid duplicates)
        let predicate = eventStore.predicateForEvents(
            withStart: startDate.addingTimeInterval(-60), // 1 minute tolerance
            end: endDate.addingTimeInterval(60),
            calendars: [calendar]
        )

        let existingEvents = eventStore.events(matching: predicate)
        let isDuplicate = existingEvents.contains { event in
            event.title == title &&
            abs(event.startDate.timeIntervalSince(startDate)) < 60 &&
            abs(event.endDate.timeIntervalSince(endDate)) < 60
        }

        if isDuplicate {
            logger.debug("Skipping duplicate event for shift \(shift.id)")
            return
        }

        // Create the event
        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = startDate
        event.endDate = endDate
        event.calendar = calendar

        // Add notes with shift details
        let hoursFormatted = String(format: "%.1f", shift.calc.hours)
        event.notes = "Duration: \(hoursFormatted) hours"

        try eventStore.save(event, span: .thisEvent, commit: true)
    }

    /// Parse ISO date string (YYYY-MM-DD) to Date
    private func parseISODate(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter.date(from: string)
    }

    /// Combine a date and time string into a full Date
    private func combineDateAndTime(date: Date, time: String) -> Date? {
        let components = time.split(separator: ":").compactMap { Int($0) }
        guard components.count >= 2 else { return nil }

        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current

        var dateComponents = calendar.dateComponents([.year, .month, .day], from: date)
        dateComponents.hour = components[0]
        dateComponents.minute = components[1]

        return calendar.date(from: dateComponents)
    }

    /// Calculate end date, handling cross-midnight shifts
    private func calculateEndDate(date: Date, startTime: String, endTime: String) -> Date? {
        guard let startDate = combineDateAndTime(date: date, time: startTime),
              var endDate = combineDateAndTime(date: date, time: endTime) else {
            return nil
        }

        // If end time is before start time, it's a cross-midnight shift
        if endDate <= startDate {
            endDate = Calendar.current.date(byAdding: .day, value: 1, to: endDate) ?? endDate
        }

        return endDate
    }
}

// MARK: - Errors

enum CalendarExportError: LocalizedError {
    case permissionDenied
    case noCalendarSource
    case invalidDate
    case exportFailed
    case noShifts

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return String(localized: .dataExportCalendarPermissionDenied)
        case .noCalendarSource:
            return "Could not find a calendar source"
        case .invalidDate:
            return "Invalid shift date or time"
        case .exportFailed:
            return "Failed to export shifts"
        case .noShifts:
            return String(localized: .dataExportCalendarNoShifts)
        }
    }
}
