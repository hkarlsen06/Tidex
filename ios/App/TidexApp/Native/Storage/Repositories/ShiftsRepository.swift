import Foundation
import SwiftData
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "ShiftsRepository")

// MARK: - Shifts Repository

/// Local-first repository for user shifts
/// All reads come from SwiftData; network calls are handled by SyncCoordinator
@MainActor
final class ShiftsRepository: ObservableObject {
    static let shared = ShiftsRepository()

    private let localStore: LocalStore

    private init(localStore: LocalStore? = nil) {
        self.localStore = localStore ?? LocalStore.shared
    }

    // MARK: - Read Operations (Local Only)

    /// Get all non-deleted shifts for a user within a date range
    /// - Parameters:
    ///   - userId: User ID
    ///   - startDate: Start date (inclusive)
    ///   - endDate: End date (inclusive)
    /// - Returns: Array of ShiftRow objects (converted from local storage)
    func getShifts(
        for userId: String,
        startDate: Date,
        endDate: Date
    ) -> [ShiftRow] {
        let context = localStore.mainContext

        // Build predicate for date range and non-deleted
        let descriptor = FetchDescriptor<LocalUserShift>(
            predicate: #Predicate { shift in
                shift.userId == userId &&
                shift.serverDeletedAt == nil &&
                shift.shiftDate >= startDate &&
                shift.shiftDate <= endDate
            },
            sortBy: [SortDescriptor(\LocalUserShift.shiftDate, order: .reverse)]
        )

