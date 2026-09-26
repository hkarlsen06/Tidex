import Foundation
import SwiftData

// MARK: - Local Sync State

/// SwiftData model for tracking sync state per user
/// Uses updated_at cursors for incremental sync (NOT revision, as revision is per-row and new rows start at 1)
@Model
final class LocalSyncState {
  // MARK: - Primary Key

  /// User ID (one sync state per user)
  @Attribute(.unique)
  var userId: String

  // MARK: - Legacy Revision Cursors (DEPRECATED - kept for debugging only)

  /// Last synced revision for user_shifts table (DEPRECATED)
  var lastRevisionUserShifts: Int64

  /// Last synced revision for recurring_shifts table (DEPRECATED)
  var lastRevisionRecurringShifts: Int64

  /// Last synced revision for wage_snapshots table (DEPRECATED)
  var lastRevisionWageSnapshots: Int64

  /// Last synced revision for user_settings table (DEPRECATED)
  var lastRevisionUserSettings: Int64

  // MARK: - Updated-At Cursors (Primary cursors for pull sync)

  // These use server-managed updated_at timestamps for incremental sync.
  // A tie-breaker (id) is used when multiple rows share the same timestamp.

  /// Last synced updated_at for jobs table
  var lastJobsUpdatedAt: Date?

  /// Tie-breaker ID at the last synced updated_at for jobs
  var lastJobsUpdatedAtTieId: String?

  /// Last synced updated_at for user_shifts table
  var lastUserShiftsUpdatedAt: Date?

  /// Tie-breaker ID at the last synced updated_at for user_shifts
  var lastUserShiftsUpdatedAtTieId: String?

  /// Last synced updated_at for events table
  var lastEventsUpdatedAt: Date?

  /// Tie-breaker ID at the last synced updated_at for events
  var lastEventsUpdatedAtTieId: String?

  /// Last synced updated_at for recurring_shifts table
  var lastRecurringShiftsUpdatedAt: Date?

  /// Tie-breaker ID at the last synced updated_at for recurring_shifts
  var lastRecurringShiftsUpdatedAtTieId: String?

  /// Last synced updated_at for wage_snapshots table
  var lastWageSnapshotsUpdatedAt: Date?

  /// Tie-breaker ID at the last synced updated_at for wage_snapshots
  var lastWageSnapshotsUpdatedAtTieId: String?

  /// Last synced updated_at for payroll_adjustments table
  var lastPayrollAdjustmentsUpdatedAt: Date?

  /// Tie-breaker ID at the last synced updated_at for payroll_adjustments
  var lastPayrollAdjustmentsUpdatedAtTieId: String?

  /// Last synced updated_at for user_settings table
  var lastUserSettingsUpdatedAt: Date?

  /// Tie-breaker ID at the last synced updated_at for user_settings
  var lastUserSettingsUpdatedAtTieId: String?

  /// Last synced updated_at for notification_preferences table
  var lastNotificationPreferencesUpdatedAt: Date?

  /// Tie-breaker ID at the last synced updated_at for notification_preferences
  var lastNotificationPreferencesUpdatedAtTieId: String?

  // MARK: - Sync Timestamps

  /// When the last successful sync completed
  var lastSuccessfulSyncAt: Date?

  /// When the last sync attempt started
  var lastSyncAttemptAt: Date?

  /// Error message from last failed sync (nil if last sync succeeded)
  var lastSyncError: String?

  // MARK: - Initialization

