import Foundation
import Observation
import Synchronization
import os.log

extension SyncCoordinator {

  // MARK: - Payroll Adjustments Push

  func pushPayrollAdjustments(userId: String) async throws -> TablePushResult {
    let storeActor = await MainActor.run { LocalStore.shared.storeActor }
    let dirtyAdjustments = try await storeActor.dirtyPayrollAdjustmentCopies(userId: userId)

    if dirtyAdjustments.isEmpty {
      return TablePushResult(
        table: .payrollAdjustments,
        rowsPushed: 0,
        newConflicts: 0,
        rebased: 0
      )
    }

    var rowsPushed = 0
    var failedRows = 0
    var newConflicts = 0

    for adjustment in dirtyAdjustments {
      let adjustmentId = adjustment.id
      let result: PushResult
      do {
        result = try await pushPayrollAdjustment(
          adjustment,
          userId: userId,
          storeActor: storeActor
        )
      } catch let error where Self.isRowRejection(error) {
        syncCoordinatorLogger.error(
          "Server rejected payroll adjustment \(adjustmentId.prefix(8)): \(error.localizedDescription)"
        )
        await storeActor.markPayrollAdjustmentConflict(id: adjustmentId, serverSnapshot: nil)
        result = .conflict
      } catch {
        try await skipRowUnlessFatal(error, table: .payrollAdjustments, id: adjustmentId)
        failedRows += 1
        result = .noChange
      }
      switch result {
      case .success, .deleted:
        rowsPushed += 1

      case .conflict:
        newConflicts += 1

      case .rebased:
        rowsPushed += 1

      case .noChange:
        break
      }
    }

    try await storeActor.save()
    return TablePushResult(
      table: .payrollAdjustments,
      rowsPushed: rowsPushed,
      newConflicts: newConflicts,
      rebased: 0,
      failedRows: failedRows
    )
  }

  func pushPayrollAdjustment(
    _ adjustment: LocalPayrollAdjustment,
    userId: String,
    storeActor: LocalStoreActor,
    isRetry: Bool = false
  ) async throws -> PushResult {
    if adjustment.syncStatus == .pendingDelete {
      return try await pushPayrollAdjustmentDelete(
        adjustment,
        userId: userId,
        storeActor: storeActor
      )
    }

    if adjustment.dirtyFieldKeys.isEmpty {
      await storeActor.markPayrollAdjustmentClean(id: adjustment.id)
      return .noChange
    }

    if adjustment.serverRevision == 0 {
      return try await insertPayrollAdjustment(adjustment, userId: userId, storeActor: storeActor)
    }

    let baseline = SyncPushBaseline(adjustment)
    let dirtyColumns = Set(adjustment.dirtyFieldKeys.map(\.rawValue))
    let updateData = payrollAdjustmentPayload(adjustment, includeIdentity: false, userId: userId)
      .filter { dirtyColumns.contains($0.key) }
    try requireNonEmptyUpdate(updateData, table: .payrollAdjustments, id: adjustment.id)

    let outcome: SyncWriteOutcome<SyncPayrollAdjustmentRow> = try await SyncConvex.update(
      .payrollAdjustments, owner: adjustment.userId, id: adjustment.id,
      expectedRevision: adjustment.serverRevision,
      data: updateData)

    switch outcome {
    case .ok(let returnedRow):
      try await markPayrollAdjustmentPushed(returnedRow, storeActor: storeActor, baseline: baseline)
      return .success
    case .conflict(let serverRow):
      return try await handlePayrollAdjustmentPushConflict(
        adjustment, serverRow: serverRow, userId: userId, storeActor: storeActor, isRetry: isRetry)
    }
  }

