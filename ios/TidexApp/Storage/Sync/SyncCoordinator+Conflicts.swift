import Foundation
import Observation
import Synchronization
import os.log

extension SyncCoordinator {

  // MARK: - Conflict Resolution API

  /// Whether the server has a row with this key, deleted or not. `key` is the user id for
  /// `user_settings`, and the row id for the other tables. `owner` is the user id of the local
  /// row.
  private func serverRowExists(table: SyncTable, owner: String, key: String) async throws -> Bool {
    let row: AnyJSON? = try await SyncConvex.currentRow(
      table, owner: owner, id: table == .userSettings ? nil : key)
    return row != nil
  }

  // Applies a conflict resolution to one row. The typed wrappers below supply the row type
  // specific store calls.
  //
  // A conflict has a server snapshot when the server row changed. It has none when the server
  // rejected the write (a `ConvexError` with a code), or when the row is gone from the server.
  // - keepServer without a snapshot drops the local row when the server has no row to keep. If
  //   the server has the row, the local row returns to its last synced state.
  // - keepLocal without a snapshot inserts the row again when the server has no row, and
  //   otherwise pushes against the current revision.
  // - `discard` is nil when a row cannot be dropped, as with user settings.
  // swiftlint:disable:next cyclomatic_complexity function_parameter_count
  private func resolveConflict<Row: SyncPushTrackedModel, Snapshot>(
    _ row: Row,
    table: SyncTable,
    id: String,
    userId: String,
    resolution: ConflictResolution,
    storeActor: LocalStoreActor,
    decode: (Data) -> Snapshot?,
    revision: (Snapshot) -> Int64,
    serverRowExists: () async throws -> Bool,
    applyServer: (Snapshot) async -> Void,
    discard: (() async -> Void)?,
    requeue: (Int64) async -> Void,
    markConflict: () async -> Void,
    push: () async throws -> Void
  ) async throws {
    let snapshot = row.conflictServerSnapshot.flatMap(decode)
    var hasServerRow = false
    if row.serverRevision > 0 {
      hasServerRow = try await serverRowExists()
    }

    switch resolution {
    case .keepServer:
      if let snapshot {
        await applyServer(snapshot)
      } else if !hasServerRow {
        guard let discard else {
          throw SyncError.missingConflictSnapshot(table: table, id: id)
        }
        await discard()
      } else if let lastSynced = decode(row.lastSyncedSnapshot) {
        await applyServer(lastSynced)
      } else {
        throw SyncError.missingConflictSnapshot(table: table, id: id)
      }

    case .keepLocal:
      if let snapshot {
        await requeue(revision(snapshot))
      } else {
        await requeue(hasServerRow ? row.serverRevision : 0)
      }

      do {
        try await push()
      } catch where Self.isRowRejection(error) {
        syncCoordinatorLogger.error(
          "Server rejected \(table.displayName) \(id.prefix(8)) again: \(error.localizedDescription)"
        )
        await markConflict()
      } catch where Self.isCancellation(error) {
        throw error
      } catch {
        // The row stays queued and the next sync retries it.
        syncCoordinatorLogger.warning(
          "Push after resolving \(table.displayName) \(id.prefix(8)) failed: \(error.localizedDescription)"
        )
      }
    }

    try await storeActor.save()
    let conflicts = try await storeActor.countConflicts(userId: userId)
    await MainActor.run {
      conflictCount = conflicts
    }
    NativeWidgetStorage.updateWidgetStorage(for: userId)
  }

  /// Resolve a conflict for a job
  func resolveJobConflict(jobId: String, resolution: ConflictResolution, userId: String)
    async throws
  {
    let storeActor = await MainActor.run { LocalStore.shared.storeActor }
    guard let job = try await storeActor.jobCopy(id: jobId) else {
      throw SyncError.notFound(table: .jobs, id: jobId)
    }
    guard job.syncStatus == .conflict else {
      throw SyncError.notInConflict(table: .jobs, id: jobId)
    }

    try await resolveConflict(
      job,
      table: .jobs,
      id: jobId,
      userId: userId,
      resolution: resolution,
      storeActor: storeActor,
      decode: { JobServerSnapshot.decode(from: $0) },
      revision: { $0.revision },
      serverRowExists: {
        try await self.serverRowExists(table: .jobs, owner: job.userId, key: jobId)
      },
      applyServer: { await storeActor.resolveJobConflictKeepServer(id: jobId, serverSnapshot: $0) },
      discard: {
        let now = Date()
        await storeActor.markJobDeleted(
          id: jobId, serverUpdatedAt: now, serverRevision: 0, deletedAt: now)
      },
      requeue: { await storeActor.resolveJobConflictKeepLocal(id: jobId, serverRevision: $0) },
      markConflict: { await storeActor.markJobConflict(id: jobId, serverSnapshot: nil) },
      push: {
        if let updated = try await storeActor.jobCopy(id: jobId) {
          _ = try await self.pushJob(
            updated, userId: userId, storeActor: storeActor, isRetry: false)
        }
      }
    )
  }

