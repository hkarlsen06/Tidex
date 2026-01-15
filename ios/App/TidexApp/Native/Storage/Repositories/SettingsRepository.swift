import Foundation
import SwiftData
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "SettingsRepository")

// MARK: - Settings Repository

/// Local-first repository for user settings
/// All reads come from SwiftData; network calls are handled by SyncCoordinator
@MainActor
final class SettingsRepository: ObservableObject {
    static let shared = SettingsRepository()

    private let localStore: LocalStore

    private init(localStore: LocalStore? = nil) {
        self.localStore = localStore ?? LocalStore.shared
    }

    // MARK: - Read Operations (Local Only)

    /// Get user settings for a user
    /// - Parameter userId: User ID
    /// - Returns: UserSettings if found, nil otherwise
    func getSettings(for userId: String) -> UserSettings? {
        let context = localStore.mainContext

        let descriptor = FetchDescriptor<LocalUserSettings>(
            predicate: #Predicate { $0.userId == userId }
        )

        do {
            guard let localSettings = try context.fetch(descriptor).first else {
                return nil
            }
            return localSettings.toUserSettings()
        } catch {
            logger.error("Failed to fetch settings: \(error.localizedDescription)")
            return nil
        }
    }

    /// Get the raw LocalUserSettings object
    /// - Parameter userId: User ID
    /// - Returns: LocalUserSettings if found
    func getLocalSettings(for userId: String) -> LocalUserSettings? {
        let context = localStore.mainContext

        let descriptor = FetchDescriptor<LocalUserSettings>(
            predicate: #Predicate { $0.userId == userId }
        )

        do {
            return try context.fetch(descriptor).first
        } catch {
            logger.error("Failed to fetch local settings: \(error.localizedDescription)")
            return nil
        }
    }

    /// Check if settings have a sync conflict
    /// - Parameter userId: User ID
    /// - Returns: True if settings are in conflict state
    func hasConflict(for userId: String) -> Bool {
        guard let localSettings = getLocalSettings(for: userId) else {
            return false
        }
        return localSettings.syncStatus == .conflict
    }

    /// Check if settings have pending changes
    /// - Parameter userId: User ID
    /// - Returns: True if settings are dirty
    func hasPendingChanges(for userId: String) -> Bool {
        guard let localSettings = getLocalSettings(for: userId) else {
            return false
        }
        return localSettings.syncStatus == .dirty
    }

    // MARK: - Write Operations (Local with Dirty Tracking)

    /// Update user settings locally
    /// Only the changed fields will be marked dirty
    /// - Parameters:
    ///   - userId: User ID
    ///   - monthlyGoal: New monthly goal (optional)
    ///   - defaultShiftsView: New default shifts view (optional)
    ///   - profilePictureUrl: New profile picture URL (optional)
    ///   - payrollDay: New payroll day (optional)
    ///   - theme: New theme (optional)
    ///   - halfTaxMonth: New half tax month (optional)
    ///   - currency: New currency (optional)
    /// - Returns: Updated UserSettings if successful
    func updateSettings(
        for userId: String,
        monthlyGoal: Int? = nil,
        defaultShiftsView: String? = nil,
        profilePictureUrl: String? = nil,
        payrollDay: Int? = nil,
        theme: String? = nil,
        halfTaxMonth: Int? = nil,
        currency: String? = nil
    ) async throws -> UserSettings? {
        let context = localStore.mainContext

        let descriptor = FetchDescriptor<LocalUserSettings>(
            predicate: #Predicate { $0.userId == userId }
        )

        guard let localSettings = try context.fetch(descriptor).first else {
            logger.warning("Settings not found for update: \(userId)")
            return nil
        }

        // Track which fields changed
        var newDirtyFields = localSettings.dirtyFieldKeys
        let now = Date()

        if let newGoal = monthlyGoal, newGoal != localSettings.monthlyGoal {
            localSettings.monthlyGoal = newGoal
            newDirtyFields.insert(.monthlyGoal)
        }

        if let newView = defaultShiftsView, newView != localSettings.defaultShiftsView {
            localSettings.defaultShiftsView = newView
            newDirtyFields.insert(.defaultShiftsView)
        }

        if let newUrl = profilePictureUrl, newUrl != localSettings.profilePictureUrl {
            localSettings.profilePictureUrl = newUrl
            newDirtyFields.insert(.profilePictureUrl)
        }

        if let newDay = payrollDay, newDay != localSettings.payrollDay {
            localSettings.payrollDay = newDay
            newDirtyFields.insert(.payrollDay)
        }

        if let newTheme = theme, newTheme != localSettings.theme {
            localSettings.theme = newTheme
            newDirtyFields.insert(.theme)
        }

        if let newHalfTax = halfTaxMonth {
            // Handle nullable field - check if actually different
            if newHalfTax != localSettings.halfTaxMonth {
                localSettings.halfTaxMonth = newHalfTax
                newDirtyFields.insert(.halfTaxMonth)
            }
        }

        if let newCurrency = currency, newCurrency != localSettings.currency {
            localSettings.currency = newCurrency
            newDirtyFields.insert(.currency)
        }

        // Update dirty tracking
        localSettings.dirtyFieldKeys = newDirtyFields
        localSettings.localUpdatedAt = now

        // Set status to dirty if we have changes
        if !newDirtyFields.isEmpty && localSettings.syncStatus == .clean {
            localSettings.syncStatus = .dirty
        }

        // Save via actor
        try await localStore.storeActor.upsertUserSettings(localSettings)
        try await localStore.storeActor.save()

        logger.info("Updated local settings for user: \(userId), dirty fields: \(newDirtyFields.map { $0.rawValue })")

        return localSettings.toUserSettings()
    }

