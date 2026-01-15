import Foundation
import SwiftData
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "LocalStore")

// MARK: - Local Store

/// Central SwiftData container for offline storage
/// Manages the ModelContainer and provides thread-safe access via ModelActor
@MainActor
final class LocalStore {
    /// Shared instance for the app
    static let shared = LocalStore()

    /// The SwiftData model container
    let container: ModelContainer

    /// Actor for serialized writes (sync operations)
    let storeActor: LocalStoreActor

    private init() {
        // Create schema with all local models
        let schema = Schema([
            LocalUserShift.self,
            LocalRecurringShift.self,
            LocalWageSnapshot.self,
            LocalUserSettings.self,
            LocalSyncState.self,
        ])

        // Configure container for persistent storage
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true
        )

        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
            storeActor = LocalStoreActor(modelContainer: container)
            logger.info("LocalStore initialized successfully")
        } catch {
            // Fatal error - app cannot function without local storage
            fatalError("Failed to initialize LocalStore: \(error)")
        }
    }

    /// Get a new ModelContext for main actor operations
    /// Use this for UI reads on the main thread
    var mainContext: ModelContext {
        container.mainContext
    }

    /// Reset all local data (for debugging or logout)
    func resetAllData() async {
        await storeActor.resetAllData()
        logger.info("All local data has been reset")
    }
}

// MARK: - Local Store Actor

