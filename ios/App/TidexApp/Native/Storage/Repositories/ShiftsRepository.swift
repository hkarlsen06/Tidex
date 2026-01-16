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
        let createdShift = try await localStore.storeActor.createUserShift(
            userId: userId,
            shiftDate: shiftDate,
            startTime: startTime,
            endTime: endTime,
            customSupplements: customSupplements
        )

        logger.info("Created new local shift: \(createdShift.id)")

        // Update widget storage with the new shift
        NativeWidgetStorage.updateWidgetStorage(for: userId)

        return createdShift
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
        do {
            let updatedShift = try await localStore.storeActor.updateUserShift(
                id: id,
                shiftDate: shiftDate,
                startTime: startTime,
                endTime: endTime,
                customSupplements: customSupplements
            )

            logger.info("Updated local shift: \(id)")

            if let userId = updatedShift.user_id {
                NativeWidgetStorage.updateWidgetStorage(for: userId)
            }

            return updatedShift
        } catch LocalStoreWriteError.notFound {
            logger.warning("Shift not found for update: \(id)")
            return nil
        } catch {
            throw error
        }
    }

    /// Mark a shift for deletion
    /// The shift will be soft-deleted on server during next sync
    /// - Parameter id: Shift ID
    func deleteShift(id: String) async throws {
        do {
            let userId = try await localStore.storeActor.markShiftPendingDelete(id: id)

            logger.info("Marked shift for deletion: \(id)")

            // Update widget storage to remove the deleted shift
            NativeWidgetStorage.updateWidgetStorage(for: userId)
        } catch LocalStoreWriteError.notFound {
            logger.warning("Shift not found for deletion: \(id)")
        } catch {
            throw error
        }
    }

    // MARK: - Conflict Resolution

    /// Resolve a conflict by keeping the local version
    /// This will mark the shift as dirty and attempt to push during next sync
    /// - Parameter id: Shift ID
    func resolveConflictKeepLocal(id: String) async throws {
        do {
            try await localStore.storeActor.resolveStoredShiftConflictKeepLocal(id: id)
            logger.info("Resolved conflict (kept local) for shift: \(id)")
        } catch LocalStoreWriteError.notFound {
            logger.warning("Shift not found for conflict resolution: \(id)")
        } catch LocalStoreWriteError.notInConflict {
            logger.warning("Shift is not in conflict state: \(id)")
        } catch LocalStoreWriteError.missingConflictSnapshot {
            logger.error("No server snapshot found for conflict: \(id)")
        } catch {
            throw error
        }
    }

    /// Resolve a conflict by accepting the server version
    /// This will overwrite local changes with server data
    /// - Parameter id: Shift ID
    func resolveConflictKeepServer(id: String) async throws {
        do {
            try await localStore.storeActor.resolveStoredShiftConflictKeepServer(id: id)
            logger.info("Resolved conflict (kept server) for shift: \(id)")
        } catch LocalStoreWriteError.notFound {
            logger.warning("Shift not found for conflict resolution: \(id)")
        } catch LocalStoreWriteError.notInConflict {
            logger.warning("Shift is not in conflict state: \(id)")
        } catch LocalStoreWriteError.missingConflictSnapshot {
            logger.error("No server snapshot found for conflict: \(id)")
        } catch {
            throw error
        }
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
