import Foundation
import SwiftData
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "SnapshotsRepository")

// MARK: - Snapshots Repository

/// Local-first repository for wage snapshots
/// All reads come from SwiftData; network calls are handled by SyncCoordinator
/// Automatically triggers sync after mutations for immediate upload
@MainActor
final class SnapshotsRepository: ObservableObject {
  static let shared = SnapshotsRepository()

  private let localStore: LocalStore
  private let syncCoordinator: SyncCoordinator

  private init(localStore: LocalStore? = nil, syncCoordinator: SyncCoordinator? = nil) {
    self.localStore = localStore ?? LocalStore.shared
    self.syncCoordinator = syncCoordinator ?? SyncCoordinator.shared
  }

  // MARK: - Sync Helper

  /// Trigger sync after a mutation (fire-and-forget)
  private func triggerSync(userId: String) {
    NotificationCenter.default.post(name: .workSetupDataDidChange, object: nil)
    Task {
      _ = await syncCoordinator.sync(reason: .localChange, userId: userId)
    }
  }

  /// During compatibility rollout, legacy local rows can still have nil jobId.
  /// Treat those rows as belonging to the active default job only.
  private func shouldIncludeLegacyNilJobRows(for userId: String, selectedJobId: String) -> Bool {
    let context = localStore.mainContext
    let descriptor = FetchDescriptor<LocalJob>(
      predicate: #Predicate { job in
        job.userId == userId
          && job.deletedAt == nil
          && job.archivedAt == nil
          && job.isDefault == true
      }
    )

