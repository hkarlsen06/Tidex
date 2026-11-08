import Foundation
import Observation
import Synchronization
import os.log

extension SyncCoordinator {

  // MARK: - Wage Snapshots Push

  func pushWageSnapshots(userId: String) async throws -> TablePushResult {
    let storeActor = await MainActor.run { LocalStore.shared.storeActor }
    let dirtySnapshots = try await storeActor.dirtyWageSnapshotCopies(userId: userId)

    if dirtySnapshots.isEmpty {
      return TablePushResult(table: .wageSnapshots, rowsPushed: 0, newConflicts: 0, rebased: 0)
    }

    var rowsPushed = 0
    var failedRows = 0
    var newConflicts = 0
    var rebased = 0

    // Deletes go first. The unique indexes on (job, from date) skip deleted rows, so a snapshot
    // that replaces a deleted one on the same date can only insert after the delete.
    let deletesFirst = dirtySnapshots.sorted {
      $0.syncStatus == .pendingDelete && $1.syncStatus != .pendingDelete
    }
    for snapshot in deletesFirst {
      let snapshotId = snapshot.id
      let result: PushResult
      do {
        result = try await pushWageSnapshot(
          snapshot, userId: userId, storeActor: storeActor, isRetry: false)
      } catch let error where Self.isRowRejection(error) {
        syncCoordinatorLogger.error(
          "Server rejected wage snapshot \(snapshotId.prefix(8)): \(error.localizedDescription)")
        await storeActor.markWageSnapshotConflict(id: snapshotId, serverSnapshot: nil)
        result = .conflict
      } catch {
        try await skipRowUnlessFatal(error, table: .wageSnapshots, id: snapshotId)
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
      table: .wageSnapshots,
      rowsPushed: rowsPushed,
      newConflicts: newConflicts,
      rebased: rebased,
      failedRows: failedRows
    )
  }

  /// Columns of a partial wage snapshot UPDATE, limited to the fields marked dirty.
  private func wageSnapshotUpdatePayload(
    for snapshot: LocalWageSnapshot, dirtyFields: Set<WageSnapshotField>
  ) throws -> [String: AnyJSON] {
    var update = PartialUpdatePayload(dirtyFields: dirtyFields)
    update.set(.jobId, "job_id", snapshot.jobId.jsonOrNull { .string($0) })
    update.set(.fromDate, "from_date", snapshot.fromDateString.jsonOrNull { .string($0) })
    update.set(.hourlyWage, "hourly_wage", .double(snapshot.hourlyWage))
    update.set(.wageLevel, "wage_level", snapshot.wageLevel.jsonOrNull { .integer($0) })
    update.set(.tariffTypeId, "tariff_type_id", snapshot.tariffTypeId.jsonOrNull { .string($0) })
    try update.set(
      .supplements, "supplements",
      try requireAnyJSON(
        snapshot.supplements, table: .wageSnapshots, id: snapshot.id, field: "supplements"))
    try update.set(
      .overtime, "overtime",
      try requireAnyJSON(
        snapshot.overtime, table: .wageSnapshots, id: snapshot.id, field: "overtime"))
    update.set(.taxEnabled, "tax_enabled", snapshot.taxEnabled.jsonOrNull { .bool($0) })
    update.set(.taxPercentage, "tax_percentage", snapshot.taxPercentage.jsonOrNull { .double($0) })
    update.set(.breakEnabled, "break_enabled", snapshot.breakEnabled.jsonOrNull { .bool($0) })
    update.set(.breakMethod, "break_method", snapshot.breakMethod.jsonOrNull { .string($0) })
    update.set(
      .breakThresholdHours, "break_threshold_hours",
      snapshot.breakThresholdHours.jsonOrNull { .double($0) })
    update.set(
      .breakDeductionMinutes, "break_deduction_minutes",
      snapshot.breakDeductionMinutes.jsonOrNull { .integer($0) })
    return update.data
  }

  func pushWageSnapshot(
    _ snapshot: LocalWageSnapshot,
    userId: String,
    storeActor: LocalStoreActor,
    isRetry: Bool
  ) async throws -> PushResult {
    let snapshotId = snapshot.id

    if snapshot.syncStatus == .pendingDelete {
      return try await pushWageSnapshotDelete(snapshot, userId: userId, storeActor: storeActor)
    }

    let dirtyFields = snapshot.dirtyFieldKeys
    if dirtyFields.isEmpty {
      await storeActor.markWageSnapshotClean(id: snapshotId)
      return .noChange
    }

    // Check if this is a new record that needs INSERT (serverRevision == 0 means never synced)
    if snapshot.serverRevision == 0 {
      return try await insertWageSnapshot(snapshot, userId: userId, storeActor: storeActor)
    }

    let baseline = SyncPushBaseline(snapshot)
    let updateData = try wageSnapshotUpdatePayload(for: snapshot, dirtyFields: dirtyFields)

    try requireNonEmptyUpdate(updateData, table: .wageSnapshots, id: snapshotId)

    let outcome: SyncWriteOutcome<SyncWageSnapshotRow> = try await SyncConvex.update(
      .wageSnapshots, owner: snapshot.userId, id: snapshotId,
      expectedRevision: snapshot.serverRevision, data: updateData)

    switch outcome {
    case .ok(let returnedRow):
      let serverUpdatedAt = parseUpdatedAt(
        returnedRow.updated_at, table: .wageSnapshots, id: snapshotId)
      let serverSnapshot = WageSnapshotServerSnapshot.from(
        row: returnedRow.toWageSnapshot(),
        updatedAt: serverUpdatedAt,
        revision: returnedRow.revision,
        deletedAt: nil
      )

      await storeActor.markWageSnapshotPushed(
        id: snapshotId,
        serverRow: returnedRow,
        serverUpdatedAt: serverUpdatedAt,
        serverRevision: returnedRow.revision,
        snapshot: serverSnapshot,
        baseline: baseline
      )

      syncCoordinatorLogger.debug("Pushed wage snapshot \(snapshotId.prefix(8))")
      return .success
    case .conflict(let serverRow):
      return try await handleWageSnapshotPushConflict(
        snapshot: snapshot,
        serverRow: serverRow,
        userId: userId,
        storeActor: storeActor,
        isRetry: isRetry
      )
    }
  }

  private func pushWageSnapshotDelete(
    _ snapshot: LocalWageSnapshot,
    userId: String,
    storeActor: LocalStoreActor,
    retryRevision: Int64? = nil
  ) async throws -> PushResult {
    let snapshotId = snapshot.id

    // A row that was never acknowledged can still exist on the server, when an insert committed
    // but its response was lost. No server row has revision 0, so the remove below reports a
    // conflict, and the row it returns decides whether the row is gone, already deleted or live.
    let outcome: SyncWriteOutcome<SyncWageSnapshotRow> = try await SyncConvex.remove(
      .wageSnapshots, owner: snapshot.userId, id: snapshotId,
      expectedRevision: retryRevision ?? snapshot.serverRevision)

    let serverRow: SyncWageSnapshotRow?
    switch outcome {
    case .ok(let returnedRow):
      let serverUpdatedAt = parseUpdatedAt(
        returnedRow.updated_at, table: .wageSnapshots, id: snapshotId)
      let serverDeletedAt = returnedRow.deleted_at.flatMap { parseISO8601($0) }

      await storeActor.markWageSnapshotDeleted(
        id: snapshotId,
        serverUpdatedAt: serverUpdatedAt,
        serverRevision: returnedRow.revision,
        serverDeletedAt: serverDeletedAt
      )

      syncCoordinatorLogger.debug("Deleted wage snapshot \(snapshotId.prefix(8))")
      return .deleted
    case .conflict(let current):
      serverRow = current
    }

    if let serverRow {
      let serverUpdatedAt = parseUpdatedAt(
        serverRow.updated_at, table: .wageSnapshots, id: snapshotId)
      let serverDeletedAt = serverRow.deleted_at.flatMap { parseISO8601($0) }

      if serverDeletedAt != nil {
        await storeActor.markWageSnapshotDeleted(
          id: snapshotId,
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
        return try await pushWageSnapshotDelete(
          snapshot, userId: userId, storeActor: storeActor, retryRevision: serverRow.revision)
      }

      let serverSnapshot = WageSnapshotServerSnapshot.from(
        row: serverRow.toWageSnapshot(),
        updatedAt: serverUpdatedAt,
        revision: serverRow.revision,
        deletedAt: serverDeletedAt
      )
      await storeActor.markWageSnapshotConflict(id: snapshotId, serverSnapshot: serverSnapshot)
    }
    // The server has no row at all, for example after it purged old soft deleted rows. The row
    // is gone there, which is what the delete wanted. Retire the local row instead of retrying
    // on every sync.
    if serverRow == nil {
      let deletedAt = Date()
      await storeActor.markWageSnapshotDeleted(
        id: snapshotId,
        serverUpdatedAt: deletedAt,
        serverRevision: snapshot.serverRevision,
        serverDeletedAt: deletedAt
      )
      return .deleted
    }
    return .conflict
  }

  /// Insert a new wage snapshot that was created locally (serverRevision == 0)
  private func insertWageSnapshot(
    _ snapshot: LocalWageSnapshot,
    userId: String,
    storeActor: LocalStoreActor
  ) async throws -> PushResult {
    let snapshotId = snapshot.id
    let baseline = SyncPushBaseline(snapshot)

    // Build full insert data
    var insertData: [String: AnyJSON] = [
      "id": .string(snapshotId),
      "user_id": .string(userId),
      "hourly_wage": .double(snapshot.hourlyWage),
    ]
    if let jobId = snapshot.jobId {
      insertData["job_id"] = .string(jobId)
    }

    // from_date (nil for baseline snapshot)
    if let fromDateString = snapshot.fromDateString {
      insertData["from_date"] = .string(fromDateString)
    }

    // wage_level
    if let level = snapshot.wageLevel {
      insertData["wage_level"] = .integer(level)
    }
    if let tariffTypeId = snapshot.tariffTypeId {
      insertData["tariff_type_id"] = .string(tariffTypeId)
    }

    // supplements (required)
    let supplementsDecoded = try requireAnyJSON(
      snapshot.supplements,
      table: .wageSnapshots,
      id: snapshotId,
      field: "supplements"
    )
    insertData["supplements"] = supplementsDecoded

    let overtimeDecoded = try requireAnyJSON(
      snapshot.overtime,
      table: .wageSnapshots,
      id: snapshotId,
      field: "overtime"
    )
    insertData["overtime"] = overtimeDecoded

    // Optional fields
    if let enabled = snapshot.taxEnabled {
      insertData["tax_enabled"] = .bool(enabled)
    }
    if let percentage = snapshot.taxPercentage {
      insertData["tax_percentage"] = .double(percentage)
    }
    if let enabled = snapshot.breakEnabled {
      insertData["break_enabled"] = .bool(enabled)
    }
    if let method = snapshot.breakMethod {
      insertData["break_method"] = .string(method)
    }
    if let hours = snapshot.breakThresholdHours {
      insertData["break_threshold_hours"] = .double(hours)
    }
    if let minutes = snapshot.breakDeductionMinutes {
      insertData["break_deduction_minutes"] = .integer(minutes)
    }

    let outcome: SyncInsertOutcome<SyncWageSnapshotRow> = try await SyncConvex.insert(
      .wageSnapshots, owner: snapshot.userId, row: insertData)

    switch outcome {
    case .ok(let returnedRow):
      let serverUpdatedAt = parseUpdatedAt(
        returnedRow.updated_at, table: .wageSnapshots, id: snapshotId)
      let serverSnapshot = WageSnapshotServerSnapshot.from(
        row: returnedRow.toWageSnapshot(),
        updatedAt: serverUpdatedAt,
        revision: returnedRow.revision,
        deletedAt: nil
      )

      await storeActor.markWageSnapshotPushed(
        id: snapshotId,
        serverRow: returnedRow,
        serverUpdatedAt: serverUpdatedAt,
        serverRevision: returnedRow.revision,
        snapshot: serverSnapshot,
        baseline: baseline
      )

      syncCoordinatorLogger.debug("Inserted new wage snapshot \(snapshotId.prefix(8))")
      return .success
    case .exists(let serverRow):
      // The row exists, usually because an earlier insert committed after the request timed
      // out locally. Merge onto it.
      syncCoordinatorLogger.warning("Wage snapshot \(snapshot.id.prefix(8)) already exists on server, merging")
      return try await handleWageSnapshotPushConflict(
        snapshot: snapshot, serverRow: serverRow, userId: userId, storeActor: storeActor,
        isRetry: false)
    }
  }

  private func handleWageSnapshotPushConflict(
    snapshot: LocalWageSnapshot,
    serverRow: SyncWageSnapshotRow?,
    userId: String,
    storeActor: LocalStoreActor,
    isRetry: Bool
  ) async throws -> PushResult {
    let snapshotId = snapshot.id

    guard let serverRow else {
      // Server row doesn't exist - check if this is a new local record that needs INSERT
      if snapshot.serverRevision == 0 {
        syncCoordinatorLogger.debug(
          "Wage snapshot \(snapshotId.prefix(8)) is new (serverRevision=0), attempting INSERT")
        return try await insertWageSnapshot(snapshot, userId: userId, storeActor: storeActor)
      }
      syncCoordinatorLogger.debug("Wage snapshot \(snapshotId.prefix(8)) was deleted on server")
      await storeActor.markWageSnapshotConflict(id: snapshotId, serverSnapshot: nil)
      return .conflict
    }

    let serverUpdatedAt = parseUpdatedAt(
      serverRow.updated_at, table: .wageSnapshots, id: snapshotId)
    let serverDeletedAt = serverRow.deleted_at.flatMap { parseISO8601($0) }

    if serverDeletedAt != nil {
      let serverSnapshot = WageSnapshotServerSnapshot.from(
        row: serverRow.toWageSnapshot(),
        updatedAt: serverUpdatedAt,
        revision: serverRow.revision,
        deletedAt: serverDeletedAt
      )
      await storeActor.markWageSnapshotConflict(id: snapshotId, serverSnapshot: serverSnapshot)
      return .conflict
    }

    let newServerSnapshot = WageSnapshotServerSnapshot.from(
      row: serverRow.toWageSnapshot(),
      updatedAt: serverUpdatedAt,
      revision: serverRow.revision,
      deletedAt: serverDeletedAt
    )
    guard !isRetry else {
      await storeActor.markWageSnapshotConflict(id: snapshotId, serverSnapshot: newServerSnapshot)
      return .conflict
    }

    await storeActor.rebaseWageSnapshot(
      id: snapshotId,
      serverRow: serverRow,
      serverUpdatedAt: serverUpdatedAt,
      serverRevision: serverRow.revision,
      serverDeletedAt: serverDeletedAt,
      newSnapshot: newServerSnapshot
    )

    if let rebasedSnapshot = try await storeActor.wageSnapshotCopy(id: snapshotId) {
      let retryResult = try await pushWageSnapshot(
        rebasedSnapshot, userId: userId, storeActor: storeActor, isRetry: true)
      if retryResult == .success {
        return .rebased
      }
      return retryResult
    }
    return .conflict
  }
}
