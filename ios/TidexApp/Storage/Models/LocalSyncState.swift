import Foundation
import SwiftData

// MARK: - Local Sync State

/// SwiftData model for tracking sync state per user
/// Pulls page by revision. Convex numbers every write with one counter for the whole deployment,
/// so a table's cursor is the revision of the last row the device has applied.
@Model
final class LocalSyncState {
  // MARK: - Primary Key

  /// User ID (one sync state per user)
  @Attribute(.unique)
  var userId: String

  // MARK: - Revision Cursors (primary cursors for pull sync)

  /// Last pulled revision for user_shifts table
  var lastRevisionUserShifts: Int64

  /// Last pulled revision for recurring_shifts table
  var lastRevisionRecurringShifts: Int64

  /// Last pulled revision for wage_snapshots table
  var lastRevisionWageSnapshots: Int64

  /// Last pulled revision for user_settings table
  var lastRevisionUserSettings: Int64

  // The tables below got a revision cursor with the move to Convex. The defaults here let
  // SwiftData add the columns to an existing store.

  /// Last pulled revision for jobs table
  var lastRevisionJobs: Int64 = 0

  /// Last pulled revision for events table
  var lastRevisionEvents: Int64 = 0

  /// Last pulled revision for payroll_adjustments table
  var lastRevisionPayrollAdjustments: Int64 = 0

  /// Last pulled revision for notification_preferences table
  var lastRevisionNotificationPreferences: Int64 = 0

  /// When the cursors were reset for Convex. Postgres revisions mean nothing there, so the first
  /// sync after the update starts every table at 0. Nil means that has not happened yet.
  var convexCursorsResetAt: Date?

  // MARK: - Updated-At Cursors (Postgres, no longer read)

  // These held the old Postgres pull position (updated_at plus an id tie-breaker). The columns stay
  // so the store opens unchanged. Nothing reads them since the pull moved to revision cursors.

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
    lastRevisionJobs: Int64 = 0,
    lastRevisionEvents: Int64 = 0,
    lastRevisionPayrollAdjustments: Int64 = 0,
    lastRevisionNotificationPreferences: Int64 = 0,
    convexCursorsResetAt: Date? = nil,
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
    self.lastRevisionJobs = lastRevisionJobs
    self.lastRevisionEvents = lastRevisionEvents
    self.lastRevisionPayrollAdjustments = lastRevisionPayrollAdjustments
    self.lastRevisionNotificationPreferences = lastRevisionNotificationPreferences
    self.convexCursorsResetAt = convexCursorsResetAt
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

  // MARK: - Postgres Cursor Methods (no longer used by the pull)

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

  // MARK: - Revision Cursor Methods

  /// Get the revision cursor for a specific table
  func cursor(for table: SyncTable) -> Int64 {
    switch table {
    case .jobs:
      return lastRevisionJobs

    case .userShifts:
      return lastRevisionUserShifts

    case .events:
      return lastRevisionEvents

    case .recurringShifts:
      return lastRevisionRecurringShifts

    case .wageSnapshots:
      return lastRevisionWageSnapshots

    case .payrollAdjustments:
      return lastRevisionPayrollAdjustments

    case .userSettings:
      return lastRevisionUserSettings

    case .notificationPreferences:
      return lastRevisionNotificationPreferences
    }
  }

  /// Update the revision cursor for a specific table
  func updateCursor(for table: SyncTable, to revision: Int64) {
    switch table {
    case .jobs:
      lastRevisionJobs = revision

    case .userShifts:
      lastRevisionUserShifts = revision

    case .events:
      lastRevisionEvents = revision

    case .recurringShifts:
      lastRevisionRecurringShifts = revision

    case .wageSnapshots:
      lastRevisionWageSnapshots = revision

    case .payrollAdjustments:
      lastRevisionPayrollAdjustments = revision

    case .userSettings:
      lastRevisionUserSettings = revision

    case .notificationPreferences:
      lastRevisionNotificationPreferences = revision
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
    lastRevisionJobs = 0
    lastRevisionUserShifts = 0
    lastRevisionEvents = 0
    lastRevisionRecurringShifts = 0
    lastRevisionWageSnapshots = 0
    lastRevisionPayrollAdjustments = 0
    lastRevisionUserSettings = 0
    lastRevisionNotificationPreferences = 0
  }

  /// Starts every table at revision 0 once. Revisions kept from Postgres mean nothing on Convex,
  /// because the migration gave every row a new one. The next pull then returns every row, and
  /// the merge gives local rows with unsent edits the server revision before they push.
  func resetCursorsForConvex(at date: Date = Date()) {
    resetAllCursors()
    convexCursorsResetAt = date
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

  /// Table name on the server
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
  /// The server has newer rows than the local cursors, seen by `SyncRevisionWatcher`
  case remoteChange = "remote_change"
}
