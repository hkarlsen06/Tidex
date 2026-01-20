import Foundation
import SwiftData
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "NotificationPreferencesRepository")

// MARK: - Notification Preferences Repository

/// Local-first repository for notification preferences
/// iOS is the source of truth for notification preferences
/// All reads come from SwiftData; network calls are handled by SyncCoordinator
@MainActor
final class NotificationPreferencesRepository: ObservableObject {
    static let shared = NotificationPreferencesRepository()

    private let localStore: LocalStore

    private init(localStore: LocalStore? = nil) {
        self.localStore = localStore ?? LocalStore.shared
    }

    // MARK: - Read Operations (Local Only)

    /// Get notification preferences for a user
    /// - Parameter userId: User ID
    /// - Returns: LocalNotificationPreferences if found, nil otherwise
    func getPreferences(for userId: String) -> LocalNotificationPreferences? {
        let context = localStore.mainContext

        let descriptor = FetchDescriptor<LocalNotificationPreferences>(
            predicate: #Predicate { $0.userId == userId }
        )

        do {
            return try context.fetch(descriptor).first
        } catch {
            logger.error("Failed to fetch notification preferences: \(error.localizedDescription)")
            return nil
        }
    }

    /// Get or create notification preferences with defaults
    /// - Parameter userId: User ID
    /// - Returns: LocalNotificationPreferences (existing or newly created with defaults)
    func getOrCreatePreferences(for userId: String) -> LocalNotificationPreferences {
        if let existing = getPreferences(for: userId) {
            return existing
        }

        // Create new preferences with defaults
        let context = localStore.mainContext
        let preferences = LocalNotificationPreferences(
            userId: userId,
            shiftRemindersEnabled: true,
            shiftReminderMinutesArray: LocalNotificationPreferences.defaultReminderMinutes,
            sharedShiftsEnabled: true,
            serverUpdatedAt: Date(),
            syncStatus: .dirty, // Mark as dirty so it gets pushed to server
            localUpdatedAt: Date()
        )

        context.insert(preferences)

        do {
            try context.save()
            logger.info("Created new notification preferences for user: \(userId)")
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
        getPreferences(for: userId)?.shiftReminderMinutesArray ?? LocalNotificationPreferences.defaultReminderMinutes
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
    /// - Returns: Updated preferences if successful
    @discardableResult
    func updatePreferences(
        for userId: String,
        remindersEnabled: Bool? = nil,
        reminderMinutes: [Int]? = nil,
        sharedShiftsEnabled: Bool? = nil
    ) -> LocalNotificationPreferences? {
        let context = localStore.mainContext
        let preferences = getOrCreatePreferences(for: userId)

        var hasChanges = false

        if let remindersEnabled = remindersEnabled, remindersEnabled != preferences.shiftRemindersEnabled {
            preferences.shiftRemindersEnabled = remindersEnabled
            hasChanges = true
        }

        if let reminderMinutes = reminderMinutes, reminderMinutes != preferences.shiftReminderMinutesArray {
            preferences.shiftReminderMinutesArray = reminderMinutes
            hasChanges = true
        }

        if let sharedShiftsEnabled = sharedShiftsEnabled, sharedShiftsEnabled != preferences.sharedShiftsEnabled {
            preferences.sharedShiftsEnabled = sharedShiftsEnabled
            hasChanges = true
        }

        if hasChanges {
            preferences.markDirty()

            do {
                try context.save()
                logger.info("Updated notification preferences for user: \(userId)")
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
    /// Only updates if local is not dirty (iOS is source of truth)
    /// - Parameters:
    ///   - row: Server response row
    ///   - serverUpdatedAt: Server's updated_at timestamp
    func saveFromServer(row: NotificationPreferencesRow, serverUpdatedAt: Date) {
        let context = localStore.mainContext

        if let existing = getPreferences(for: row.user_id) {
            // Only update from server if not dirty (iOS is source of truth)
            existing.updateFromServer(row: row, serverUpdatedAt: serverUpdatedAt)
        } else {
            // Insert new record from server
            let preferences = LocalNotificationPreferences.from(
                serverRow: row,
                serverUpdatedAt: serverUpdatedAt
            )
            context.insert(preferences)
        }

        do {
            try context.save()
            logger.debug("Saved notification preferences from server for user: \(row.user_id)")
        } catch {
            logger.error("Failed to save notification preferences from server: \(error.localizedDescription)")
        }
    }

    /// Get dirty preferences for a user (needs to be pushed)
    /// - Parameter userId: User ID
    /// - Returns: Dirty preferences if exists, nil otherwise
    func getDirtyPreferences(for userId: String) -> LocalNotificationPreferences? {
        guard let preferences = getPreferences(for: userId),
              preferences.isDirty else {
            return nil
        }
        return preferences
    }

    /// Mark preferences as clean after successful push
    /// - Parameters:
    ///   - userId: User ID
    ///   - serverUpdatedAt: Server's updated_at timestamp
    func markClean(for userId: String, serverUpdatedAt: Date) {
        let context = localStore.mainContext

        guard let preferences = getPreferences(for: userId) else {
            return
        }

        preferences.markClean(serverUpdatedAt: serverUpdatedAt)

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
        let context = localStore.mainContext

        guard let preferences = getPreferences(for: userId) else {
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
