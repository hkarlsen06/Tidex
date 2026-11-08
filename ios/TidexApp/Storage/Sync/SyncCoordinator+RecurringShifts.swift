import Foundation
import Observation
import Synchronization
import os.log

extension SyncCoordinator {

  // MARK: - Recurring Shifts Push

  func pushRecurringShifts(userId: String) async throws -> TablePushResult {
    let storeActor = await MainActor.run { LocalStore.shared.storeActor }
    let dirtyShifts = try await storeActor.dirtyRecurringShiftCopies(userId: userId)

    if dirtyShifts.isEmpty {
      return TablePushResult(table: .recurringShifts, rowsPushed: 0, newConflicts: 0, rebased: 0)
    }

    var rowsPushed = 0
    var failedRows = 0
    var newConflicts = 0
    var rebased = 0

    for shift in dirtyShifts {
      let shiftId = shift.id
      let result: PushResult
      do {
        result = try await pushRecurringShift(
          shift, userId: userId, storeActor: storeActor, isRetry: false)
      } catch let error where Self.isRowRejection(error) {
        syncCoordinatorLogger.error(
          "Server rejected recurring shift \(shiftId.prefix(8)): \(error.localizedDescription)")
        await storeActor.markRecurringShiftConflict(id: shiftId, serverSnapshot: nil)
        result = .conflict
      } catch {
        try await skipRowUnlessFatal(error, table: .recurringShifts, id: shiftId)
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
      table: .recurringShifts,
      rowsPushed: rowsPushed,
      newConflicts: newConflicts,
      rebased: rebased,
      failedRows: failedRows
    )
  }

  func pushRecurringShift(
    _ shift: LocalRecurringShift,
    userId: String,
    storeActor: LocalStoreActor,
    isRetry: Bool
  ) async throws -> PushResult {
    let shiftId = shift.id

    if shift.syncStatus == .pendingDelete {
      return try await pushRecurringShiftDelete(shift, userId: userId, storeActor: storeActor)
    }

    let dirtyFields = shift.dirtyFieldKeys
    if dirtyFields.isEmpty {
      await storeActor.markRecurringShiftClean(id: shiftId)
      return .noChange
    }

    // Check if this is a new record that needs INSERT (serverRevision == 0 means never synced)
    if shift.serverRevision == 0 {
      return try await insertRecurringShift(shift, userId: userId, storeActor: storeActor)
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
    if dirtyFields.contains(.startTime) {
      updateData["start_time"] = .string(shift.startTime)
    }
    if dirtyFields.contains(.endTime) {
      updateData["end_time"] = .string(shift.endTime)
    }
    if dirtyFields.contains(.repeatIntervalWeeks) {
      updateData["repeat_interval_weeks"] = .integer(shift.repeatIntervalWeeks)
    }
    if dirtyFields.contains(.selectedDays) {
      let decoded = try requireAnyJSON(
        shift.selectedDays,
        table: .recurringShifts,
        id: shiftId,
        field: "selected_days"
      )
      updateData["selected_days"] = decoded
    }
    if dirtyFields.contains(.endCondition) {
      if let data = shift.endCondition {
        let decoded = try requireAnyJSON(
          data,
          table: .recurringShifts,
          id: shiftId,
          field: "end_condition"
        )
        updateData["end_condition"] = decoded
      } else {
        updateData["end_condition"] = .null
      }
    }
    if dirtyFields.contains(.exclusions) {
      if let data = shift.exclusions {
        let decoded = try requireAnyJSON(
          data,
          table: .recurringShifts,
          id: shiftId,
          field: "exclusions"
        )
        updateData["exclusions"] = decoded
      } else {
        updateData["exclusions"] = .null
      }
    }
    if dirtyFields.contains(.dateSpecificPauseWindows) {
      if let data = shift.dateSpecificPauseWindows {
        let decoded = try requireAnyJSON(
          data,
          table: .recurringShifts,
          id: shiftId,
          field: "date_specific_pause_windows"
        )
        updateData["date_specific_pause_windows"] = decoded
      } else {
        updateData["date_specific_pause_windows"] = .null
      }
    }
    if dirtyFields.contains(.dateSpecificSupplements) {
      if let data = shift.dateSpecificSupplements {
        let decoded = try requireAnyJSON(
          data,
          table: .recurringShifts,
          id: shiftId,
          field: "date_specific_supplements"
        )
        updateData["date_specific_supplements"] = decoded
      } else {
        updateData["date_specific_supplements"] = .null
      }
    }
    if dirtyFields.contains(.dateSpecificNotes) {
      if let data = shift.dateSpecificNotes {
        let decoded = try requireAnyJSON(
          data,
          table: .recurringShifts,
          id: shiftId,
          field: "date_specific_notes"
        )
        updateData["date_specific_notes"] = decoded
      } else {
        updateData["date_specific_notes"] = .null
      }
    }

    try requireNonEmptyUpdate(updateData, table: .recurringShifts, id: shiftId)

    let outcome: SyncWriteOutcome<SyncRecurringShiftRow> = try await SyncConvex.update(
      .recurringShifts, owner: shift.userId, id: shiftId,
      expectedRevision: shift.serverRevision, data: updateData)

    switch outcome {
    case .ok(let returnedRow):
      let serverUpdatedAt = parseUpdatedAt(
        returnedRow.updated_at, table: .recurringShifts, id: shiftId)
      let serverSnapshot = RecurringShiftServerSnapshot.from(
        row: returnedRow.toRecurringShiftRow(),
        updatedAt: serverUpdatedAt,
        revision: returnedRow.revision,
        deletedAt: nil
      )

      await storeActor.markRecurringShiftPushed(
        id: shiftId,
        serverRow: returnedRow,
        serverUpdatedAt: serverUpdatedAt,
        serverRevision: returnedRow.revision,
        snapshot: serverSnapshot,
        baseline: baseline
      )

      syncCoordinatorLogger.debug("Pushed recurring shift \(shiftId.prefix(8))")
      return .success
    case .conflict(let serverRow):
      return try await handleRecurringShiftPushConflict(
        shift: shift,
        serverRow: serverRow,
        userId: userId,
        storeActor: storeActor,
        isRetry: isRetry
      )
    }
  }

  private func pushRecurringShiftDelete(
    _ shift: LocalRecurringShift,
    userId: String,
    storeActor: LocalStoreActor,
    retryRevision: Int64? = nil
  ) async throws -> PushResult {
    let shiftId = shift.id

    // A row that was never acknowledged can still exist on the server, when an insert committed
    // but its response was lost. No server row has revision 0, so the remove below reports a
    // conflict, and the row it returns decides whether the row is gone, already deleted or live.
    let outcome: SyncWriteOutcome<SyncRecurringShiftRow> = try await SyncConvex.remove(
      .recurringShifts, owner: shift.userId, id: shiftId,
      expectedRevision: retryRevision ?? shift.serverRevision)

    let serverRow: SyncRecurringShiftRow?
    switch outcome {
    case .ok(let returnedRow):
      let serverUpdatedAt = parseUpdatedAt(
        returnedRow.updated_at, table: .recurringShifts, id: shiftId)
      let serverDeletedAt = returnedRow.deleted_at.flatMap { parseISO8601($0) }

      await storeActor.markRecurringShiftDeleted(
        id: shiftId,
        serverUpdatedAt: serverUpdatedAt,
        serverRevision: returnedRow.revision,
        serverDeletedAt: serverDeletedAt
      )

      syncCoordinatorLogger.debug("Deleted recurring shift \(shiftId.prefix(8))")
      return .deleted
    case .conflict(let current):
      serverRow = current
    }

    if let serverRow {
      let serverUpdatedAt = parseUpdatedAt(
        serverRow.updated_at, table: .recurringShifts, id: shiftId)
      let serverDeletedAt = serverRow.deleted_at.flatMap { parseISO8601($0) }

      if serverDeletedAt != nil {
        await storeActor.markRecurringShiftDeleted(
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
        return try await pushRecurringShiftDelete(
          shift, userId: userId, storeActor: storeActor, retryRevision: serverRow.revision)
      }

      let serverSnapshot = RecurringShiftServerSnapshot.from(
        row: serverRow.toRecurringShiftRow(),
        updatedAt: serverUpdatedAt,
        revision: serverRow.revision,
        deletedAt: serverDeletedAt
      )
      await storeActor.markRecurringShiftConflict(id: shiftId, serverSnapshot: serverSnapshot)
    }
    // The server has no row at all, for example after it purged old soft deleted rows. The row
    // is gone there, which is what the delete wanted. Retire the local row instead of retrying
    // on every sync.
    if serverRow == nil {
      let deletedAt = Date()
      await storeActor.markRecurringShiftDeleted(
        id: shiftId,
        serverUpdatedAt: deletedAt,
        serverRevision: shift.serverRevision,
        serverDeletedAt: deletedAt
      )
      return .deleted
    }
    return .conflict
  }

  /// Insert a new recurring shift that was created locally (serverRevision == 0)
  private func insertRecurringShift(
    _ shift: LocalRecurringShift,
    userId: String,
    storeActor: LocalStoreActor
  ) async throws -> PushResult {
    let shiftId = shift.id
    let baseline = SyncPushBaseline(shift)

    // Build full insert data
    var insertData: [String: AnyJSON] = [
      "id": .string(shiftId),
      "user_id": .string(userId),
      "start_time": .string(shift.startTime),
      "end_time": .string(shift.endTime),
      "repeat_interval_weeks": .integer(shift.repeatIntervalWeeks),
    ]
    if let jobId = shift.jobId {
      insertData["job_id"] = .string(jobId)
    }

    // selected_days is required
    let selectedDaysDecoded = try requireAnyJSON(
      shift.selectedDays,
      table: .recurringShifts,
      id: shiftId,
      field: "selected_days"
    )
    insertData["selected_days"] = selectedDaysDecoded

    if let data = shift.endCondition {
      let decoded = try requireAnyJSON(
        data, table: .recurringShifts, id: shiftId, field: "end_condition")
      insertData["end_condition"] = decoded
    }

    if let data = shift.exclusions {
      let decoded = try requireAnyJSON(
        data, table: .recurringShifts, id: shiftId, field: "exclusions")
      insertData["exclusions"] = decoded
    }

    if let data = shift.dateSpecificPauseWindows {
      let decoded = try requireAnyJSON(
        data, table: .recurringShifts, id: shiftId, field: "date_specific_pause_windows")
      insertData["date_specific_pause_windows"] = decoded
    }

    if let data = shift.dateSpecificSupplements {
      let decoded = try requireAnyJSON(
        data, table: .recurringShifts, id: shiftId, field: "date_specific_supplements")
      insertData["date_specific_supplements"] = decoded
    }
    if let data = shift.dateSpecificNotes {
      let decoded = try requireAnyJSON(
        data, table: .recurringShifts, id: shiftId, field: "date_specific_notes")
      insertData["date_specific_notes"] = decoded
    }

    let outcome: SyncInsertOutcome<SyncRecurringShiftRow> = try await SyncConvex.insert(
      .recurringShifts, owner: shift.userId, row: insertData)

    switch outcome {
    case .ok(let returnedRow):
      let serverUpdatedAt = parseUpdatedAt(
        returnedRow.updated_at, table: .recurringShifts, id: shiftId)
      let serverSnapshot = RecurringShiftServerSnapshot.from(
        row: returnedRow.toRecurringShiftRow(),
        updatedAt: serverUpdatedAt,
        revision: returnedRow.revision,
        deletedAt: nil
      )

      await storeActor.markRecurringShiftPushed(
        id: shiftId,
        serverRow: returnedRow,
        serverUpdatedAt: serverUpdatedAt,
        serverRevision: returnedRow.revision,
        snapshot: serverSnapshot,
        baseline: baseline
      )

      syncCoordinatorLogger.debug("Inserted new recurring shift \(shiftId.prefix(8))")
      return .success
    case .exists(let serverRow):
      // The row exists, usually because an earlier insert committed after the request timed
      // out locally. Merge onto it.
      syncCoordinatorLogger.warning("Recurring shift \(shift.id.prefix(8)) already exists on server, merging")
      return try await handleRecurringShiftPushConflict(
        shift: shift, serverRow: serverRow, userId: userId, storeActor: storeActor,
        isRetry: false)
    }
  }

  private func handleRecurringShiftPushConflict(
    shift: LocalRecurringShift,
    serverRow: SyncRecurringShiftRow?,
    userId: String,
    storeActor: LocalStoreActor,
    isRetry: Bool
  ) async throws -> PushResult {
    let shiftId = shift.id

    guard let serverRow else {
      // Server row doesn't exist - check if this is a new local record that needs INSERT
      if shift.serverRevision == 0 {
        syncCoordinatorLogger.debug(
          "Recurring shift \(shiftId.prefix(8)) is new (serverRevision=0), attempting INSERT")
        return try await insertRecurringShift(shift, userId: userId, storeActor: storeActor)
      }
      syncCoordinatorLogger.debug("Recurring shift \(shiftId.prefix(8)) was deleted on server")
      await storeActor.markRecurringShiftConflict(id: shiftId, serverSnapshot: nil)
      return .conflict
    }

    let serverUpdatedAt = parseUpdatedAt(serverRow.updated_at, table: .recurringShifts, id: shiftId)
    let serverDeletedAt = serverRow.deleted_at.flatMap { parseISO8601($0) }

    if serverDeletedAt != nil {
      let serverSnapshot = RecurringShiftServerSnapshot.from(
        row: serverRow.toRecurringShiftRow(),
        updatedAt: serverUpdatedAt,
        revision: serverRow.revision,
        deletedAt: serverDeletedAt
      )
      await storeActor.markRecurringShiftConflict(id: shiftId, serverSnapshot: serverSnapshot)
      return .conflict
    }

    let newServerSnapshot = RecurringShiftServerSnapshot.from(
      row: serverRow.toRecurringShiftRow(),
      updatedAt: serverUpdatedAt,
      revision: serverRow.revision,
      deletedAt: serverDeletedAt
    )
    guard !isRetry else {
      await storeActor.markRecurringShiftConflict(id: shiftId, serverSnapshot: newServerSnapshot)
      return .conflict
    }

    await storeActor.rebaseRecurringShift(
      id: shiftId,
      serverRow: serverRow,
      serverUpdatedAt: serverUpdatedAt,
      serverRevision: serverRow.revision,
      serverDeletedAt: serverDeletedAt,
      newSnapshot: newServerSnapshot
    )

    if let rebasedShift = try await storeActor.recurringShiftCopy(id: shiftId) {
      let retryResult = try await pushRecurringShift(
        rebasedShift, userId: userId, storeActor: storeActor, isRetry: true)
      if retryResult == .success {
        return .rebased
      }
      return retryResult
    }
    return .conflict
  }
}