  /// Handles an update that matched no row. A moved revision is merged the way a pull merges it,
  /// and the push is retried once. A deleted or missing row, or a second miss, is a conflict
  /// that carries the server row when there is one.
  private func handlePayrollAdjustmentPushConflict(
    _ adjustment: LocalPayrollAdjustment,
    serverRow: SyncPayrollAdjustmentRow?,
    userId: String,
    storeActor: LocalStoreActor,
    isRetry: Bool
  ) async throws -> PushResult {
    guard let serverRow else {
      await storeActor.markPayrollAdjustmentConflict(id: adjustment.id, serverSnapshot: nil)
      return .conflict
    }
    let serverUpdatedAt = try requireISO8601(
      serverRow.updated_at, table: .payrollAdjustments, id: serverRow.id)
    let serverDeletedAt = serverRow.deleted_at.flatMap { parseISO8601($0) }
    let snapshot = PayrollAdjustmentServerSnapshot.from(
      row: serverRow, updatedAt: serverUpdatedAt, deletedAt: serverDeletedAt)
    guard serverDeletedAt == nil, !isRetry else {
      await storeActor.markPayrollAdjustmentConflict(id: adjustment.id, serverSnapshot: snapshot)
      return .conflict
    }

    await storeActor.mergePayrollAdjustmentFromServer(
      id: serverRow.id,
      serverRow: serverRow,
      serverUpdatedAt: serverUpdatedAt,
      serverDeletedAt: serverDeletedAt,
      snapshot: snapshot
    )
    guard let rebased = try await storeActor.payrollAdjustmentCopy(id: adjustment.id) else {
      return .conflict
    }
    let retryResult = try await pushPayrollAdjustment(
      rebased, userId: userId, storeActor: storeActor, isRetry: true)
    return retryResult == .success ? .rebased : retryResult
  }

  private func insertPayrollAdjustment(
    _ adjustment: LocalPayrollAdjustment,
    userId: String,
    storeActor: LocalStoreActor
  ) async throws -> PushResult {
    let baseline = SyncPushBaseline(adjustment)
    let insertData = payrollAdjustmentPayload(adjustment, includeIdentity: true, userId: userId)
    let outcome: SyncInsertOutcome<SyncPayrollAdjustmentRow> = try await SyncConvex.insert(
      .payrollAdjustments, owner: adjustment.userId, row: insertData)

    switch outcome {
    case .ok(let returnedRow):
      try await markPayrollAdjustmentPushed(returnedRow, storeActor: storeActor, baseline: baseline)
      return .success
    case .exists(let serverRow):
      // The row exists, usually because an earlier insert committed after the request timed
      // out locally. Adopt the server row instead of failing on every sync.
      let serverUpdatedAt = try requireISO8601(
        serverRow.updated_at, table: .payrollAdjustments, id: serverRow.id)
      let serverDeletedAt = serverRow.deleted_at.flatMap { parseISO8601($0) }
      await storeActor.mergePayrollAdjustmentFromServer(
        id: serverRow.id,
        serverRow: serverRow,
        serverUpdatedAt: serverUpdatedAt,
        serverDeletedAt: serverDeletedAt,
        snapshot: PayrollAdjustmentServerSnapshot.from(
          row: serverRow,
          updatedAt: serverUpdatedAt,
          deletedAt: serverDeletedAt
        )
      )
      return .rebased
    }
  }