    /// Update last active timestamp
    /// This is typically not synced but can be used locally
    /// - Parameter userId: User ID
    func updateLastActive(for userId: String) async throws {
        let context = localStore.mainContext

        let descriptor = FetchDescriptor<LocalUserSettings>(
            predicate: #Predicate { $0.userId == userId }
        )

        guard let localSettings = try context.fetch(descriptor).first else {
            return
        }

        let now = Date()
        localSettings.lastActive = now
        localSettings.localUpdatedAt = now

        // Don't mark as dirty - lastActive updates don't need to sync
        // They are primarily used for local tracking

        try await localStore.storeActor.upsertUserSettings(localSettings)
        try await localStore.storeActor.save()

        logger.debug("Updated last active for user: \(userId)")
    }

    // MARK: - Conflict Resolution

    /// Resolve a conflict by keeping the local version
    /// - Parameter userId: User ID
    func resolveConflictKeepLocal(for userId: String) async throws {
        let context = localStore.mainContext

        let descriptor = FetchDescriptor<LocalUserSettings>(
            predicate: #Predicate { $0.userId == userId }
        )

        guard let localSettings = try context.fetch(descriptor).first else {
            logger.warning("Settings not found for conflict resolution: \(userId)")
            return
        }

        guard localSettings.syncStatus == .conflict else {
            logger.warning("Settings are not in conflict state: \(userId)")
            return
        }

        guard let serverSnapshot = UserSettingsServerSnapshot.decode(from: localSettings.conflictServerSnapshot ?? Data()) else {
            logger.error("No server snapshot found for settings conflict: \(userId)")
            return
        }

        // Update server metadata but keep local values
        localSettings.serverRevision = serverSnapshot.revision
        localSettings.serverUpdatedAt = serverSnapshot.updatedAt
        localSettings.syncStatus = .dirty
        localSettings.conflictServerSnapshot = nil
        localSettings.localUpdatedAt = Date()

        try await localStore.storeActor.upsertUserSettings(localSettings)
        try await localStore.storeActor.save()

        logger.info("Resolved settings conflict (kept local) for user: \(userId)")
    }

    /// Resolve a conflict by accepting the server version
    /// - Parameter userId: User ID
    func resolveConflictKeepServer(for userId: String) async throws {
        let context = localStore.mainContext

        let descriptor = FetchDescriptor<LocalUserSettings>(
            predicate: #Predicate { $0.userId == userId }
        )

        guard let localSettings = try context.fetch(descriptor).first else {
            logger.warning("Settings not found for conflict resolution: \(userId)")
            return
        }

        guard localSettings.syncStatus == .conflict else {
            logger.warning("Settings are not in conflict state: \(userId)")
            return
        }

        guard let serverSnapshot = UserSettingsServerSnapshot.decode(from: localSettings.conflictServerSnapshot ?? Data()) else {
            logger.error("No server snapshot found for settings conflict: \(userId)")
            return
        }

        // Apply server values
        localSettings.monthlyGoal = serverSnapshot.monthlyGoal
        localSettings.defaultShiftsView = serverSnapshot.defaultShiftsView
        localSettings.profilePictureUrl = serverSnapshot.profilePictureUrl
        localSettings.payrollDay = serverSnapshot.payrollDay
        localSettings.theme = serverSnapshot.theme
        localSettings.halfTaxMonth = serverSnapshot.halfTaxMonth
        localSettings.currency = serverSnapshot.currency
        localSettings.lastActive = serverSnapshot.lastActive
        localSettings.serverRevision = serverSnapshot.revision
        localSettings.serverUpdatedAt = serverSnapshot.updatedAt

        // Clear dirty state
        localSettings.syncStatus = .clean
        localSettings.dirtyFieldKeys = []
        localSettings.lastSyncedSnapshot = localSettings.conflictServerSnapshot ?? Data()
        localSettings.conflictServerSnapshot = nil
        localSettings.localUpdatedAt = Date()

        try await localStore.storeActor.upsertUserSettings(localSettings)
        try await localStore.storeActor.save()

        logger.info("Resolved settings conflict (kept server) for user: \(userId)")
    }
}
