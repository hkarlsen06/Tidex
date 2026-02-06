import Foundation
import SwiftUI
import UserNotifications
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "SmartNotificationScheduler")

@MainActor
final class SmartNotificationScheduler {
  static let shared = SmartNotificationScheduler()

  private static let morningIdentifierPrefix = "smart-morning-"
  private static let eveningIdentifierPrefix = "smart-evening-"
  private static let maxSmartNotifications = 12
  private static let scheduleDaysAhead = 7
  private static let morningHour = 8
  private static let eveningOffsetMinutes = 120

  /// Status of smart notifications for display in settings
  enum Status {
    case active(scheduledCount: Int, workDays: Int)
    case insufficientData(weeksFound: Int, weeksRequired: Int)
    case noShifts
    case noPatternDetected
    case disabled
    case permissionDenied
  }

  private init() {}

  // MARK: - Public API

  /// Get the current status of smart notifications without scheduling
  func getStatus(for userId: String) async -> Status {
    let center = UNUserNotificationCenter.current()
    let settings = await center.notificationSettings()

    guard
      settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        || settings.authorizationStatus == .ephemeral
    else {
      return .permissionDenied
    }

    let prefsRepository = NotificationPreferencesRepository.shared
    let preferences = prefsRepository.getOrCreatePreferences(for: userId)

    guard preferences.smartNotificationsEnabled ?? true else {
      return .disabled
    }

    let analysisResult = WorkPatternAnalyzer.analyzeDetailed(for: userId)

    switch analysisResult {
    case .noShifts:
      return .noShifts
    case .insufficientData(let weeksFound):
      return .insufficientData(
        weeksFound: weeksFound,
        weeksRequired: WorkPatternAnalyzer.WorkPattern.minimumWeeksRequired
      )
    case .noPatternDetected:
      return .noPatternDetected
    case .success(let pattern):
      let pendingRequests = await center.pendingNotificationRequests()
      let scheduledCount = pendingRequests.filter { request in
        let id = request.identifier
        return id.hasPrefix(Self.morningIdentifierPrefix)
          || id.hasPrefix(Self.eveningIdentifierPrefix)
      }.count
      return .active(scheduledCount: scheduledCount, workDays: pattern.typicalWorkDays.count)
    }
  }

  func scheduleSmartNotifications(for userId: String) async {
    logger.info("Scheduling smart notifications for user \(userId.prefix(8))...")

    let center = UNUserNotificationCenter.current()
    let settings = await center.notificationSettings()

    guard
      settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        || settings.authorizationStatus == .ephemeral
    else {
      logger.warning("Notification permission not granted, skipping smart notifications")
      return
    }

    let prefsRepository = NotificationPreferencesRepository.shared
    let preferences = prefsRepository.getOrCreatePreferences(for: userId)

    guard preferences.smartNotificationsEnabled ?? true else {
      logger.info("Smart notifications disabled, cancelling existing")
      await cancelAllSmartNotifications()
      return
    }

    guard let pattern = WorkPatternAnalyzer.analyze(for: userId) else {
      logger.info("No work pattern detected, cancelling smart notifications")
      await cancelAllSmartNotifications()
      return
    }

    // Cancel existing smart notifications before scheduling
    let pendingRequests = await center.pendingNotificationRequests()
    let nonSmartPendingCount = pendingRequests.filter { request in
      let id = request.identifier
      return !id.hasPrefix(Self.morningIdentifierPrefix)
        && !id.hasPrefix(Self.eveningIdentifierPrefix)
    }.count

    await cancelAllSmartNotifications()

    let availableSlots = max(0, 64 - nonSmartPendingCount)
    let maxToSchedule = min(Self.maxSmartNotifications, availableSlots)
    if maxToSchedule == 0 {
      logger.info("No available slots for smart notifications")
      return
    }

    let calendar = Calendar.current
    let now = Date()
    let startOfToday = calendar.startOfDay(for: now)
    let existingShiftDates = getUpcomingShiftDates(for: userId, from: startOfToday)

    var scheduledCount = 0
    for dayOffset in 0..<Self.scheduleDaysAhead {
      guard scheduledCount < maxToSchedule else { break }
      guard let date = calendar.date(byAdding: .day, value: dayOffset, to: startOfToday) else {
        continue
      }
      let dateISO = date.toISODateString()

      if existingShiftDates.contains(dateISO) {
        continue
      }

      let weekday = calendar.component(.weekday, from: date) - 1
      guard let dayPattern = pattern.typicalWorkDays[weekday] else { continue }

      if scheduledCount < maxToSchedule {
        if await scheduleMorningPrompt(for: date, dateISO: dateISO, now: now) {
          scheduledCount += 1
        }
      }

      if scheduledCount < maxToSchedule {
        if await scheduleEveningPrompt(for: date, dateISO: dateISO, pattern: dayPattern, now: now) {
          scheduledCount += 1
        }
      }
    }

    logger.info("Scheduled \(scheduledCount) smart notifications")
  }

