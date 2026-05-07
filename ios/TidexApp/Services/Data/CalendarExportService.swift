import EventKit
import Foundation
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "CalendarExportService")

struct CalendarEventSchedule: Equatable {
  let startDate: Date
  let endDate: Date
  let isAllDay: Bool
}

/// Service for exporting shifts and events to the device calendar
final class CalendarExportService {
  static let shared = CalendarExportService()

  private let eventStore = EKEventStore()

  /// Calendar identifier key for UserDefaults
  private let calendarIdentifierKey = "tidex.calendar.identifier"
  private let eventIdentifierMappingKey = "tidex.calendar.eventIdentifiers"

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
  @discardableResult
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

  /// Export a single Tidex event to the iOS calendar.
  /// - Returns: True when a new calendar event was created, false when a matching event already exists.
  @discardableResult
  func exportEvent(_ event: EventRow, calendarName: String) async throws -> Bool {
    if !isAuthorized {
      let granted = try await requestAccess()
      if !granted {
        throw CalendarExportError.permissionDenied
      }
    }

    let calendar = try getOrCreateCalendar(name: calendarName)
    return try createOrUpdateCalendarEvent(for: event, in: calendar)
  }

  /// Delete the iOS calendar event that was previously created for a Tidex event.
  /// - Returns: True if an event was found and removed.
  @discardableResult
  func deleteExportedEvent(_ event: EventRow) async throws -> Bool {
    guard isAuthorized else {
      return false
    }

    if let storedIdentifier = storedEventIdentifier(for: event.id),
      let storedEvent = eventStore.event(withIdentifier: storedIdentifier)
    {
      try eventStore.remove(storedEvent, span: .thisEvent, commit: true)
      removeStoredEventIdentifier(for: event.id)
      logger.info("Deleted calendar event for Tidex event \(event.id)")
      return true
    }

    guard let schedule = Self.schedule(for: event) else {
      removeStoredEventIdentifier(for: event.id)
      return false
    }

    let calendars = storedCalendar().map { [$0] }
    let predicate = eventStore.predicateForEvents(
      withStart: schedule.startDate.addingTimeInterval(-60),
      end: schedule.endDate.addingTimeInterval(60),
      calendars: calendars
    )

    guard
      let matchingEvent = eventStore.events(matching: predicate).first(where: { calendarEvent in
        calendarEvent.url == Self.calendarURL(for: event.id)
          || (calendars != nil
            && calendarEvent.title == event.trimmedNote
            && calendarEvent.startDate == schedule.startDate
            && calendarEvent.endDate == schedule.endDate)
      })
    else {
      removeStoredEventIdentifier(for: event.id)
      return false
    }

    try eventStore.remove(matchingEvent, span: .thisEvent, commit: true)
    removeStoredEventIdentifier(for: event.id)
    logger.info("Deleted calendar event for Tidex event \(event.id) via lookup")
    return true
  }

  static func schedule(for event: EventRow) -> CalendarEventSchedule? {
    guard let startDay = parseISODate(event.start_date) else { return nil }

    if event.is_all_day {
      guard let inclusiveEndDay = parseISODate(event.end_date),
        let exclusiveEndDay = Calendar.current.date(byAdding: .day, value: 1, to: inclusiveEndDay)
      else {
        return nil
      }

      return CalendarEventSchedule(
        startDate: startDay,
        endDate: exclusiveEndDay,
        isAllDay: true
      )
    }

    guard let startTime = event.start_time, let endTime = event.end_time,
      let startDate = combineDateAndTime(date: startDay, time: startTime),
      let endDay = parseISODate(event.end_date),
      let endDate = combineDateAndTime(date: endDay, time: endTime)
    else {
      return nil
    }

    return CalendarEventSchedule(
      startDate: startDate,
      endDate: max(endDate, startDate.addingTimeInterval(60)),
      isAllDay: false
    )
  }

  // MARK: - Private Methods

