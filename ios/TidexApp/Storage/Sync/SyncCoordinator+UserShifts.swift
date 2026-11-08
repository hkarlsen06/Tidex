import Foundation
import Observation
import Synchronization
import os.log

extension SyncCoordinator {

  // MARK: - User Shifts Push

  func pushUserShifts(userId: String) async throws -> TablePushResult {
    let storeActor = await MainActor.run { LocalStore.shared.storeActor }
    let dirtyShifts = try await storeActor.dirtyUserShiftCopies(userId: userId)

    if dirtyShifts.isEmpty {
      return TablePushResult(table: .userShifts, rowsPushed: 0, newConflicts: 0, rebased: 0)
    }

    var rowsPushed = 0
    var failedRows = 0
    var newConflicts = 0
    var rebased = 0

    for shift in dirtyShifts {
      let shiftId = shift.id
      let result: PushResult
      do {
        result = try await pushUserShift(
          shift, userId: userId, storeActor: storeActor, isRetry: false)
      } catch let error where Self.isRowRejection(error) {
        syncCoordinatorLogger.error("Server rejected shift \(shiftId.prefix(8)): \(error.localizedDescription)")
        await storeActor.markShiftConflict(id: shiftId, serverSnapshot: nil)
        result = .conflict
      } catch {
        try await skipRowUnlessFatal(error, table: .userShifts, id: shiftId)
        failedRows += 1
        result = .noChange
      }
      switch result {
      case .success, .deleted:
        rowsPushed += 1

      case .conflict:
        newConflicts += 1

      case .rebased:
        rebased += 1
        rowsPushed += 1

      case .noChange:
        break
      }
    }

    try await storeActor.save()
    return TablePushResult(
      table: .userShifts,
      rowsPushed: rowsPushed,
      newConflicts: newConflicts,
      rebased: rebased,
      failedRows: failedRows
    )
  }

  func pushUserShift(
    _ shift: LocalUserShift,
    userId: String,
    storeActor: LocalStoreActor,
    isRetry: Bool
  ) async throws -> PushResult {
    let shiftId = shift.id

    if shift.syncStatus == .pendingDelete {
      // Soft delete: UPDATE deleted_at = now()
      return try await pushUserShiftDelete(shift, userId: userId, storeActor: storeActor)
    }

    // Build update patch using only dirty fields
    let dirtyFields = shift.dirtyFieldKeys
    if dirtyFields.isEmpty {
      // No fields dirty, mark as clean
      await storeActor.markShiftClean(id: shiftId)
      return .noChange
    }

    // Check if this is a new record that needs INSERT (serverRevision == 0 means never synced)
    if shift.serverRevision == 0 {
      return try await insertUserShift(shift, userId: userId, storeActor: storeActor)
    }

    let baseline = SyncPushBaseline(shift)
    // Build partial update
    var updateData: [String: AnyJSON] = [:]
    if dirtyFields.contains(.jobId) {
      if let jobId = shift.jobId {
        updateData["job_id"] = .string(jobId)
      } else {
        updateData["job_id"] = .null
      }
    }
    if dirtyFields.contains(.shiftDate) {
      updateData["shift_date"] = .string(shift.shiftDateString)
    }
    if dirtyFields.contains(.startTime) {
      updateData["start_time"] = .string(shift.startTime)
    }
    if dirtyFields.contains(.endTime) {
      updateData["end_time"] = .string(shift.endTime)
    }
    if dirtyFields.contains(.customPauseWindows) {
      if let data = shift.customPauseWindows {
        let decoded = try requireAnyJSON(
          data,
          table: .userShifts,
          id: shiftId,
          field: "custom_pause_windows"
        )
        updateData["custom_pause_windows"] = decoded
      } else {
        updateData["custom_pause_windows"] = .null
      }
    }
    if dirtyFields.contains(.customSupplements) {
      if let data = shift.customSupplements {
        let decoded = try requireAnyJSON(
          data,
          table: .userShifts,
          id: shiftId,
          field: "custom_supplements"
        )
        updateData["custom_supplements"] = decoded
      } else {
        updateData["custom_supplements"] = .null
      }
    }
    if dirtyFields.contains(.note) {
      if let note = shift.note {
        updateData["note"] = .string(note)
      } else {
        updateData["note"] = .null
      }
    }

    try requireNonEmptyUpdate(updateData, table: .userShifts, id: shiftId)

    let outcome: SyncWriteOutcome<SyncShiftRow> = try await SyncConvex.update(
      .userShifts, owner: shift.userId, id: shiftId,
      expectedRevision: shift.serverRevision, data: updateData)

    switch outcome {
    case .ok(let returnedRow):
      // Success - update local with canonical server values
      let serverUpdatedAt = parseUpdatedAt(
        returnedRow.updated_at, table: .userShifts, id: shiftId)
      let serverSnapshot = UserShiftServerSnapshot.from(
        jobId: returnedRow.job_id,
        shiftDate: returnedRow.shift_date,
        startTime: returnedRow.start_time,
        endTime: returnedRow.end_time,
        note: returnedRow.note,
        customPauseWindows: returnedRow.custom_pause_windows,
        customSupplements: returnedRow.custom_supplements,
        updatedAt: serverUpdatedAt,
        revision: returnedRow.revision,
        deletedAt: nil
      )

      await storeActor.markShiftPushed(
        id: shiftId,
        serverRow: returnedRow,
        serverUpdatedAt: serverUpdatedAt,
        serverRevision: returnedRow.revision,
        snapshot: serverSnapshot,
        baseline: baseline
      )

      syncCoordinatorLogger.debug("Pushed shift \(shiftId.prefix(8))")

      return .success
    case .conflict(let serverRow):
      return try await handleShiftPushConflict(
        shift: shift,
        serverRow: serverRow,
        userId: userId,
        storeActor: storeActor,
        isRetry: isRetry
      )
    }
  }