  func cancelAllSmartNotifications() async {
    let center = UNUserNotificationCenter.current()
    let pendingRequests = await center.pendingNotificationRequests()

    let smartIds =
      pendingRequests
      .map { $0.identifier }
      .filter {
        $0.hasPrefix(Self.morningIdentifierPrefix) || $0.hasPrefix(Self.eveningIdentifierPrefix)
      }

    if !smartIds.isEmpty {
      center.removePendingNotificationRequests(withIdentifiers: smartIds)
      logger.info("Cancelled \(smartIds.count) smart notifications")
    }
  }

  // MARK: - Scheduling Helpers

  private func scheduleMorningPrompt(
    for date: Date,
    dateISO: String,
    now: Date
  ) async -> Bool {
    let calendar = Calendar.current
    var components = calendar.dateComponents([.year, .month, .day], from: date)
    components.hour = Self.morningHour
    components.minute = 0

    guard let fireDate = calendar.date(from: components), fireDate > now else { return false }

    let content = buildMorningContent(date: date)
    let identifier = "\(Self.morningIdentifierPrefix)\(dateISO)"
    return await scheduleNotification(identifier: identifier, content: content, fireDate: fireDate)
  }

  private func scheduleEveningPrompt(
    for date: Date,
    dateISO: String,
    pattern: WorkPatternAnalyzer.DayPattern,
    now: Date
  ) async -> Bool {
    let calendar = Calendar.current
    let baseMinutes = pattern.medianEndMinutes + Self.eveningOffsetMinutes
    let dayOffset = baseMinutes / (24 * 60)
    let minuteOfDay = baseMinutes % (24 * 60)

    var components = calendar.dateComponents([.year, .month, .day], from: date)
    components.hour = minuteOfDay / 60
    components.minute = minuteOfDay % 60

    guard let baseDate = calendar.date(from: components),
      let fireDate = calendar.date(byAdding: .day, value: dayOffset, to: baseDate),
      fireDate > now
    else {
      return false
    }

    let content = buildEveningContent(dateISO: dateISO)
    let identifier = "\(Self.eveningIdentifierPrefix)\(dateISO)"
    return await scheduleNotification(identifier: identifier, content: content, fireDate: fireDate)
  }

  private func scheduleNotification(
    identifier: String,
    content: UNMutableNotificationContent,
    fireDate: Date
  ) async -> Bool {
    let center = UNUserNotificationCenter.current()
    let calendar = Calendar.current
    let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

    let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

    do {
      try await center.add(request)
      logger.debug("Scheduled smart notification: \(identifier) for \(fireDate)")
      return true
    } catch {
      logger.error("Failed to schedule smart notification: \(error.localizedDescription)")
      return false
    }
  }

  private func buildMorningContent(date: Date) -> UNMutableNotificationContent {
    let content = UNMutableNotificationContent()
    let weekday = localizedWeekdayName(for: date)

    content.title = String(localized: .notificationsSmartMorningTitle)
    content.body = String(localized: .notificationsSmartMorningBody(weekday))

    content.sound = UNNotificationSound(named: UNNotificationSoundName("tidex_notification.caf"))
    content.userInfo = [
      "type": "smart_prompt",
      "date": date.toISODateString(),
      "prompt_type": "morning",
    ]
    content.categoryIdentifier = "SMART_PROMPT"

    return content
  }

