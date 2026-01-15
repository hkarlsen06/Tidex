import Foundation
import SwiftData

// MARK: - Local Sync State

/// SwiftData model for tracking sync state per user
/// Stores revision cursors for incremental sync
@Model
final class LocalSyncState {
    // MARK: - Primary Key

    /// User ID (one sync state per user)
    @Attribute(.unique)
    var userId: String

    // MARK: - Revision Cursors

    /// Last synced revision for user_shifts table
    var lastRevisionUserShifts: Int64

    /// Last synced revision for recurring_shifts table
    var lastRevisionRecurringShifts: Int64

    /// Last synced revision for wage_snapshots table
    var lastRevisionWageSnapshots: Int64

    /// Last synced revision for user_settings table
    var lastRevisionUserSettings: Int64

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
        lastSyncError: String? = nil
    ) {
        self.userId = userId
        self.lastRevisionUserShifts = lastRevisionUserShifts
        self.lastRevisionRecurringShifts = lastRevisionRecurringShifts
        self.lastRevisionWageSnapshots = lastRevisionWageSnapshots
        self.lastRevisionUserSettings = lastRevisionUserSettings
        self.lastSuccessfulSyncAt = lastSuccessfulSyncAt
        self.lastSyncAttemptAt = lastSyncAttemptAt
        self.lastSyncError = lastSyncError
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

    /// Get cursor for a specific table
    func cursor(for table: SyncTable) -> Int64 {
        switch table {
        case .userShifts:
            return lastRevisionUserShifts
        case .recurringShifts:
            return lastRevisionRecurringShifts
        case .wageSnapshots:
            return lastRevisionWageSnapshots
        case .userSettings:
            return lastRevisionUserSettings
        }
    }

    /// Update cursor for a specific table
    func updateCursor(for table: SyncTable, to revision: Int64) {
        switch table {
        case .userShifts:
            lastRevisionUserShifts = revision
        case .recurringShifts:
            lastRevisionRecurringShifts = revision
        case .wageSnapshots:
            lastRevisionWageSnapshots = revision
        case .userSettings:
            lastRevisionUserSettings = revision
        }
    }

    /// Mark sync as started
    func markSyncStarted() {
        lastSyncAttemptAt = Date()
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
        lastRevisionUserShifts = 0
        lastRevisionRecurringShifts = 0
        lastRevisionWageSnapshots = 0
        lastRevisionUserSettings = 0
    }
}

// MARK: - Sync Table Enum

/// Tables that participate in sync
enum SyncTable: String, CaseIterable {
    case userShifts = "user_shifts"
    case recurringShifts = "recurring_shifts"
    case wageSnapshots = "wage_snapshots"
    case userSettings = "user_settings"

    /// Supabase table name
    var tableName: String {
        rawValue
    }

    /// Display name for logging
    var displayName: String {
        switch self {
        case .userShifts: return "User Shifts"
        case .recurringShifts: return "Recurring Shifts"
        case .wageSnapshots: return "Wage Snapshots"
        case .userSettings: return "User Settings"
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