        do {
            let localShifts: [LocalUserShift] = try context.fetch(descriptor)
            return localShifts.map { $0.toShiftRow() }
        } catch {
            logger.error("Failed to fetch shifts: \(error.localizedDescription)")
            return []
        }
    }

    /// Get all non-deleted shifts for a user (no date filter)
    /// - Parameter userId: User ID
    /// - Returns: Array of ShiftRow objects
    func getAllShifts(for userId: String) -> [ShiftRow] {
        let context = localStore.mainContext

        let descriptor = FetchDescriptor<LocalUserShift>(
            predicate: #Predicate { shift in
                shift.userId == userId && shift.serverDeletedAt == nil
            },
            sortBy: [SortDescriptor(\LocalUserShift.shiftDate, order: .reverse)]
        )

        do {
            let localShifts: [LocalUserShift] = try context.fetch(descriptor)
            return localShifts.map { $0.toShiftRow() }
        } catch {
            logger.error("Failed to fetch all shifts: \(error.localizedDescription)")
            return []
        }
    }

    /// Get a single shift by ID
    /// - Parameter id: Shift ID
    /// - Returns: ShiftRow if found, nil otherwise
    func getShift(id: String) -> ShiftRow? {
        let context = localStore.mainContext

        let descriptor = FetchDescriptor<LocalUserShift>(
            predicate: #Predicate { $0.id == id }
        )

        do {
            guard let localShift = try context.fetch(descriptor).first else {
                return nil
            }
            return localShift.toShiftRow()
        } catch {
            logger.error("Failed to fetch shift by ID: \(error.localizedDescription)")
            return nil
        }
    }

    /// Get shifts that have sync conflicts
    /// - Parameter userId: User ID
    /// - Returns: Array of local shifts in conflict state
    func getConflictingShifts(for userId: String) -> [LocalUserShift] {
        let context = localStore.mainContext

        let descriptor = FetchDescriptor<LocalUserShift>(
            predicate: #Predicate { shift in
                shift.userId == userId && shift.syncStatusRaw == "conflict"
            }
        )

        do {
            return try context.fetch(descriptor)
        } catch {
            logger.error("Failed to fetch conflicting shifts: \(error.localizedDescription)")
            return []
        }
    }

    /// Get shifts that have pending changes
    /// - Parameter userId: User ID
    /// - Returns: Array of local shifts with dirty or pending delete status
    func getPendingShifts(for userId: String) -> [LocalUserShift] {
        let context = localStore.mainContext

        let descriptor = FetchDescriptor<LocalUserShift>(
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
            logger.error("Failed to fetch pending shifts: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Write Operations (Local with Dirty Tracking)

    /// Create a new shift locally
    /// The shift will be marked as dirty and pushed to server during next sync
    /// - Parameters:
    ///   - userId: User ID
    ///   - shiftDate: Date of the shift
    ///   - startTime: Start time (HH:mm)
    ///   - endTime: End time (HH:mm)
    ///   - customSupplements: Optional custom supplements
    /// - Returns: The created ShiftRow
    func createShift(
        userId: String,
        shiftDate: Date,
        startTime: String,
        endTime: String,
        customSupplements: CustomSupplementsData? = nil
    ) async throws -> ShiftRow {
        // Generate new UUID for the shift
        let id = UUID().uuidString.lowercased()
        let now = Date()

        // Encode supplements if provided
        let supplementsData = customSupplements.flatMap { try? canonicalJSONEncoder.encode($0) }

        // Create snapshot for the new shift (will be empty until server confirms)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        let shiftDateString = dateFormatter.string(from: shiftDate)

        let snapshot = UserShiftServerSnapshot(
            shiftDate: shiftDateString,
            startTime: startTime,
            endTime: endTime,
            customSupplements: supplementsData,
            updatedAt: now,
            revision: 0, // Will be set by server
            deletedAt: nil
        )

        // Mark all fields as dirty since this is a new record
        let allFields = UserShiftField.allCases.map { $0.rawValue }
        let dirtyFieldsData = (try? canonicalJSONEncoder.encode(allFields)) ?? Data()

        let localShift = LocalUserShift(
            id: id,
            userId: userId,
            shiftDate: shiftDate,
            startTime: startTime,
            endTime: endTime,
            customSupplements: supplementsData,
            serverUpdatedAt: now,
            serverRevision: 0, // New shift, no server revision yet
            serverDeletedAt: nil,
            syncStatus: .dirty,
            dirtyFields: dirtyFieldsData,
            lastSyncedSnapshot: snapshot.encoded(),
            localUpdatedAt: now,
            conflictServerSnapshot: nil
        )

        // Save via actor for thread safety
        try await localStore.storeActor.upsertUserShift(localShift)
        try await localStore.storeActor.save()

        logger.info("Created new local shift: \(id)")

        return localShift.toShiftRow()
    }

    /// Update a shift locally
    /// Only the changed fields will be marked dirty
    /// - Parameters:
    ///   - id: Shift ID
    ///   - shiftDate: New shift date (optional)
    ///   - startTime: New start time (optional)
    ///   - endTime: New end time (optional)
    ///   - customSupplements: New custom supplements (optional)
    /// - Returns: Updated ShiftRow if successful
    func updateShift(
        id: String,
        shiftDate: Date? = nil,
        startTime: String? = nil,
        endTime: String? = nil,
        customSupplements: CustomSupplementsData? = nil
    ) async throws -> ShiftRow? {
        let context = localStore.mainContext

        // Fetch existing shift
        let descriptor = FetchDescriptor<LocalUserShift>(
            predicate: #Predicate { $0.id == id }
        )

        guard let localShift = try context.fetch(descriptor).first else {
            logger.warning("Shift not found for update: \(id)")
            return nil
        }

        // Track which fields changed
        var newDirtyFields = localShift.dirtyFieldKeys
        let now = Date()

        if let newDate = shiftDate, newDate != localShift.shiftDate {
            localShift.shiftDate = newDate
            newDirtyFields.insert(.shiftDate)
        }

        if let newStart = startTime, newStart != localShift.startTime {
            localShift.startTime = newStart
            newDirtyFields.insert(.startTime)
        }

        if let newEnd = endTime, newEnd != localShift.endTime {
            localShift.endTime = newEnd
            newDirtyFields.insert(.endTime)
        }

        if let newSupplements = customSupplements {
            let newData = try? canonicalJSONEncoder.encode(newSupplements)
            if newData != localShift.customSupplements {
                localShift.customSupplements = newData
                newDirtyFields.insert(.customSupplements)
            }
        }

        // Update dirty tracking
        localShift.dirtyFieldKeys = newDirtyFields
        localShift.localUpdatedAt = now

        // Set status to dirty if we have changes
        if !newDirtyFields.isEmpty && localShift.syncStatus == .clean {
            localShift.syncStatus = .dirty
        }

        // Save via actor
        try await localStore.storeActor.upsertUserShift(localShift)
        try await localStore.storeActor.save()

        logger.info("Updated local shift: \(id), dirty fields: \(newDirtyFields.map { $0.rawValue })")

        return localShift.toShiftRow()
    }

    /// Mark a shift for deletion
    /// The shift will be soft-deleted on server during next sync
    /// - Parameter id: Shift ID
    func deleteShift(id: String) async throws {
        let context = localStore.mainContext

        let descriptor = FetchDescriptor<LocalUserShift>(
            predicate: #Predicate { $0.id == id }
        )

        guard let localShift = try context.fetch(descriptor).first else {
            logger.warning("Shift not found for deletion: \(id)")
            return
        }

        // Mark for deletion
        localShift.syncStatus = .pendingDelete
        localShift.localUpdatedAt = Date()

        try await localStore.storeActor.upsertUserShift(localShift)
        try await localStore.storeActor.save()

        logger.info("Marked shift for deletion: \(id)")
    }

    // MARK: - Conflict Resolution

    /// Resolve a conflict by keeping the local version
    /// This will mark the shift as dirty and attempt to push during next sync
    /// - Parameter id: Shift ID
    func resolveConflictKeepLocal(id: String) async throws {
        let context = localStore.mainContext

        let descriptor = FetchDescriptor<LocalUserShift>(
            predicate: #Predicate { $0.id == id }
        )

        guard let localShift = try context.fetch(descriptor).first else {
            logger.warning("Shift not found for conflict resolution: \(id)")
            return
        }

        guard localShift.syncStatus == .conflict else {
            logger.warning("Shift is not in conflict state: \(id)")
            return
        }

        // Get server version to update our server metadata
        guard let serverSnapshot = UserShiftServerSnapshot.decode(from: localShift.conflictServerSnapshot ?? Data()) else {
            logger.error("No server snapshot found for conflict: \(id)")
            return
        }

        // Update server metadata but keep local values
        localShift.serverRevision = serverSnapshot.revision
        localShift.serverUpdatedAt = serverSnapshot.updatedAt
        localShift.syncStatus = .dirty
        localShift.conflictServerSnapshot = nil
        localShift.localUpdatedAt = Date()

        try await localStore.storeActor.upsertUserShift(localShift)
        try await localStore.storeActor.save()

        logger.info("Resolved conflict (kept local) for shift: \(id)")
    }

    /// Resolve a conflict by accepting the server version
    /// This will overwrite local changes with server data
    /// - Parameter id: Shift ID
    func resolveConflictKeepServer(id: String) async throws {
        let context = localStore.mainContext

        let descriptor = FetchDescriptor<LocalUserShift>(
            predicate: #Predicate { $0.id == id }
        )

        guard let localShift = try context.fetch(descriptor).first else {
            logger.warning("Shift not found for conflict resolution: \(id)")
            return
        }

        guard localShift.syncStatus == .conflict else {
            logger.warning("Shift is not in conflict state: \(id)")
            return
        }

        guard let serverSnapshot = UserShiftServerSnapshot.decode(from: localShift.conflictServerSnapshot ?? Data()) else {
            logger.error("No server snapshot found for conflict: \(id)")
            return
        }

        // Apply server values
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")

        localShift.shiftDate = dateFormatter.date(from: serverSnapshot.shiftDate) ?? localShift.shiftDate
        localShift.startTime = serverSnapshot.startTime
        localShift.endTime = serverSnapshot.endTime
        localShift.customSupplements = serverSnapshot.customSupplements
        localShift.serverRevision = serverSnapshot.revision
        localShift.serverUpdatedAt = serverSnapshot.updatedAt
        localShift.serverDeletedAt = serverSnapshot.deletedAt

        // Clear dirty state
        localShift.syncStatus = .clean
        localShift.dirtyFieldKeys = []
        localShift.lastSyncedSnapshot = localShift.conflictServerSnapshot ?? Data()
        localShift.conflictServerSnapshot = nil
        localShift.localUpdatedAt = Date()

        try await localStore.storeActor.upsertUserShift(localShift)
        try await localStore.storeActor.save()

        logger.info("Resolved conflict (kept server) for shift: \(id)")
    }

    // MARK: - Local Shift Access (For Sync)

    /// Get the raw LocalUserShift object
    /// Used by sync coordinator for advanced operations
    func getLocalShift(id: String) -> LocalUserShift? {
        let context = localStore.mainContext

        let descriptor = FetchDescriptor<LocalUserShift>(
            predicate: #Predicate { $0.id == id }
        )

        do {
            return try context.fetch(descriptor).first
        } catch {
            logger.error("Failed to fetch local shift: \(error.localizedDescription)")
            return nil
        }
    }
}
