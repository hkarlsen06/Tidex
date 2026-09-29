// swiftlint:disable explicit_type_interface
// swiftlint:disable:previous blanket_disable_command
import Foundation
import SwiftData
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "ShiftsRepository")

// MARK: - Shifts Repository

/// Local-first repository for user shifts
/// All reads come from SwiftData; network calls are handled by SyncCoordinator
/// Automatically triggers sync after mutations for immediate upload
@MainActor
final class ShiftsRepository {
  static let shared = ShiftsRepository()

  private let localStore: LocalStore
  private let syncCoordinator: SyncCoordinator
  private let jobPaySetupStatusService: JobPaySetupStatusService

  private init(
    localStore: LocalStore? = nil,
    syncCoordinator: SyncCoordinator? = nil,
    jobPaySetupStatusService: JobPaySetupStatusService? = nil
  ) {
    self.localStore = localStore ?? LocalStore.shared
    self.syncCoordinator = syncCoordinator ?? SyncCoordinator.shared
    self.jobPaySetupStatusService = jobPaySetupStatusService ?? JobPaySetupStatusService.shared
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
    let includeLegacyNil =
      jobId.map {
        shouldIncludeLegacyNilJobRows(for: userId, selectedJobId: $0)
      } ?? false

    do {
      let visibleShifts = #Predicate<LocalUserShift> { shift in
        shift.userId == userId && shift.serverDeletedAt == nil
          && shift.syncStatusRaw != "pendingDelete"
      }
      let matchingJob = #Predicate<LocalUserShift> { shift in
        jobId == nil || shift.jobId == jobId || (includeLegacyNil && shift.jobId == nil)
      }
      let withinDates = #Predicate<LocalUserShift> { shift in
        shift.shiftDate >= startDate && shift.shiftDate <= endDate
      }
      let descriptor = FetchDescriptor<LocalUserShift>(
        predicate: #Predicate<LocalUserShift> { shift in
          visibleShifts.evaluate(shift) && matchingJob.evaluate(shift)
            && withinDates.evaluate(shift)
        },
        sortBy: [SortDescriptor(\LocalUserShift.shiftDate, order: .reverse)]
      )
      return try context.fetch(descriptor).map { $0.toShiftRow() }
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
    await localStore.storeActor.fetchShifts(
      userId: userId,
      startDate: startDate,
      endDate: endDate,
      jobId: jobId
    )
  }

  /// Get all non-deleted shifts for a user (no date filter)
  /// - Parameter userId: User ID
  /// - Returns: Array of ShiftRow objects
  func getAllShifts(for userId: String, jobId: String? = nil) -> [ShiftRow] {
    let context = localStore.mainContext
    let includeLegacyNil =
      jobId.map {
        shouldIncludeLegacyNilJobRows(for: userId, selectedJobId: $0)
      } ?? false

    do {
      let visibleShifts = #Predicate<LocalUserShift> { shift in
        shift.userId == userId && shift.serverDeletedAt == nil
          && shift.syncStatusRaw != "pendingDelete"
      }
      let matchingJob = #Predicate<LocalUserShift> { shift in
        jobId == nil || shift.jobId == jobId || (includeLegacyNil && shift.jobId == nil)
      }
      let descriptor = FetchDescriptor<LocalUserShift>(
        predicate: #Predicate<LocalUserShift> { shift in
          visibleShifts.evaluate(shift) && matchingJob.evaluate(shift)
        },
        sortBy: [SortDescriptor(\LocalUserShift.shiftDate, order: .reverse)]
      )
      return try context.fetch(descriptor).map { $0.toShiftRow() }
    } catch {
      logger.error("Failed to fetch all shifts: \(error.localizedDescription)")
      return []
    }
  }

  /// Whether the user has a shift or recurring shift in any job or month.
  /// Home, Shifts and Stats use this to show the first-shift prompt. It returns true until
  /// the first sync has finished, so a returning user on a new device doesn't see the prompt.
  func hasAnyShifts(for userId: String?, initialSyncComplete: Bool) -> Bool {
    guard initialSyncComplete, let userId else { return true }

    var shifts = FetchDescriptor<LocalUserShift>(
      predicate: #Predicate { shift in
        shift.userId == userId && shift.serverDeletedAt == nil
          && shift.syncStatusRaw != "pendingDelete"
      }
    )
    shifts.fetchLimit = 1
    var recurringShifts = FetchDescriptor<LocalRecurringShift>(
      predicate: #Predicate { shift in
        shift.userId == userId && shift.serverDeletedAt == nil
          && shift.syncStatusRaw != "pendingDelete"
      }
    )
    recurringShifts.fetchLimit = 1

    do {
      let context = localStore.mainContext
      return try context.fetchCount(shifts) > 0 || context.fetchCount(recurringShifts) > 0
    } catch {
      logger.error("Failed to check for any shifts: \(error.localizedDescription)")
      return true
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

}

