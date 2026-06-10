import Foundation
import SwiftData
import os.log

private let logger = Logger(
  subsystem: "com.tidex.app", category: "NotificationPreferencesRepository")

// MARK: - Notification Preferences Repository

/// Local-first repository for notification preferences
/// iOS is the source of truth for notification preferences
/// All reads come from SwiftData; network calls are handled by SyncCoordinator
/// Automatically triggers sync after mutations for immediate upload
@MainActor
final class NotificationPreferencesRepository: ObservableObject {
  static let shared = NotificationPreferencesRepository()

  private let localStore: LocalStore
  private let syncCoordinator: SyncCoordinator

  private init(localStore: LocalStore? = nil, syncCoordinator: SyncCoordinator? = nil) {
    self.localStore = localStore ?? LocalStore.shared
    self.syncCoordinator = syncCoordinator ?? SyncCoordinator.shared
  }

  // MARK: - Sync Helper

  /// Trigger sync after a mutation (fire-and-forget)
  private func triggerSync(userId: String) {
    Task {
      _ = await syncCoordinator.sync(reason: .localChange, userId: userId)
    }
  }

  // MARK: - Read Operations (Local Only)

  /// Get notification preferences for a user
  /// - Parameter userId: User ID (will be normalized to uppercase)
  /// - Returns: LocalNotificationPreferences if found, nil otherwise
  func getPreferences(for userId: String) -> LocalNotificationPreferences? {
    let context = localStore.mainContext
    let normalizedUserId = userId.uppercased()

    let descriptor = FetchDescriptor<LocalNotificationPreferences>(
      predicate: #Predicate { $0.userId == normalizedUserId }
    )

    do {
      return try context.fetch(descriptor).first
    } catch {
      logger.error("Failed to fetch notification preferences: \(error.localizedDescription)")
      return nil
    }
  }

  /// Get or create notification preferences with defaults
  /// - Parameter userId: User ID (will be normalized to uppercase)
  /// - Returns: LocalNotificationPreferences (existing or newly created with defaults)
  func getOrCreatePreferences(for userId: String) -> LocalNotificationPreferences {
    let normalizedUserId = userId.uppercased()

    if let existing = getPreferences(for: normalizedUserId) {
      if existing.smartNotificationsEnabled == nil {
        existing.smartNotificationsEnabled = true
        existing.markDirty()
        if let context = existing.modelContext {
          do {
            try context.save()
            logger.info("Backfilled smart notifications preference for user: \(normalizedUserId)")
            triggerSync(userId: normalizedUserId)
          } catch {
            logger.error(
              "Failed to backfill smart notifications preference: \(error.localizedDescription)")
          }
        } else {
          logger.error("Preferences object has no model context for backfill")
        }
      }
      return existing
    }

    // Create new preferences with defaults (always use normalized userId)
    let context = localStore.mainContext
    let preferences = LocalNotificationPreferences(
      userId: normalizedUserId,
      shiftRemindersEnabled: true,
      shiftReminderMinutesArray: LocalNotificationPreferences.defaultReminderMinutes,
      sharedShiftsEnabled: true,
      smartNotificationsEnabled: true,
      serverUpdatedAt: Date(),
      syncStatus: .dirty,  // Mark as dirty so it gets pushed to server
      localUpdatedAt: Date()
    )

    context.insert(preferences)

    do {
      try context.save()
      logger.info("Created new notification preferences for user: \(normalizedUserId)")
    } catch {
      logger.error("Failed to save new notification preferences: \(error.localizedDescription)")
    }

    return preferences
  }

  /// Check if reminders are enabled for a user
  /// - Parameter userId: User ID
  /// - Returns: True if shift reminders are enabled (defaults to true if no preferences exist)
  func areRemindersEnabled(for userId: String) -> Bool {
    getPreferences(for: userId)?.shiftRemindersEnabled ?? true
  }

  /// Get reminder minutes array for a user
  /// - Parameter userId: User ID
  /// - Returns: Array of reminder times in minutes (defaults to [300] if no preferences exist)
  func getReminderMinutes(for userId: String) -> [Int] {
    getPreferences(for: userId)?.shiftReminderMinutesArray
      ?? LocalNotificationPreferences.defaultReminderMinutes
  }

  /// Check if preferences have pending changes to sync
  /// - Parameter userId: User ID
  /// - Returns: True if preferences need to be pushed to server
  func hasPendingChanges(for userId: String) -> Bool {
    getPreferences(for: userId)?.isDirty ?? false
  }

  // MARK: - Write Operations (Local with Dirty Tracking)

