import Foundation
import UserNotifications
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "EventReminderScheduler")

struct EventReminderSchedule: Equatable {
  let eventId: String
  let minutesBefore: Int
  let fireDate: Date
}

struct PrioritizedEventReminder: Equatable {
  let event: EventRow
  let schedule: EventReminderSchedule
}

enum EventReminderPlanner {
  static let maxScheduledNotifications = 16

  static func normalizedReminderMinutes(_ minutes: [Int]?) -> [Int] {
    Array(Set((minutes ?? []).filter { $0 >= 0 })).sorted(by: >)
  }

  static func reminderSchedules(for event: EventRow, referenceDate: Date = Date())
    -> [EventReminderSchedule]
  {
    guard !hasEventPassed(event, referenceDate: referenceDate) else { return [] }
    guard let baseDate = reminderBaseDate(for: event) else { return [] }

    return normalizedReminderMinutes(event.notification_minutes_array)
      .compactMap { minutesBefore in
        guard
          let fireDate = Calendar.current.date(
            byAdding: .minute, value: -minutesBefore, to: baseDate),
          fireDate > referenceDate
        else {
          return nil
        }

        return EventReminderSchedule(
          eventId: event.id,
          minutesBefore: minutesBefore,
          fireDate: fireDate
        )
      }
      .sorted { lhs, rhs in
        if lhs.fireDate == rhs.fireDate {
          return lhs.minutesBefore < rhs.minutesBefore
        }
        return lhs.fireDate < rhs.fireDate
      }
  }

  static func prioritizedSchedules(
    for events: [EventRow],
    referenceDate: Date = Date(),
    limit: Int = maxScheduledNotifications
  ) -> [PrioritizedEventReminder] {
    Array(
      events
        .flatMap { event in
          reminderSchedules(for: event, referenceDate: referenceDate).map {
            PrioritizedEventReminder(event: event, schedule: $0)
          }
        }
        .sorted { lhs, rhs in
          if lhs.schedule.fireDate == rhs.schedule.fireDate {
            if lhs.event.id == rhs.event.id {
              return lhs.schedule.minutesBefore < rhs.schedule.minutesBefore
            }
            return lhs.event.id < rhs.event.id
          }
          return lhs.schedule.fireDate < rhs.schedule.fireDate
        }
        .prefix(limit)
    )
  }

  static func hasEventPassed(_ event: EventRow, referenceDate: Date = Date()) -> Bool {
    guard let effectiveEndDate = effectiveEndDate(for: event) else { return false }
    return effectiveEndDate <= referenceDate
  }

  static func reminderBaseDate(for event: EventRow) -> Date? {
    if event.is_all_day {
      guard let anchorTime = event.notification_anchor_time else { return nil }
      return Date.fromDateAndTime(event.start_date, time: anchorTime)
    }

    guard let startTime = event.start_time else { return nil }
    return Date.fromDateAndTime(event.start_date, time: startTime)
  }

  static func effectiveEndDate(for event: EventRow) -> Date? {
    if event.is_all_day {
      guard let endDate = Date.fromISODateString(event.end_date) else { return nil }
      var calendar = Calendar.current
      calendar.timeZone = Date.localTimeZone
      let startOfEndDate = calendar.startOfDay(for: endDate)
      return calendar.date(byAdding: .day, value: 1, to: startOfEndDate)
    }

    guard let endTime = event.end_time else { return nil }
    return Date.fromDateAndTime(event.end_date, time: endTime)
  }
}

@MainActor
final class EventReminderScheduler {
  static let shared = EventReminderScheduler()

  private static let identifierPrefix = "event-reminder-"

  private init() {}

  func scheduleAllReminders(for userId: String, events: [EventRow]? = nil) async {
    logger.info("Scheduling event reminders for user \(userId.prefix(8))...")

    let center = UNUserNotificationCenter.current()
    let settings = await center.notificationSettings()

    await cancelAllReminders()

    guard
      settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        || settings.authorizationStatus == .ephemeral
    else {
      logger.warning("Notification permission not granted, skipping event reminder scheduling")
      return
    }

    let eventRows: [EventRow]
    if let events {
      eventRows = events
    } else {
      eventRows = await EventsRepository.shared.getAllEventsOffMain(for: userId)
    }
    let schedules = EventReminderPlanner.prioritizedSchedules(for: eventRows)

    var scheduledCount = 0
    for entry in schedules {
      guard await scheduleNotification(for: entry.event, schedule: entry.schedule) else { continue }
      scheduledCount += 1
    }

    logger.info("Scheduled \(scheduledCount) event reminder notifications")
  }

