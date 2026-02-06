import Foundation
import SwiftData

// MARK: - Local Notification Preferences

/// SwiftData model for locally persisted notification preferences
/// Maps to the `notification_preferences` table in Supabase
/// Note: iOS is the source of truth for notification preferences
@Model
final class LocalNotificationPreferences {
  // MARK: - Primary Key

  /// User ID (primary key - one preferences row per user)
  @Attribute(.unique)
  var userId: String

  // MARK: - Notification Preferences Data

  /// Whether shift reminders are enabled
  var shiftRemindersEnabled: Bool

  /// Array of reminder times in minutes before shift (e.g., [60, 300] = 1hr and 5hr before)
  var shiftReminderMinutesArray: [Int]

  /// Whether notifications for shared shift changes are enabled
  var sharedShiftsEnabled: Bool

  /// Whether smart notifications are enabled
  var smartNotificationsEnabled: Bool?

  // MARK: - Server Metadata

  /// Server's updated_at timestamp
  var serverUpdatedAt: Date

  // MARK: - Sync Metadata

  /// Current sync status (clean or dirty - no conflict detection since iOS is source of truth)
  var syncStatusRaw: String

  /// When the user last modified this record locally
  var localUpdatedAt: Date

  // MARK: - Computed Properties

  var syncStatus: SyncStatus {
    get { SyncStatus(rawValue: syncStatusRaw) ?? .clean }
    set { syncStatusRaw = newValue.rawValue }
  }

  /// Whether this record has local changes that need to be pushed
  var isDirty: Bool {
    syncStatus == .dirty
  }

  // MARK: - Initialization

  init(
    userId: String,
    shiftRemindersEnabled: Bool = true,
    shiftReminderMinutesArray: [Int] = [300],
    sharedShiftsEnabled: Bool = true,
    smartNotificationsEnabled: Bool = true,
    serverUpdatedAt: Date = Date(),
    syncStatus: SyncStatus = .clean,
    localUpdatedAt: Date = Date()
  ) {
    self.userId = userId
    self.shiftRemindersEnabled = shiftRemindersEnabled
    self.shiftReminderMinutesArray = shiftReminderMinutesArray
    self.sharedShiftsEnabled = sharedShiftsEnabled
    self.smartNotificationsEnabled = smartNotificationsEnabled
    self.serverUpdatedAt = serverUpdatedAt
    self.syncStatusRaw = syncStatus.rawValue
    self.localUpdatedAt = localUpdatedAt
  }

  // MARK: - Default Values

  /// Default reminder minutes (5 hours before shift)
  static let defaultReminderMinutes: [Int] = [300]
}

// MARK: - Server Response Model

/// Codable model matching the notification_preferences table structure
struct NotificationPreferencesRow: Codable {
  let user_id: String
  let shared_shifts_enabled: Bool
  let shift_reminders_enabled: Bool
  let shift_reminder_minutes_array: [Int]?
  let updated_at: String

  /// Parse updated_at string to Date
  var updatedAtDate: Date? {
    ISO8601DateFormatter().date(from: updated_at)
  }
}

// MARK: - Conversion Extensions

extension LocalNotificationPreferences {
  /// Create from a server response row
  static func from(
    serverRow: NotificationPreferencesRow,
    serverUpdatedAt: Date
  ) -> LocalNotificationPreferences {
    LocalNotificationPreferences(
      userId: serverRow.user_id,
      shiftRemindersEnabled: serverRow.shift_reminders_enabled,
      shiftReminderMinutesArray: serverRow.shift_reminder_minutes_array ?? defaultReminderMinutes,
      sharedShiftsEnabled: serverRow.shared_shifts_enabled,
      smartNotificationsEnabled: true,
      serverUpdatedAt: serverUpdatedAt,
      syncStatus: .clean,
      localUpdatedAt: Date()
    )
  }

  /// Update from server row (preserves local changes if dirty)
  func updateFromServer(row: NotificationPreferencesRow, serverUpdatedAt: Date) {
    // Only update if not dirty (iOS is source of truth)
    guard syncStatus == .clean else { return }

    self.shiftRemindersEnabled = row.shift_reminders_enabled
    self.shiftReminderMinutesArray =
      row.shift_reminder_minutes_array ?? LocalNotificationPreferences.defaultReminderMinutes
    self.sharedShiftsEnabled = row.shared_shifts_enabled
    self.serverUpdatedAt = serverUpdatedAt
  }

  /// Mark as dirty after local modification
  func markDirty() {
    syncStatus = .dirty
    localUpdatedAt = Date()
  }

  /// Mark as clean after successful push
  func markClean(serverUpdatedAt: Date) {
    syncStatus = .clean
    self.serverUpdatedAt = serverUpdatedAt
  }
}