  /// Update notification preferences
  /// - Parameters:
  ///   - userId: User ID
  ///   - remindersEnabled: Whether shift reminders are enabled (optional)
  ///   - reminderMinutes: Array of reminder times in minutes (optional)
  ///   - sharedShiftsEnabled: Whether shared shift notifications are enabled (optional)
  ///   - smartNotificationsEnabled: Whether smart notifications are enabled (optional)
  /// - Returns: Updated preferences if successful
  @discardableResult
  func updatePreferences(
    for userId: String,
    remindersEnabled: Bool? = nil,
    reminderMinutes: [Int]? = nil,
    sharedShiftsEnabled: Bool? = nil,
    smartNotificationsEnabled: Bool? = nil
  ) -> LocalNotificationPreferences? {
    let preferences = getOrCreatePreferences(for: userId)

    var hasChanges = false

    if let remindersEnabled,
      remindersEnabled != preferences.shiftRemindersEnabled
    {
      preferences.shiftRemindersEnabled = remindersEnabled
      hasChanges = true
    }

    if let reminderMinutes,
      reminderMinutes != preferences.shiftReminderMinutesArray
    {
      preferences.shiftReminderMinutesArray = reminderMinutes
      hasChanges = true
    }

    if let sharedShiftsEnabled,
      sharedShiftsEnabled != preferences.sharedShiftsEnabled
    {
      preferences.sharedShiftsEnabled = sharedShiftsEnabled
      hasChanges = true
    }

    let currentSmartEnabled = preferences.smartNotificationsEnabled ?? true
    if let smartNotificationsEnabled,
      smartNotificationsEnabled != currentSmartEnabled
    {
      preferences.smartNotificationsEnabled = smartNotificationsEnabled
      hasChanges = true
    }

    if hasChanges {
      preferences.markDirty()

      // Use the context that contains the preferences object
      guard let context = preferences.modelContext else {
        logger.error("Preferences object has no model context")
        return nil
      }

      do {
        try context.save()
        logger.info("Updated notification preferences for user: \(userId)")

        // Trigger sync to upload immediately
        triggerSync(userId: userId)
      } catch {
        logger.error("Failed to save notification preferences: \(error.localizedDescription)")
        return nil
      }
    }

    return preferences
  }

  /// Toggle shift reminders on/off
  /// - Parameter userId: User ID
  /// - Returns: New enabled state
  @discardableResult
  func toggleReminders(for userId: String) -> Bool {
    let preferences = getOrCreatePreferences(for: userId)
    let newState = !preferences.shiftRemindersEnabled

    updatePreferences(for: userId, remindersEnabled: newState)

    return newState
  }

  // MARK: - Sync Support

  /// Save preferences from server response
  /// iOS is source of truth - only creates new record if none exists locally
  /// Never updates existing local data from server
  /// - Parameters:
  ///   - row: Server response row
  ///   - serverUpdatedAt: Server's updated_at timestamp
  func saveFromServer(row: NotificationPreferencesRow, serverUpdatedAt: Date) {
    let context = localStore.mainContext
    let normalizedUserId = row.user_id.uppercased()

    // iOS is source of truth - only create new record if none exists locally
    if getPreferences(for: normalizedUserId) != nil {
      return
    }

    // Insert new record from server (first sync after install/login)
    let preferences = LocalNotificationPreferences(
      userId: normalizedUserId,
      shiftRemindersEnabled: row.shift_reminders_enabled,
      shiftReminderMinutesArray: row.shift_reminder_minutes_array
        ?? LocalNotificationPreferences.defaultReminderMinutes,
      sharedShiftsEnabled: row.shared_shifts_enabled,
      serverUpdatedAt: serverUpdatedAt,
      syncStatus: .clean,
      localUpdatedAt: Date()
    )
    context.insert(preferences)

    do {
      try context.save()
      logger.debug("Created notification preferences from server for user: \(normalizedUserId)")
    } catch {
      logger.error(
        "Failed to save notification preferences from server: \(error.localizedDescription)")
    }
  }

  /// Get dirty preferences for a user (needs to be pushed)
  /// - Parameter userId: User ID
  /// - Returns: Dirty preferences if exists, nil otherwise
  func getDirtyPreferences(for userId: String) -> LocalNotificationPreferences? {
    guard let preferences = getPreferences(for: userId),
      preferences.isDirty
    else {
      return nil
    }
    return preferences
  }

  /// Mark preferences as clean after successful push
  /// - Parameters:
  ///   - userId: User ID
  ///   - serverUpdatedAt: Server's updated_at timestamp
  func markClean(for userId: String, serverUpdatedAt: Date) {
    guard let preferences = getPreferences(for: userId) else {
      return
    }

    preferences.markClean(serverUpdatedAt: serverUpdatedAt)

    // Use the context that contains the preferences object
    guard let context = preferences.modelContext else {
      logger.error("Preferences object has no model context")
      return
    }

    do {
      try context.save()
      logger.debug("Marked notification preferences as clean for user: \(userId)")
    } catch {
      logger.error("Failed to mark preferences as clean: \(error.localizedDescription)")
    }
  }

  // MARK: - Cleanup

  /// Delete all preferences for a user (on logout)
  /// - Parameter userId: User ID
  func deleteAll(for userId: String) {
    guard let preferences = getPreferences(for: userId) else {
      return
    }

    // Use the context that contains the preferences object
    guard let context = preferences.modelContext else {
      logger.error("Preferences object has no model context")
      return
    }

    context.delete(preferences)

    do {
      try context.save()
      logger.info("Deleted notification preferences for user: \(userId)")
    } catch {
      logger.error("Failed to delete notification preferences: \(error.localizedDescription)")
    }
  }
}
