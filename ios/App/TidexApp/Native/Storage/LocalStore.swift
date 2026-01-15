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

    /// Count total conflicts for a user
    func countConflicts(userId: String) throws -> Int {
        let conflicts = try getConflicts(userId: userId)
        return conflicts.shifts.count +
               conflicts.recurringShifts.count +
               conflicts.wageSnapshots.count +
               (conflicts.settings != nil ? 1 : 0)
    }

    /// Update sync state with a closure
    func updateSyncState(userId: String, update: (LocalSyncState) -> Void) {
        let descriptor = FetchDescriptor<LocalSyncState>(
            predicate: #Predicate { $0.userId == userId }
        )

        guard let state = try? modelContext.fetch(descriptor).first else {
            return
        }

        update(state)
        try? modelContext.save()
    }

    // MARK: - Sync Update Operations for User Shifts

    /// Update a shift from server data (for clean rows)
    func updateShiftFromServer(
        id: String,
        serverRow: SyncShiftRow,
        serverUpdatedAt: Date,
        serverRevision: Int64,
        serverDeletedAt: Date?,
        snapshot: UserShiftServerSnapshot
    ) {
        let descriptor = FetchDescriptor<LocalUserShift>(
            predicate: #Predicate { $0.id == id }
        )

        guard let existing = try? modelContext.fetch(descriptor).first else { return }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")

        existing.shiftDate = dateFormatter.date(from: serverRow.shift_date) ?? existing.shiftDate
        existing.startTime = serverRow.start_time
        existing.endTime = serverRow.end_time
        existing.customSupplements = serverRow.custom_supplements.flatMap { try? canonicalJSONEncoder.encode($0) }
        existing.serverUpdatedAt = serverUpdatedAt
        existing.serverRevision = serverRevision
        existing.serverDeletedAt = serverDeletedAt
        existing.lastSyncedSnapshot = snapshot.encoded()
        existing.localUpdatedAt = Date()
    }

    /// Mark a shift as having a conflict
    func markShiftConflict(id: String, serverSnapshot: UserShiftServerSnapshot) {
        let descriptor = FetchDescriptor<LocalUserShift>(
            predicate: #Predicate { $0.id == id }
        )

        guard let existing = try? modelContext.fetch(descriptor).first else { return }

        existing.syncStatus = .conflict
        existing.conflictServerSnapshot = serverSnapshot.encoded()
    }

    /// Update conflict snapshot for a shift already in conflict
    func updateShiftConflictSnapshot(id: String, serverSnapshot: UserShiftServerSnapshot) {
        let descriptor = FetchDescriptor<LocalUserShift>(
            predicate: #Predicate { $0.id == id }
        )

        guard let existing = try? modelContext.fetch(descriptor).first else { return }

        existing.conflictServerSnapshot = serverSnapshot.encoded()
    }

    /// Auto-merge a shift (apply server changes for non-dirty fields)
    func autoMergeShift(
        id: String,
        serverRow: SyncShiftRow,
        serverUpdatedAt: Date,
        serverRevision: Int64,
        serverDeletedAt: Date?,
        newSnapshot: UserShiftServerSnapshot,
        localDirtyFields: Set<UserShiftField>
    ) {
        let descriptor = FetchDescriptor<LocalUserShift>(
            predicate: #Predicate { $0.id == id }
        )

        guard let existing = try? modelContext.fetch(descriptor).first else { return }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")

        // Apply server changes only for non-dirty fields
        if !localDirtyFields.contains(.shiftDate) {
            existing.shiftDate = dateFormatter.date(from: serverRow.shift_date) ?? existing.shiftDate
        }
        if !localDirtyFields.contains(.startTime) {
            existing.startTime = serverRow.start_time
        }
        if !localDirtyFields.contains(.endTime) {
            existing.endTime = serverRow.end_time
        }
        if !localDirtyFields.contains(.customSupplements) {
            existing.customSupplements = serverRow.custom_supplements.flatMap { try? canonicalJSONEncoder.encode($0) }
        }

        // Update server metadata
        existing.serverUpdatedAt = serverUpdatedAt
        existing.serverRevision = serverRevision
        existing.serverDeletedAt = serverDeletedAt
        existing.lastSyncedSnapshot = newSnapshot.encoded()
        // Keep syncStatus = dirty (still needs push)
    }

    // MARK: - Sync Update Operations for Recurring Shifts

    func updateRecurringShiftFromServer(
        id: String,
        serverRow: SyncRecurringShiftRow,
        serverUpdatedAt: Date,
        serverRevision: Int64,
        serverDeletedAt: Date?,
        snapshot: RecurringShiftServerSnapshot
    ) {
        let descriptor = FetchDescriptor<LocalRecurringShift>(
            predicate: #Predicate { $0.id == id }
        )

        guard let existing = try? modelContext.fetch(descriptor).first else { return }

        existing.startTime = serverRow.cleanStartTime
        existing.endTime = serverRow.cleanEndTime
        existing.repeatIntervalWeeks = serverRow.repeat_interval_weeks
        existing.selectedDays = (try? canonicalJSONEncoder.encode(serverRow.selected_days)) ?? Data()
        existing.endCondition = serverRow.end_condition.flatMap { try? canonicalJSONEncoder.encode($0) }
        existing.exclusions = serverRow.exclusions.flatMap { try? canonicalJSONEncoder.encode($0) }
        existing.dateSpecificSupplements = serverRow.date_specific_supplements.flatMap { try? canonicalJSONEncoder.encode($0) }
        existing.serverUpdatedAt = serverUpdatedAt
        existing.serverRevision = serverRevision
        existing.serverDeletedAt = serverDeletedAt
        existing.lastSyncedSnapshot = snapshot.encoded()
        existing.localUpdatedAt = Date()
    }

    func markRecurringShiftConflict(id: String, serverSnapshot: RecurringShiftServerSnapshot) {
        let descriptor = FetchDescriptor<LocalRecurringShift>(
            predicate: #Predicate { $0.id == id }
        )

        guard let existing = try? modelContext.fetch(descriptor).first else { return }

        existing.syncStatus = .conflict
        existing.conflictServerSnapshot = serverSnapshot.encoded()
    }

    func updateRecurringShiftConflictSnapshot(id: String, serverSnapshot: RecurringShiftServerSnapshot) {
        let descriptor = FetchDescriptor<LocalRecurringShift>(
            predicate: #Predicate { $0.id == id }
        )

        guard let existing = try? modelContext.fetch(descriptor).first else { return }

        existing.conflictServerSnapshot = serverSnapshot.encoded()
    }

    func autoMergeRecurringShift(
        id: String,
        serverRow: SyncRecurringShiftRow,
        serverUpdatedAt: Date,
        serverRevision: Int64,
        serverDeletedAt: Date?,
        newSnapshot: RecurringShiftServerSnapshot,
        localDirtyFields: Set<RecurringShiftField>
    ) {
        let descriptor = FetchDescriptor<LocalRecurringShift>(
            predicate: #Predicate { $0.id == id }
        )

        guard let existing = try? modelContext.fetch(descriptor).first else { return }

        if !localDirtyFields.contains(.startTime) {
            existing.startTime = serverRow.cleanStartTime
        }
        if !localDirtyFields.contains(.endTime) {
            existing.endTime = serverRow.cleanEndTime
        }
        if !localDirtyFields.contains(.repeatIntervalWeeks) {
            existing.repeatIntervalWeeks = serverRow.repeat_interval_weeks
        }
        if !localDirtyFields.contains(.selectedDays) {
            existing.selectedDays = (try? canonicalJSONEncoder.encode(serverRow.selected_days)) ?? Data()
        }
        if !localDirtyFields.contains(.endCondition) {
            existing.endCondition = serverRow.end_condition.flatMap { try? canonicalJSONEncoder.encode($0) }
        }
        if !localDirtyFields.contains(.exclusions) {
            existing.exclusions = serverRow.exclusions.flatMap { try? canonicalJSONEncoder.encode($0) }
        }
        if !localDirtyFields.contains(.dateSpecificSupplements) {
            existing.dateSpecificSupplements = serverRow.date_specific_supplements.flatMap { try? canonicalJSONEncoder.encode($0) }
        }

        existing.serverUpdatedAt = serverUpdatedAt
        existing.serverRevision = serverRevision
        existing.serverDeletedAt = serverDeletedAt
        existing.lastSyncedSnapshot = newSnapshot.encoded()
    }

    // MARK: - Sync Update Operations for Wage Snapshots

    func updateWageSnapshotFromServer(
        id: String,
        serverRow: SyncWageSnapshotRow,
        serverUpdatedAt: Date,
        serverRevision: Int64,
        serverDeletedAt: Date?,
        snapshot: WageSnapshotServerSnapshot
    ) {
        let descriptor = FetchDescriptor<LocalWageSnapshot>(
            predicate: #Predicate { $0.id == id }
        )

        guard let existing = try? modelContext.fetch(descriptor).first else { return }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")

        existing.fromDate = serverRow.from_date.flatMap { dateFormatter.date(from: $0) }
        existing.hourlyWage = serverRow.hourly_wage
        existing.wageLevel = serverRow.wage_level
        existing.supplements = (try? canonicalJSONEncoder.encode(serverRow.supplements)) ?? Data()
        existing.taxEnabled = serverRow.tax_enabled
        existing.taxPercentage = serverRow.tax_percentage
        existing.breakEnabled = serverRow.break_enabled
        existing.breakMethod = serverRow.break_method
        existing.breakThresholdHours = serverRow.break_threshold_hours
        existing.breakDeductionMinutes = serverRow.break_deduction_minutes
        existing.serverUpdatedAt = serverUpdatedAt
        existing.serverRevision = serverRevision
        existing.serverDeletedAt = serverDeletedAt
        existing.lastSyncedSnapshot = snapshot.encoded()
        existing.localUpdatedAt = Date()
    }

    func markWageSnapshotConflict(id: String, serverSnapshot: WageSnapshotServerSnapshot) {
        let descriptor = FetchDescriptor<LocalWageSnapshot>(
            predicate: #Predicate { $0.id == id }
        )

        guard let existing = try? modelContext.fetch(descriptor).first else { return }

        existing.syncStatus = .conflict
        existing.conflictServerSnapshot = serverSnapshot.encoded()
    }

    func updateWageSnapshotConflictSnapshot(id: String, serverSnapshot: WageSnapshotServerSnapshot) {
        let descriptor = FetchDescriptor<LocalWageSnapshot>(
            predicate: #Predicate { $0.id == id }
        )

        guard let existing = try? modelContext.fetch(descriptor).first else { return }

        existing.conflictServerSnapshot = serverSnapshot.encoded()
    }

    func autoMergeWageSnapshot(
        id: String,
        serverRow: SyncWageSnapshotRow,
        serverUpdatedAt: Date,
        serverRevision: Int64,
        serverDeletedAt: Date?,
        newSnapshot: WageSnapshotServerSnapshot,
        localDirtyFields: Set<WageSnapshotField>
    ) {
        let descriptor = FetchDescriptor<LocalWageSnapshot>(
            predicate: #Predicate { $0.id == id }
        )

        guard let existing = try? modelContext.fetch(descriptor).first else { return }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")

        if !localDirtyFields.contains(.fromDate) {
            existing.fromDate = serverRow.from_date.flatMap { dateFormatter.date(from: $0) }
        }
        if !localDirtyFields.contains(.hourlyWage) {
            existing.hourlyWage = serverRow.hourly_wage
        }
        if !localDirtyFields.contains(.wageLevel) {
            existing.wageLevel = serverRow.wage_level
        }
        if !localDirtyFields.contains(.supplements) {
            existing.supplements = (try? canonicalJSONEncoder.encode(serverRow.supplements)) ?? Data()
        }
        if !localDirtyFields.contains(.taxEnabled) {
            existing.taxEnabled = serverRow.tax_enabled
        }
        if !localDirtyFields.contains(.taxPercentage) {
            existing.taxPercentage = serverRow.tax_percentage
        }
        if !localDirtyFields.contains(.breakEnabled) {
            existing.breakEnabled = serverRow.break_enabled
        }
        if !localDirtyFields.contains(.breakMethod) {
            existing.breakMethod = serverRow.break_method
        }
        if !localDirtyFields.contains(.breakThresholdHours) {
            existing.breakThresholdHours = serverRow.break_threshold_hours
        }
        if !localDirtyFields.contains(.breakDeductionMinutes) {
            existing.breakDeductionMinutes = serverRow.break_deduction_minutes
        }

        existing.serverUpdatedAt = serverUpdatedAt
        existing.serverRevision = serverRevision
        existing.serverDeletedAt = serverDeletedAt
        existing.lastSyncedSnapshot = newSnapshot.encoded()
    }

    // MARK: - Sync Update Operations for User Settings

    func updateUserSettingsFromServer(
        userId: String,
        serverRow: SyncUserSettingsRow,
        serverUpdatedAt: Date,
        serverRevision: Int64,
        snapshot: UserSettingsServerSnapshot
    ) {
        let descriptor = FetchDescriptor<LocalUserSettings>(
            predicate: #Predicate { $0.userId == userId }
        )

        guard let existing = try? modelContext.fetch(descriptor).first else { return }

        let dateFormatter = ISO8601DateFormatter()

        existing.monthlyGoal = serverRow.monthly_goal
        existing.defaultShiftsView = serverRow.default_shifts_view
        existing.profilePictureUrl = serverRow.profile_picture_url
        existing.payrollDay = serverRow.payroll_day
        existing.theme = serverRow.theme
        existing.halfTaxMonth = serverRow.half_tax_month
        existing.currency = serverRow.currency
        existing.lastActive = serverRow.last_active.flatMap { dateFormatter.date(from: $0) }
        existing.createdAt = serverRow.created_at.flatMap { dateFormatter.date(from: $0) }
        existing.serverUpdatedAt = serverUpdatedAt
        existing.serverRevision = serverRevision
        existing.lastSyncedSnapshot = snapshot.encoded()
        existing.localUpdatedAt = Date()
    }

    func markUserSettingsConflict(userId: String, serverSnapshot: UserSettingsServerSnapshot) {
        let descriptor = FetchDescriptor<LocalUserSettings>(
            predicate: #Predicate { $0.userId == userId }
        )

        guard let existing = try? modelContext.fetch(descriptor).first else { return }

        existing.syncStatus = .conflict
        existing.conflictServerSnapshot = serverSnapshot.encoded()
    }

    func updateUserSettingsConflictSnapshot(userId: String, serverSnapshot: UserSettingsServerSnapshot) {
        let descriptor = FetchDescriptor<LocalUserSettings>(
            predicate: #Predicate { $0.userId == userId }
        )

        guard let existing = try? modelContext.fetch(descriptor).first else { return }

        existing.conflictServerSnapshot = serverSnapshot.encoded()
    }

    func autoMergeUserSettings(
        userId: String,
        serverRow: SyncUserSettingsRow,
        serverUpdatedAt: Date,
        serverRevision: Int64,
        newSnapshot: UserSettingsServerSnapshot,
        localDirtyFields: Set<UserSettingsField>
    ) {
        let descriptor = FetchDescriptor<LocalUserSettings>(
            predicate: #Predicate { $0.userId == userId }
        )

        guard let existing = try? modelContext.fetch(descriptor).first else { return }

        let dateFormatter = ISO8601DateFormatter()

        if !localDirtyFields.contains(.monthlyGoal) {
            existing.monthlyGoal = serverRow.monthly_goal
        }
        if !localDirtyFields.contains(.defaultShiftsView) {
            existing.defaultShiftsView = serverRow.default_shifts_view
        }
        if !localDirtyFields.contains(.profilePictureUrl) {
            existing.profilePictureUrl = serverRow.profile_picture_url
        }
        if !localDirtyFields.contains(.payrollDay) {
            existing.payrollDay = serverRow.payroll_day
        }
        if !localDirtyFields.contains(.theme) {
            existing.theme = serverRow.theme
        }
        if !localDirtyFields.contains(.halfTaxMonth) {
            existing.halfTaxMonth = serverRow.half_tax_month
        }
        if !localDirtyFields.contains(.currency) {
            existing.currency = serverRow.currency
        }
        if !localDirtyFields.contains(.lastActive) {
            existing.lastActive = serverRow.last_active.flatMap { dateFormatter.date(from: $0) }
        }

        existing.serverUpdatedAt = serverUpdatedAt
        existing.serverRevision = serverRevision
        existing.lastSyncedSnapshot = newSnapshot.encoded()
    }
}