  /// Get or create the Tidex calendar
  private func getOrCreateCalendar(name: String) throws -> EKCalendar {
    if let existingCalendar = storedCalendar() {
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

  private func storedCalendar() -> EKCalendar? {
    guard let identifier = UserDefaults.standard.string(forKey: calendarIdentifierKey) else {
      return nil
    }

    return eventStore.calendar(withIdentifier: identifier)
  }

  /// Create a calendar event for a shift
  private func createEvent(for shift: ExportedShift, in calendar: EKCalendar, title: String) throws
  {
    // Parse dates
    guard let shiftDate = parseISODate(shift.date) else {
      throw CalendarExportError.invalidDate
    }

    guard let startDate = combineDateAndTime(date: shiftDate, time: shift.startTime),
      let endDate = calculateEndDate(
        date: shiftDate, startTime: shift.startTime, endTime: shift.endTime)
    else {
      throw CalendarExportError.invalidDate
    }

    // Check if event already exists (to avoid duplicates)
    let predicate = eventStore.predicateForEvents(
      withStart: startDate.addingTimeInterval(-60),  // 1 minute tolerance
      end: endDate.addingTimeInterval(60),
      calendars: [calendar]
    )

    let existingEvents = eventStore.events(matching: predicate)
    let isDuplicate = existingEvents.contains { event in
      event.title == title && abs(event.startDate.timeIntervalSince(startDate)) < 60
        && abs(event.endDate.timeIntervalSince(endDate)) < 60
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
    let hoursFormatted = shift.calc.hours.formatted(.number.precision(.fractionLength(1)))
    event.notes = String(localized: .dataExportCalendarEventNotes(hoursFormatted))

    try eventStore.save(event, span: .thisEvent, commit: true)
  }

  /// Parse ISO date string (YYYY-MM-DD) to Date
  private func parseISODate(_ string: String) -> Date? {
    Self.parseISODate(string)
  }

  /// Combine a date and time string into a full Date
  private func combineDateAndTime(date: Date, time: String) -> Date? {
    Self.combineDateAndTime(date: date, time: time)
  }

  private static func parseISODate(_ string: String) -> Date? {
    FormatterCache.isoDateFormatter(timeZone: TimeZone.current).date(from: string)
  }

  private static func combineDateAndTime(date: Date, time: String) -> Date? {
    let components = time.split(separator: ":").compactMap { Int($0) }
    guard components.count >= 2 else { return nil }

    var calendar = Calendar.current
    calendar.timeZone = TimeZone.current

    var dateComponents = calendar.dateComponents([.year, .month, .day], from: date)
    if components[0] == 24 && components[1] == 0 {
      guard let nextDay = calendar.date(byAdding: .day, value: 1, to: date) else { return nil }
      dateComponents = calendar.dateComponents([.year, .month, .day], from: nextDay)
      dateComponents.hour = 0
      dateComponents.minute = 0
    } else {
      guard (0...23).contains(components[0]), (0...59).contains(components[1]) else {
        return nil
      }
      dateComponents.hour = components[0]
      dateComponents.minute = components[1]
    }

    return calendar.date(from: dateComponents)
  }

  @discardableResult
  private func createOrUpdateCalendarEvent(for event: EventRow, in calendar: EKCalendar) throws
    -> Bool
  {
    guard let schedule = Self.schedule(for: event) else {
      throw CalendarExportError.invalidDate
    }

    let calendarEvent =
      storedEventIdentifier(for: event.id)
      .flatMap { eventStore.event(withIdentifier: $0) }
      ?? existingCalendarEvent(for: event, schedule: schedule, in: calendar)
      ?? EKEvent(eventStore: eventStore)

    let isNewEvent = calendarEvent.eventIdentifier == nil
    calendarEvent.title = event.trimmedNote
    calendarEvent.startDate = schedule.startDate
    calendarEvent.endDate = schedule.endDate
    calendarEvent.isAllDay = schedule.isAllDay
    calendarEvent.calendar = calendar
    calendarEvent.notes = event.trimmedNote
    calendarEvent.url = Self.calendarURL(for: event.id)

    try eventStore.save(calendarEvent, span: .thisEvent, commit: true)

    if let eventIdentifier = calendarEvent.eventIdentifier {
      storeEventIdentifier(eventIdentifier, for: event.id)
    }

    logger.info("Saved calendar event for Tidex event \(event.id)")
    return isNewEvent
  }

  private func existingCalendarEvent(
    for event: EventRow,
    schedule: CalendarEventSchedule,
    in calendar: EKCalendar
  ) -> EKEvent? {
    let predicate = eventStore.predicateForEvents(
      withStart: schedule.startDate.addingTimeInterval(-60),
      end: schedule.endDate.addingTimeInterval(60),
      calendars: [calendar]
    )

    return eventStore.events(matching: predicate).first { calendarEvent in
      calendarEvent.url == Self.calendarURL(for: event.id)
        || (calendarEvent.title == event.trimmedNote
          && calendarEvent.startDate == schedule.startDate
          && calendarEvent.endDate == schedule.endDate)
    }
  }

  private static func calendarURL(for eventId: String) -> URL? {
    URL(string: "tidex://event/\(eventId)")
  }

  private func storedEventIdentifier(for eventId: String) -> String? {
    eventIdentifierMappings()[eventId]
  }

  private func storeEventIdentifier(_ eventIdentifier: String, for eventId: String) {
    var mappings = eventIdentifierMappings()
    mappings[eventId] = eventIdentifier
    UserDefaults.standard.set(mappings, forKey: eventIdentifierMappingKey)
  }

  private func removeStoredEventIdentifier(for eventId: String) {
    var mappings = eventIdentifierMappings()
    mappings.removeValue(forKey: eventId)
    UserDefaults.standard.set(mappings, forKey: eventIdentifierMappingKey)
  }

  private func eventIdentifierMappings() -> [String: String] {
    UserDefaults.standard.dictionary(forKey: eventIdentifierMappingKey) as? [String: String] ?? [:]
  }

  /// Calculate end date, handling cross-midnight shifts
  private func calculateEndDate(date: Date, startTime: String, endTime: String) -> Date? {
    guard let startDate = combineDateAndTime(date: date, time: startTime),
      var endDate = combineDateAndTime(date: date, time: endTime)
    else {
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