  /// Resolve a conflict for a user shift
  func resolveShiftConflict(shiftId: String, resolution: ConflictResolution, userId: String)
    async throws
  {
    let storeActor = await MainActor.run { LocalStore.shared.storeActor }
    guard let shift = try await storeActor.userShiftCopy(id: shiftId) else {
      throw SyncError.notFound(table: .userShifts, id: shiftId)
    }
    guard shift.syncStatus == .conflict else {
      throw SyncError.notInConflict(table: .userShifts, id: shiftId)
    }

    try await resolveConflict(
      shift,
      table: .userShifts,
      id: shiftId,
      userId: userId,
      resolution: resolution,
      storeActor: storeActor,
      decode: { UserShiftServerSnapshot.decode(from: $0) },
      revision: { $0.revision },
      serverRowExists: {
        try await self.serverRowExists(table: .userShifts, owner: shift.userId, key: shiftId)
      },
      applyServer: {
        await storeActor.resolveShiftConflictKeepServer(id: shiftId, serverSnapshot: $0)
      },
      discard: {
        let now = Date()
        await storeActor.markShiftDeleted(
          id: shiftId, serverUpdatedAt: now, serverRevision: 0, serverDeletedAt: now)
      },
      requeue: { await storeActor.resolveShiftConflictKeepLocal(id: shiftId, serverRevision: $0) },
      markConflict: { await storeActor.markShiftConflict(id: shiftId, serverSnapshot: nil) },
      push: {
        if let updated = try await storeActor.userShiftCopy(id: shiftId) {
          _ = try await self.pushUserShift(
            updated, userId: userId, storeActor: storeActor, isRetry: false)
        }
      }
    )
  }

  /// Resolve a conflict for an event
  func resolveEventConflict(eventId: String, resolution: ConflictResolution, userId: String)
    async throws
  {
    let storeActor = await MainActor.run { LocalStore.shared.storeActor }
    guard let event = try await storeActor.eventCopy(id: eventId) else {
      throw SyncError.notFound(table: .events, id: eventId)
    }
    guard event.syncStatus == .conflict else {
      throw SyncError.notInConflict(table: .events, id: eventId)
    }

    try await resolveConflict(
      event,
      table: .events,
      id: eventId,
      userId: userId,
      resolution: resolution,
      storeActor: storeActor,
      decode: { EventServerSnapshot.decode(from: $0) },
      revision: { $0.revision },
      serverRowExists: {
        try await self.serverRowExists(table: .events, owner: event.userId, key: eventId)
      },
      applyServer: {
        await storeActor.resolveEventConflictKeepServer(id: eventId, serverSnapshot: $0)
      },
      discard: {
        let now = Date()
        await storeActor.markEventDeleted(
          id: eventId, serverUpdatedAt: now, serverRevision: 0, serverDeletedAt: now)
      },
      requeue: { await storeActor.resolveEventConflictKeepLocal(id: eventId, serverRevision: $0) },
      markConflict: { await storeActor.markEventConflict(id: eventId, serverSnapshot: nil) },
      push: {
        if let updated = try await storeActor.eventCopy(id: eventId) {
          _ = try await self.pushEvent(
            updated, userId: userId, storeActor: storeActor, isRetry: false)
        }
      }
    )
  }

  /// Resolve a conflict for a recurring shift
  func resolveRecurringShiftConflict(
    shiftId: String, resolution: ConflictResolution, userId: String
  ) async throws {
    let storeActor = await MainActor.run { LocalStore.shared.storeActor }
    guard let shift = try await storeActor.recurringShiftCopy(id: shiftId) else {
      throw SyncError.notFound(table: .recurringShifts, id: shiftId)
    }
    guard shift.syncStatus == .conflict else {
      throw SyncError.notInConflict(table: .recurringShifts, id: shiftId)
    }

    try await resolveConflict(
      shift,
      table: .recurringShifts,
      id: shiftId,
      userId: userId,
      resolution: resolution,
      storeActor: storeActor,
      decode: { RecurringShiftServerSnapshot.decode(from: $0) },
      revision: { $0.revision },
      serverRowExists: {
        try await self.serverRowExists(table: .recurringShifts, owner: shift.userId, key: shiftId)
      },
      applyServer: {
        await storeActor.resolveRecurringShiftConflictKeepServer(id: shiftId, serverSnapshot: $0)
      },
      discard: {
        let now = Date()
        await storeActor.markRecurringShiftDeleted(
          id: shiftId, serverUpdatedAt: now, serverRevision: 0, serverDeletedAt: now)
      },
      requeue: {
        await storeActor.resolveRecurringShiftConflictKeepLocal(id: shiftId, serverRevision: $0)
      },
      markConflict: { await storeActor.markRecurringShiftConflict(id: shiftId, serverSnapshot: nil) },
      push: {
        if let updated = try await storeActor.recurringShiftCopy(id: shiftId) {
          _ = try await self.pushRecurringShift(
            updated, userId: userId, storeActor: storeActor, isRetry: false)
        }
      }
    )
  }

