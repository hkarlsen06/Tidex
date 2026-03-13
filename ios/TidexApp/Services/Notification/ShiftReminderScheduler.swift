import Foundation
import UserNotifications
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "ShiftReminderScheduler")

// MARK: - Shift Reminder Scheduler

/// Schedules local notifications for shift reminders
/// iOS is the source of truth for notification preferences
@MainActor
final class ShiftReminderScheduler {
  static let shared = ShiftReminderScheduler()

  /// Notification identifier prefix
  private static let identifierPrefix = "shift-reminder-"

  /// Maximum scheduled notifications (iOS limit is 64)
  private static let maxScheduledNotifications = 16

  /// How many days ahead to schedule all reminders (full coverage)
  private static let fullCoverageDays = 14

  /// How many days ahead to schedule single reminders (reduced coverage)
  private static let reducedCoverageDays = 30

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
      await cancelAllReminders()
      return
    }

    let reminderMinutes = preferences.shiftReminderMinutesArray
    guard !reminderMinutes.isEmpty else {
      logger.info("No reminder times configured, skipping scheduling")
      await cancelAllReminders()
      return
    }

    // Cancel existing reminders first
    await cancelAllReminders()

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

    // Filter to future shifts only
    let now = Date()
    let calendar = Calendar.current
    let futureShifts = storedShifts.filter { shift in
      guard let shiftStart = parseShiftStart(shift) else { return false }
      return shiftStart > now
    }

    if futureShifts.isEmpty {
      logger.info("No future shifts to schedule reminders for")
      return
    }

    // Schedule reminders with iOS limit in mind
    var scheduledCount = 0
    let maxNotifications = Self.maxScheduledNotifications

    for shift in futureShifts {
      guard let shiftStart = parseShiftStart(shift) else { continue }

      // Calculate days until shift
      let daysUntil = calendar.dateComponents([.day], from: now, to: shiftStart).day ?? 0

      // Determine which reminder times to use based on how far out the shift is
      let reminderTimesToUse: [Int]
      if daysUntil <= Self.fullCoverageDays {
        // Full coverage: all configured reminder times
        reminderTimesToUse = reminderMinutes
      } else if daysUntil <= Self.reducedCoverageDays {
        // Reduced coverage: only first (shortest) reminder time
        reminderTimesToUse = Array(reminderMinutes.prefix(1))
      } else {
        // Skip shifts too far in the future
        continue
      }

      for minutes in reminderTimesToUse {
        // Check if we've hit the limit
        guard scheduledCount < maxNotifications else {
          logger.info("Reached max scheduled notifications (\(maxNotifications)), stopping")
          return
        }

        // Calculate notification fire date
        guard let fireDate = calendar.date(byAdding: .minute, value: -minutes, to: shiftStart),
          fireDate > now
        else {
          continue
        }

        // Schedule the notification
        let scheduled = await scheduleNotification(
          for: shift,
          fireDate: fireDate,
          minutesBefore: minutes
        )

        if scheduled {
          scheduledCount += 1
        }
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
      .map { $0.identifier }
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
      .map { $0.identifier }
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
    let calendar = Calendar.current
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
    if #available(iOS 15.0, *) {
      content.targetContentIdentifier = "shift-reminder:\(shift.shiftId)"
      content.interruptionLevel = .active
      content.relevanceScore = minutesBefore <= 60 ? 0.85 : 0.7
    }

    content.categoryIdentifier = "SHIFT_REMINDER"

    return content
  }

  /// Format day text (Today/Tomorrow/Date)
  private func formatDayText(for shiftDateString: String, relativeTo referenceDate: Date) -> String
  {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"

    guard let shiftDate = formatter.date(from: shiftDateString) else {
      return shiftDateString
    }

    let calendar = Calendar.current
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
    if minutes == 1440 {  // 24 hours
      return String(localized: .notificationReminderOneDay)
    }
    if minutes == 2880 {  // 48 hours
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

  /// Parse shift start date from StoredShift
  private func parseShiftStart(_ shift: StoredShift) -> Date? {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    formatter.timeZone = TimeZone.current

    return formatter.date(from: "\(shift.shiftDate) \(shift.startTime)")
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
