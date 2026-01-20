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
    private static let maxScheduledNotifications = 60

    /// How many days ahead to schedule all reminders (full coverage)
    private static let fullCoverageDays = 14

    /// How many days ahead to schedule single reminders (reduced coverage)
    private static let reducedCoverageDays = 30

    private init() {}

    // MARK: - Public API

    /// Schedule reminders for all upcoming shifts
    /// Call after sync completes or when preferences change
    /// - Parameter userId: User ID
    func scheduleAllReminders(for userId: String) async {
        logger.info("Scheduling shift reminders for user \(userId.prefix(8))...")

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

        // Get upcoming shifts from widget storage (already computed and sorted)
        guard let storedShifts = getStoredShifts() else {
            logger.info("No shifts available for scheduling")
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

        // Get locale for notification content
        let locale = getAppLocale()

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
                reminderTimesToUse = reminderMinutes.prefix(1).map { $0 }
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
                let notificationDate = calendar.date(byAdding: .minute, value: -minutes, to: shiftStart)
                guard let fireDate = notificationDate, fireDate > now else {
                    // Reminder time already passed
                    continue
                }

                // Schedule the notification
                let scheduled = await scheduleNotification(
                    for: shift,
                    fireDate: fireDate,
                    minutesBefore: minutes,
                    locale: locale
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

        let shiftReminderIds = pendingRequests
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

        let matchingIds = pendingRequests
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
        minutesBefore: Int,
        locale: String
    ) async -> Bool {
        let center = UNUserNotificationCenter.current()

        // Build notification content
        let content = buildNotificationContent(
            shift: shift,
            minutesBefore: minutesBefore,
            locale: locale
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
        minutesBefore: Int,
        locale: String
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()

        // Calculate hours until shift (using CEIL like server)
        let hours = Int(ceil(Double(minutesBefore) / 60.0))

        // Title: "X timer til neste vakt" / "X hours until next shift"
        if locale == "no" {
            content.title = hours == 1 ? "1 time til neste vakt" : "\(hours) timer til neste vakt"
        } else {
            content.title = hours == 1 ? "1 hour until next shift" : "\(hours) hours until next shift"
        }

        // Body: "I dag/I morgen kl. {start}-{end}" / "Today/Tomorrow at {start}-{end}"
        let dayText = formatDayText(for: shift.shiftDate, locale: locale)
        if locale == "no" {
            content.body = "\(dayText) kl. \(shift.startTime)-\(shift.endTime)"
        } else {
            content.body = "\(dayText) at \(shift.startTime)-\(shift.endTime)"
        }

        // Sound
        content.sound = UNNotificationSound(named: UNNotificationSoundName("tidex_notification.caf"))

        // Data for deep linking
        content.userInfo = [
            "type": "shift_reminder",
            "shift_id": shift.shiftId,
            "shift_date": shift.shiftDate
        ]

        // Category for potential future actions
        content.categoryIdentifier = "SHIFT_REMINDER"

        return content
    }

    /// Format day text (Today/Tomorrow/Date)
    private func formatDayText(for shiftDateString: String, locale: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        guard let shiftDate = formatter.date(from: shiftDateString) else {
            return shiftDateString
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let shiftDay = calendar.startOfDay(for: shiftDate)

        if calendar.isDate(shiftDay, inSameDayAs: today) {
            return locale == "no" ? "I dag" : "Today"
        }

        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
           calendar.isDate(shiftDay, inSameDayAs: tomorrow) {
            return locale == "no" ? "I morgen" : "Tomorrow"
        }

        // Format as weekday + date
        let displayFormatter = DateFormatter()
        displayFormatter.locale = Locale(identifier: locale == "no" ? "nb_NO" : "en_US")
        displayFormatter.dateFormat = "EEEE d. MMMM" // e.g., "onsdag 15. januar"

        var text = displayFormatter.string(from: shiftDate)
        // Capitalize first letter
        text = text.prefix(1).uppercased() + text.dropFirst()
        return text
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
              let data = jsonString.data(using: .utf8) else {
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

/// Get the app's effective locale from iOS system settings
private func getAppLocale() -> String {
    if let preferred = Bundle.main.preferredLocalizations.first {
        if preferred.hasPrefix("nb") || preferred.hasPrefix("no") || preferred.hasPrefix("nn") {
            return "no"
        }
    }
    return "en"
}
