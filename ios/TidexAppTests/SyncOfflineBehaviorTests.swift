import SwiftData
import XCTest

@testable import Tidex

/// Regression tests for sync behavior when the network or the server misbehaves.
@MainActor
// swiftlint:disable:next type_body_length
internal final class SyncOfflineBehaviorTests: XCTestCase {
  func testPrefetchedPagesKeepMergeOrderWhenTheLaterTableReturnsFirst() async throws {
    let jobsStarted = expectation(description: "Jobs download started")
    let settingsFinished = expectation(description: "Settings downloaded first")
    let pending = PendingLaunchSyncPage()
    let replies = LaunchSyncReplies()
    let task = Task {
      await SyncDownloadedPage.consumePair(
        [(.jobs, 10), (.userSettings, 20)], limit: 500,
        fetch: {
          table, cursor, _ in
          if table == .jobs { return try await pending.wait(started: jobsStarted) }
          settingsFinished.fulfill()
          return .userSettings(SyncPullPage(rows: [], cursor: cursor + 1, done: true))
        }, consume: { _, _, result in await replies.append(result) })
    }
    await fulfillment(of: [jobsStarted, settingsFinished], timeout: 2)
    await pending.complete(.jobs(SyncPullPage(rows: [], cursor: 11, done: true)))
    _ = await task.value
    let pages = await replies.values
    guard case .jobs(let jobs) = try pages[0].get(),
      case .userSettings(let settings) = try pages[1].get()
    else { return XCTFail("Network completion order changed the merge order") }
    XCTAssertEqual(jobs.cursor, 11)
    XCTAssertEqual(settings.cursor, 21)
  }

