import Foundation
import SwiftData
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "RecurringShiftsRepository")

// MARK: - Recurring Shifts Repository

/// Local-first repository for recurring shifts
/// All reads come from SwiftData; network calls are handled by SyncCoordinator
@MainActor
final class RecurringShiftsRepository: ObservableObject {
    static let shared = RecurringShiftsRepository()

    private let localStore: LocalStore

    private init(localStore: LocalStore? = nil) {
        self.localStore = localStore ?? LocalStore.shared
    }

    // MARK: - Read Operations (Local Only)

    /// Get all non-deleted recurring shifts for a user
    /// - Parameter userId: User ID
    /// - Returns: Array of RecurringShiftRow objects
    func getRecurringShifts(for userId: String) -> [RecurringShiftRow] {
        let context = localStore.mainContext

        let descriptor = FetchDescriptor<LocalRecurringShift>(
            predicate: #Predicate { shift in
                shift.userId == userId && shift.serverDeletedAt == nil
            }
        )

        do {
            let localShifts = try context.fetch(descriptor)
            return localShifts.map { $0.toRecurringShiftRow() }
        } catch {
            logger.error("Failed to fetch recurring shifts: \(error.localizedDescription)")
            return []
        }
    }

    /// Get a single recurring shift by ID
    /// - Parameter id: Recurring shift ID
    /// - Returns: RecurringShiftRow if found
    func getRecurringShift(id: String) -> RecurringShiftRow? {
        let context = localStore.mainContext

        let descriptor = FetchDescriptor<LocalRecurringShift>(
            predicate: #Predicate { $0.id == id }
        )

        do {
            guard let localShift = try context.fetch(descriptor).first else {
                return nil
            }
            return localShift.toRecurringShiftRow()
        } catch {
            logger.error("Failed to fetch recurring shift by ID: \(error.localizedDescription)")
            return nil
        }
    }

    /// Get recurring shifts that have sync conflicts
    /// - Parameter userId: User ID
    /// - Returns: Array of local recurring shifts in conflict state
    func getConflictingRecurringShifts(for userId: String) -> [LocalRecurringShift] {
        let context = localStore.mainContext

        let descriptor = FetchDescriptor<LocalRecurringShift>(
            predicate: #Predicate { shift in
                shift.userId == userId && shift.syncStatusRaw == "conflict"
            }
        )

        do {
            return try context.fetch(descriptor)
        } catch {
            logger.error("Failed to fetch conflicting recurring shifts: \(error.localizedDescription)")
            return []
        }
    }

    /// Get recurring shifts that have pending changes
    /// - Parameter userId: User ID
    /// - Returns: Array of local recurring shifts with dirty or pending delete status
    func getPendingRecurringShifts(for userId: String) -> [LocalRecurringShift] {
        let context = localStore.mainContext

        let descriptor = FetchDescriptor<LocalRecurringShift>(
            predicate: #Predicate { shift in
                shift.userId == userId && (
                    shift.syncStatusRaw == "dirty" ||
                    shift.syncStatusRaw == "pendingDelete"
                )
            }
        )

        do {
            return try context.fetch(descriptor)
        } catch {
            logger.error("Failed to fetch pending recurring shifts: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Write Operations (Local with Dirty Tracking)

    /// Create a new recurring shift locally
    /// - Parameters:
    ///   - userId: User ID
    ///   - startTime: Start time (HH:mm)
    ///   - endTime: End time (HH:mm)
    ///   - repeatIntervalWeeks: Repetition interval (0 = weekly, 1 = biweekly, etc.)
    ///   - selectedDays: Selected days with anchor dates
    ///   - endCondition: End condition (optional)
    ///   - exclusions: Excluded dates (optional)
    ///   - dateSpecificSupplements: Date-specific supplements (optional)
    /// - Returns: Created RecurringShiftRow
    func createRecurringShift(
        userId: String,
        startTime: String,
        endTime: String,
        repeatIntervalWeeks: Int,
        selectedDays: SelectedDays,
        endCondition: EndCondition? = nil,
        exclusions: [String]? = nil,
        dateSpecificSupplements: [String: CustomSupplementsData]? = nil
    ) async throws -> RecurringShiftRow {
        let id = UUID().uuidString.lowercased()
        let now = Date()

        // Encode JSON fields
        let selectedDaysData = (try? canonicalJSONEncoder.encode(selectedDays)) ?? Data()
        let endConditionData = endCondition.flatMap { try? canonicalJSONEncoder.encode($0) }
        let exclusionsData = exclusions.flatMap { try? canonicalJSONEncoder.encode($0) }
        let supplementsData = dateSpecificSupplements.flatMap { try? canonicalJSONEncoder.encode($0) }

        // Create server snapshot for tracking
        let serverSnapshot = RecurringShiftServerSnapshot(
            startTime: startTime,
            endTime: endTime,
            repeatIntervalWeeks: repeatIntervalWeeks,
            selectedDays: selectedDaysData,
            endCondition: endConditionData,
            exclusions: exclusionsData,
            dateSpecificSupplements: supplementsData,
            updatedAt: now,
            revision: 0,
            deletedAt: nil
        )

        // Mark all fields as dirty for new record
        let allFields = RecurringShiftField.allCases.map { $0.rawValue }
        let dirtyFieldsData = (try? canonicalJSONEncoder.encode(allFields)) ?? Data()

        let localShift = LocalRecurringShift(
            id: id,
            userId: userId,
            startTime: startTime,
            endTime: endTime,
            repeatIntervalWeeks: repeatIntervalWeeks,
            selectedDays: selectedDaysData,
            endCondition: endConditionData,
            exclusions: exclusionsData,
            dateSpecificSupplements: supplementsData,
            serverUpdatedAt: now,
            serverRevision: 0,
            serverDeletedAt: nil,
            syncStatus: .dirty,
            dirtyFields: dirtyFieldsData,
            lastSyncedSnapshot: serverSnapshot.encoded(),
            localUpdatedAt: now,
            conflictServerSnapshot: nil
        )

        try await localStore.storeActor.upsertRecurringShift(localShift)
        try await localStore.storeActor.save()

        logger.info("Created new local recurring shift: \(id)")

        return localShift.toRecurringShiftRow()
    }

    /// Update a recurring shift locally
    /// - Parameters:
    ///   - id: Recurring shift ID
    ///   - startTime: New start time (optional)
    ///   - endTime: New end time (optional)
    ///   - repeatIntervalWeeks: New repeat interval (optional)
    ///   - selectedDays: New selected days (optional)
    ///   - endCondition: New end condition (optional)
    ///   - exclusions: New exclusions (optional)
    ///   - dateSpecificSupplements: New date-specific supplements (optional)
    /// - Returns: Updated RecurringShiftRow if successful
    func updateRecurringShift(
        id: String,
        startTime: String? = nil,
        endTime: String? = nil,
        repeatIntervalWeeks: Int? = nil,
        selectedDays: SelectedDays? = nil,
        endCondition: EndCondition? = nil,
        exclusions: [String]? = nil,
        dateSpecificSupplements: [String: CustomSupplementsData]? = nil
    ) async throws -> RecurringShiftRow? {
        let context = localStore.mainContext

        let descriptor = FetchDescriptor<LocalRecurringShift>(
            predicate: #Predicate { $0.id == id }
        )

        guard let localShift = try context.fetch(descriptor).first else {
            logger.warning("Recurring shift not found for update: \(id)")
            return nil
        }

        var newDirtyFields = localShift.dirtyFieldKeys
        let now = Date()

        if let newStart = startTime, newStart != localShift.startTime {
            localShift.startTime = newStart
            newDirtyFields.insert(.startTime)
        }

        if let newEnd = endTime, newEnd != localShift.endTime {
            localShift.endTime = newEnd
            newDirtyFields.insert(.endTime)
        }

        if let newInterval = repeatIntervalWeeks, newInterval != localShift.repeatIntervalWeeks {
            localShift.repeatIntervalWeeks = newInterval
            newDirtyFields.insert(.repeatIntervalWeeks)
        }

        if let newDays = selectedDays {
            let newData = (try? canonicalJSONEncoder.encode(newDays)) ?? Data()
            if newData != localShift.selectedDays {
                localShift.selectedDays = newData
                newDirtyFields.insert(.selectedDays)
            }
        }

        if let newCondition = endCondition {
            let newData = try? canonicalJSONEncoder.encode(newCondition)
            if newData != localShift.endCondition {
                localShift.endCondition = newData
                newDirtyFields.insert(.endCondition)
            }
        }

        if let newExclusions = exclusions {
            let newData = try? canonicalJSONEncoder.encode(newExclusions)
            if newData != localShift.exclusions {
                localShift.exclusions = newData
                newDirtyFields.insert(.exclusions)
            }
        }

        if let newSupplements = dateSpecificSupplements {
            let newData = try? canonicalJSONEncoder.encode(newSupplements)
            if newData != localShift.dateSpecificSupplements {
                localShift.dateSpecificSupplements = newData
                newDirtyFields.insert(.dateSpecificSupplements)
            }
        }

        localShift.dirtyFieldKeys = newDirtyFields
        localShift.localUpdatedAt = now

        if !newDirtyFields.isEmpty && localShift.syncStatus == .clean {
            localShift.syncStatus = .dirty
        }

        try await localStore.storeActor.upsertRecurringShift(localShift)
        try await localStore.storeActor.save()

        logger.info("Updated local recurring shift: \(id), dirty fields: \(newDirtyFields.map { $0.rawValue })")

        return localShift.toRecurringShiftRow()
    }

    /// Add an exclusion date to a recurring shift
    /// - Parameters:
    ///   - id: Recurring shift ID
    ///   - date: Date to exclude (ISO string YYYY-MM-DD)
    func addExclusion(id: String, date: String) async throws {
        let context = localStore.mainContext

        let descriptor = FetchDescriptor<LocalRecurringShift>(
            predicate: #Predicate { $0.id == id }
        )

        guard let localShift = try context.fetch(descriptor).first else {
            logger.warning("Recurring shift not found for exclusion: \(id)")
            return
        }

        var exclusions = localShift.decodedExclusions
        if !exclusions.contains(date) {
            exclusions.append(date)
            localShift.decodedExclusions = exclusions

            var dirtyFields = localShift.dirtyFieldKeys
            dirtyFields.insert(.exclusions)
            localShift.dirtyFieldKeys = dirtyFields

            if localShift.syncStatus == .clean {
                localShift.syncStatus = .dirty
            }
            localShift.localUpdatedAt = Date()

            try await localStore.storeActor.upsertRecurringShift(localShift)
            try await localStore.storeActor.save()

            logger.info("Added exclusion \(date) to recurring shift: \(id)")
        }
    }

    /// Mark a recurring shift for deletion
    /// - Parameter id: Recurring shift ID
    func deleteRecurringShift(id: String) async throws {
        let context = localStore.mainContext

        let descriptor = FetchDescriptor<LocalRecurringShift>(
            predicate: #Predicate { $0.id == id }
        )

        guard let localShift = try context.fetch(descriptor).first else {
            logger.warning("Recurring shift not found for deletion: \(id)")
            return
        }

        localShift.syncStatus = .pendingDelete
        localShift.localUpdatedAt = Date()

        try await localStore.storeActor.upsertRecurringShift(localShift)
        try await localStore.storeActor.save()

        logger.info("Marked recurring shift for deletion: \(id)")
    }

    // MARK: - Conflict Resolution

    /// Resolve a conflict by keeping the local version
    /// - Parameter id: Recurring shift ID
    func resolveConflictKeepLocal(id: String) async throws {
        let context = localStore.mainContext

        let descriptor = FetchDescriptor<LocalRecurringShift>(
            predicate: #Predicate { $0.id == id }
        )

        guard let localShift = try context.fetch(descriptor).first else {
            logger.warning("Recurring shift not found for conflict resolution: \(id)")
            return
        }

        guard localShift.syncStatus == .conflict else {
            logger.warning("Recurring shift is not in conflict state: \(id)")
            return
        }

        guard let serverSnapshot = RecurringShiftServerSnapshot.decode(from: localShift.conflictServerSnapshot ?? Data()) else {
            logger.error("No server snapshot found for conflict: \(id)")
            return
        }

        localShift.serverRevision = serverSnapshot.revision
        localShift.serverUpdatedAt = serverSnapshot.updatedAt
        localShift.syncStatus = .dirty
        localShift.conflictServerSnapshot = nil
        localShift.localUpdatedAt = Date()

        try await localStore.storeActor.upsertRecurringShift(localShift)
        try await localStore.storeActor.save()

        logger.info("Resolved conflict (kept local) for recurring shift: \(id)")
    }

    /// Resolve a conflict by accepting the server version
    /// - Parameter id: Recurring shift ID
    func resolveConflictKeepServer(id: String) async throws {
        let context = localStore.mainContext

        let descriptor = FetchDescriptor<LocalRecurringShift>(
            predicate: #Predicate { $0.id == id }
        )

        guard let localShift = try context.fetch(descriptor).first else {
            logger.warning("Recurring shift not found for conflict resolution: \(id)")
            return
        }

        guard localShift.syncStatus == .conflict else {
            logger.warning("Recurring shift is not in conflict state: \(id)")
            return
        }

        guard let serverSnapshot = RecurringShiftServerSnapshot.decode(from: localShift.conflictServerSnapshot ?? Data()) else {
            logger.error("No server snapshot found for conflict: \(id)")
            return
        }

        // Apply server values
        localShift.startTime = serverSnapshot.startTime
        localShift.endTime = serverSnapshot.endTime
        localShift.repeatIntervalWeeks = serverSnapshot.repeatIntervalWeeks
        localShift.selectedDays = serverSnapshot.selectedDays
        localShift.endCondition = serverSnapshot.endCondition
        localShift.exclusions = serverSnapshot.exclusions
        localShift.dateSpecificSupplements = serverSnapshot.dateSpecificSupplements
        localShift.serverRevision = serverSnapshot.revision
        localShift.serverUpdatedAt = serverSnapshot.updatedAt
        localShift.serverDeletedAt = serverSnapshot.deletedAt

        localShift.syncStatus = .clean
        localShift.dirtyFieldKeys = []
        localShift.lastSyncedSnapshot = localShift.conflictServerSnapshot ?? Data()
        localShift.conflictServerSnapshot = nil
        localShift.localUpdatedAt = Date()

        try await localStore.storeActor.upsertRecurringShift(localShift)
        try await localStore.storeActor.save()

        logger.info("Resolved conflict (kept server) for recurring shift: \(id)")
    }

    // MARK: - Local Shift Access (For Sync)

    /// Get the raw LocalRecurringShift object
    func getLocalRecurringShift(id: String) -> LocalRecurringShift? {
        let context = localStore.mainContext

        let descriptor = FetchDescriptor<LocalRecurringShift>(
            predicate: #Predicate { $0.id == id }
        )

        do {
            return try context.fetch(descriptor).first
        } catch {
            logger.error("Failed to fetch local recurring shift: \(error.localizedDescription)")
            return nil
        }
    }
}
