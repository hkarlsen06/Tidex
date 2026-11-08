import Foundation
import Observation
import Synchronization
import os.log

extension SyncCoordinator {

  // MARK: - Events Push

  func pushEvents(userId: String) async throws -> TablePushResult {
    let storeActor = await MainActor.run { LocalStore.shared.storeActor }
    let dirtyEvents = try await storeActor.dirtyEventCopies(userId: userId)

    if dirtyEvents.isEmpty {
      return TablePushResult(table: .events, rowsPushed: 0, newConflicts: 0, rebased: 0)
    }

    var rowsPushed = 0
    var failedRows = 0
    var newConflicts = 0
    var rebased = 0

    for event in dirtyEvents {
      let eventId = event.id
      let result: PushResult
      do {
        result = try await pushEvent(
          event, userId: userId, storeActor: storeActor, isRetry: false)
      } catch let error where Self.isRowRejection(error) {
        syncCoordinatorLogger.error("Server rejected event \(eventId.prefix(8)): \(error.localizedDescription)")
        await storeActor.markEventConflict(id: eventId, serverSnapshot: nil)
        result = .conflict
      } catch {
        try await skipRowUnlessFatal(error, table: .events, id: eventId)
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
      table: .events,
      rowsPushed: rowsPushed,
      newConflicts: newConflicts,
      rebased: rebased,
      failedRows: failedRows
    )
  }

  func pushEvent(
    _ event: LocalEvent,
    userId: String,
    storeActor: LocalStoreActor,
    isRetry: Bool
  ) async throws -> PushResult {
    let eventId = event.id

    if event.syncStatus == .pendingDelete {
      return try await pushEventDelete(event, userId: userId, storeActor: storeActor)
    }

    let dirtyFields = event.dirtyFieldKeys
    if dirtyFields.isEmpty {
      await storeActor.markEventClean(id: eventId)
      return .noChange
    }

    if event.serverRevision == 0 {
      return try await insertEvent(event, userId: userId, storeActor: storeActor)
    }

    let baseline = SyncPushBaseline(event)
    var updateData: [String: AnyJSON] = [:]
    if dirtyFields.contains(.startDate) {
      updateData["start_date"] = .string(event.startDateString)
    }
    if dirtyFields.contains(.endDate) {
      updateData["end_date"] = .string(event.endDateString)
    }
    if dirtyFields.contains(.isAllDay) {
      updateData["is_all_day"] = .bool(event.isAllDay)
    }
    if dirtyFields.contains(.startTime) {
      if let startTime = event.startTime {
        updateData["start_time"] = .string(startTime)
      } else {
        updateData["start_time"] = .null
      }
    }
    if dirtyFields.contains(.endTime) {
      if let endTime = event.endTime {
        updateData["end_time"] = .string(endTime)
      } else {
        updateData["end_time"] = .null
      }
    }
    if dirtyFields.contains(.note) {
      updateData["note"] = .string(event.note)
    }
    if dirtyFields.contains(.notificationMinutesArray) {
      updateData["notification_minutes_array"] =
        event.notificationMinutesArray.isEmpty
        ? .array([])
        : .array(event.notificationMinutesArray.map { .integer($0) })
    }
    if dirtyFields.contains(.notificationAnchorTime) {
      if let notificationAnchorTime = event.notificationAnchorTime {
        updateData["notification_anchor_time"] = .string(notificationAnchorTime)
      } else {
        updateData["notification_anchor_time"] = .null
      }
    }

    try requireNonEmptyUpdate(updateData, table: .events, id: eventId)

    let outcome: SyncWriteOutcome<SyncEventRow> = try await SyncConvex.update(
      .events, owner: event.userId, id: eventId,
      expectedRevision: event.serverRevision, data: updateData)

    switch outcome {
    case .ok(let returnedRow):
      let serverUpdatedAt = parseUpdatedAt(returnedRow.updated_at, table: .events, id: eventId)
      let serverDeletedAt = returnedRow.deleted_at.flatMap { parseISO8601($0) }
      let serverSnapshot = EventServerSnapshot.from(
        serverRow: returnedRow,
        updatedAt: serverUpdatedAt,
        deletedAt: serverDeletedAt
      )

      await storeActor.markEventPushed(
        id: eventId,
        serverRow: returnedRow,
        serverUpdatedAt: serverUpdatedAt,
        serverRevision: returnedRow.revision,
        snapshot: serverSnapshot,
        baseline: baseline
      )

      syncCoordinatorLogger.debug("Pushed event \(eventId.prefix(8))")
      return .success
    case .conflict(let serverRow):
      return try await handleEventPushConflict(
        event: event,
        serverRow: serverRow,
        userId: userId,
        storeActor: storeActor,
        isRetry: isRetry
      )
    }
  }

  private func pushEventDelete(
    _ event: LocalEvent,
    userId: String,
    storeActor: LocalStoreActor,
    retryRevision: Int64? = nil
  ) async throws -> PushResult {
    let eventId = event.id

    // A row that was never acknowledged can still exist on the server, when an insert committed
    // but its response was lost. No server row has revision 0, so the remove below reports a
    // conflict, and the row it returns decides whether the row is gone, already deleted or live.
    let outcome: SyncWriteOutcome<SyncEventRow> = try await SyncConvex.remove(
      .events, owner: event.userId, id: eventId,
      expectedRevision: retryRevision ?? event.serverRevision)

    let serverRow: SyncEventRow?
    switch outcome {
    case .ok(let returnedRow):
      let serverUpdatedAt = parseUpdatedAt(returnedRow.updated_at, table: .events, id: eventId)
      let serverDeletedAt = returnedRow.deleted_at.flatMap { parseISO8601($0) }

      await storeActor.markEventDeleted(
        id: eventId,
        serverUpdatedAt: serverUpdatedAt,
        serverRevision: returnedRow.revision,
        serverDeletedAt: serverDeletedAt
      )

      syncCoordinatorLogger.debug("Deleted event \(eventId.prefix(8))")
      return .deleted
    case .conflict(let current):
      serverRow = current
    }

    if let serverRow {
      let serverUpdatedAt = parseUpdatedAt(serverRow.updated_at, table: .events, id: eventId)
      let serverDeletedAt = serverRow.deleted_at.flatMap { parseISO8601($0) }

      if serverDeletedAt != nil {
        await storeActor.markEventDeleted(
          id: eventId,
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
        return try await pushEventDelete(
          event, userId: userId, storeActor: storeActor, retryRevision: serverRow.revision)
      }

      let serverSnapshot = EventServerSnapshot.from(
        serverRow: serverRow,
        updatedAt: serverUpdatedAt,
        deletedAt: serverDeletedAt
      )
      await storeActor.markEventConflict(id: eventId, serverSnapshot: serverSnapshot)
    }
    // The server has no row at all, for example after it purged old soft deleted rows. The row
    // is gone there, which is what the delete wanted. Retire the local row instead of retrying
    // on every sync.
    if serverRow == nil {
      let deletedAt = Date()
      await storeActor.markEventDeleted(
        id: eventId,
        serverUpdatedAt: deletedAt,
        serverRevision: event.serverRevision,
        serverDeletedAt: deletedAt
      )
      return .deleted
    }
    return .conflict
  }

  private func insertEvent(
    _ event: LocalEvent,
    userId: String,
    storeActor: LocalStoreActor
  ) async throws -> PushResult {
    let eventId = event.id
    let baseline = SyncPushBaseline(event)
    var insertData: [String: AnyJSON] = [
      "id": .string(eventId),
      "user_id": .string(userId),
      "start_date": .string(event.startDateString),
      "end_date": .string(event.endDateString),
      "is_all_day": .bool(event.isAllDay),
      "note": .string(event.note),
    ]

    if let startTime = event.startTime {
      insertData["start_time"] = .string(startTime)
    }
    if let endTime = event.endTime {
      insertData["end_time"] = .string(endTime)
    }
    if !event.notificationMinutesArray.isEmpty {
      insertData["notification_minutes_array"] = .array(
        event.notificationMinutesArray.map { .integer($0) }
      )
    }
    if let notificationAnchorTime = event.notificationAnchorTime {
      insertData["notification_anchor_time"] = .string(notificationAnchorTime)
    }

    let outcome: SyncInsertOutcome<SyncEventRow> = try await SyncConvex.insert(
      .events, owner: event.userId, row: insertData)

    switch outcome {
    case .ok(let returnedRow):
      let serverUpdatedAt = parseUpdatedAt(returnedRow.updated_at, table: .events, id: eventId)
      let serverDeletedAt = returnedRow.deleted_at.flatMap { parseISO8601($0) }
      let serverSnapshot = EventServerSnapshot.from(
        serverRow: returnedRow,
        updatedAt: serverUpdatedAt,
        deletedAt: serverDeletedAt
      )

      await storeActor.markEventPushed(
        id: eventId,
        serverRow: returnedRow,
        serverUpdatedAt: serverUpdatedAt,
        serverRevision: returnedRow.revision,
        snapshot: serverSnapshot,
        baseline: baseline
      )

      syncCoordinatorLogger.debug("Inserted new event \(eventId.prefix(8))")
      return .success
    case .exists(let serverRow):
      // The row exists, usually because an earlier insert committed after the request timed
      // out locally. Merge onto it.
      syncCoordinatorLogger.warning("Event \(event.id.prefix(8)) already exists on server, merging")
      return try await handleEventPushConflict(
        event: event, serverRow: serverRow, userId: userId, storeActor: storeActor,
        isRetry: false)
    }
  }

  private func handleEventPushConflict(
    event: LocalEvent,
    serverRow: SyncEventRow?,
    userId: String,
    storeActor: LocalStoreActor,
    isRetry: Bool
  ) async throws -> PushResult {
    let eventId = event.id

    guard let serverRow else {
      if event.serverRevision == 0 {
        syncCoordinatorLogger.debug("Event \(eventId.prefix(8)) is new (serverRevision=0), attempting INSERT")
        return try await insertEvent(event, userId: userId, storeActor: storeActor)
      }
      syncCoordinatorLogger.debug("Event \(eventId.prefix(8)) was deleted on server")
      await storeActor.markEventConflict(id: eventId, serverSnapshot: nil)
      return .conflict
    }

    let serverUpdatedAt = parseUpdatedAt(serverRow.updated_at, table: .events, id: eventId)
    let serverDeletedAt = serverRow.deleted_at.flatMap { parseISO8601($0) }

    if serverDeletedAt != nil {
      let serverSnapshot = EventServerSnapshot.from(
        serverRow: serverRow,
        updatedAt: serverUpdatedAt,
        deletedAt: serverDeletedAt
      )
      await storeActor.markEventConflict(id: eventId, serverSnapshot: serverSnapshot)
      return .conflict
    }

    let newServerSnapshot = EventServerSnapshot.from(
      serverRow: serverRow,
      updatedAt: serverUpdatedAt,
      deletedAt: serverDeletedAt
    )
    guard !isRetry else {
      await storeActor.markEventConflict(id: eventId, serverSnapshot: newServerSnapshot)
      return .conflict
    }

    await storeActor.rebaseEvent(
      id: eventId,
      serverRow: serverRow,
      serverUpdatedAt: serverUpdatedAt,
      serverRevision: serverRow.revision,
      serverDeletedAt: serverDeletedAt,
      newSnapshot: newServerSnapshot
    )

    if let rebasedEvent = try await storeActor.eventCopy(id: eventId) {
      let retryResult = try await pushEvent(
        rebasedEvent, userId: userId, storeActor: storeActor, isRetry: true)
      if retryResult == .success {
        return .rebased
      }
      return retryResult
    }
    return .conflict
  }
}