  func testPrefetchPreservesCompletedPagesAndErrorsForOrderedRetry() async throws {
    let replies = LaunchSyncReplies()
    _ = await SyncDownloadedPage.consumePair(
      [(.jobs, 10), (.userSettings, 20)], limit: 500,
      fetch: {
        table, cursor, _ in
        if table == .userSettings { throw URLError(.notConnectedToInternet) }
        return .jobs(SyncPullPage(rows: [], cursor: cursor + 1, done: true))
      }, consume: { _, _, result in await replies.append(result) })
    let pages = await replies.values
    guard case .jobs(let jobs) = try pages[0].get() else {
      return XCTFail("Completed page was lost")
    }
    XCTAssertEqual(jobs.cursor, 11)
    do {
      _ = try pages[1].get()
      XCTFail("The failed page must remain retryable")
    } catch {
      XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet)
    }
  }

  func testCancellingPrefetchCancelsItsNetworkRequests() async {
    let started = expectation(description: "Download started")
    let replies = LaunchSyncReplies()
    let task = Task {
      await SyncDownloadedPage.consumePair(
        [(.jobs, 0)], limit: 500,
        fetch: { _, _, _ in
          started.fulfill()
          try await Task.sleep(for: .seconds(30))
          return .jobs(SyncPullPage(rows: [], cursor: 1, done: true))
        }, consume: { _, _, result in await replies.append(result) })
    }
    await fulfillment(of: [started], timeout: 2)
    task.cancel()
    _ = await task.value
    let pages = await replies.values
    do {
      _ = try pages[0].get()
      XCTFail("Cancelled prefetch returned a page to merge")
    } catch {
      XCTAssertTrue(SyncCoordinator.isCancellation(error))
    }
  }

  func testSlowSecondDownloadCannotStarveTheFirstPagesDurableCursor() async throws {
    let store = LocalStoreActor(modelContainer: try makeContainer())
    _ = try await store.syncStateCopyCreatingIfNeeded(userId: "user-1")
    await store.updateSyncState(userId: "user-1") { @Sendable state in
      state.updateCursor(for: .jobs, to: 10)
      state.updateCursor(for: .userSettings, to: 20)
    }
    let saved = expectation(description: "Leading page saved while the next download waits")
    let secondStarted = expectation(description: "Second download started")
    let task = Task {
      await SyncDownloadedPage.consumePair(
        [(.jobs, 10), (.userSettings, 20)], limit: 500,
        fetch: {
          table, _, _ in
          if table == .jobs { return .jobs(SyncPullPage(rows: [], cursor: 11, done: true)) }
          secondStarted.fulfill()
          try await Task.sleep(for: .seconds(30))
          return .userSettings(SyncPullPage(rows: [], cursor: 21, done: true))
        },
        consume: { table, _, result in
          guard !Task.isCancelled, case .jobs(let page) = try? result.get() else { return false }
          await store.updateSyncState(userId: "user-1") {
            $0.updateCursor(for: table, to: page.cursor)
          }
          saved.fulfill()
          return true
        })
    }
    await fulfillment(of: [saved, secondStarted], timeout: 2)
    task.cancel()
    _ = await task.value
    let state = try await store.syncStateCopy(userId: "user-1")
    XCTAssertEqual(state?.cursor(for: .jobs), 11)
    XCTAssertEqual(state?.cursor(for: .userSettings), 20)
  }

  private let userId: String = "user-1"

  private func makeContainer() throws -> ModelContainer {
    let schema = Schema([
      LocalJob.self,
      LocalUserShift.self,
      LocalEvent.self,
      LocalRecurringShift.self,
      LocalWageSnapshot.self,
      LocalPayrollAdjustment.self,
      LocalUserSettings.self,
      LocalNotificationPreferences.self,
      LocalSyncState.self,
      LocalSharedShift.self,
      LocalSharer.self,
      LocalShiftPreview.self,
      LocalSharedShiftFetchRecord.self,
      LocalPendingFriendComposerDraft.self,
      LocalThread.self,
      LocalThreadState.self,
      LocalThreadFeedPlacement.self,
      LocalMessage.self,
      LocalMessageAttachment.self,
      LocalMessageReaction.self,
      LocalFriendMessagingSyncState.self,
    ])
    let configuration = ModelConfiguration(
      schema: schema,
      isStoredInMemoryOnly: true,
      allowsSave: true
    )
    return try ModelContainer(for: schema, configurations: [configuration])
  }

  private func makeShift(id: String, in store: LocalStoreActor) async throws -> LocalUserShift {
    _ = try await store.createUserShift(
      id: id,
      userId: userId,
      jobId: "job-1",
      shiftDate: Date.fromDateAndTime("2026-03-02", time: "00:00") ?? Date(),
      startTime: "09:00",
      endTime: "17:00",
      customSupplements: nil
    )
    return try await storedShift(id: id, in: store)
  }

  /// The row as stored now. A copy doesn't follow later changes, so read again after each store call.
  private func storedShift(id: String, in store: LocalStoreActor) async throws -> LocalUserShift {
    let record = try await store.userShiftCopy(id: id)
    return try XCTUnwrap(record)
  }

  private func storedAdjustment(id: String, in store: LocalStoreActor) async throws
    -> LocalPayrollAdjustment
  {
    let record = try await store.payrollAdjustmentCopy(id: id)
    return try XCTUnwrap(record)
  }

  private func makeAdjustment(in store: LocalStoreActor) async throws -> LocalPayrollAdjustment {
    let created = try await store.createPayrollAdjustment(
      userId: userId,
      jobId: nil,
      amount: 500,
      currency: "kr",
      category: .other,
      taxTreatment: .grossTaxable,
      description: "Bonus",
      note: nil,
      earnedFromDate: nil,
      earnedToDate: nil,
      payoutDate: Date()
    )
    return try await storedAdjustment(id: created.id, in: store)
  }

  private func serverShiftRow(id: String, startTime: String, revision: Int64) -> SyncShiftRow {
    SyncShiftRow(
      id: id,
      user_id: userId,
      job_id: "job-1",
      shift_date: "2026-03-02",
      start_time: startTime,
      end_time: "17:00",
      note: nil,
      custom_pause_windows: nil,
      custom_supplements: nil,
      created_at: nil,
      updated_at: ISO8601Timestamp.string(from: Date()),
      revision: revision,
      deleted_at: nil
    )
  }

  private func serverShiftSnapshot(startTime: String, revision: Int64) -> UserShiftServerSnapshot {
    UserShiftServerSnapshot.from(
      jobId: "job-1",
      shiftDate: "2026-03-02",
      startTime: startTime,
      endTime: "17:00",
      note: nil,
      customPauseWindows: nil,
      customSupplements: nil,
      updatedAt: Date(),
      revision: revision,
      deletedAt: nil
    )
  }

  // MARK: - Interval guard after a failed sync

  internal func testFailedSyncClearsIntervalGuard() async {
    let store = SyncStateStore()

    let first = await store.beginSync(reason: .foreground, userId: userId, minimumSyncInterval: 60)
    XCTAssertEqual(first, .started(generation: 0))
    _ = await store.endSync(success: false, generation: 0)

    let second = await store.beginSync(
      reason: .foreground, userId: userId, minimumSyncInterval: 60)
    XCTAssertEqual(
      second, .started(generation: 0), "A failed sync must not suppress the next foreground sync")
  }

  internal func testSuccessfulSyncKeepsIntervalGuard() async {
    let store = SyncStateStore()

    _ = await store.beginSync(reason: .foreground, userId: userId, minimumSyncInterval: 60)
    _ = await store.endSync(success: true, generation: 0)

    let foreground = await store.beginSync(
      reason: .foreground, userId: userId, minimumSyncInterval: 60)
    XCTAssertEqual(foreground, .skippedInterval)
    _ = await store.endSync(success: true, generation: 0)

    let manual = await store.beginSync(
      reason: .manualRefresh, userId: userId, minimumSyncInterval: 60)
    XCTAssertEqual(manual, .started(generation: 0), "A manual refresh ignores the interval guard")
  }

  internal func testSecondSyncCannotStartWhileOneRuns() async {
    let store = SyncStateStore()

    let first = await store.beginSync(reason: .foreground, userId: userId, minimumSyncInterval: 60)
    let second = await store.beginSync(
      reason: .localChange, userId: userId, minimumSyncInterval: 60)

    XCTAssertEqual(first, .started(generation: 0))
    XCTAssertEqual(second, .alreadySyncing(generation: 0))
    let followUp = await store.endSync(success: true, generation: 0)
    XCTAssertEqual(followUp, true, "A local change during a sync queues a follow-up sync")
  }

  internal func testManualRefreshWaitsForRunningSyncCompletion() async {
    let store = SyncStateStore()
    _ = await store.beginSync(reason: .foreground, userId: userId, minimumSyncInterval: 60)
    let updates = await store.idleUpdates(generation: 0)
    _ = await store.endSync(success: true, generation: 0)
    var ready = false
    for await value in updates { ready = value }
    XCTAssertTrue(ready)
    let refresh = await store.beginSync(
      reason: .manualRefresh, userId: userId, minimumSyncInterval: 60)
    XCTAssertEqual(refresh, .started(generation: 0))
  }

  internal func testManualRefreshDoesNotMissCompletionBeforeItStartsWaiting() async {
    let store = SyncStateStore()
    _ = await store.beginSync(reason: .foreground, userId: userId, minimumSyncInterval: 60)
    _ = await store.endSync(success: false, generation: 0)
    let updates = await store.idleUpdates(generation: 0)
    var ready = false
    for await value in updates { ready = value }
    XCTAssertTrue(ready)
  }

  internal func testAccountResetStopsWaitingRefreshForPreviousUser() async {
    let store = SyncStateStore()
    _ = await store.beginSync(reason: .foreground, userId: userId, minimumSyncInterval: 60)
    let updates = await store.idleUpdates(generation: 0)
    await store.reset()
    var ready = true
    for await value in updates { ready = value }
    XCTAssertFalse(ready)
    let lateUpdates = await store.idleUpdates(generation: 0)
    for await value in lateUpdates { XCTAssertFalse(value) }
  }

  internal func testCancelledManualRefreshStopsWaiting() async {
    let store = SyncStateStore()
    _ = await store.beginSync(reason: .foreground, userId: userId, minimumSyncInterval: 60)
    let updates = await store.idleUpdates(generation: 0)
    let waiter = Task {
      for await _ in updates { return true }
      return false
    }
    waiter.cancel()
    let completed = await waiter.value
    XCTAssertFalse(completed)
  }

  // MARK: - Sync outcome

  /// Stands in for the sync work, which returns `.cancelled` when its task is cancelled.
  private nonisolated static func slowSync() async -> SyncResult {
    let finished = (try? await Task.sleep(for: .seconds(60))) != nil
    return SyncResult(outcome: finished ? .completed : .cancelled)
  }

  /// SwiftUI cancels a refresh when the user leaves the screen. That used to show "Sync timed out".
  internal func testCancelledSyncIsNotReportedAsTimeout() async {
    let sync = Task {
      await SyncCoordinator.race(timeout: .seconds(30), startTime: Date()) {
        await Self.slowSync()
      }
    }
    sync.cancel()
    let result = await sync.value
    XCTAssertEqual(result.outcome, .cancelled)
  }

  internal func testSyncPastTheTimeLimitTimesOut() async {
    let result = await SyncCoordinator.race(timeout: .milliseconds(50), startTime: Date()) {
      await Self.slowSync()
    }
    XCTAssertEqual(result.outcome, .timedOut)
  }

  internal func testCancelledRefreshRestoresTheEarlierStatus() {
    let status = SyncStatusManager()
    status.setOffline()
    status.syncStarted()
    status.syncCancelled()
    XCTAssertEqual(status.status, .offline, "A cancelled refresh neither fails nor claims a sync")
  }

  /// An account switch resets the store while the old user's sync is still winding down. When
  /// that sync ends, the new user's sync must keep running, so a second one can't start beside it.
  internal func testSyncFromBeforeResetDoesNotEndTheNextUsersSync() async {
    let store = SyncStateStore()

    let oldUserSync = await store.beginSync(
      reason: .foreground, userId: userId, minimumSyncInterval: 60)
    await store.reset()
    let newUserSync = await store.beginSync(
      reason: .appLaunch, userId: "other-user", minimumSyncInterval: 60)
    XCTAssertEqual(oldUserSync, .started(generation: 0))
    XCTAssertEqual(newUserSync, .started(generation: 1))

    let staleEnd = await store.endSync(success: false, generation: 0)
    XCTAssertNil(staleEnd)
    let overlapping = await store.beginSync(
      reason: .foreground, userId: "other-user", minimumSyncInterval: 60)
    XCTAssertEqual(
      overlapping, .alreadySyncing(generation: 1), "The new user's sync is still running")

    let end = await store.endSync(success: true, generation: 1)
    XCTAssertNotNil(end, "The new user's own sync ends normally")
  }

  // MARK: - Sign-out guard

  internal func testConflictWithServerRevisionCountsAsPendingChange() async throws {
    let store = LocalStoreActor(modelContainer: try makeContainer())
    _ = try await makeShift(id: "shift-1", in: store)
    await store.resolveShiftConflictKeepServer(
      id: "shift-1", serverSnapshot: serverShiftSnapshot(startTime: "09:00", revision: 3))
    let cleanHasPending = try await store.hasPendingChanges(userId: userId)
    XCTAssertFalse(cleanHasPending)

    await store.markShiftConflict(id: "shift-1", serverSnapshot: nil)

    let hasPending = try await store.hasPendingChanges(userId: userId)
    XCTAssertTrue(hasPending, "A conflicted row holds a local edit that sign-out would delete")
  }

  internal func testPayrollAdjustmentConflictIsCounted() async throws {
    let store = LocalStoreActor(modelContainer: try makeContainer())
    let adjustment = try await makeAdjustment(in: store)
    await store.markPayrollAdjustmentClean(id: adjustment.id)
    let cleanCount = try await store.countConflicts(userId: userId)
    XCTAssertEqual(cleanCount, 0)

    await store.markPayrollAdjustmentConflict(id: adjustment.id, serverSnapshot: nil)

    let conflictIds = try await store.conflictedPayrollAdjustmentIds(userId: userId)
    XCTAssertEqual(conflictIds, [adjustment.id])
    let count = try await store.countConflicts(userId: userId)
    XCTAssertEqual(count, 1)
    let hasConflicts = try await store.hasConflicts(userId: userId)
    XCTAssertTrue(hasConflicts)
    let hasPending = try await store.hasPendingChanges(userId: userId)
    XCTAssertTrue(hasPending)
  }

  internal func testDirtyNotificationPreferencesCountAsPendingChange() async throws {
    let container = try makeContainer()
    let store = LocalStoreActor(modelContainer: container)
    let context = ModelContext(container)
    // The repository stores the user id in upper case.
    context.insert(LocalNotificationPreferences(userId: "USER-1", syncStatus: .dirty))
    try context.save()

    let hasPending = try await store.hasPendingChanges(userId: userId)

    XCTAssertTrue(hasPending)
  }

  internal func testCleanNotificationPreferencesAreNotPending() async throws {
    let container = try makeContainer()
    let store = LocalStoreActor(modelContainer: container)
    let context = ModelContext(container)
    context.insert(LocalNotificationPreferences(userId: "USER-1", syncStatus: .clean))
    try context.save()

    let hasPending = try await store.hasPendingChanges(userId: userId)

    XCTAssertFalse(hasPending)
  }

  internal func testUnsentMessagesCountAsPendingChange() async throws {
    let container = try makeContainer()
    let store = LocalStoreActor(modelContainer: container)
    let context = ModelContext(container)
    for (index, state) in [FriendMessageSendState.sent, .sending, .failed].enumerated() {
      context.insert(
        LocalMessage(
          id: "message-\(index)",
          viewerUserId: userId,
          threadId: "thread-1",
          senderUserId: userId,
          messageTypeRaw: "text",
          body: "Hi",
          clientId: "client-\(index)",
          replyToMessageId: nil,
          createdAt: Date(),
          editedAt: nil,
          deletedAt: nil,
          sendStateRaw: state.rawValue
        ))
    }
    try context.save()

    let hasUnsent = try await store.hasUnsentMessages(userId: userId)
    XCTAssertTrue(hasUnsent)
    let otherUser = try await store.hasUnsentMessages(userId: "user-2")
    XCTAssertFalse(otherUser)
  }

  internal func testSentMessagesAreNotPending() async throws {
    let container = try makeContainer()
    let store = LocalStoreActor(modelContainer: container)
    let context = ModelContext(container)
    context.insert(
      LocalMessage(
        id: "message-1",
        viewerUserId: userId,
        threadId: "thread-1",
        senderUserId: userId,
        messageTypeRaw: "text",
        body: "Hi",
        clientId: "client-1",
        replyToMessageId: nil,
        createdAt: Date(),
        editedAt: nil,
        deletedAt: nil,
        sendStateRaw: FriendMessageSendState.sent.rawValue
      ))
    try context.save()

    let hasPending = try await store.hasPendingChanges(userId: userId)

    XCTAssertFalse(hasPending)
  }

  // MARK: - Switching users

  // Starting or ending an impersonation clears the local store, so it must first push the
  // changes and refuse while some are still only on this device.

  internal func testUnpushedShiftIsNotSafeToClear() async throws {
    let store = LocalStoreActor(modelContainer: try makeContainer())
    _ = try await makeShift(id: "shift-1", in: store)

    // Offline: the push sends nothing.
    let canClear = await AppCoordinator.pushPendingChanges(userId: userId, store: store) { _ in }

    XCTAssertFalse(canClear)
    let stored = try await storedShift(id: "shift-1", in: store)
    XCTAssertEqual(stored.syncStatus, .dirty)
  }

  internal func testPushedShiftIsSafeToClear() async throws {
    let store = LocalStoreActor(modelContainer: try makeContainer())
    _ = try await makeShift(id: "shift-1", in: store)

    let canClear = await AppCoordinator.pushPendingChanges(userId: userId, store: store) { _ in
      await store.markShiftClean(id: "shift-1")
    }

    XCTAssertTrue(canClear)
  }

  internal func testUnknownUserIsNeverSafeToClear() async throws {
    let store = LocalStoreActor(modelContainer: try makeContainer())

    let canClear = await AppCoordinator.pushPendingChanges(userId: nil, store: store) { _ in }

    XCTAssertFalse(canClear)
  }

  // MARK: - Never pushed delete

  internal func testRetiredNeverPushedShiftIsNoLongerDirty() async throws {
    let store = LocalStoreActor(modelContainer: try makeContainer())
    let shift = try await makeShift(id: "shift-1", in: store)
    _ = try await store.markShiftPendingDelete(id: "shift-1")
    let dirtyBefore = try await store.dirtyUserShiftCopies(userId: userId)
    XCTAssertEqual(dirtyBefore.map(\.id), ["shift-1"])
    XCTAssertEqual(shift.serverRevision, 0)

    // This is what the push does for a pending delete with serverRevision 0.
    let deletedAt = Date()
    await store.markShiftDeleted(
      id: "shift-1", serverUpdatedAt: deletedAt, serverRevision: 0, serverDeletedAt: deletedAt)

    let dirtyAfter = try await store.dirtyUserShiftCopies(userId: userId)
    XCTAssertTrue(dirtyAfter.isEmpty)
    let stored = try await storedShift(id: "shift-1", in: store)
    XCTAssertEqual(stored.syncStatus, .clean)
    XCTAssertNotNil(stored.serverDeletedAt)
    let hasPending = try await store.hasPendingChanges(userId: userId)
    XCTAssertFalse(hasPending)
  }

  // MARK: - Pull does not overwrite a row that became dirty

  internal func testPullDoesNotOverwriteDirtyShift() async throws {
    let store = LocalStoreActor(modelContainer: try makeContainer())
    let shift = try await makeShift(id: "shift-1", in: store)
    XCTAssertEqual(shift.syncStatus, .dirty)

    let applied = await store.updateShiftFromServer(
      id: "shift-1",
      serverRow: serverShiftRow(id: "shift-1", startTime: "08:00", revision: 2),
      serverUpdatedAt: Date(),
      serverRevision: 2,
      serverDeletedAt: nil,
      snapshot: serverShiftSnapshot(startTime: "08:00", revision: 2)
    )

    XCTAssertFalse(applied, "The overwrite must be refused for a dirty row")
    let stored = try await storedShift(id: "shift-1", in: store)
    XCTAssertEqual(stored.startTime, "09:00")
    XCTAssertEqual(stored.syncStatus, .dirty)
    XCTAssertEqual(stored.serverRevision, 0)
  }

  internal func testPullOverwritesCleanShift() async throws {
    let store = LocalStoreActor(modelContainer: try makeContainer())
    _ = try await makeShift(id: "shift-1", in: store)
    await store.markShiftClean(id: "shift-1")

    let applied = await store.updateShiftFromServer(
      id: "shift-1",
      serverRow: serverShiftRow(id: "shift-1", startTime: "08:00", revision: 2),
      serverUpdatedAt: Date(),
      serverRevision: 2,
      serverDeletedAt: nil,
      snapshot: serverShiftSnapshot(startTime: "08:00", revision: 2)
    )

    XCTAssertTrue(applied)
    let stored = try await storedShift(id: "shift-1", in: store)
    XCTAssertEqual(stored.startTime, "08:00")
    XCTAssertEqual(stored.serverRevision, 2)
  }

  internal func testPullDoesNotOverwriteDirtyPayrollAdjustment() async throws {
    let store = LocalStoreActor(modelContainer: try makeContainer())
    let adjustment = try await makeAdjustment(in: store)
    let row = SyncPayrollAdjustmentRow(
      id: adjustment.id,
      user_id: userId,
      job_id: nil,
      amount: 900,
      currency: "kr",
      category: .other,
      tax_treatment: .grossTaxable,
      description: "Bonus",
      note: nil,
      curated_note: nil,
      curated_description: nil,
      curated_link: nil,
      curated_link_title: nil,
      earned_from_date: nil,
      earned_to_date: nil,
      payout_date: "2026-03-02",
      created_at: nil,
      updated_at: ISO8601Timestamp.string(from: Date()),
      revision: 2,
      deleted_at: nil
    )
    let snapshot = PayrollAdjustmentServerSnapshot.from(
      row: row, updatedAt: Date(), deletedAt: nil)

    let applied = await store.updatePayrollAdjustmentFromServer(
      id: adjustment.id,
      serverRow: row,
      serverUpdatedAt: Date(),
      serverDeletedAt: nil,
      snapshot: snapshot,
      onlyIfClean: true
    )

    XCTAssertFalse(applied)
    let stored = try await storedAdjustment(id: adjustment.id, in: store)
    XCTAssertEqual(stored.amount, 500)
    XCTAssertEqual(stored.syncStatus, .dirty)
  }

  // swiftlint:disable:next function_body_length
  internal func testPayrollAdjustmentEditKeepsAnotherDevicesChangeToOtherFields() async throws {
    let store = LocalStoreActor(modelContainer: try makeContainer())
    let adjustment = try await makeAdjustment(in: store)
    await store.markPayrollAdjustmentClean(id: adjustment.id)

    // The editor saves every field, but only the note changed.
    _ = try await store.updatePayrollAdjustment(
      id: adjustment.id,
      jobId: nil,
      amount: 500,
      currency: "kr",
      category: .other,
      taxTreatment: .grossTaxable,
      description: "Bonus",
      note: "Local note",
      earnedFromDate: nil,
      earnedToDate: nil,
      payoutDate: adjustment.payoutDate
    )
    let edited = try await storedAdjustment(id: adjustment.id, in: store)
    XCTAssertEqual(edited.dirtyFieldKeys, [.note])

    // Another device changed the amount. The merge takes it and keeps the unpushed note.
    let row = SyncPayrollAdjustmentRow(
      id: adjustment.id,
      user_id: userId,
      job_id: nil,
      amount: 900,
      currency: "kr",
      category: .other,
      tax_treatment: .grossTaxable,
      description: "Bonus",
      note: nil,
      curated_note: nil,
      curated_description: nil,
      curated_link: nil,
      curated_link_title: nil,
      earned_from_date: nil,
      earned_to_date: nil,
      payout_date: adjustment.payoutDateString,
      created_at: nil,
      updated_at: ISO8601Timestamp.string(from: Date()),
      revision: 2,
      deleted_at: nil
    )
    await store.mergePayrollAdjustmentFromServer(
      id: adjustment.id,
      serverRow: row,
      serverUpdatedAt: Date(),
      serverDeletedAt: nil,
      snapshot: PayrollAdjustmentServerSnapshot.from(row: row, updatedAt: Date(), deletedAt: nil)
    )

    let merged = try await storedAdjustment(id: adjustment.id, in: store)
    XCTAssertEqual(merged.amount, 900)
    XCTAssertEqual(merged.note, "Local note")
    XCTAssertEqual(merged.dirtyFieldKeys, [.note])
    XCTAssertEqual(merged.syncStatus, .dirty)
    XCTAssertEqual(merged.serverRevision, 2)
  }

  // MARK: - Payroll adjustment conflict resolution

  internal func testKeepLocalRequeuesPayrollAdjustmentAsWholeRow() async throws {
    let store = LocalStoreActor(modelContainer: try makeContainer())
    let adjustment = try await makeAdjustment(in: store)
    await store.markPayrollAdjustmentClean(id: adjustment.id)
    await store.markPayrollAdjustmentConflict(id: adjustment.id, serverSnapshot: nil)

    await store.resolvePayrollAdjustmentConflictKeepLocal(id: adjustment.id, serverRevision: 4)

    let stored = try await storedAdjustment(id: adjustment.id, in: store)
    XCTAssertEqual(stored.syncStatus, .dirty)
    XCTAssertEqual(stored.serverRevision, 4)
    XCTAssertEqual(stored.dirtyFieldKeys, Set(PayrollAdjustmentField.allCases))
    XCTAssertNil(stored.conflictServerSnapshot)
  }

  internal func testKeepServerRestoresPayrollAdjustmentFromSnapshot() async throws {
    let store = LocalStoreActor(modelContainer: try makeContainer())
    let adjustment = try await makeAdjustment(in: store)
    let snapshot = PayrollAdjustmentServerSnapshot(
      jobId: nil,
      amount: 900,
      currency: "kr",
      category: .other,
      taxTreatment: .grossTaxable,
      description: "Server bonus",
      note: nil,
      curatedNote: nil,
      curatedDescription: nil,
      curatedLink: nil,
      curatedLinkTitle: nil,
      earnedFromDate: nil,
      earnedToDate: nil,
      payoutDate: "2026-03-02",
      updatedAt: Date(),
      revision: 5,
      deletedAt: nil
    )
    await store.markPayrollAdjustmentConflict(id: adjustment.id, serverSnapshot: snapshot)

    await store.resolvePayrollAdjustmentConflictKeepServer(
      id: adjustment.id, serverSnapshot: snapshot)

    let stored = try await storedAdjustment(id: adjustment.id, in: store)
    XCTAssertEqual(stored.amount, 900)
    XCTAssertEqual(stored.descriptionText, "Server bonus")
    XCTAssertEqual(stored.serverRevision, 5)
    XCTAssertEqual(stored.syncStatus, .clean)
    XCTAssertEqual(stored.dirtyFieldKeys, [])
  }

  // MARK: - Notification preferences edited during a push

  internal func testEditDuringPushKeepsNotificationPreferencesDirty() {
    let pushedAt = Date(timeIntervalSince1970: 1_000)
    let preferences = LocalNotificationPreferences(
      userId: "USER-1", syncStatus: .dirty, localUpdatedAt: pushedAt)

    // The user edits the preferences after the push request was built.
    preferences.markDirty()
    preferences.markPushed(serverUpdatedAt: Date(), pushedLocalUpdatedAt: pushedAt)

    XCTAssertEqual(preferences.syncStatus, .dirty)
  }

  internal func testUnchangedNotificationPreferencesBecomeCleanAfterPush() {
    let pushedAt = Date(timeIntervalSince1970: 1_000)
    let preferences = LocalNotificationPreferences(
      userId: "USER-1", syncStatus: .dirty, localUpdatedAt: pushedAt)

    preferences.markPushed(serverUpdatedAt: Date(), pushedLocalUpdatedAt: pushedAt)

    XCTAssertEqual(preferences.syncStatus, .clean)
  }

  // MARK: - Pull poison row

  internal func testConvexCursorResetStartsEveryTableAtZeroOnce() {
    let state = LocalSyncState(userId: userId, lastRevisionUserShifts: 812, lastRevisionJobs: 9)
    state.updateCursor(for: .events, to: 40)
    XCTAssertNil(state.convexCursorsResetAt)

    state.resetCursorsForConvex(at: Date(timeIntervalSince1970: 5))

    for table in SyncTable.allCases {
      XCTAssertEqual(state.cursor(for: table), 0, table.rawValue)
    }
    XCTAssertEqual(state.convexCursorsResetAt, Date(timeIntervalSince1970: 5))

    state.updateCursor(for: .jobs, to: 7)
    XCTAssertEqual(state.cursor(for: .jobs), 7)
    XCTAssertEqual(state.cursor(for: .userShifts), 0)
  }

  internal func testOnlyDataErrorsCountAsUnreadableRows() {
    XCTAssertTrue(
      SyncCoordinator.isUnreadableRowError(
        SyncError.dateParsingFailed(table: .userShifts, id: "a", rawValue: "bad")))
    XCTAssertTrue(
      SyncCoordinator.isUnreadableRowError(SyncEncodingError.emptyUpdatePayload(type: "x")))
    XCTAssertFalse(
      SyncCoordinator.isUnreadableRowError(
        SyncError.localSaveFailed(table: .userShifts, message: "disk full")))
    XCTAssertFalse(SyncCoordinator.isUnreadableRowError(URLError(.notConnectedToInternet)))
  }

  deinit {
    // Required by SwiftLint for XCTestCase subclasses.
  }
}

private actor PendingLaunchSyncPage {
  private var continuation: CheckedContinuation<SyncDownloadedPage, Error>?

  func wait(started: XCTestExpectation) async throws -> SyncDownloadedPage {
    try await withCheckedThrowingContinuation {
      continuation = $0
      started.fulfill()
    }
  }

  func complete(_ page: SyncDownloadedPage) {
    continuation?.resume(returning: page)
    continuation = nil
  }
}

private actor LaunchSyncReplies {
  private(set) var values: [Result<SyncDownloadedPage, Error>] = []

  func append(_ result: Result<SyncDownloadedPage, Error>) -> Bool {
    values.append(result)
    return true
  }
}