  private func pushPayrollAdjustmentDelete(
    _ adjustment: LocalPayrollAdjustment,
    userId: String,
    storeActor: LocalStoreActor,
    retryRevision: Int64? = nil
  ) async throws -> PushResult {
    // A row that was never acknowledged can still exist on the server, when an insert committed
    // but its response was lost. No server row has revision 0, so the remove below reports a
    // conflict, and the row it returns decides whether the row is gone, already deleted or live.
    let outcome: SyncWriteOutcome<SyncPayrollAdjustmentRow> = try await SyncConvex.remove(
      .payrollAdjustments, owner: adjustment.userId, id: adjustment.id,
      expectedRevision: retryRevision ?? adjustment.serverRevision)

    let returnedRow: SyncPayrollAdjustmentRow
    switch outcome {
    case .ok(let row):
      returnedRow = row

    case .conflict(let serverRow):
      // The server has no row, which is what the delete wanted. Retire the local row.
      guard let serverRow else {
        let deletedAt = Date()
        await storeActor.markPayrollAdjustmentDeleted(
          id: adjustment.id,
          serverUpdatedAt: deletedAt,
          serverRevision: adjustment.serverRevision,
          serverDeletedAt: deletedAt
        )
        return .deleted
      }
      let serverUpdatedAt = try requireISO8601(
        serverRow.updated_at, table: .payrollAdjustments, id: serverRow.id)
      let serverDeletedAt = serverRow.deleted_at.flatMap { parseISO8601($0) }
      if serverDeletedAt != nil {
        await storeActor.markPayrollAdjustmentDeleted(
          id: adjustment.id,
          serverUpdatedAt: serverUpdatedAt,
          serverRevision: serverRow.revision,
          serverDeletedAt: serverDeletedAt
        )
        return .deleted
      }
      // Another write moved the revision after this device last saw the row. The user deleted
      // the row, so the delete wins. Retry once against the current revision.
      if retryRevision == nil {
        return try await pushPayrollAdjustmentDelete(
          adjustment, userId: userId, storeActor: storeActor, retryRevision: serverRow.revision)
      }
      await storeActor.markPayrollAdjustmentConflict(
        id: adjustment.id,
        serverSnapshot: PayrollAdjustmentServerSnapshot.from(
          row: serverRow, updatedAt: serverUpdatedAt, deletedAt: nil)
      )
      return .conflict
    }

    let serverUpdatedAt = try requireISO8601(
      returnedRow.updated_at, table: .payrollAdjustments, id: returnedRow.id)
    let serverDeletedAt = returnedRow.deleted_at.flatMap { parseISO8601($0) }
    await storeActor.markPayrollAdjustmentDeleted(
      id: returnedRow.id,
      serverUpdatedAt: serverUpdatedAt,
      serverRevision: returnedRow.revision,
      serverDeletedAt: serverDeletedAt
    )
    return .deleted
  }

  private func payrollAdjustmentPayload(
    _ adjustment: LocalPayrollAdjustment,
    includeIdentity: Bool,
    userId: String
  ) -> [String: AnyJSON] {
    var payload: [String: AnyJSON] = [
      "amount": .double(adjustment.amount),
      "currency": .string(adjustment.currency),
      "category": .string(adjustment.category.rawValue),
      "tax_treatment": .string(adjustment.taxTreatment.rawValue),
      "description": .string(adjustment.descriptionText),
      "payout_date": .string(adjustment.payoutDateString),
    ]

    if includeIdentity {
      payload["id"] = .string(adjustment.id)
      payload["user_id"] = .string(userId)
    }
    payload["job_id"] = adjustment.jobId.map(AnyJSON.string) ?? .null
    payload["note"] = adjustment.note.map(AnyJSON.string) ?? .null
    payload["curated_note"] = adjustment.curatedNote.map(AnyJSON.string) ?? .null
    payload["curated_description"] = adjustment.curatedDescription.map(AnyJSON.string) ?? .null
    payload["curated_link"] = adjustment.curatedLink.map(AnyJSON.string) ?? .null
    payload["curated_link_title"] = adjustment.curatedLinkTitle.map(AnyJSON.string) ?? .null
    payload["earned_from_date"] = adjustment.earnedFromDateString.map(AnyJSON.string) ?? .null
    payload["earned_to_date"] = adjustment.earnedToDateString.map(AnyJSON.string) ?? .null

    return payload
  }

  private func markPayrollAdjustmentPushed(
    _ row: SyncPayrollAdjustmentRow,
    storeActor: LocalStoreActor,
    baseline: SyncPushBaseline
  ) async throws {
    let serverUpdatedAt = try requireISO8601(
      row.updated_at, table: .payrollAdjustments, id: row.id)
    let serverDeletedAt = row.deleted_at.flatMap { parseISO8601($0) }
    let snapshot = PayrollAdjustmentServerSnapshot.from(
      row: row,
      updatedAt: serverUpdatedAt,
      deletedAt: serverDeletedAt
    )
    await storeActor.markPayrollAdjustmentPushed(
      id: row.id,
      serverRow: row,
      serverUpdatedAt: serverUpdatedAt,
      serverDeletedAt: serverDeletedAt,
      snapshot: snapshot,
      baseline: baseline
    )
  }

  // MARK: - Payroll Adjustments Pull