  private func pushUserShiftDelete(
    _ shift: LocalUserShift,
    userId: String,
    storeActor: LocalStoreActor,
    retryRevision: Int64? = nil
  ) async throws -> PushResult {
    let shiftId = shift.id

    let outcome: SyncWriteOutcome<SyncShiftRow> = try await SyncConvex.remove(
      .userShifts, owner: shift.userId, id: shiftId,
      expectedRevision: retryRevision ?? shift.serverRevision)

    let serverRow: SyncShiftRow?
    switch outcome {
    case .ok(let returnedRow):
      // Success - mark as deleted locally
      let serverUpdatedAt = parseUpdatedAt(returnedRow.updated_at, table: .userShifts, id: shiftId)
      let serverDeletedAt = returnedRow.deleted_at.flatMap { parseISO8601($0) }

      await storeActor.markShiftDeleted(
        id: shiftId,
        serverUpdatedAt: serverUpdatedAt,
        serverRevision: returnedRow.revision,
        serverDeletedAt: serverDeletedAt
      )

      syncCoordinatorLogger.debug("Deleted shift \(shiftId.prefix(8))")

      return .deleted
    case .conflict(let current):
      serverRow = current
    }

    if let serverRow {
      let serverUpdatedAt = parseUpdatedAt(serverRow.updated_at, table: .userShifts, id: shiftId)
      let serverDeletedAt = serverRow.deleted_at.flatMap { parseISO8601($0) }

      if serverDeletedAt != nil {
        // Already deleted on server, just clean up local
        await storeActor.markShiftDeleted(
          id: shiftId,
          serverUpdatedAt: serverUpdatedAt,
          serverRevision: serverRow.revision,
          serverDeletedAt: serverDeletedAt
        )
        return .deleted
      }

      // Another write moved the revision after this device last saw the row. The user deleted
      // the row, so the delete wins, as the local fields do when an update is rebased. Retry
      // once against the current revision.
      if retryRevision == nil {
        return try await pushUserShiftDelete(
          shift, userId: userId, storeActor: storeActor, retryRevision: serverRow.revision)
      }

      // Mark conflict
      let serverSnapshot = UserShiftServerSnapshot.from(
        jobId: serverRow.job_id,
        shiftDate: serverRow.shift_date,
        startTime: serverRow.start_time,
        endTime: serverRow.end_time,
        note: serverRow.note,
        customPauseWindows: serverRow.custom_pause_windows,
        customSupplements: serverRow.custom_supplements,
        updatedAt: serverUpdatedAt,
        revision: serverRow.revision,
        deletedAt: serverDeletedAt
      )
      await storeActor.markShiftConflict(id: shiftId, serverSnapshot: serverSnapshot)
    }
    // The server has no row at all, for example after it purged old soft deleted rows. The row
    // is gone there, which is what the delete wanted. Retire the local row instead of retrying
    // on every sync.
    if serverRow == nil {
      let deletedAt = Date()
      await storeActor.markShiftDeleted(
        id: shiftId,
        serverUpdatedAt: deletedAt,
        serverRevision: shift.serverRevision,
        serverDeletedAt: deletedAt
      )
      return .deleted
    }
    return .conflict
  }