  /// Resolve a conflict for a wage snapshot
  func resolveWageSnapshotConflict(
    snapshotId: String, resolution: ConflictResolution, userId: String
  ) async throws {
    let storeActor = await MainActor.run { LocalStore.shared.storeActor }
    guard let snapshot = try await storeActor.wageSnapshotCopy(id: snapshotId) else {
      throw SyncError.notFound(table: .wageSnapshots, id: snapshotId)
    }
    guard snapshot.syncStatus == .conflict else {
      throw SyncError.notInConflict(table: .wageSnapshots, id: snapshotId)
    }

    try await resolveConflict(
      snapshot,
      table: .wageSnapshots,
      id: snapshotId,
      userId: userId,
      resolution: resolution,
      storeActor: storeActor,
      decode: { WageSnapshotServerSnapshot.decode(from: $0) },
      revision: { $0.revision },
      serverRowExists: {
        try await self.serverRowExists(
          table: .wageSnapshots, owner: snapshot.userId, key: snapshotId)
      },
      applyServer: {
        await storeActor.resolveWageSnapshotConflictKeepServer(id: snapshotId, serverSnapshot: $0)
      },
      discard: {
        let now = Date()
        await storeActor.markWageSnapshotDeleted(
          id: snapshotId, serverUpdatedAt: now, serverRevision: 0, serverDeletedAt: now)
      },
      requeue: {
        await storeActor.resolveWageSnapshotConflictKeepLocal(id: snapshotId, serverRevision: $0)
      },
      markConflict: {
        await storeActor.markWageSnapshotConflict(id: snapshotId, serverSnapshot: nil)
      },
      push: {
        if let updated = try await storeActor.wageSnapshotCopy(id: snapshotId) {
          _ = try await self.pushWageSnapshot(
            updated, userId: userId, storeActor: storeActor, isRetry: false)
        }
      }
    )
  }

  /// Resolve a conflict for a payroll adjustment
  func resolvePayrollAdjustmentConflict(
    adjustmentId: String, resolution: ConflictResolution, userId: String
  ) async throws {
    let storeActor = await MainActor.run { LocalStore.shared.storeActor }
    guard let adjustment = try await storeActor.payrollAdjustmentCopy(id: adjustmentId) else {
      throw SyncError.notFound(table: .payrollAdjustments, id: adjustmentId)
    }
    guard adjustment.syncStatus == .conflict else {
      throw SyncError.notInConflict(table: .payrollAdjustments, id: adjustmentId)
    }

    try await resolveConflict(
      adjustment,
      table: .payrollAdjustments,
      id: adjustmentId,
      userId: userId,
      resolution: resolution,
      storeActor: storeActor,
      decode: { PayrollAdjustmentServerSnapshot.decode(from: $0) },
      revision: { $0.revision },
      serverRowExists: {
        try await self.serverRowExists(
          table: .payrollAdjustments, owner: adjustment.userId, key: adjustmentId)
      },
      applyServer: {
        await storeActor.resolvePayrollAdjustmentConflictKeepServer(
          id: adjustmentId, serverSnapshot: $0)
      },
      discard: {
        let now = Date()
        await storeActor.markPayrollAdjustmentDeleted(
          id: adjustmentId, serverUpdatedAt: now, serverRevision: 0, serverDeletedAt: now)
      },
      requeue: {
        await storeActor.resolvePayrollAdjustmentConflictKeepLocal(
          id: adjustmentId, serverRevision: $0)
      },
      markConflict: {
        await storeActor.markPayrollAdjustmentConflict(id: adjustmentId, serverSnapshot: nil)
      },
      push: {
        if let updated = try await storeActor.payrollAdjustmentCopy(id: adjustmentId) {
          _ = try await self.pushPayrollAdjustment(
            updated, userId: userId, storeActor: storeActor)
        }
      }
    )
  }

  /// Resolve a conflict for user settings
  func resolveUserSettingsConflict(resolution: ConflictResolution, userId: String) async throws {
    let storeActor = await MainActor.run { LocalStore.shared.storeActor }
    guard let settings = try await storeActor.userSettingsCopy(userId: userId) else {
      throw SyncError.notFound(table: .userSettings, id: userId)
    }
    guard settings.syncStatus == .conflict else {
      throw SyncError.notInConflict(table: .userSettings, id: userId)
    }

    try await resolveConflict(
      settings,
      table: .userSettings,
      id: userId,
      userId: userId,
      resolution: resolution,
      storeActor: storeActor,
      decode: { UserSettingsServerSnapshot.decode(from: $0) },
      revision: { $0.revision },
      serverRowExists: {
        try await self.serverRowExists(table: .userSettings, owner: settings.userId, key: userId)
      },
      applyServer: {
        await storeActor.resolveUserSettingsConflictKeepServer(userId: userId, serverSnapshot: $0)
      },
      discard: nil,
      requeue: {
        await storeActor.resolveUserSettingsConflictKeepLocal(userId: userId, serverRevision: $0)
      },
      markConflict: { await storeActor.markUserSettingsConflict(userId: userId, serverSnapshot: nil) },
      push: {
        if let updated = try await storeActor.userSettingsCopy(userId: userId) {
          _ = try await self.pushUserSettingsRow(
            updated, userId: userId, storeActor: storeActor, isRetry: false)
        }
      }
    )
  }
}