  func pullPayrollAdjustmentsPage(userId: String, cursor: Int64) async throws
    -> PagePullResult
  {
    let page: SyncPullPage<SyncPayrollAdjustmentRow> = try await SyncConvex.pull(
      .payrollAdjustments, after: cursor, limit: pageSize)
    let rows = page.rows

    if rows.isEmpty {
      return PagePullResult(
        rowsProcessed: 0,
        cursor: page.cursor,
        newConflicts: 0,
        autoMerged: 0,
        hasMore: false
      )
    }

    let storeActor = await MainActor.run { LocalStore.shared.storeActor }
    var newConflicts = 0
    var affectedMonths = Self.affectedMonths(forPayrollAdjustmentRows: rows)

    for row in rows {
      if let existing = try await storeActor.payrollAdjustmentCopy(id: row.id) {
        affectedMonths.insert(ShiftChangeAffectedMonth(date: existing.payoutDate))
      }

      let result = try await applyIsolated(table: .payrollAdjustments, id: row.id) {
        try await self.applyPayrollAdjustmentRow(row, storeActor: storeActor)
      }
      if result == .conflict { newConflicts += 1 }
    }

    try await storeActor.save()

    return PagePullResult(
      rowsProcessed: rows.count,
      cursor: page.cursor,
      newConflicts: newConflicts,
      autoMerged: 0,
      hasMore: !page.done,
      affectedMonths: affectedMonths
    )
  }

  private func applyPayrollAdjustmentRow(
    _ serverRow: SyncPayrollAdjustmentRow,
    storeActor: LocalStoreActor
  ) async throws -> ApplyResult {
    let serverUpdatedAt = try requireISO8601(
      serverRow.updated_at, table: .payrollAdjustments, id: serverRow.id)
    let serverDeletedAt = serverRow.deleted_at.flatMap { parseISO8601($0) }
    let serverSnapshot = PayrollAdjustmentServerSnapshot.from(
      row: serverRow,
      updatedAt: serverUpdatedAt,
      deletedAt: serverDeletedAt
    )

    if let existing = try await storeActor.payrollAdjustmentCopy(id: serverRow.id) {
      return await applyPayrollAdjustmentToExisting(
        existing: existing,
        serverRow: serverRow,
        serverUpdatedAt: serverUpdatedAt,
        serverDeletedAt: serverDeletedAt,
        serverSnapshot: serverSnapshot,
        storeActor: storeActor
      )
    }

    let local = LocalPayrollAdjustment.from(serverRow: serverRow, serverUpdatedAt: serverUpdatedAt)
    try await storeActor.upsertPayrollAdjustment(local)
    return .inserted
  }

  // swiftlint:disable:next function_parameter_count
  private func applyPayrollAdjustmentToExisting(
    existing: LocalPayrollAdjustment,
    serverRow: SyncPayrollAdjustmentRow,
    serverUpdatedAt: Date,
    serverDeletedAt: Date?,
    serverSnapshot: PayrollAdjustmentServerSnapshot,
    storeActor: LocalStoreActor
  ) async -> ApplyResult {
    switch existing.syncStatus {
    case .clean:
      if await storeActor.updatePayrollAdjustmentFromServer(
        id: serverRow.id,
        serverRow: serverRow,
        serverUpdatedAt: serverUpdatedAt,
        serverDeletedAt: serverDeletedAt,
        snapshot: serverSnapshot,
        onlyIfClean: true
      ) {
        return .updated
      }
      // The row stopped being clean after it was read. Read it again and take the merge path.
      guard let fresh = try? await storeActor.payrollAdjustmentCopy(id: serverRow.id),
        fresh.syncStatus != .clean
      else {
        return .noChange
      }
      return await applyPayrollAdjustmentToExisting(
        existing: fresh,
        serverRow: serverRow,
        serverUpdatedAt: serverUpdatedAt,
        serverDeletedAt: serverDeletedAt,
        serverSnapshot: serverSnapshot,
        storeActor: storeActor
      )

    case .dirty, .pendingDelete:
      if serverRow.revision == existing.serverRevision { return .noChange }
      await storeActor.mergePayrollAdjustmentFromServer(
        id: serverRow.id,
        serverRow: serverRow,
        serverUpdatedAt: serverUpdatedAt,
        serverDeletedAt: serverDeletedAt,
        snapshot: serverSnapshot
      )
      return .autoMerged

    case .conflict:
      await storeActor.markPayrollAdjustmentConflict(
        id: serverRow.id,
        serverSnapshot: serverSnapshot
      )
      return .noChange
    }
  }
}
