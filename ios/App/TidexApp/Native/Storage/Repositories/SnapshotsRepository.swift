import Foundation
import SwiftData
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "SnapshotsRepository")

// MARK: - Snapshots Repository

/// Local-first repository for wage snapshots
/// All reads come from SwiftData; network calls are handled by SyncCoordinator
@MainActor
final class SnapshotsRepository: ObservableObject {
    static let shared = SnapshotsRepository()

    private let localStore: LocalStore

    private init(localStore: LocalStore? = nil) {
        self.localStore = localStore ?? LocalStore.shared
    }

    // MARK: - Read Operations (Local Only)

    /// Get all non-deleted wage snapshots for a user
    /// Ordered by from_date descending (most recent first), with baseline (nil date) last
    /// - Parameter userId: User ID
    /// - Returns: Array of WageSnapshot objects
    func getSnapshots(for userId: String) -> [WageSnapshot] {
        let context = localStore.mainContext

        let descriptor = FetchDescriptor<LocalWageSnapshot>(
            predicate: #Predicate { snapshot in
                snapshot.userId == userId && snapshot.serverDeletedAt == nil
            },
            sortBy: [SortDescriptor(\.fromDate, order: .reverse)]
        )

        do {
            let localSnapshots = try context.fetch(descriptor)
            return localSnapshots.map { $0.toWageSnapshot() }
        } catch {
            logger.error("Failed to fetch snapshots: \(error.localizedDescription)")
            return []
        }
    }

    /// Get a single wage snapshot by ID
    /// - Parameter id: Snapshot ID
    /// - Returns: WageSnapshot if found
    func getSnapshot(id: String) -> WageSnapshot? {
        let context = localStore.mainContext

        let descriptor = FetchDescriptor<LocalWageSnapshot>(
            predicate: #Predicate { $0.id == id }
        )

        do {
            guard let localSnapshot = try context.fetch(descriptor).first else {
                return nil
            }
            return localSnapshot.toWageSnapshot()
        } catch {
            logger.error("Failed to fetch snapshot by ID: \(error.localizedDescription)")
            return nil
        }
    }

    /// Find the applicable snapshot for a specific date
    /// Uses binary search for efficiency
    /// - Parameters:
    ///   - date: ISO date string (YYYY-MM-DD)
    ///   - userId: User ID
    /// - Returns: Applicable WageSnapshot or nil
    func snapshotForDate(_ date: String, userId: String) -> WageSnapshot? {
        let snapshots = getSnapshots(for: userId)
        return SnapshotsService.snapshotForDate(date, from: snapshots)
    }

    /// Batch lookup for multiple dates
    /// - Parameters:
    ///   - dates: Array of ISO date strings
    ///   - userId: User ID
    /// - Returns: Dictionary mapping dates to applicable snapshots
    func snapshotsForDates(_ dates: [String], userId: String) -> [String: WageSnapshot] {
        let snapshots = getSnapshots(for: userId)
        var map: [String: WageSnapshot] = [:]
        for date in dates {
            if let snapshot = SnapshotsService.snapshotForDate(date, from: snapshots) {
                map[date] = snapshot
            }
        }
        return map
    }

    /// Get the baseline (undated) snapshot for a user
    /// - Parameter userId: User ID
    /// - Returns: Baseline WageSnapshot if found
    func getBaselineSnapshot(for userId: String) -> WageSnapshot? {
        let context = localStore.mainContext

        let descriptor = FetchDescriptor<LocalWageSnapshot>(
            predicate: #Predicate { snapshot in
                snapshot.userId == userId &&
                snapshot.fromDate == nil &&
                snapshot.serverDeletedAt == nil
            }
        )

        do {
            guard let localSnapshot = try context.fetch(descriptor).first else {
                return nil
            }
            return localSnapshot.toWageSnapshot()
        } catch {
            logger.error("Failed to fetch baseline snapshot: \(error.localizedDescription)")
            return nil
        }
    }

    /// Get snapshots that have sync conflicts
    /// - Parameter userId: User ID
    /// - Returns: Array of local snapshots in conflict state
    func getConflictingSnapshots(for userId: String) -> [LocalWageSnapshot] {
        let context = localStore.mainContext

        let descriptor = FetchDescriptor<LocalWageSnapshot>(
            predicate: #Predicate { snapshot in
                snapshot.userId == userId && snapshot.syncStatusRaw == "conflict"
            }
        )

        do {
            return try context.fetch(descriptor)
        } catch {
            logger.error("Failed to fetch conflicting snapshots: \(error.localizedDescription)")
            return []
        }
    }

    /// Get snapshots that have pending changes
    /// - Parameter userId: User ID
    /// - Returns: Array of local snapshots with dirty or pending delete status
    func getPendingSnapshots(for userId: String) -> [LocalWageSnapshot] {
        let context = localStore.mainContext

        let descriptor = FetchDescriptor<LocalWageSnapshot>(
            predicate: #Predicate { snapshot in
                snapshot.userId == userId && (
                    snapshot.syncStatusRaw == "dirty" ||
                    snapshot.syncStatusRaw == "pendingDelete"
                )
            }
        )

        do {
            return try context.fetch(descriptor)
        } catch {
            logger.error("Failed to fetch pending snapshots: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Write Operations (Local with Dirty Tracking)

    /// Create a new wage snapshot locally
    /// - Parameters:
    ///   - userId: User ID
    ///   - fromDate: Effective date (nil for baseline)
    ///   - hourlyWage: Hourly wage
    ///   - wageLevel: Wage level (nil for custom)
    ///   - supplements: Supplement rules
    ///   - taxEnabled: Tax enabled flag
    ///   - taxPercentage: Tax percentage
    ///   - breakEnabled: Break enabled flag
    ///   - breakMethod: Break method
    ///   - breakThresholdHours: Break threshold hours
    ///   - breakDeductionMinutes: Break deduction minutes
    /// - Returns: Created WageSnapshot
    func createSnapshot(
        userId: String,
        fromDate: Date? = nil,
        hourlyWage: Double,
        wageLevel: Int? = nil,
        supplements: SupplementRulesSnapshot,
        taxEnabled: Bool? = nil,
        taxPercentage: Double? = nil,
        breakEnabled: Bool? = nil,
        breakMethod: String? = nil,
        breakThresholdHours: Double? = nil,
        breakDeductionMinutes: Int? = nil
    ) async throws -> WageSnapshot {
        let createdSnapshot = try await localStore.storeActor.createWageSnapshot(
            userId: userId,
            fromDate: fromDate,
            hourlyWage: hourlyWage,
            wageLevel: wageLevel,
            supplements: supplements,
            taxEnabled: taxEnabled,
            taxPercentage: taxPercentage,
            breakEnabled: breakEnabled,
            breakMethod: breakMethod,
            breakThresholdHours: breakThresholdHours,
            breakDeductionMinutes: breakDeductionMinutes
        )

        logger.info("Created new local snapshot: \(createdSnapshot.id)")

        return createdSnapshot
    }

    /// Update a wage snapshot locally
    /// - Parameters:
    ///   - id: Snapshot ID
    ///   - hourlyWage: New hourly wage (optional)
    ///   - wageLevel: New wage level (optional)
    ///   - supplements: New supplements (optional)
    ///   - taxEnabled: New tax enabled flag (optional)
    ///   - taxPercentage: New tax percentage (optional)
    ///   - breakEnabled: New break enabled flag (optional)
    ///   - breakMethod: New break method (optional)
    ///   - breakThresholdHours: New break threshold (optional)
    ///   - breakDeductionMinutes: New break deduction (optional)
    /// - Returns: Updated WageSnapshot if successful
    func updateSnapshot(
        id: String,
        hourlyWage: Double? = nil,
        wageLevel: Int? = nil,
        supplements: SupplementRulesSnapshot? = nil,
        taxEnabled: Bool? = nil,
        taxPercentage: Double? = nil,
        breakEnabled: Bool? = nil,
        breakMethod: String? = nil,
        breakThresholdHours: Double? = nil,
        breakDeductionMinutes: Int? = nil
    ) async throws -> WageSnapshot? {
        do {
            let updatedSnapshot = try await localStore.storeActor.updateWageSnapshot(
                id: id,
                hourlyWage: hourlyWage,
                wageLevel: wageLevel,
                supplements: supplements,
                taxEnabled: taxEnabled,
                taxPercentage: taxPercentage,
                breakEnabled: breakEnabled,
                breakMethod: breakMethod,
                breakThresholdHours: breakThresholdHours,
                breakDeductionMinutes: breakDeductionMinutes
            )

            logger.info("Updated local snapshot: \(id)")

            return updatedSnapshot
        } catch LocalStoreWriteError.notFound {
            logger.warning("Snapshot not found for update: \(id)")
            return nil
        } catch {
            throw error
        }
    }

    /// Mark a snapshot for deletion
    /// - Parameter id: Snapshot ID
    func deleteSnapshot(id: String) async throws {
        do {
            try await localStore.storeActor.markWageSnapshotPendingDelete(id: id)
            logger.info("Marked snapshot for deletion: \(id)")
        } catch LocalStoreWriteError.notFound {
            logger.warning("Snapshot not found for deletion: \(id)")
        } catch {
            throw error
        }
    }

    // MARK: - Conflict Resolution

    /// Resolve a conflict by keeping the local version
    /// - Parameter id: Snapshot ID
    func resolveConflictKeepLocal(id: String) async throws {
        do {
            try await localStore.storeActor.resolveStoredWageSnapshotConflictKeepLocal(id: id)
            logger.info("Resolved conflict (kept local) for snapshot: \(id)")
        } catch LocalStoreWriteError.notFound {
            logger.warning("Snapshot not found for conflict resolution: \(id)")
        } catch LocalStoreWriteError.notInConflict {
            logger.warning("Snapshot is not in conflict state: \(id)")
        } catch LocalStoreWriteError.missingConflictSnapshot {
            logger.error("No server snapshot found for conflict: \(id)")
        } catch {
            throw error
        }
    }

    /// Resolve a conflict by accepting the server version
    /// - Parameter id: Snapshot ID
    func resolveConflictKeepServer(id: String) async throws {
        do {
            try await localStore.storeActor.resolveStoredWageSnapshotConflictKeepServer(id: id)
            logger.info("Resolved conflict (kept server) for snapshot: \(id)")
        } catch LocalStoreWriteError.notFound {
            logger.warning("Snapshot not found for conflict resolution: \(id)")
        } catch LocalStoreWriteError.notInConflict {
            logger.warning("Snapshot is not in conflict state: \(id)")
        } catch LocalStoreWriteError.missingConflictSnapshot {
            logger.error("No server snapshot found for conflict: \(id)")
        } catch {
            throw error
        }
    }

    // MARK: - Local Snapshot Access (For Sync)

    /// Get the raw LocalWageSnapshot object
    func getLocalSnapshot(id: String) -> LocalWageSnapshot? {
        let context = localStore.mainContext

        let descriptor = FetchDescriptor<LocalWageSnapshot>(
            predicate: #Predicate { $0.id == id }
        )

        do {
            return try context.fetch(descriptor).first
        } catch {
            logger.error("Failed to fetch local snapshot: \(error.localizedDescription)")
            return nil
        }
    }
}