    do {
      guard let defaultJob = try context.fetch(descriptor).first else {
        return false
      }
      return defaultJob.id == selectedJobId
    } catch {
      logger.error(
        "Failed to determine default job for legacy fallback: \(error.localizedDescription)")
      return false
    }
  }

  // MARK: - Read Operations (Local Only)

  /// Get all non-deleted wage snapshots for a user
  /// Ordered by from_date descending (most recent first), with baseline (nil date) last
  /// - Parameter userId: User ID
  /// - Returns: Array of WageSnapshot objects
  func getSnapshots(for userId: String, jobId: String? = nil) -> [WageSnapshot] {
    let context = localStore.mainContext

    do {
      let localSnapshots: [LocalWageSnapshot]

      if let jobId {
        let includeLegacyNil = shouldIncludeLegacyNilJobRows(for: userId, selectedJobId: jobId)
        let primaryDescriptor = FetchDescriptor<LocalWageSnapshot>(
          predicate: #Predicate { snapshot in
            snapshot.userId == userId && snapshot.serverDeletedAt == nil
              && snapshot.syncStatusRaw != "pendingDelete" && snapshot.jobId == jobId
          },
          sortBy: [SortDescriptor(\.fromDate, order: .reverse)]
        )

        if includeLegacyNil {
          let legacyDescriptor = FetchDescriptor<LocalWageSnapshot>(
            predicate: #Predicate { snapshot in
              snapshot.userId == userId && snapshot.serverDeletedAt == nil
                && snapshot.syncStatusRaw != "pendingDelete" && snapshot.jobId == nil
            },
            sortBy: [SortDescriptor(\.fromDate, order: .reverse)]
          )
          var combined = try context.fetch(primaryDescriptor)
          combined.append(contentsOf: try context.fetch(legacyDescriptor))
          localSnapshots = combined.sorted { lhs, rhs in
            switch (lhs.fromDate, rhs.fromDate) {
            case (let l?, let r?):
              return l > r

            case (_?, nil):
              return true

            case (nil, _?):
              return false

            case (nil, nil):
              return lhs.localUpdatedAt > rhs.localUpdatedAt
            }
          }
        } else {
          localSnapshots = try context.fetch(primaryDescriptor)
        }
      } else {
        let descriptor = FetchDescriptor<LocalWageSnapshot>(
          predicate: #Predicate { snapshot in
            snapshot.userId == userId && snapshot.serverDeletedAt == nil
              && snapshot.syncStatusRaw != "pendingDelete"
          },
          sortBy: [SortDescriptor(\.fromDate, order: .reverse)]
        )
        localSnapshots = try context.fetch(descriptor)
      }

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
  func snapshotForDate(_ date: String, userId: String, jobId: String? = nil) -> WageSnapshot? {
    let snapshots = getSnapshots(for: userId, jobId: jobId)
    return SnapshotsService.snapshotForDate(date, from: snapshots)
  }

  /// Batch lookup for multiple dates
  /// - Parameters:
  ///   - dates: Array of ISO date strings
  ///   - userId: User ID
  /// - Returns: Dictionary mapping dates to applicable snapshots
  func snapshotsForDates(
    _ dates: [String],
    userId: String,
    jobId: String? = nil
  ) -> [String: WageSnapshot] {
    let snapshots = getSnapshots(for: userId, jobId: jobId)
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
  func getBaselineSnapshot(for userId: String, jobId: String? = nil) -> WageSnapshot? {
    let context = localStore.mainContext

    do {
      let baselineDescriptor = FetchDescriptor<LocalWageSnapshot>(
        predicate: #Predicate { snapshot in
          snapshot.userId == userId && snapshot.fromDate == nil && snapshot.serverDeletedAt == nil
            && snapshot.syncStatusRaw != "pendingDelete"
        }
      )
      let baselineRows = try context.fetch(baselineDescriptor)

      if let jobId {
        let includeLegacyNil = shouldIncludeLegacyNilJobRows(for: userId, selectedJobId: jobId)

        if let localSnapshot = baselineRows.first(where: { $0.jobId == jobId }) {
          return localSnapshot.toWageSnapshot()
        }

        guard includeLegacyNil else {
          return nil
        }

        guard let localSnapshot = baselineRows.first(where: { $0.jobId == nil }) else {
          return nil
        }
        return localSnapshot.toWageSnapshot()
      }

      guard let localSnapshot = baselineRows.first else {
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
        snapshot.userId == userId
          && (snapshot.syncStatusRaw == "dirty" || snapshot.syncStatusRaw == "pendingDelete")
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
  ///   - tariffTypeId: Tariff type ID (e.g., "hk_retail") or nil for custom wage
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
    jobId: String? = nil,
    fromDate: Date? = nil,
    hourlyWage: Double,
    wageLevel: Int? = nil,
    tariffTypeId: String? = nil,
    supplements: SupplementRulesSnapshot,
    overtime: OvertimeConfig = .disabled,
    taxEnabled: Bool? = nil,
    taxPercentage: Double? = nil,
    breakEnabled: Bool? = nil,
    breakMethod: String? = nil,
    breakThresholdHours: Double? = nil,
    breakDeductionMinutes: Int? = nil
  ) async throws -> WageSnapshot {
    let createdSnapshot = try await localStore.storeActor.createWageSnapshot(
      userId: userId,
      jobId: jobId,
      fromDate: fromDate,
      hourlyWage: hourlyWage,
      wageLevel: wageLevel,
      tariffTypeId: tariffTypeId,
      supplements: supplements,
      overtime: overtime,
      taxEnabled: taxEnabled,
      taxPercentage: taxPercentage,
      breakEnabled: breakEnabled,
      breakMethod: breakMethod,
      breakThresholdHours: breakThresholdHours,
      breakDeductionMinutes: breakDeductionMinutes
    )

    logger.info("Created new local snapshot: \(createdSnapshot.id)")

    // Trigger sync to upload immediately
    triggerSync(userId: userId)

    return createdSnapshot
  }

  /// Update a wage snapshot locally
  /// - Parameters:
  ///   - id: Snapshot ID
  ///   - hourlyWage: New hourly wage (optional)
  ///   - wageLevel: New wage level (optional)
  ///   - updateWageLevel: Whether to apply `wageLevel`, including nil clears
  ///   - updateTariffTypeId: Whether to apply `tariffTypeId`, including nil clears
  ///   - supplements: New supplements (optional)
  ///   - taxEnabled: New tax enabled flag (optional)
  ///   - taxPercentage: New tax percentage (optional)
  ///   - updateTaxPercentage: Whether to apply `taxPercentage`, including nil clears
  ///   - breakEnabled: New break enabled flag (optional)
  ///   - breakMethod: New break method (optional)
  ///   - breakThresholdHours: New break threshold (optional)
  ///   - breakDeductionMinutes: New break deduction (optional)
  /// - Returns: Updated WageSnapshot if successful
  func updateSnapshot(
    id: String,
    jobId: String? = nil,
    hourlyWage: Double? = nil,
    wageLevel: Int? = nil,
    updateWageLevel: Bool = false,
    tariffTypeId: String? = nil,
    updateTariffTypeId: Bool = false,
    supplements: SupplementRulesSnapshot? = nil,
    overtime: OvertimeConfig? = nil,
    taxEnabled: Bool? = nil,
    taxPercentage: Double? = nil,
    updateTaxPercentage: Bool = false,
    breakEnabled: Bool? = nil,
    breakMethod: String? = nil,
    breakThresholdHours: Double? = nil,
    breakDeductionMinutes: Int? = nil
  ) async throws -> WageSnapshot? {
    do {
      let updatedSnapshot = try await localStore.storeActor.updateWageSnapshot(
        id: id,
        jobId: jobId,
        hourlyWage: hourlyWage,
        wageLevel: wageLevel,
        updateWageLevel: updateWageLevel,
        tariffTypeId: tariffTypeId,
        updateTariffTypeId: updateTariffTypeId,
        supplements: supplements,
        overtime: overtime,
        taxEnabled: taxEnabled,
        taxPercentage: taxPercentage,
        updateTaxPercentage: updateTaxPercentage,
        breakEnabled: breakEnabled,
        breakMethod: breakMethod,
        breakThresholdHours: breakThresholdHours,
        breakDeductionMinutes: breakDeductionMinutes
      )

      logger.info("Updated local snapshot: \(id)")

      // Trigger sync to upload immediately
      triggerSync(userId: updatedSnapshot.user_id)

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
    // Get userId before mutation for sync
    let userId = getLocalSnapshot(id: id)?.userId

    do {
      try await localStore.storeActor.markWageSnapshotPendingDelete(id: id)
      logger.info("Marked snapshot for deletion: \(id)")

      // Trigger sync to upload immediately
      if let userId {
        triggerSync(userId: userId)
      }
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