  init(
    userId: String,
    lastRevisionUserShifts: Int64 = 0,
    lastRevisionRecurringShifts: Int64 = 0,
    lastRevisionWageSnapshots: Int64 = 0,
    lastRevisionUserSettings: Int64 = 0,
    lastSuccessfulSyncAt: Date? = nil,
    lastSyncAttemptAt: Date? = nil,
    lastSyncError: String? = nil,
    lastJobsUpdatedAt: Date? = nil,
    lastJobsUpdatedAtTieId: String? = nil,
    lastUserShiftsUpdatedAt: Date? = nil,
    lastUserShiftsUpdatedAtTieId: String? = nil,
    lastEventsUpdatedAt: Date? = nil,
    lastEventsUpdatedAtTieId: String? = nil,
    lastRecurringShiftsUpdatedAt: Date? = nil,
    lastRecurringShiftsUpdatedAtTieId: String? = nil,
    lastWageSnapshotsUpdatedAt: Date? = nil,
    lastWageSnapshotsUpdatedAtTieId: String? = nil,
    lastPayrollAdjustmentsUpdatedAt: Date? = nil,
    lastPayrollAdjustmentsUpdatedAtTieId: String? = nil,
    lastUserSettingsUpdatedAt: Date? = nil,
    lastUserSettingsUpdatedAtTieId: String? = nil,
    lastNotificationPreferencesUpdatedAt: Date? = nil,
    lastNotificationPreferencesUpdatedAtTieId: String? = nil
  ) {
    self.userId = userId
    self.lastRevisionUserShifts = lastRevisionUserShifts
    self.lastRevisionRecurringShifts = lastRevisionRecurringShifts
    self.lastRevisionWageSnapshots = lastRevisionWageSnapshots
    self.lastRevisionUserSettings = lastRevisionUserSettings
    self.lastSuccessfulSyncAt = lastSuccessfulSyncAt
    self.lastSyncAttemptAt = lastSyncAttemptAt
    self.lastSyncError = lastSyncError
    self.lastJobsUpdatedAt = lastJobsUpdatedAt
    self.lastJobsUpdatedAtTieId = lastJobsUpdatedAtTieId
    self.lastUserShiftsUpdatedAt = lastUserShiftsUpdatedAt
    self.lastUserShiftsUpdatedAtTieId = lastUserShiftsUpdatedAtTieId
    self.lastEventsUpdatedAt = lastEventsUpdatedAt
    self.lastEventsUpdatedAtTieId = lastEventsUpdatedAtTieId
    self.lastRecurringShiftsUpdatedAt = lastRecurringShiftsUpdatedAt
    self.lastRecurringShiftsUpdatedAtTieId = lastRecurringShiftsUpdatedAtTieId
    self.lastWageSnapshotsUpdatedAt = lastWageSnapshotsUpdatedAt
    self.lastWageSnapshotsUpdatedAtTieId = lastWageSnapshotsUpdatedAtTieId
    self.lastPayrollAdjustmentsUpdatedAt = lastPayrollAdjustmentsUpdatedAt
    self.lastPayrollAdjustmentsUpdatedAtTieId = lastPayrollAdjustmentsUpdatedAtTieId
    self.lastUserSettingsUpdatedAt = lastUserSettingsUpdatedAt
    self.lastUserSettingsUpdatedAtTieId = lastUserSettingsUpdatedAtTieId
    self.lastNotificationPreferencesUpdatedAt = lastNotificationPreferencesUpdatedAt
    self.lastNotificationPreferencesUpdatedAtTieId = lastNotificationPreferencesUpdatedAtTieId
  }

  // MARK: - Convenience Methods

  /// Whether any data has been synced for this user
  var hasSyncedBefore: Bool {
    lastSuccessfulSyncAt != nil
  }

  /// Whether the last sync was successful
  var isLastSyncSuccessful: Bool {
    lastSyncError == nil && lastSuccessfulSyncAt != nil
  }

  // MARK: - Updated-At Cursor Methods (Primary)

