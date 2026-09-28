import Foundation
import UserNotifications
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "ShiftReminderScheduler")

struct ShiftReminderSchedule: Equatable {
  let shiftId: String
  let minutesBefore: Int
  let fireDate: Date
}

struct PrioritizedShiftReminder: Equatable {
  let shift: StoredShift
  let schedule: ShiftReminderSchedule
}

enum ShiftReminderPlanner {
  /// Maximum scheduled notifications (iOS limit is 64)
  static let maxScheduledNotifications = 16

  /// How many days ahead to schedule all reminders (full coverage)
  private static let fullCoverageDays = 14

  /// How many days ahead to schedule single reminders (reduced coverage)
  private static let reducedCoverageDays = 30

  static func normalizedReminderMinutes(_ minutes: [Int]) -> [Int] {
    Array(Set(minutes.filter { $0 >= 0 })).sorted(by: >)
  }

  static func shiftStartDate(for shift: StoredShift) -> Date? {
    Date.fromDateAndTime(shift.shiftDate, time: shift.startTime)
  }

  static func reminderSchedules(
    for shift: StoredShift,
    reminderMinutes: [Int],
    referenceDate: Date = Date()
  ) -> [ShiftReminderSchedule] {
    guard let shiftStart = shiftStartDate(for: shift), shiftStart > referenceDate else {
      return []
    }

    let calendar = Calendar.gregorianCurrent
    let daysUntil = calendar.dateComponents([.day], from: referenceDate, to: shiftStart).day ?? 0
    let normalizedMinutes = normalizedReminderMinutes(reminderMinutes)

    let reminderTimesToUse: [Int]
    if daysUntil <= fullCoverageDays {
      reminderTimesToUse = normalizedMinutes
    } else if daysUntil <= reducedCoverageDays {
      reminderTimesToUse = normalizedMinutes.last.map { [$0] } ?? []
    } else {
      reminderTimesToUse = []
    }

    return
      reminderTimesToUse
      .compactMap { minutesBefore in
        guard
          let fireDate = calendar.date(byAdding: .minute, value: -minutesBefore, to: shiftStart),
          fireDate > referenceDate
        else {
          return nil
        }

        return ShiftReminderSchedule(
          shiftId: shift.shiftId,
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
    for shifts: [StoredShift],
    reminderMinutes: [Int],
    referenceDate: Date = Date(),
    limit: Int = maxScheduledNotifications
  ) -> [PrioritizedShiftReminder] {
    Array(
      shifts
        .flatMap { shift in
          reminderSchedules(
            for: shift,
            reminderMinutes: reminderMinutes,
            referenceDate: referenceDate
          ).map {
            PrioritizedShiftReminder(shift: shift, schedule: $0)
          }
        }
        .sorted { lhs, rhs in
          if lhs.schedule.fireDate == rhs.schedule.fireDate {
            if lhs.shift.shiftId == rhs.shift.shiftId {
              return lhs.schedule.minutesBefore < rhs.schedule.minutesBefore
            }
            return lhs.shift.shiftId < rhs.shift.shiftId
          }
          return lhs.schedule.fireDate < rhs.schedule.fireDate
        }
        .prefix(limit)
    )
  }
}

// MARK: - Shift Reminder Scheduler

/// Schedules local notifications for shift reminders
/// iOS is the source of truth for notification preferences
@MainActor
final class ShiftReminderScheduler {
  static let shared = ShiftReminderScheduler()

  /// Notification identifier prefix
  private static let identifierPrefix = "shift-reminder-"

  private init() {}

  // MARK: - Public API

  /// Schedule reminders for all upcoming shifts
  /// Call after sync completes or when preferences change
  /// - Parameters:
  ///   - userId: User ID
  ///   - shifts: Optional pre-loaded shifts. If nil, reads from widget storage.
  func scheduleAllReminders(for userId: String, shifts: [StoredShift]? = nil) async {
    logger.info("Scheduling shift reminders for user \(userId.prefix(8))...")

    // Check system notification permission first
    let center = UNUserNotificationCenter.current()
    let settings = await center.notificationSettings()

    // Always clear old requests before returning; permission can be revoked while stale
    // notifications are still pending and may fire later if permission is re-enabled.
    await cancelAllReminders()

    guard
      settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        || settings.authorizationStatus == .ephemeral
    else {
      logger.warning("Notification permission not granted, skipping scheduling")
      return
    }

    // Get notification preferences
    let prefsRepository = NotificationPreferencesRepository.shared
    let preferences = prefsRepository.getOrCreatePreferences(for: userId)

    // Check if reminders are enabled
    guard preferences.shiftRemindersEnabled else {
      logger.info("Shift reminders disabled, cancelling all existing reminders")
      return
    }

    let reminderMinutes = preferences.shiftReminderMinutesArray
    guard !reminderMinutes.isEmpty else {
      logger.info("No reminder times configured, skipping scheduling")
      return
    }

    // Use provided shifts or read from widget storage
    let storedShifts: [StoredShift]
    if let providedShifts = shifts {
      storedShifts = providedShifts
    } else if let shiftsFromStorage = getStoredShifts() {
      storedShifts = shiftsFromStorage
    } else {
      logger.warning("No shifts available for scheduling")
      return
    }

    let schedules = ShiftReminderPlanner.prioritizedSchedules(
      for: storedShifts,
      reminderMinutes: reminderMinutes
    )

    if schedules.isEmpty {
      logger.info("No future shifts to schedule reminders for")
      return
    }

    var scheduledCount = 0

    for entry in schedules {
      let scheduled = await scheduleNotification(
        for: entry.shift,
        fireDate: entry.schedule.fireDate,
        minutesBefore: entry.schedule.minutesBefore
      )

      if scheduled {
        scheduledCount += 1
      }
    }

    logger.info("Scheduled \(scheduledCount) shift reminder notifications")
  }

  /// Cancel all scheduled shift reminders
  func cancelAllReminders() async {
    let center = UNUserNotificationCenter.current()
    let pendingRequests = await center.pendingNotificationRequests()

    let shiftReminderIds =
      pendingRequests
      .map(\.identifier)
      .filter { $0.hasPrefix(Self.identifierPrefix) }

    if !shiftReminderIds.isEmpty {
      center.removePendingNotificationRequests(withIdentifiers: shiftReminderIds)
      logger.info("Cancelled \(shiftReminderIds.count) shift reminder notifications")
    }
  }

  /// Cancel reminders for a specific shift
  /// - Parameter shiftId: The shift ID
  func cancelReminders(forShiftId shiftId: String) async {
    let center = UNUserNotificationCenter.current()
    let pendingRequests = await center.pendingNotificationRequests()

    let matchingIds =
      pendingRequests
      .map(\.identifier)
      .filter { $0.hasPrefix("\(Self.identifierPrefix)\(shiftId)-") }

    if !matchingIds.isEmpty {
      center.removePendingNotificationRequests(withIdentifiers: matchingIds)
      logger.debug("Cancelled \(matchingIds.count) reminders for shift \(shiftId.prefix(8))")
    }
  }

  // MARK: - Private Methods

  /// Schedule a single notification
  private func scheduleNotification(
    for shift: StoredShift,
    fireDate: Date,
    minutesBefore: Int
  ) async -> Bool {
    let center = UNUserNotificationCenter.current()

    // Build notification content
    let content = buildNotificationContent(
      shift: shift,
      referenceDate: fireDate,
      minutesBefore: minutesBefore
    )

    // Create trigger using calendar components for precise timing
    let calendar = Calendar.gregorianCurrent
    let components = calendar.dateComponents(
      [.year, .month, .day, .hour, .minute],
      from: fireDate
    )
    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

    // Create unique identifier: shift-reminder-{shiftId}-{minutes}
    let identifier = "\(Self.identifierPrefix)\(shift.shiftId)-\(minutesBefore)"

    let request = UNNotificationRequest(
      identifier: identifier,
      content: content,
      trigger: trigger
    )

    do {
      try await center.add(request)
      logger.debug("Scheduled reminder: \(identifier) for \(fireDate)")
      return true
    } catch {
      logger.error("Failed to schedule notification: \(error.localizedDescription)")
      return false
    }
  }

  /// Build notification content
  private func buildNotificationContent(
    shift: StoredShift,
    referenceDate: Date,
    minutesBefore: Int
  ) -> UNMutableNotificationContent {
    let content = UNMutableNotificationContent()

    // Format the time remaining for the title
    let timeText = formatTimeRemaining(minutes: minutesBefore)

    // Title: "{time} until next shift"
    let untilNextShift = String(localized: .notificationUntilNextShift)
    content.title = "\(timeText) \(untilNextShift)"

    // Body: "Today/Tomorrow at {start}-{end}"
    let dayText = formatDayText(for: shift.shiftDate, relativeTo: referenceDate)
    let atTime = String(localized: .notificationAtTime)
    content.body = "\(dayText) \(atTime) \(shift.startTime)-\(shift.endTime)"

    // Sound
    content.sound = UNNotificationSound(named: UNNotificationSoundName("tidex_notification.caf"))

    // Data for deep linking
    content.userInfo = [
      "type": "shift_reminder",
      "shift_id": shift.shiftId,
      "shift_date": shift.shiftDate,
    ]

    content.threadIdentifier = "shift-reminders"
    content.targetContentIdentifier = "shift-reminder:\(shift.shiftId)"
    content.interruptionLevel = .active
    content.relevanceScore = minutesBefore <= 60 ? 0.85 : 0.7

    content.categoryIdentifier = "SHIFT_REMINDER"

    return content
  }

  /// Format day text (Today/Tomorrow/Date)
  private func formatDayText(for shiftDateString: String, relativeTo referenceDate: Date) -> String
  {
    guard let shiftDate = Date.fromISODateString(shiftDateString) else {
      return shiftDateString
    }

    let calendar = Calendar.gregorianCurrent
    let today = calendar.startOfDay(for: referenceDate)
    let shiftDay = calendar.startOfDay(for: shiftDate)

    if calendar.isDate(shiftDay, inSameDayAs: today) {
      return String(localized: .commonToday)
    }

    if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
      calendar.isDate(shiftDay, inSameDayAs: tomorrow)
    {
      return String(localized: .commonTomorrow)
    }

    // Format as weekday + date
    let displayFormatter = DateFormatter()
    displayFormatter.locale = appLocale()
    displayFormatter.dateFormat = "EEEE d MMMM"  // e.g., "onsdag 15 januar"

    var text = displayFormatter.string(from: shiftDate)
    // Capitalize first letter
    text = text.prefix(1).uppercased() + text.dropFirst()
    return text
  }

  /// Format time remaining for notification title
  /// Handles minutes, hours, days, and mixed values
  private func formatTimeRemaining(minutes: Int) -> String {
    let hours = minutes / 60
    let mins = minutes % 60

    // Handle special day cases
    // swiftlint:disable:next no_magic_numbers
    if minutes == 1_440 {  // 24 hours
      return String(localized: .notificationReminderOneDay)
    }
    // swiftlint:disable:next no_magic_numbers
    if minutes == 2_880 {  // 48 hours
      return String(localized: .notificationReminderTwoDays)
    }

    // Minutes only (less than 1 hour)
    if hours == 0 {
      return String(localized: .notificationReminderMinutes(Int(Int32(mins))))
    }

    // Hours only (no remaining minutes)
    if mins == 0 {
      return String(localized: .notificationReminderHours(Int(Int32(hours))))
    }

    // Mixed hours and minutes
    return "\(hours) \(String(localized: .commonHoursShort)) \(mins) min"
  }

  /// Get stored shifts from App Group UserDefaults
  private func getStoredShifts() -> [StoredShift]? {
    let appGroupId = "group.no.tidex.app"
    guard let userDefaults = UserDefaults(suiteName: appGroupId),
      let jsonString = userDefaults.string(forKey: "upcoming_shifts"),
      let data = jsonString.data(using: .utf8)
    else {
      return nil
    }

    do {
      return try JSONDecoder().decode([StoredShift].self, from: data)
    } catch {
      logger.error("Failed to decode stored shifts: \(error.localizedDescription)")
      return nil
    }
  }
}

// MARK: - App Locale Helper

private func appLocale() -> Locale {
  let identifier = Bundle.main.preferredLocalizations.first ?? Locale.autoupdatingCurrent.identifier
  return Locale(identifier: identifier)
}