/// ModelActor for serialized write operations
/// All sync operations should use this actor to prevent data races
@ModelActor
actor LocalStoreActor {
    /// Delete all data from all tables
    func resetAllData() {
        do {
            try modelContext.delete(model: LocalUserShift.self)
            try modelContext.delete(model: LocalRecurringShift.self)
            try modelContext.delete(model: LocalWageSnapshot.self)
            try modelContext.delete(model: LocalUserSettings.self)
            try modelContext.delete(model: LocalSyncState.self)
            try modelContext.save()
        } catch {
            logger.error("Failed to reset all data: \(error.localizedDescription)")
        }
    }

    /// Save changes to the context
    func save() throws {
        try modelContext.save()
    }

    // MARK: - Sync State Operations

    /// Get or create sync state for a user
    func getOrCreateSyncState(userId: String) throws -> LocalSyncState {
        let descriptor = FetchDescriptor<LocalSyncState>(
            predicate: #Predicate { $0.userId == userId }
        )

        if let existing = try modelContext.fetch(descriptor).first {
            return existing
        }

        let newState = LocalSyncState(userId: userId)
        modelContext.insert(newState)
        try modelContext.save()
        return newState
    }

    /// Get sync state for a user (returns nil if not found)
    func getSyncState(userId: String) throws -> LocalSyncState? {
        let descriptor = FetchDescriptor<LocalSyncState>(
            predicate: #Predicate { $0.userId == userId }
        )
        return try modelContext.fetch(descriptor).first
    }

    // MARK: - User Shift Operations

    /// Upsert a user shift from server data
    func upsertUserShift(_ shift: LocalUserShift) throws {
        let shiftId = shift.id
        let descriptor = FetchDescriptor<LocalUserShift>(
            predicate: #Predicate { $0.id == shiftId }
        )

        if let existing = try modelContext.fetch(descriptor).first {
            // Update existing - copy all fields
            existing.shiftDate = shift.shiftDate
            existing.startTime = shift.startTime
            existing.endTime = shift.endTime
            existing.customSupplements = shift.customSupplements
            existing.serverUpdatedAt = shift.serverUpdatedAt
            existing.serverRevision = shift.serverRevision
            existing.serverDeletedAt = shift.serverDeletedAt
            existing.syncStatusRaw = shift.syncStatusRaw
            existing.dirtyFields = shift.dirtyFields
            existing.lastSyncedSnapshot = shift.lastSyncedSnapshot
            existing.localUpdatedAt = shift.localUpdatedAt
            existing.conflictServerSnapshot = shift.conflictServerSnapshot
        } else {
            // Insert new
            modelContext.insert(shift)
        }
    }

    /// Get user shift by ID
    func getUserShift(id: String) throws -> LocalUserShift? {
        let descriptor = FetchDescriptor<LocalUserShift>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    /// Get all user shifts for a user (including soft-deleted for sync)
    func getAllUserShifts(userId: String) throws -> [LocalUserShift] {
        let descriptor = FetchDescriptor<LocalUserShift>(
            predicate: #Predicate { $0.userId == userId }
        )
        return try modelContext.fetch(descriptor)
    }

    /// Get dirty user shifts that need to be pushed
    func getDirtyUserShifts(userId: String) throws -> [LocalUserShift] {
        let descriptor = FetchDescriptor<LocalUserShift>(
            predicate: #Predicate { shift in
                shift.userId == userId && (
                    shift.syncStatusRaw == "dirty" ||
                    shift.syncStatusRaw == "pendingDelete"
                )
            }
        )
        return try modelContext.fetch(descriptor)
    }

    // MARK: - Recurring Shift Operations

    /// Upsert a recurring shift from server data
    func upsertRecurringShift(_ shift: LocalRecurringShift) throws {
        let shiftId = shift.id
        let descriptor = FetchDescriptor<LocalRecurringShift>(
            predicate: #Predicate { $0.id == shiftId }
        )

        if let existing = try modelContext.fetch(descriptor).first {
            // Update existing
            existing.startTime = shift.startTime
            existing.endTime = shift.endTime
            existing.repeatIntervalWeeks = shift.repeatIntervalWeeks
            existing.selectedDays = shift.selectedDays
            existing.endCondition = shift.endCondition
            existing.exclusions = shift.exclusions
            existing.dateSpecificSupplements = shift.dateSpecificSupplements
            existing.serverUpdatedAt = shift.serverUpdatedAt
            existing.serverRevision = shift.serverRevision
            existing.serverDeletedAt = shift.serverDeletedAt
            existing.syncStatusRaw = shift.syncStatusRaw
            existing.dirtyFields = shift.dirtyFields
            existing.lastSyncedSnapshot = shift.lastSyncedSnapshot
            existing.localUpdatedAt = shift.localUpdatedAt
            existing.conflictServerSnapshot = shift.conflictServerSnapshot
        } else {
            // Insert new
            modelContext.insert(shift)
        }
    }

    /// Get recurring shift by ID
    func getRecurringShift(id: String) throws -> LocalRecurringShift? {
        let descriptor = FetchDescriptor<LocalRecurringShift>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    /// Get all recurring shifts for a user
    func getAllRecurringShifts(userId: String) throws -> [LocalRecurringShift] {
        let descriptor = FetchDescriptor<LocalRecurringShift>(
            predicate: #Predicate { $0.userId == userId }
        )
        return try modelContext.fetch(descriptor)
    }

    /// Get dirty recurring shifts that need to be pushed
    func getDirtyRecurringShifts(userId: String) throws -> [LocalRecurringShift] {
        let descriptor = FetchDescriptor<LocalRecurringShift>(
            predicate: #Predicate { shift in
                shift.userId == userId && (
                    shift.syncStatusRaw == "dirty" ||
                    shift.syncStatusRaw == "pendingDelete"
                )
            }
        )
        return try modelContext.fetch(descriptor)
    }

    // MARK: - Wage Snapshot Operations

    /// Upsert a wage snapshot from server data
    func upsertWageSnapshot(_ snapshot: LocalWageSnapshot) throws {
        let snapshotId = snapshot.id
        let descriptor = FetchDescriptor<LocalWageSnapshot>(
            predicate: #Predicate { $0.id == snapshotId }
        )

        if let existing = try modelContext.fetch(descriptor).first {
            // Update existing
            existing.fromDate = snapshot.fromDate
            existing.hourlyWage = snapshot.hourlyWage
            existing.wageLevel = snapshot.wageLevel
            existing.supplements = snapshot.supplements
            existing.taxEnabled = snapshot.taxEnabled
            existing.taxPercentage = snapshot.taxPercentage
            existing.breakEnabled = snapshot.breakEnabled
            existing.breakMethod = snapshot.breakMethod
            existing.breakThresholdHours = snapshot.breakThresholdHours
            existing.breakDeductionMinutes = snapshot.breakDeductionMinutes
            existing.serverUpdatedAt = snapshot.serverUpdatedAt
            existing.serverRevision = snapshot.serverRevision
            existing.serverDeletedAt = snapshot.serverDeletedAt
            existing.syncStatusRaw = snapshot.syncStatusRaw
            existing.dirtyFields = snapshot.dirtyFields
            existing.lastSyncedSnapshot = snapshot.lastSyncedSnapshot
            existing.localUpdatedAt = snapshot.localUpdatedAt
            existing.conflictServerSnapshot = snapshot.conflictServerSnapshot
        } else {
            // Insert new
            modelContext.insert(snapshot)
        }
    }

    /// Get wage snapshot by ID
    func getWageSnapshot(id: String) throws -> LocalWageSnapshot? {
        let descriptor = FetchDescriptor<LocalWageSnapshot>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    /// Get all wage snapshots for a user
    func getAllWageSnapshots(userId: String) throws -> [LocalWageSnapshot] {
        let descriptor = FetchDescriptor<LocalWageSnapshot>(
            predicate: #Predicate { $0.userId == userId },
            sortBy: [SortDescriptor(\.fromDate, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    /// Get dirty wage snapshots that need to be pushed
    func getDirtyWageSnapshots(userId: String) throws -> [LocalWageSnapshot] {
        let descriptor = FetchDescriptor<LocalWageSnapshot>(
            predicate: #Predicate { snapshot in
                snapshot.userId == userId && (
                    snapshot.syncStatusRaw == "dirty" ||
                    snapshot.syncStatusRaw == "pendingDelete"
                )
            }
        )
        return try modelContext.fetch(descriptor)
    }

    // MARK: - User Settings Operations

    /// Upsert user settings from server data
    func upsertUserSettings(_ settings: LocalUserSettings) throws {
        let settingsUserId = settings.userId
        let descriptor = FetchDescriptor<LocalUserSettings>(
            predicate: #Predicate { $0.userId == settingsUserId }
        )

        if let existing = try modelContext.fetch(descriptor).first {
            // Update existing
            existing.monthlyGoal = settings.monthlyGoal
            existing.defaultShiftsView = settings.defaultShiftsView
            existing.profilePictureUrl = settings.profilePictureUrl
            existing.payrollDay = settings.payrollDay
            existing.theme = settings.theme
            existing.halfTaxMonth = settings.halfTaxMonth
            existing.currency = settings.currency
            existing.lastActive = settings.lastActive
            existing.createdAt = settings.createdAt
            existing.serverUpdatedAt = settings.serverUpdatedAt
            existing.serverRevision = settings.serverRevision
            existing.syncStatusRaw = settings.syncStatusRaw
            existing.dirtyFields = settings.dirtyFields
            existing.lastSyncedSnapshot = settings.lastSyncedSnapshot
            existing.localUpdatedAt = settings.localUpdatedAt
            existing.conflictServerSnapshot = settings.conflictServerSnapshot
        } else {
            // Insert new
            modelContext.insert(settings)
        }
    }

    /// Get user settings by user ID
    func getUserSettings(userId: String) throws -> LocalUserSettings? {
        let descriptor = FetchDescriptor<LocalUserSettings>(
            predicate: #Predicate { $0.userId == userId }
        )
        return try modelContext.fetch(descriptor).first
    }

    /// Get dirty user settings that need to be pushed
    func getDirtyUserSettings(userId: String) throws -> LocalUserSettings? {
        let descriptor = FetchDescriptor<LocalUserSettings>(
            predicate: #Predicate { settings in
                settings.userId == userId && settings.syncStatusRaw == "dirty"
            }
        )
        return try modelContext.fetch(descriptor).first
    }

    // MARK: - Conflict Helpers

    /// Get all records with conflicts for a user
    func getConflicts(userId: String) throws -> (
        shifts: [LocalUserShift],
        recurringShifts: [LocalRecurringShift],
        wageSnapshots: [LocalWageSnapshot],
        settings: LocalUserSettings?
    ) {
        let shiftsDescriptor = FetchDescriptor<LocalUserShift>(
            predicate: #Predicate { shift in
                shift.userId == userId && shift.syncStatusRaw == "conflict"
            }
        )
        let shifts = try modelContext.fetch(shiftsDescriptor)

        let recurringDescriptor = FetchDescriptor<LocalRecurringShift>(
            predicate: #Predicate { shift in
                shift.userId == userId && shift.syncStatusRaw == "conflict"
            }
        )
        let recurringShifts = try modelContext.fetch(recurringDescriptor)

        let snapshotsDescriptor = FetchDescriptor<LocalWageSnapshot>(
            predicate: #Predicate { snapshot in
                snapshot.userId == userId && snapshot.syncStatusRaw == "conflict"
            }
        )
        let wageSnapshots = try modelContext.fetch(snapshotsDescriptor)

        let settingsDescriptor = FetchDescriptor<LocalUserSettings>(
            predicate: #Predicate { settings in
                settings.userId == userId && settings.syncStatusRaw == "conflict"
            }
        )
        let settings = try modelContext.fetch(settingsDescriptor).first

        return (shifts, recurringShifts, wageSnapshots, settings)
    }

    /// Check if user has any conflicts
    func hasConflicts(userId: String) throws -> Bool {
        let conflicts = try getConflicts(userId: userId)
        return !conflicts.shifts.isEmpty ||
               !conflicts.recurringShifts.isEmpty ||
               !conflicts.wageSnapshots.isEmpty ||
               conflicts.settings != nil
    }

    /// Check if user has any pending changes
    func hasPendingChanges(userId: String) throws -> Bool {
        let dirtyShifts = try getDirtyUserShifts(userId: userId)
        let dirtyRecurring = try getDirtyRecurringShifts(userId: userId)
        let dirtySnapshots = try getDirtyWageSnapshots(userId: userId)
        let dirtySettings = try getDirtyUserSettings(userId: userId)

        return !dirtyShifts.isEmpty ||
               !dirtyRecurring.isEmpty ||
               !dirtySnapshots.isEmpty ||
               dirtySettings != nil
    }
}
