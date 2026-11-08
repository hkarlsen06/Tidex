import Foundation
import Observation
import Synchronization
import os.log

extension SyncCoordinator {

  // MARK: - Push Implementation

  /// Push dirty records for a single table
  func pushTable(_ table: SyncTable, userId: String) async throws -> TablePushResult {
    syncCoordinatorLogger.debug("Pushing \(table.displayName)")

    switch table {
    case .jobs:
      return try await pushJobs(userId: userId)

    case .userShifts:
      return try await pushUserShifts(userId: userId)

    case .events:
      return try await pushEvents(userId: userId)

    case .recurringShifts:
      return try await pushRecurringShifts(userId: userId)

    case .wageSnapshots:
      return try await pushWageSnapshots(userId: userId)

    case .payrollAdjustments:
      return try await pushPayrollAdjustments(userId: userId)

    case .userSettings:
      return try await pushUserSettings(userId: userId)

    case .notificationPreferences:
      return try await pushNotificationPreferences(userId: userId)
    }
  }

  // swiftlint:disable:next cyclomatic_complexity
  private func pushJobs(userId: String) async throws -> TablePushResult {
    let storeActor = await MainActor.run { LocalStore.shared.storeActor }
    let dirtyJobs = try await storeActor.dirtyJobCopies(userId: userId)

    if dirtyJobs.isEmpty {
      return TablePushResult(table: .jobs, rowsPushed: 0, newConflicts: 0, rebased: 0)
    }

    var rowsPushed = 0
    var failedRows = 0
    var newConflicts = 0
    var rebased = 0

    // Keep default-workplace updates constraint-safe:
    // 1) push rows unsetting is_default first
    // 2) push regular updates
    // 3) push rows setting is_default=true last
    let orderedDirtyJobs = dirtyJobs.sorted { lhs, rhs in
      let lhsPriority = jobPushPriority(lhs)
      let rhsPriority = jobPushPriority(rhs)

      if lhsPriority != rhsPriority {
        return lhsPriority < rhsPriority
      }

      if lhs.localUpdatedAt != rhs.localUpdatedAt {
        return lhs.localUpdatedAt < rhs.localUpdatedAt
      }

      return lhs.id < rhs.id
    }

    for job in orderedDirtyJobs {
      let jobId = job.id
      let result: PushResult
      do {
        result = try await pushJob(job, userId: userId, storeActor: storeActor, isRetry: false)
      } catch let error where Self.isRowRejection(error) {
        syncCoordinatorLogger.error("Server rejected job \(jobId.prefix(8)): \(error.localizedDescription)")
        await storeActor.markJobConflict(id: jobId, serverSnapshot: nil)
        result = .conflict
      } catch {
        try await skipRowUnlessFatal(error, table: .jobs, id: jobId)
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
      table: .jobs,
      rowsPushed: rowsPushed,
      newConflicts: newConflicts,
      rebased: rebased,
      failedRows: failedRows
    )
  }

  private func jobPushPriority(_ job: LocalJob) -> Int {
    let dirtyFields = job.dirtyFieldKeys
    guard dirtyFields.contains(.isDefault) else {
      return 1
    }
    return job.isDefault ? 2 : 0
  }

  /// Columns of a partial job UPDATE, limited to the fields marked dirty.
  private func jobUpdatePayload(
    for job: LocalJob, dirtyFields: Set<JobField>
  ) throws -> [String: AnyJSON] {
    var update = PartialUpdatePayload(dirtyFields: dirtyFields)
    update.set(.name, "name", .string(job.name))
    update.set(.color, "color", job.color.jsonOrNull { .string($0) })
    update.set(.currency, "currency", .string(job.currency))
    update.set(.isDefault, "is_default", .bool(job.isDefault))
    update.set(.sortOrder, "sort_order", .integer(job.sortOrder))
    update.set(.payrollDay, "payroll_day", job.payrollDay.jsonOrNull { .integer($0) })
    update.set(.halfTaxMonth, "half_tax_month", job.halfTaxMonth.jsonOrNull { .integer($0) })
    try update.set(
      .payPeriod, "pay_period",
      try job.payPeriodJSON.flatMap { $0.data(using: .utf8) }.jsonOrNull {
        try requireAnyJSON($0, table: .jobs, id: job.id, field: "pay_period")
      })
    update.set(.monthlyGoal, "monthly_goal", job.monthlyGoal.jsonOrNull { .integer($0) })
    update.set(
      .archivedAt, "archived_at",
      job.archivedAt.jsonOrNull { .string(formatTimestamp($0)) })
    update.set(
      .deletedAt, "deleted_at",
      job.deletedAt.jsonOrNull { .string(formatTimestamp($0)) })
    return update.data
  }

  func pushJob(
    _ job: LocalJob,
    userId: String,
    storeActor: LocalStoreActor,
    isRetry: Bool
  ) async throws -> PushResult {
    let jobId = job.id

    if job.syncStatus == .pendingDelete {
      return try await pushJobDelete(job, userId: userId, storeActor: storeActor)
    }

    let dirtyFields = job.dirtyFieldKeys
    if dirtyFields.isEmpty {
      await storeActor.markJobClean(id: jobId)
      return .noChange
    }

    if job.serverRevision == 0 {
      return try await insertJob(job, userId: userId, storeActor: storeActor)
    }

    let baseline = SyncPushBaseline(job)
    let updateData = try jobUpdatePayload(for: job, dirtyFields: dirtyFields)

    try requireNonEmptyUpdate(updateData, table: .jobs, id: jobId)

    let outcome: SyncWriteOutcome<SyncJobRow>
    do {
      outcome = try await SyncConvex.update(
        .jobs, owner: job.userId, id: jobId, expectedRevision: job.serverRevision, data: updateData)
    } catch let failure as ConvexAPI.Failure where failure.code == Self.defaultJobExistsCode {
      // Another job is the default. Resolve it like a moved revision: rebase onto the server
      // row and retry once, then mark the conflict with the server row.
      syncCoordinatorLogger.warning(
        "Job \(jobId.prefix(8)) hit the one default job rule on UPDATE, resolving via conflict flow"
      )
      let serverRow: SyncJobRow? = try await SyncConvex.currentRow(
        .jobs, owner: job.userId, id: jobId)
      return try await handleJobPushConflict(
        job: job,
        serverRow: serverRow,
        userId: userId,
        storeActor: storeActor,
        isRetry: isRetry
      )
    }

    switch outcome {
    case .ok(let returnedRow):
      let serverUpdatedAt = parseUpdatedAt(returnedRow.updated_at, table: .jobs, id: jobId)
      let serverArchivedAt = returnedRow.archived_at.flatMap { parseISO8601($0) }
      let serverDeletedAt = returnedRow.deleted_at.flatMap { parseISO8601($0) }
      let serverSnapshot = JobServerSnapshot.from(row: returnedRow, updatedAt: serverUpdatedAt)

      await storeActor.markJobPushed(
        id: jobId,
        serverRow: returnedRow,
        serverUpdatedAt: serverUpdatedAt,
        serverRevision: returnedRow.revision,
        archivedAt: serverArchivedAt,
        deletedAt: serverDeletedAt,
        snapshot: serverSnapshot,
        baseline: baseline
      )

      syncCoordinatorLogger.debug("Pushed job \(jobId.prefix(8))")
      return .success
    case .conflict(let serverRow):
      return try await handleJobPushConflict(
        job: job,
        serverRow: serverRow,
        userId: userId,
        storeActor: storeActor,
        isRetry: isRetry
      )
    }
  }

  private func pushJobDelete(
    _ job: LocalJob,
    userId: String,
    storeActor: LocalStoreActor,
    retryRevision: Int64? = nil
  ) async throws -> PushResult {
    let jobId = job.id

    // A row that was never acknowledged can still exist on the server, when an insert committed
    // but its response was lost. No server row has revision 0, so the remove below reports a
    // conflict, and the row it returns decides whether the row is gone, already deleted or live.
    let outcome: SyncWriteOutcome<SyncJobRow> = try await SyncConvex.remove(
      .jobs, owner: job.userId, id: jobId, expectedRevision: retryRevision ?? job.serverRevision)

    let serverRow: SyncJobRow?
    switch outcome {
    case .ok(let returnedRow):
      let serverUpdatedAt = parseUpdatedAt(returnedRow.updated_at, table: .jobs, id: jobId)
      let serverDeletedAt = returnedRow.deleted_at.flatMap { parseISO8601($0) }
      await storeActor.markJobDeleted(
        id: jobId,
        serverUpdatedAt: serverUpdatedAt,
        serverRevision: returnedRow.revision,
        deletedAt: serverDeletedAt
      )
      syncCoordinatorLogger.debug("Deleted job \(jobId.prefix(8))")
      return .deleted
    case .conflict(let current):
      serverRow = current
    }

    if let serverRow {
      let serverUpdatedAt = parseUpdatedAt(serverRow.updated_at, table: .jobs, id: jobId)
      let serverDeletedAt = serverRow.deleted_at.flatMap { parseISO8601($0) }

      if serverDeletedAt != nil {
        await storeActor.markJobDeleted(
          id: jobId,
          serverUpdatedAt: serverUpdatedAt,
          serverRevision: serverRow.revision,
          deletedAt: serverDeletedAt
        )
        return .deleted
      }

      // Another write moved the revision after this device last saw the row. The user deleted
      // the row, so the delete wins, as the local fields do when an update is rebased. Retry
      // once against the current revision.
      if retryRevision == nil {
        return try await pushJobDelete(
          job, userId: userId, storeActor: storeActor, retryRevision: serverRow.revision)
      }

      let serverSnapshot = JobServerSnapshot.from(row: serverRow, updatedAt: serverUpdatedAt)
      await storeActor.markJobConflict(id: jobId, serverSnapshot: serverSnapshot)
    }

    // The server has no row at all, for example after it purged old soft deleted rows. The row
    // is gone there, which is what the delete wanted. Retire the local row instead of retrying
    // on every sync.
    if serverRow == nil {
      let deletedAt = Date()
      await storeActor.markJobDeleted(
        id: jobId,
        serverUpdatedAt: deletedAt,
        serverRevision: job.serverRevision,
        deletedAt: deletedAt
      )
      return .deleted
    }
    return .conflict
  }

  private func insertJob(
    _ job: LocalJob,
    userId: String,
    storeActor: LocalStoreActor
  ) async throws -> PushResult {
    let jobId = job.id
    let baseline = SyncPushBaseline(job)
    var insertData: [String: AnyJSON] = [
      "id": .string(jobId),
      "user_id": .string(userId),
      "name": .string(job.name),
      "currency": .string(job.currency),
      "is_default": .bool(job.isDefault),
      "sort_order": .integer(job.sortOrder),
    ]

    let optionalColumns: [String: AnyJSON?] = [
      "color": job.color.map { AnyJSON.string($0) },
      "payroll_day": job.payrollDay.map { AnyJSON.integer($0) },
      "half_tax_month": job.halfTaxMonth.map { AnyJSON.integer($0) },
      "pay_period": try job.payPeriodJSON.flatMap { $0.data(using: .utf8) }.map {
        try requireAnyJSON($0, table: .jobs, id: jobId, field: "pay_period")
      },
      "monthly_goal": job.monthlyGoal.map { AnyJSON.integer($0) },
      "archived_at": job.archivedAt.map { AnyJSON.string(formatTimestamp($0)) },
    ]
    insertData.merge(optionalColumns.compactMapValues { $0 }) { _, new in new }

    let outcome: SyncInsertOutcome<SyncJobRow> = try await SyncConvex.insert(
      .jobs, owner: job.userId, row: insertData)

    switch outcome {
    case .ok(let returnedRow):
      let serverUpdatedAt = parseUpdatedAt(returnedRow.updated_at, table: .jobs, id: jobId)
      let serverArchivedAt = returnedRow.archived_at.flatMap { parseISO8601($0) }
      let serverDeletedAt = returnedRow.deleted_at.flatMap { parseISO8601($0) }
      let serverSnapshot = JobServerSnapshot.from(row: returnedRow, updatedAt: serverUpdatedAt)

      await storeActor.markJobPushed(
        id: jobId,
        serverRow: returnedRow,
        serverUpdatedAt: serverUpdatedAt,
        serverRevision: returnedRow.revision,
        archivedAt: serverArchivedAt,
        deletedAt: serverDeletedAt,
        snapshot: serverSnapshot,
        baseline: baseline
      )

      syncCoordinatorLogger.debug("Inserted new job \(jobId.prefix(8))")
      return .success
    case .exists(let serverRow):
      // The row exists, usually because an earlier insert committed after the request timed
      // out locally. Merge onto it.
      syncCoordinatorLogger.warning("Job \(jobId.prefix(8)) already exists on server, merging")
      return try await handleJobPushConflict(
        job: job, serverRow: serverRow, userId: userId, storeActor: storeActor, isRetry: false)
    }
  }

  private func handleJobPushConflict(
    job: LocalJob,
    serverRow: SyncJobRow?,
    userId: String,
    storeActor: LocalStoreActor,
    isRetry: Bool
  ) async throws -> PushResult {
    let jobId = job.id

    guard let serverRow else {
      if job.serverRevision == 0 {
        syncCoordinatorLogger.debug("Job \(jobId.prefix(8)) is new (serverRevision=0), attempting INSERT")
        return try await insertJob(job, userId: userId, storeActor: storeActor)
      }
      syncCoordinatorLogger.debug("Job \(jobId.prefix(8)) was deleted on server")
      await storeActor.markJobConflict(id: jobId, serverSnapshot: nil)
      return .conflict
    }

    let serverUpdatedAt = parseUpdatedAt(serverRow.updated_at, table: .jobs, id: jobId)
    let serverArchivedAt = serverRow.archived_at.flatMap { parseISO8601($0) }
    let serverDeletedAt = serverRow.deleted_at.flatMap { parseISO8601($0) }

    if serverDeletedAt != nil {
      if job.syncStatus == .pendingDelete {
        await storeActor.markJobDeleted(
          id: jobId,
          serverUpdatedAt: serverUpdatedAt,
          serverRevision: serverRow.revision,
          deletedAt: serverDeletedAt
        )
        return .deleted
      }

      let serverSnapshot = JobServerSnapshot.from(row: serverRow, updatedAt: serverUpdatedAt)
      await storeActor.markJobConflict(id: jobId, serverSnapshot: serverSnapshot)
      return .conflict
    }

    let newServerSnapshot = JobServerSnapshot.from(row: serverRow, updatedAt: serverUpdatedAt)
    guard !isRetry else {
      await storeActor.markJobConflict(id: jobId, serverSnapshot: newServerSnapshot)
      return .conflict
    }

    await storeActor.rebaseJob(
      id: jobId,
      serverRow: serverRow,
      serverUpdatedAt: serverUpdatedAt,
      serverRevision: serverRow.revision,
      archivedAt: serverArchivedAt,
      deletedAt: serverDeletedAt,
      newSnapshot: newServerSnapshot
    )

    if let rebasedJob = try await storeActor.jobCopy(id: jobId) {
      let retryResult = try await pushJob(
        rebasedJob, userId: userId, storeActor: storeActor, isRetry: true)
      if retryResult == .success {
        return .rebased
      }
      return retryResult
    }
    return .conflict
  }
}
