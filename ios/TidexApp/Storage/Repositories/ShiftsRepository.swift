import Foundation
import SwiftData
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "ShiftsRepository")

// MARK: - Shift Creation Error

/// Errors specific to shift creation with tier gating
enum ShiftCreationError: Error, LocalizedError {
  /// Free user trying to create shifts in a new month when they already have shifts in another month
  case monthLimitReached(existingMonths: Set<DateComponents>)

  var errorDescription: String? {
    switch self {
    case .monthLimitReached:
      return "Month limit reached. Upgrade to Pro or Max to add shifts in multiple months."
    }
  }
}

// MARK: - Shifts Repository

/// Local-first repository for user shifts
/// All reads come from SwiftData; network calls are handled by SyncCoordinator
/// Automatically triggers sync after mutations for immediate upload
@MainActor
final class ShiftsRepository: ObservableObject {
  static let shared = ShiftsRepository()

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
      guard let defaultJob = try context.fetch(descriptor).first else { return false }
      return defaultJob.id == selectedJobId
    } catch {
      logger.error(
        "Failed to determine default job for legacy fallback: \(error.localizedDescription)")
      return false
    }
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
    endDate: Date,
    jobId: String? = nil
  ) -> [ShiftRow] {
    let context = localStore.mainContext

    do {
      let descriptor = FetchDescriptor<LocalUserShift>(
        predicate: #Predicate { shift in
          shift.userId == userId && shift.serverDeletedAt == nil
            && shift.syncStatusRaw != "pendingDelete" && shift.shiftDate >= startDate
            && shift.shiftDate <= endDate
        },
        sortBy: [SortDescriptor(\LocalUserShift.shiftDate, order: .reverse)]
      )
      let fetchedShifts = try context.fetch(descriptor)

      let localShifts: [LocalUserShift]
      if let jobId {
        let includeLegacyNil = shouldIncludeLegacyNilJobRows(for: userId, selectedJobId: jobId)
        if includeLegacyNil {
          localShifts = fetchedShifts.filter { $0.jobId == jobId || $0.jobId == nil }
        } else {
          localShifts = fetchedShifts.filter { $0.jobId == jobId }
        }
      } else {
        localShifts = fetchedShifts
      }

      return localShifts.map { $0.toShiftRow() }
    } catch {
      logger.error("Failed to fetch shifts: \(error.localizedDescription)")
      return []
    }
  }

  /// Get all non-deleted shifts for a user within a date range via `LocalStoreActor`.
  /// This avoids blocking the main actor during larger reads.
  func getShiftsOffMain(
    for userId: String,
    startDate: Date,
    endDate: Date,
    jobId: String? = nil
  ) async -> [ShiftRow] {
    let fetchedShifts = await localStore.storeActor.fetchShifts(
      userId: userId,
      startDate: startDate,
      endDate: endDate
    )

    guard let jobId else {
      return fetchedShifts
    }

    let includeLegacyNil = shouldIncludeLegacyNilJobRows(for: userId, selectedJobId: jobId)
    if includeLegacyNil {
      return fetchedShifts.filter { $0.job_id == jobId || $0.job_id == nil }
    }
    return fetchedShifts.filter { $0.job_id == jobId }
  }

  /// Get all non-deleted shifts for a user (no date filter)
  /// - Parameter userId: User ID
  /// - Returns: Array of ShiftRow objects
  func getAllShifts(for userId: String, jobId: String? = nil) -> [ShiftRow] {
    let context = localStore.mainContext

    do {
      let descriptor = FetchDescriptor<LocalUserShift>(
        predicate: #Predicate { shift in
          shift.userId == userId && shift.serverDeletedAt == nil
            && shift.syncStatusRaw != "pendingDelete"
        },
        sortBy: [SortDescriptor(\LocalUserShift.shiftDate, order: .reverse)]
      )
      let fetchedShifts = try context.fetch(descriptor)

      let localShifts: [LocalUserShift]
      if let jobId {
        let includeLegacyNil = shouldIncludeLegacyNilJobRows(for: userId, selectedJobId: jobId)
        if includeLegacyNil {
          localShifts = fetchedShifts.filter { $0.jobId == jobId || $0.jobId == nil }
        } else {
          localShifts = fetchedShifts.filter { $0.jobId == jobId }
        }
      } else {
        localShifts = fetchedShifts
      }

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
        shift.userId == userId
          && (shift.syncStatusRaw == "dirty" || shift.syncStatusRaw == "pendingDelete")
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
  ///   - shiftId: Optional deterministic shift ID for idempotent create flows
  ///   - userId: User ID
  ///   - jobId: Job ID (optional for compatibility; server assigns default when omitted)
  ///   - shiftDate: Date of the shift
  ///   - startTime: Start time (HH:mm)
  ///   - endTime: End time (HH:mm)
  ///   - customSupplements: Optional custom supplements
  /// - Returns: The created ShiftRow
  func createShift(
    shiftId: String? = nil,
    userId: String,
    jobId: String? = nil,
    shiftDate: Date,
    startTime: String,
    endTime: String,
    customSupplements: CustomSupplementsData? = nil
  ) async throws -> ShiftRow {
    let createdShift = try await localStore.storeActor.createUserShift(
      id: shiftId,
      userId: userId,
      jobId: jobId,
      shiftDate: shiftDate,
      startTime: startTime,
      endTime: endTime,
      customSupplements: customSupplements
    )

    logger.info("Created new local shift: \(createdShift.id)")

    // Update widget storage with the new shift
    NativeWidgetStorage.updateWidgetStorage(for: userId)

    // Update Apple Watch with new shift data
    WatchConnectivityManager.shared.sendUpdatedData(userId: userId)

    // Trigger sync to upload immediately
    triggerSync(userId: userId)

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
    jobId: String? = nil,
    shiftDate: Date? = nil,
    startTime: String? = nil,
    endTime: String? = nil,
    customSupplements: CustomSupplementsData? = nil
  ) async throws -> ShiftRow? {
    do {
      let updatedShift = try await localStore.storeActor.updateUserShift(
        id: id,
        jobId: jobId,
        shiftDate: shiftDate,
        startTime: startTime,
        endTime: endTime,
        customSupplements: customSupplements
      )

      logger.info("Updated local shift: \(id)")

      if let userId = updatedShift.user_id {
        NativeWidgetStorage.updateWidgetStorage(for: userId)
        // Update Apple Watch with new shift data
        WatchConnectivityManager.shared.sendUpdatedData(userId: userId)
        // Trigger sync to upload immediately
        triggerSync(userId: userId)
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

      // Update Apple Watch with new shift data
      WatchConnectivityManager.shared.sendUpdatedData(userId: userId)

      // Trigger sync to upload immediately
      triggerSync(userId: userId)
    } catch LocalStoreWriteError.notFound {
      logger.warning("Shift not found for deletion: \(id)")
    } catch {
      throw error
    }
  }

  /// Mark multiple shifts for deletion in one write transaction.
  /// Side effects (widget/watch/sync) are dispatched once per affected user.
  func deleteShifts(ids: [String]) async throws {
    let uniqueIds = Array(Set(ids))
    guard !uniqueIds.isEmpty else { return }

    let userIds = try await localStore.storeActor.markShiftsPendingDelete(ids: uniqueIds)
    guard !userIds.isEmpty else {
      logger.warning("No shifts found for batch deletion (\(uniqueIds.count) IDs)")
      return
    }

    for userId in userIds {
      NativeWidgetStorage.updateWidgetStorage(for: userId)
      WatchConnectivityManager.shared.sendUpdatedData(userId: userId)
      triggerSync(userId: userId)
    }

    logger.info("Marked \(uniqueIds.count) shifts for batch deletion")
  }

  /// Delete all shifts that are NOT in the target month
  /// Used when free tier users choose to delete other months to add shifts to a new month
  /// - Parameters:
  ///   - userId: User ID
  ///   - targetMonth: The month to keep (year and month components)
  /// - Returns: Number of shifts deleted
  func deleteShiftsInOtherMonths(userId: String, targetMonth: DateComponents) async throws -> Int {
    let context = localStore.mainContext
    let calendar = Calendar.current

    // Fetch all active shifts for user
    let descriptor = FetchDescriptor<LocalUserShift>(
      predicate: #Predicate { shift in
        shift.userId == userId && shift.serverDeletedAt == nil
      }
    )

    let allShifts: [LocalUserShift]
    do {
      allShifts = try context.fetch(descriptor)
    } catch {
      logger.error("Failed to fetch shifts for deletion: \(error.localizedDescription)")
      throw error
    }

    // Filter to only active shifts (not pending delete) that are NOT in target month
    let shiftsToDelete = allShifts.filter { shift in
      guard shift.isActiveShift else { return false }

      let shiftComponents = calendar.dateComponents([.year, .month], from: shift.shiftDate)
      return shiftComponents.year != targetMonth.year || shiftComponents.month != targetMonth.month
    }

    guard !shiftsToDelete.isEmpty else {
      logger.info("No shifts to delete in other months")
      return 0
    }

    let deletedIds = shiftsToDelete.map(\.id)
    let affectedUserIds = try await localStore.storeActor.markShiftsPendingDelete(ids: deletedIds)
    let deletedCount = deletedIds.count

    logger.info(
      "Marked \(deletedCount) shifts for deletion in other months (target: \(targetMonth.year ?? 0)-\(targetMonth.month ?? 0))"
    )

    // Update widget storage
    for affectedUserId in affectedUserIds {
      NativeWidgetStorage.updateWidgetStorage(for: affectedUserId)
    }

    // Trigger sync to upload immediately (only if we actually deleted something)
    if deletedCount > 0 {
      for affectedUserId in affectedUserIds {
        triggerSync(userId: affectedUserId)
      }
    }

    return deletedCount
  }

  // MARK: - Month Limit Gating

  /// Get set of months that have at least one active (non-deleted) shift
  /// Uses isActiveShift computed property to avoid stringly-typed checks
  /// - Parameter userId: User ID
  /// - Returns: Set of DateComponents with year and month
  func getExistingShiftMonths(for userId: String) -> Set<DateComponents> {
    let context = localStore.mainContext
    let calendar = Calendar.current

    // Fetch all shifts for user where serverDeletedAt is nil
    // (SwiftData predicates can't use computed properties like isActiveShift)
    let descriptor = FetchDescriptor<LocalUserShift>(
      predicate: #Predicate { shift in
        shift.userId == userId && shift.serverDeletedAt == nil
      }
    )

    do {
      let shifts = try context.fetch(descriptor)
      // Filter out pending deletes using the computed property
      let activeShifts = shifts.filter { $0.isActiveShift }
      return Set(activeShifts.map { calendar.dateComponents([.year, .month], from: $0.shiftDate) })
    } catch {
      logger.error("Failed to fetch existing shift months: \(error.localizedDescription)")
      return []
    }
  }

  /// Check if a user can create a shift in the target month based on their tier
  /// - Free users can create shifts if:
  ///   1. No existing shifts (first month free), OR
  ///   2. Target month already has shifts (already "unlocked")
  /// - Pro and Max users can always create shifts
  /// - Parameters:
  ///   - userId: User ID
  ///   - targetDate: Date of the shift to create
  ///   - tier: User's current subscription tier
  /// - Returns: Whether the shift can be created
  func canCreateShift(userId: String, targetDate: Date, tier: SubscriptionTier) -> Bool {
    // Pro and Max can always create
    guard tier == .free else { return true }

    let calendar = Calendar.current
    let targetMonth = calendar.dateComponents([.year, .month], from: targetDate)
    let existingMonths = getExistingShiftMonths(for: userId)

    // Allow if no existing shifts OR target month already has shifts
    return existingMonths.isEmpty || existingMonths.contains(targetMonth)
  }

  /// Create shift with tier check (throws if free user blocked)
  /// - Parameters:
  ///   - userId: User ID
  ///   - shiftDate: Date of the shift
  ///   - startTime: Start time (HH:mm)
  ///   - endTime: End time (HH:mm)
  ///   - customSupplements: Optional custom supplements
  ///   - tier: User's current subscription tier
  /// - Returns: The created ShiftRow
  /// - Throws: ShiftCreationError.monthLimitReached if free user is blocked
  func createShiftWithTierCheck(
    userId: String,
    jobId: String? = nil,
    shiftDate: Date,
    startTime: String,
    endTime: String,
    customSupplements: CustomSupplementsData? = nil,
    tier: SubscriptionTier
  ) async throws -> ShiftRow {
    guard canCreateShift(userId: userId, targetDate: shiftDate, tier: tier) else {
      let existingMonths = getExistingShiftMonths(for: userId)
      throw ShiftCreationError.monthLimitReached(existingMonths: existingMonths)
    }

    return try await createShift(
      userId: userId,
      jobId: jobId,
      shiftDate: shiftDate,
      startTime: startTime,
      endTime: endTime,
      customSupplements: customSupplements
    )
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
