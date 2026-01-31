import Foundation
import SwiftData
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "RecurringShiftsRepository")

// MARK: - Recurring Shifts Repository

/// Local-first repository for recurring shifts
/// All reads come from SwiftData; network calls are handled by SyncCoordinator
/// Automatically triggers sync after mutations for immediate upload
@MainActor
final class RecurringShiftsRepository: ObservableObject {
    static let shared = RecurringShiftsRepository()

    private let localStore: LocalStore
    private let syncCoordinator: SyncCoordinator

    private init(localStore: LocalStore? = nil, syncCoordinator: SyncCoordinator? = nil) {
        self.localStore = localStore ?? LocalStore.shared
        self.syncCoordinator = syncCoordinator ?? SyncCoordinator.shared
    }

    // MARK: - Sync Helper

    /// Trigger sync after a mutation (fire-and-forget)
    private func triggerSync(userId: String) {
        Task {
            _ = await syncCoordinator.sync(reason: .localChange, userId: userId)
        }
    }

    // MARK: - Read Operations (Local Only)

    /// Get all non-deleted recurring shifts for a user
    /// - Parameter userId: User ID
    /// - Returns: Array of RecurringShiftRow objects
    func getRecurringShifts(for userId: String) -> [RecurringShiftRow] {
        let context = localStore.mainContext

        // Filter out both server-deleted and locally pending delete shifts
        let descriptor = FetchDescriptor<LocalRecurringShift>(
            predicate: #Predicate { shift in
                shift.userId == userId &&
                shift.serverDeletedAt == nil &&
                shift.syncStatusRaw != "pendingDelete"
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
        let createdShift = try await localStore.storeActor.createRecurringShift(
            userId: userId,
            startTime: startTime,
            endTime: endTime,
            repeatIntervalWeeks: repeatIntervalWeeks,
            selectedDays: selectedDays,
            endCondition: endCondition,
            exclusions: exclusions,
            dateSpecificSupplements: dateSpecificSupplements
        )

        logger.info("Created new local recurring shift: \(createdShift.id)")

        // Trigger sync to upload immediately
        triggerSync(userId: userId)

        return createdShift
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
        do {
            let updatedShift = try await localStore.storeActor.updateRecurringShift(
                id: id,
                startTime: startTime,
                endTime: endTime,
                repeatIntervalWeeks: repeatIntervalWeeks,
                selectedDays: selectedDays,
                endCondition: endCondition,
                exclusions: exclusions,
                dateSpecificSupplements: dateSpecificSupplements
            )

            logger.info("Updated local recurring shift: \(id)")

            // Trigger sync to upload immediately
            triggerSync(userId: updatedShift.user_id)

            return updatedShift
        } catch LocalStoreWriteError.notFound {
            logger.warning("Recurring shift not found for update: \(id)")
            return nil
        } catch {
            throw error
        }
    }

    /// Add an exclusion date to a recurring shift
    /// - Parameters:
    ///   - id: Recurring shift ID
    ///   - date: Date to exclude (ISO string YYYY-MM-DD)
    func addExclusion(id: String, date: String) async throws {
        // Get userId before mutation for sync
        let userId = getLocalRecurringShift(id: id)?.userId

        do {
            let didAdd = try await localStore.storeActor.addRecurringShiftExclusion(id: id, date: date)
            if didAdd {
                logger.info("Added exclusion \(date) to recurring shift: \(id)")

                // Trigger sync to upload immediately
                if let userId = userId {
                    triggerSync(userId: userId)
                }
            }
        } catch LocalStoreWriteError.notFound {
            logger.warning("Recurring shift not found for exclusion: \(id)")
        } catch {
            throw error
        }
    }

    /// Mark a recurring shift for deletion
    /// - Parameter id: Recurring shift ID
    func deleteRecurringShift(id: String) async throws {
        // Get userId before mutation for sync
        let userId = getLocalRecurringShift(id: id)?.userId

        do {
            try await localStore.storeActor.markRecurringShiftPendingDelete(id: id)
            logger.info("Marked recurring shift for deletion: \(id)")

            // Trigger sync to upload immediately
            if let userId = userId {
                triggerSync(userId: userId)
            }
        } catch LocalStoreWriteError.notFound {
            logger.warning("Recurring shift not found for deletion: \(id)")
        } catch {
            throw error
        }
    }

    // MARK: - Conflict Resolution

    /// Resolve a conflict by keeping the local version
    /// - Parameter id: Recurring shift ID
    func resolveConflictKeepLocal(id: String) async throws {
        do {
            try await localStore.storeActor.resolveStoredRecurringShiftConflictKeepLocal(id: id)
            logger.info("Resolved conflict (kept local) for recurring shift: \(id)")
        } catch LocalStoreWriteError.notFound {
            logger.warning("Recurring shift not found for conflict resolution: \(id)")
        } catch LocalStoreWriteError.notInConflict {
            logger.warning("Recurring shift is not in conflict state: \(id)")
        } catch LocalStoreWriteError.missingConflictSnapshot {
            logger.error("No server snapshot found for conflict: \(id)")
        } catch {
            throw error
        }
    }

    /// Resolve a conflict by accepting the server version
    /// - Parameter id: Recurring shift ID
    func resolveConflictKeepServer(id: String) async throws {
        do {
            try await localStore.storeActor.resolveStoredRecurringShiftConflictKeepServer(id: id)
            logger.info("Resolved conflict (kept server) for recurring shift: \(id)")
        } catch LocalStoreWriteError.notFound {
            logger.warning("Recurring shift not found for conflict resolution: \(id)")
        } catch LocalStoreWriteError.notInConflict {
            logger.warning("Recurring shift is not in conflict state: \(id)")
        } catch LocalStoreWriteError.missingConflictSnapshot {
            logger.error("No server snapshot found for conflict: \(id)")
        } catch {
            throw error
        }
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
