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
      guard let defaultJob = try context.fetch(descriptor).first else { return false }
      return defaultJob.id == selectedJobId
    } catch {
      logger.error(
        "Failed to determine default job for legacy fallback: \(error.localizedDescription)")
      return false
    }
  }

  // MARK: - Read Operations (Local Only)

  /// Get all non-deleted recurring shifts for a user
  /// - Parameter userId: User ID
  /// - Returns: Array of RecurringShiftRow objects
  func getRecurringShifts(for userId: String, jobId: String? = nil) -> [RecurringShiftRow] {
    let context = localStore.mainContext

    if let jobId {
      let selectedJobDescriptor = FetchDescriptor<LocalRecurringShift>(
        predicate: #Predicate { shift in
          shift.userId == userId && shift.serverDeletedAt == nil
            && shift.syncStatusRaw != "pendingDelete" && shift.jobId == jobId
        }
      )

      do {
        var localShifts = try context.fetch(selectedJobDescriptor)

        if shouldIncludeLegacyNilJobRows(for: userId, selectedJobId: jobId) {
          let legacyNilDescriptor = FetchDescriptor<LocalRecurringShift>(
            predicate: #Predicate { shift in
              shift.userId == userId && shift.serverDeletedAt == nil
                && shift.syncStatusRaw != "pendingDelete" && shift.jobId == nil
            }
          )
          let legacyNilShifts = try context.fetch(legacyNilDescriptor)
          localShifts.append(contentsOf: legacyNilShifts)
        }

        return localShifts.map { $0.toRecurringShiftRow() }
      } catch {
        logger.error("Failed to fetch recurring shifts: \(error.localizedDescription)")
        return []
      }
    }

    // Filter out both server-deleted and locally pending delete shifts
    let descriptor = FetchDescriptor<LocalRecurringShift>(
      predicate: #Predicate { shift in
        shift.userId == userId && shift.serverDeletedAt == nil
          && shift.syncStatusRaw != "pendingDelete"
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
        shift.userId == userId
          && (shift.syncStatusRaw == "dirty" || shift.syncStatusRaw == "pendingDelete")
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
    jobId: String? = nil,
    startTime: String,
    endTime: String,
    repeatIntervalWeeks: Int,
    selectedDays: SelectedDays,
    endCondition: EndCondition? = nil,
    exclusions: [String]? = nil,
    dateSpecificPauseWindows: DateSpecificPauseWindows? = nil,
    dateSpecificSupplements: [String: CustomSupplementsData]? = nil,
    dateSpecificNotes: [String: String]? = nil
  ) async throws -> RecurringShiftRow {
    let configuredJob = try jobPaySetupStatusService.requireConfiguredActiveJob(
      userId: userId,
      requestedJobId: jobId
    )

    let createdShift = try await localStore.storeActor.createRecurringShift(
      userId: userId,
      jobId: configuredJob.id,
      startTime: startTime,
      endTime: endTime,
      repeatIntervalWeeks: repeatIntervalWeeks,
      selectedDays: selectedDays,
      endCondition: endCondition,
      exclusions: exclusions,
      dateSpecificPauseWindows: dateSpecificPauseWindows,
      dateSpecificSupplements: dateSpecificSupplements,
      dateSpecificNotes: dateSpecificNotes
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
    jobId: String? = nil,
    startTime: String? = nil,
    endTime: String? = nil,
    repeatIntervalWeeks: Int? = nil,
    selectedDays: SelectedDays? = nil,
    endCondition: EndCondition? = nil,
    exclusions: [String]? = nil,
    dateSpecificSupplements: [String: CustomSupplementsData]? = nil,
    dateSpecificNotes: [String: String]? = nil
  ) async throws -> RecurringShiftRow? {
    do {
      let updatedShift = try await localStore.storeActor.updateRecurringShift(
        id: id,
        jobId: jobId,
        startTime: startTime,
        endTime: endTime,
        repeatIntervalWeeks: repeatIntervalWeeks,
        selectedDays: selectedDays,
        endCondition: endCondition,
        exclusions: exclusions,
        dateSpecificSupplements: dateSpecificSupplements,
        dateSpecificNotes: dateSpecificNotes
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

  func updateDateSpecificPauseWindows(
    id: String,
    dateSpecificPauseWindows: DateSpecificPauseWindows?
  ) async throws -> RecurringShiftRow? {
    do {
      let updatedShift = try await localStore.storeActor
        .updateRecurringShiftDateSpecificPauseWindows(
          id: id,
          dateSpecificPauseWindows: dateSpecificPauseWindows
        )

      logger.info("Updated local recurring shift pause windows: \(id)")
      triggerSync(userId: updatedShift.user_id)
      return updatedShift
    } catch LocalStoreWriteError.notFound {
      logger.warning("Recurring shift not found for pause update: \(id)")
      return nil
    } catch {
      throw error
    }
  }

  func updateDateSpecificNotes(
    id: String,
    dateSpecificNotes: [String: String]?
  ) async throws -> RecurringShiftRow? {
    do {
      let updatedShift = try await localStore.storeActor
        .updateRecurringShiftDateSpecificNotes(
          id: id,
          dateSpecificNotes: dateSpecificNotes
        )

      logger.info("Updated local recurring shift notes: \(id)")
      triggerSync(userId: updatedShift.user_id)
      return updatedShift
    } catch LocalStoreWriteError.notFound {
      logger.warning("Recurring shift not found for note update: \(id)")
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
    try await addExclusions(id: id, dates: [date])
  }

  /// Add multiple exclusion dates to a recurring shift in a single local mutation.
  /// - Parameters:
  ///   - id: Recurring shift ID
  ///   - dates: Dates to exclude (ISO strings YYYY-MM-DD)
  func addExclusions(id: String, dates: [String]) async throws {
    // Get userId before mutation for sync
    let userId = getLocalRecurringShift(id: id)?.userId

    do {
      let addedCount = try await localStore.storeActor.addRecurringShiftExclusions(
        id: id,
        dates: dates
      )
      if addedCount > 0 {
        logger.info("Added \(addedCount) exclusion(s) to recurring shift: \(id)")

        // Trigger sync to upload immediately
        if let userId {
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
      if let userId {
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