  /// Insert a new user shift that was created locally (serverRevision == 0)
  private func insertUserShift(
    _ shift: LocalUserShift,
    userId: String,
    storeActor: LocalStoreActor
  ) async throws -> PushResult {
    let shiftId = shift.id
    let baseline = SyncPushBaseline(shift)

    // Build full insert data
    var insertData: [String: AnyJSON] = [
      "id": .string(shiftId),
      "user_id": .string(userId),
      "shift_date": .string(shift.shiftDateString),
      "start_time": .string(shift.startTime),
      "end_time": .string(shift.endTime),
    ]
    if let jobId = shift.jobId {
      insertData["job_id"] = .string(jobId)
    }

    if let data = shift.customPauseWindows {
      let decoded = try requireAnyJSON(
        data,
        table: .userShifts,
        id: shiftId,
        field: "custom_pause_windows"
      )
      insertData["custom_pause_windows"] = decoded
    }

    if let data = shift.customSupplements {
      let decoded = try requireAnyJSON(
        data,
        table: .userShifts,
        id: shiftId,
        field: "custom_supplements"
      )
      insertData["custom_supplements"] = decoded
    }
    if let note = shift.note {
      insertData["note"] = .string(note)
    }

    let outcome: SyncInsertOutcome<SyncShiftRow> = try await SyncConvex.insert(
      .userShifts, owner: shift.userId, row: insertData)

    switch outcome {
    case .ok(let returnedRow):
      let serverUpdatedAt = parseUpdatedAt(
        returnedRow.updated_at, table: .userShifts, id: shiftId)
      let serverSnapshot = UserShiftServerSnapshot.from(
        jobId: returnedRow.job_id,
        shiftDate: returnedRow.shift_date,
        startTime: returnedRow.start_time,
        endTime: returnedRow.end_time,
        note: returnedRow.note,
        customPauseWindows: returnedRow.custom_pause_windows,
        customSupplements: returnedRow.custom_supplements,
        updatedAt: serverUpdatedAt,
        revision: returnedRow.revision,
        deletedAt: nil
      )

      await storeActor.markShiftPushed(
        id: shiftId,
        serverRow: returnedRow,
        serverUpdatedAt: serverUpdatedAt,
        serverRevision: returnedRow.revision,
        snapshot: serverSnapshot,
        baseline: baseline
      )

      syncCoordinatorLogger.debug("Inserted new shift \(shiftId.prefix(8))")

      return .success
    case .exists(let serverRow):
      // The row exists, usually because an earlier insert committed after the request timed
      // out locally. Merge onto it.
      syncCoordinatorLogger.warning("Shift \(shift.id.prefix(8)) already exists on server, merging")
      return try await handleShiftPushConflict(
        shift: shift, serverRow: serverRow, userId: userId, storeActor: storeActor,
        isRetry: false)
    }
  }

  private func handleShiftPushConflict(
    shift: LocalUserShift,
    serverRow: SyncShiftRow?,
    userId: String,
    storeActor: LocalStoreActor,
    isRetry: Bool
  ) async throws -> PushResult {
    let shiftId = shift.id

    guard let serverRow else {
      // Server row doesn't exist - check if this is a new local record that needs INSERT
      if shift.serverRevision == 0 {
        syncCoordinatorLogger.debug("Shift \(shiftId.prefix(8)) is new (serverRevision=0), attempting INSERT")
        return try await insertUserShift(shift, userId: userId, storeActor: storeActor)
      }
      // Row was deleted on server
      syncCoordinatorLogger.debug("Shift \(shiftId.prefix(8)) was deleted on server")
      await storeActor.markShiftConflict(id: shiftId, serverSnapshot: nil)
      return .conflict
    }

    let serverUpdatedAt = parseUpdatedAt(serverRow.updated_at, table: .userShifts, id: shiftId)
    let serverDeletedAt = serverRow.deleted_at.flatMap { parseISO8601($0) }

    if serverDeletedAt != nil {
      // Server soft-deleted this row
      let serverSnapshot = UserShiftServerSnapshot.from(
        jobId: serverRow.job_id,
        shiftDate: serverRow.shift_date,
        startTime: serverRow.start_time,
        endTime: serverRow.end_time,
        note: serverRow.note,
        customPauseWindows: serverRow.custom_pause_windows,
        customSupplements: serverRow.custom_supplements,
        updatedAt: serverUpdatedAt,
        revision: serverRow.revision,
        deletedAt: serverDeletedAt
      )
      await storeActor.markShiftConflict(id: shiftId, serverSnapshot: serverSnapshot)
      return .conflict
    }

    let newServerSnapshot = UserShiftServerSnapshot.from(
      jobId: serverRow.job_id,
      shiftDate: serverRow.shift_date,
      startTime: serverRow.start_time,
      endTime: serverRow.end_time,
      note: serverRow.note,
      customPauseWindows: serverRow.custom_pause_windows,
      customSupplements: serverRow.custom_supplements,
      updatedAt: serverUpdatedAt,
      revision: serverRow.revision,
      deletedAt: serverDeletedAt
    )

    guard !isRetry else {
      // The server moved again during the retry
      await storeActor.markShiftConflict(id: shiftId, serverSnapshot: newServerSnapshot)
      return .conflict
    }

    // Rebase onto the server row and retry once. Local values that still differ stay, and the
    // unacknowledged local values remain pending.
    await storeActor.rebaseShift(
      id: shiftId,
      serverRow: serverRow,
      serverUpdatedAt: serverUpdatedAt,
      serverRevision: serverRow.revision,
      serverDeletedAt: serverDeletedAt,
      newSnapshot: newServerSnapshot
    )

    // Reload and retry
    if let rebasedShift = try await storeActor.userShiftCopy(id: shiftId) {
      let retryResult = try await pushUserShift(
        rebasedShift, userId: userId, storeActor: storeActor, isRetry: true)
      if retryResult == .success {
        return .rebased
      }
      return retryResult
    }
    return .conflict
  }
}