  func scheduleReminder(for event: EventRow) async {
    if let userId = event.user_id {
      await scheduleAllReminders(for: userId)
      return
    }

    await cancelReminders(forEventId: event.id)

    let center = UNUserNotificationCenter.current()
    let settings = await center.notificationSettings()

    guard
      settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        || settings.authorizationStatus == .ephemeral
    else {
      return
    }

    for schedule in EventReminderPlanner.reminderSchedules(for: event) {
      _ = await scheduleNotification(for: event, schedule: schedule)
    }
  }

  func cancelAllReminders() async {
    let center = UNUserNotificationCenter.current()
    let pendingRequests = await center.pendingNotificationRequests()

    let identifiers =
      pendingRequests
      .map(\.identifier)
      .filter { $0.hasPrefix(Self.identifierPrefix) }

    if !identifiers.isEmpty {
      center.removePendingNotificationRequests(withIdentifiers: identifiers)
      logger.info("Cancelled \(identifiers.count) event reminder notifications")
    }
  }

  func cancelReminders(for event: EventRow) async {
    await cancelReminders(forEventId: event.id)
  }

  func cancelReminders(forEventId eventId: String) async {
    let center = UNUserNotificationCenter.current()
    let pendingRequests = await center.pendingNotificationRequests()

    let identifiers =
      pendingRequests
      .map(\.identifier)
      .filter { $0.hasPrefix("\(Self.identifierPrefix)\(eventId)-") }

    if !identifiers.isEmpty {
      center.removePendingNotificationRequests(withIdentifiers: identifiers)
      logger.debug("Cancelled \(identifiers.count) reminders for event \(eventId.prefix(8))")
    }
  }

  private func scheduleNotification(for event: EventRow, schedule: EventReminderSchedule) async
    -> Bool
  {
    let center = UNUserNotificationCenter.current()
    let content = buildNotificationContent(for: event, schedule: schedule)

    let components = Calendar.current.dateComponents(
      [.year, .month, .day, .hour, .minute],
      from: schedule.fireDate
    )
    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    let identifier = "\(Self.identifierPrefix)\(event.id)-\(schedule.minutesBefore)"
    let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

    do {
      try await center.add(request)
      logger.debug("Scheduled event reminder \(identifier) for \(schedule.fireDate)")
      return true
    } catch {
      logger.error("Failed to schedule event reminder: \(error.localizedDescription)")
      return false
    }
  }

  private func buildNotificationContent(
    for event: EventRow,
    schedule: EventReminderSchedule
  ) -> UNMutableNotificationContent {
    let content = UNMutableNotificationContent()
    content.title = event.note
    content.body = buildBody(for: event, schedule: schedule)
    content.sound = UNNotificationSound(named: UNNotificationSoundName("tidex_notification.caf"))
    content.userInfo = [
      "type": "event_reminder",
      "event_id": event.id,
      "event_start_date": event.start_date,
    ]
    content.threadIdentifier = "event-reminders"

    content.targetContentIdentifier = "event-reminder:\(event.id)"
    content.interruptionLevel = .active
    content.relevanceScore = schedule.minutesBefore <= 60 ? 0.85 : 0.7

    content.categoryIdentifier = "EVENT_REMINDER"
    return content
  }

  private func buildBody(for event: EventRow, schedule: EventReminderSchedule) -> String {
    let dayText = formatDayText(for: event.start_date, relativeTo: schedule.fireDate)
    let baseTime = event.is_all_day ? event.notification_anchor_time : event.start_time

    if let baseTime, !baseTime.isEmpty {
      return "\(dayText) • \(baseTime)"
    }

    return dayText
  }

  private func formatDayText(for isoDate: String, relativeTo referenceDate: Date) -> String {
    guard let eventDate = Date.fromISODateString(isoDate) else { return isoDate }

    let calendar = Calendar.current
    let today = calendar.startOfDay(for: referenceDate)
    let reminderDay = calendar.startOfDay(for: eventDate)

    if calendar.isDate(reminderDay, inSameDayAs: today) {
      return String(localized: .commonToday)
    }

    if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
      calendar.isDate(reminderDay, inSameDayAs: tomorrow)
    {
      return String(localized: .commonTomorrow)
    }

    let formatter = DateFormatter()
    formatter.locale = eventReminderAppLocale()
    formatter.dateFormat = "EEEE d MMMM"

    let text = formatter.string(from: eventDate)
    return text.prefix(1).uppercased() + text.dropFirst()
  }
}

private func eventReminderAppLocale() -> Locale {
  let identifier = Bundle.main.preferredLocalizations.first ?? Locale.autoupdatingCurrent.identifier
  return Locale(identifier: identifier)
}