  private func buildEveningContent(dateISO: String) -> UNMutableNotificationContent {
    let content = UNMutableNotificationContent()
    content.title = String(localized: .notificationsSmartEveningTitle)
    content.body = String(localized: .notificationsSmartEveningBody)

    content.sound = UNNotificationSound(named: UNNotificationSoundName("tidex_notification.caf"))
    content.userInfo = [
      "type": "smart_prompt",
      "date": dateISO,
      "prompt_type": "evening",
    ]
    content.categoryIdentifier = "SMART_PROMPT"

    return content
  }

  private func localizedWeekdayName(for date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "EEEE"
    formatter.locale = appLocale()
    let text = formatter.string(from: date)
    return text.prefix(1).uppercased() + text.dropFirst()
  }

  private func getUpcomingShiftDates(for userId: String, from startDate: Date) -> Set<String> {
    let calendar = Calendar.current
    guard
      let endDate = calendar.date(byAdding: .day, value: Self.scheduleDaysAhead - 1, to: startDate)
    else {
      return []
    }

    let shiftsRepository = ShiftsRepository.shared
    let recurringRepository = RecurringShiftsRepository.shared

    let realShifts = shiftsRepository.getShifts(for: userId, startDate: startDate, endDate: endDate)
    let realDates = Set(realShifts.map { $0.shift_date })

    let recurringPatterns = recurringRepository.getRecurringShifts(for: userId)
    let monthsInRange = getMonthsInRange(startDate: startDate, endDate: endDate)

    var virtualDates: [String] = []
    for (year, month) in monthsInRange {
      for recurring in recurringPatterns {
        let generated = RecurringShiftGenerator.generateVirtualShiftsForMonth(
          year: year,
          month: month,
          recurring: recurring
        )

        for virtual in generated {
          guard let virtualDate = Date.fromISODateString(virtual.date),
            virtualDate >= startDate,
            virtualDate <= endDate
          else {
            continue
          }
          virtualDates.append(virtual.date)
        }
      }
    }

    let dedupedVirtuals = Set(virtualDates.filter { !realDates.contains($0) })
    return realDates.union(dedupedVirtuals)
  }

  private func getMonthsInRange(startDate: Date, endDate: Date) -> [(Int, Int)] {
    var months: [(Int, Int)] = []
    let calendar = Calendar.current

    var current =
      calendar.date(from: calendar.dateComponents([.year, .month], from: startDate)) ?? startDate
    let endMonth =
      calendar.date(from: calendar.dateComponents([.year, .month], from: endDate)) ?? endDate

    while current <= endMonth {
      let year = calendar.component(.year, from: current)
      let month = calendar.component(.month, from: current)
      months.append((year, month))
      current = calendar.date(byAdding: .month, value: 1, to: current) ?? current
    }

    return months
  }

  // MARK: - Debug Testing

  #if DEBUG
    enum TestNotificationType {
      case morning
      case evening
    }

    /// Schedule a test notification that fires 5 seconds from now
    func scheduleTestNotification(type: TestNotificationType) async -> Bool {
      let now = Date()
      let dateISO = now.toISODateString()

      let content: UNMutableNotificationContent
      let identifier: String

      switch type {
      case .morning:
        content = buildMorningContent(date: now)
        identifier = "smart-test-morning-\(Int(now.timeIntervalSince1970))"
      case .evening:
        content = buildEveningContent(dateISO: dateISO)
        identifier = "smart-test-evening-\(Int(now.timeIntervalSince1970))"
      }

      // Use time interval trigger for precise short delays
      // (UNCalendarNotificationTrigger only has minute-level granularity)
      let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
      let request = UNNotificationRequest(
        identifier: identifier, content: content, trigger: trigger)

      do {
        try await UNUserNotificationCenter.current().add(request)
        logger.debug("Scheduled test notification: \(identifier)")
        return true
      } catch {
        logger.error("Failed to schedule test notification: \(error.localizedDescription)")
        return false
      }
    }
  #endif
}

// MARK: - App Locale Helper

private func appLocale() -> Locale {
  let identifier = Bundle.main.preferredLocalizations.first ?? Locale.autoupdatingCurrent.identifier
  return Locale(identifier: identifier)
}