  /// Get updated_at cursor for a specific table
  func updatedAtCursor(for table: SyncTable) -> SyncCursor {
    switch table {
    case .jobs:
      return SyncCursor(
        updatedAt: lastJobsUpdatedAt, tieId: lastJobsUpdatedAtTieId ?? "")

    case .userShifts:
      return SyncCursor(
        updatedAt: lastUserShiftsUpdatedAt, tieId: lastUserShiftsUpdatedAtTieId ?? "")

    case .events:
      return SyncCursor(
        updatedAt: lastEventsUpdatedAt, tieId: lastEventsUpdatedAtTieId ?? "")

    case .recurringShifts:
      return SyncCursor(
        updatedAt: lastRecurringShiftsUpdatedAt, tieId: lastRecurringShiftsUpdatedAtTieId ?? "")

    case .wageSnapshots:
      return SyncCursor(
        updatedAt: lastWageSnapshotsUpdatedAt, tieId: lastWageSnapshotsUpdatedAtTieId ?? "")

    case .payrollAdjustments:
      return SyncCursor(
        updatedAt: lastPayrollAdjustmentsUpdatedAt,
        tieId: lastPayrollAdjustmentsUpdatedAtTieId ?? "")

    case .userSettings:
      return SyncCursor(
        updatedAt: lastUserSettingsUpdatedAt, tieId: lastUserSettingsUpdatedAtTieId ?? "")

    case .notificationPreferences:
      return SyncCursor(
        updatedAt: lastNotificationPreferencesUpdatedAt,
        tieId: lastNotificationPreferencesUpdatedAtTieId ?? "")
    }
  }

  /// Update updated_at cursor for a specific table
  func updateUpdatedAtCursor(for table: SyncTable, updatedAt: Date, tieId: String) {
    switch table {
    case .jobs:
      lastJobsUpdatedAt = updatedAt
      lastJobsUpdatedAtTieId = tieId

    case .userShifts:
      lastUserShiftsUpdatedAt = updatedAt
      lastUserShiftsUpdatedAtTieId = tieId

    case .events:
      lastEventsUpdatedAt = updatedAt
      lastEventsUpdatedAtTieId = tieId

    case .recurringShifts:
      lastRecurringShiftsUpdatedAt = updatedAt
      lastRecurringShiftsUpdatedAtTieId = tieId

    case .wageSnapshots:
      lastWageSnapshotsUpdatedAt = updatedAt
      lastWageSnapshotsUpdatedAtTieId = tieId

    case .payrollAdjustments:
      lastPayrollAdjustmentsUpdatedAt = updatedAt
      lastPayrollAdjustmentsUpdatedAtTieId = tieId

    case .userSettings:
      lastUserSettingsUpdatedAt = updatedAt
      lastUserSettingsUpdatedAtTieId = tieId

    case .notificationPreferences:
      lastNotificationPreferencesUpdatedAt = updatedAt
      lastNotificationPreferencesUpdatedAtTieId = tieId
    }
  }

  // MARK: - Legacy Revision Cursor Methods (DEPRECATED)

  /// Get cursor for a specific table (DEPRECATED - use updatedAtCursor instead)
  func cursor(for table: SyncTable) -> Int64 {
    switch table {
    case .jobs:
      return 0

    case .userShifts:
      return lastRevisionUserShifts

    case .events:
      return 0

    case .recurringShifts:
      return lastRevisionRecurringShifts

    case .wageSnapshots:
      return lastRevisionWageSnapshots

    case .payrollAdjustments:
      return 0

    case .userSettings:
      return lastRevisionUserSettings

    case .notificationPreferences:
      return 0  // No legacy revision for notification preferences
    }
  }

  /// Update cursor for a specific table (DEPRECATED - use updateUpdatedAtCursor instead)
  func updateCursor(for table: SyncTable, to revision: Int64) {
    switch table {
    case .jobs:
      break

    case .userShifts:
      lastRevisionUserShifts = revision

    case .events:
      break

    case .recurringShifts:
      lastRevisionRecurringShifts = revision

    case .wageSnapshots:
      lastRevisionWageSnapshots = revision

    case .payrollAdjustments:
      break

    case .userSettings:
      lastRevisionUserSettings = revision

    case .notificationPreferences:
      break  // No legacy revision for notification preferences
    }
  }