extension ShiftsRepository {
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
  ///   - creationMethod: How the shift was entered, recorded if it is the user's first shift
  /// - Returns: The created ShiftRow
  func createShift(
    shiftId: String? = nil,
    userId: String,
    jobId: String? = nil,
    shiftDate: Date,
    startTime: String,
    endTime: String,
    note: String? = nil,
    customPauseWindows: CustomPauseWindows? = nil,
    customSupplements: CustomSupplementsData? = nil,
    creationMethod: String = "manual"
  ) async throws -> ShiftRow {
    let configuredJob = try jobPaySetupStatusService.requireConfiguredActiveJob(
      userId: userId,
      requestedJobId: jobId
    )

    let createdShift = try await localStore.storeActor.createUserShift(
      id: shiftId,
      userId: userId,
      jobId: configuredJob.id,
      shiftDate: shiftDate,
      startTime: startTime,
      endTime: endTime,
      note: note,
      customPauseWindows: customPauseWindows,
      customSupplements: customSupplements
    )

    logger.info("Created new local shift: \(createdShift.id)")
    OnboardingFunnelRecorder.shared.recordShiftCreated(method: creationMethod)

    // Update widget storage with the new shift
    NativeWidgetStorage.updateWidgetStorage(for: userId)

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
    note: String? = nil,
    noteWasEdited: Bool = false,
    customSupplements: CustomSupplementsData? = nil
  ) async throws -> ShiftRow? {
    do {
      let updatedShift = try await localStore.storeActor.updateUserShift(
        id: id,
        jobId: jobId,
        shiftDate: shiftDate,
        startTime: startTime,
        endTime: endTime,
        note: note,
        noteWasEdited: noteWasEdited,
        customSupplements: customSupplements
      )

      logger.info("Updated local shift: \(id)")

      if let userId = updatedShift.user_id {
        NativeWidgetStorage.updateWidgetStorage(for: userId)
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

  func updateCustomPauseWindows(
    id: String,
    customPauseWindows: CustomPauseWindows?
  ) async throws -> ShiftRow? {
    do {
      let updatedShift = try await localStore.storeActor.updateUserShiftCustomPauseWindows(
        id: id,
        customPauseWindows: customPauseWindows
      )

      logger.info("Updated local shift pause windows: \(id)")

      if let userId = updatedShift.user_id {
        NativeWidgetStorage.updateWidgetStorage(for: userId)
        triggerSync(userId: userId)
      }

      return updatedShift
    } catch LocalStoreWriteError.notFound {
      logger.warning("Shift not found for pause update: \(id)")
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

      // Trigger sync to upload immediately
      triggerSync(userId: userId)
    } catch LocalStoreWriteError.notFound {
      logger.warning("Shift not found for deletion: \(id)")
    } catch {
      throw error
    }
  }

  /// Mark multiple shifts for deletion in one write transaction.
  /// Widget updates and sync are dispatched once per affected user.
  func deleteShifts(ids: [String]) async throws {
    let uniqueIds = Array(Set(ids))
    guard !uniqueIds.isEmpty else {
      return
    }

    let userIds = try await localStore.storeActor.markShiftsPendingDelete(ids: uniqueIds)
    guard !userIds.isEmpty else {
      logger.warning("No shifts found for batch deletion (\(uniqueIds.count) IDs)")
      return
    }

    for userId in userIds {
      NativeWidgetStorage.updateWidgetStorage(for: userId)
      triggerSync(userId: userId)
    }

    logger.info("Marked \(uniqueIds.count) shifts for batch deletion")
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