  /// Mark sync as started
  internal func markSyncStarted(at date: Date = Date()) {
    lastSyncAttemptAt = date
    lastSyncError = nil
  }

  /// Mark sync as completed successfully
  func markSyncSucceeded() {
    lastSuccessfulSyncAt = Date()
    lastSyncError = nil
  }

  /// Mark sync as failed with error
  func markSyncFailed(error: String) {
    lastSyncError = error
  }

  /// Reset all cursors (for full re-sync)
  func resetAllCursors() {
    // Reset updated_at cursors
    lastJobsUpdatedAt = nil
    lastJobsUpdatedAtTieId = nil
    lastUserShiftsUpdatedAt = nil
    lastUserShiftsUpdatedAtTieId = nil
    lastEventsUpdatedAt = nil
    lastEventsUpdatedAtTieId = nil
    lastRecurringShiftsUpdatedAt = nil
    lastRecurringShiftsUpdatedAtTieId = nil
    lastWageSnapshotsUpdatedAt = nil
    lastWageSnapshotsUpdatedAtTieId = nil
    lastPayrollAdjustmentsUpdatedAt = nil
    lastPayrollAdjustmentsUpdatedAtTieId = nil
    lastUserSettingsUpdatedAt = nil
    lastUserSettingsUpdatedAtTieId = nil
    lastNotificationPreferencesUpdatedAt = nil
    lastNotificationPreferencesUpdatedAtTieId = nil

    // Reset legacy revision cursors (for debugging)
    lastRevisionUserShifts = 0
    lastRevisionRecurringShifts = 0
    lastRevisionWageSnapshots = 0
    lastRevisionUserSettings = 0
  }
}

// MARK: - Sync Cursor Type

/// Cursor for incremental sync using updated_at timestamp with tie-breaker
struct SyncCursor {
  /// Server updated_at timestamp (nil means start from beginning)
  let updatedAt: Date?

  /// Tie-breaker ID (used when multiple rows share the same timestamp)
  let tieId: String

  /// Whether this is the initial sync (no cursor set)
  var isInitial: Bool {
    updatedAt == nil
  }

  /// Format the cursor for logging
  var description: String {
    if let updatedAt {
      let formattedUpdatedAt = FormatterCache.iso8601Formatter().string(from: updatedAt)
      return
        "updated_at: \(formattedUpdatedAt), tieId: \(tieId.prefix(8))..."
    }
    return "initial (no cursor)"
  }
}

// MARK: - Sync Table Enum

/// Tables that participate in sync
enum SyncTable: String, CaseIterable {
  case jobs = "jobs"
  case userShifts = "user_shifts"
  case events = "events"
  case recurringShifts = "recurring_shifts"
  case wageSnapshots = "wage_snapshots"
  case payrollAdjustments = "payroll_adjustments"
  case userSettings = "user_settings"
  case notificationPreferences = "notification_preferences"

  /// Supabase table name
  var tableName: String {
    rawValue
  }

  /// Display name for logging
  var displayName: String {
    switch self {
    case .jobs: return "Jobs"
    case .userShifts: return "User Shifts"
    case .events: return "Events"
    case .recurringShifts: return "Recurring Shifts"
    case .wageSnapshots: return "Wage Snapshots"
    case .payrollAdjustments: return "Payroll Adjustments"
    case .userSettings: return "User Settings"
    case .notificationPreferences: return "Notification Preferences"
    }
  }
}

// MARK: - Sync Reason

/// Reason for triggering a sync
enum SyncReason: String {
  /// Sync on app launch after authentication
  case appLaunch = "app_launch"
  /// Sync when app enters foreground
  case foreground = "foreground"
  /// User manually triggered refresh
  case manualRefresh = "manual_refresh"
  /// Sync after local changes (e.g., adding a shift)
  case localChange = "local_change"
}
