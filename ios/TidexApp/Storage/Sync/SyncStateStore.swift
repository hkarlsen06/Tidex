import Foundation
import Observation
import Synchronization
import os.log

internal enum SyncState {
  case idle
  case syncing(userId: String, startedAt: Date)
}

internal enum SyncStartDecision: Equatable {
  /// The sync may run. It passes `generation` back to `endSync`.
  case started(generation: Int)
  case alreadySyncing(generation: Int)
  case skippedInterval
}

internal actor SyncStateStore {
  private var syncState: SyncState = .idle
  private var lastAutoSyncAt: Date?
  private var needsFollowUpSync = false
  private var idleWaiters: [UUID: AsyncStream<Bool>.Continuation] = [:]
  /// Goes up on every reset. A sync that started before the last reset ran for the previous
  /// user, and its `endSync` must not end the sync of the user signed in now.
  private var generation = 0

  internal func beginSync(reason: SyncReason, userId: String, minimumSyncInterval: TimeInterval)
    -> SyncStartDecision
  {
    switch syncState {
    case .syncing:
      if reason.shouldQueueFollowUp {
        needsFollowUpSync = true
      }
      return .alreadySyncing(generation: generation)

    case .idle:
      break
    }

    let requiresIntervalCheck =
      reason != .manualRefresh && reason != .localChange && reason != .remoteChange
    if requiresIntervalCheck,
      let lastAuto = lastAutoSyncAt,
      Date().timeIntervalSince(lastAuto) < minimumSyncInterval
    {
      return .skippedInterval
    }

    // The interval guard starts when a sync succeeds (see endSync). The syncing state above
    // already stops two syncs from starting at once.
    syncState = .syncing(userId: userId, startedAt: Date())
    return .started(generation: generation)
  }

  /// Ends the running sync and returns whether a coalesced follow-up sync is due.
  /// A failed sync clears the interval guard so the next foreground sync can retry at once.
  /// Returns nil and changes nothing when `generation` is from before the last reset.
  internal func endSync(success: Bool, generation: Int) -> Bool? {
    guard generation == self.generation else { return nil }
    syncState = .idle
    lastAutoSyncAt = success ? Date() : nil
    let shouldRunFollowUp = needsFollowUpSync
    needsFollowUpSync = false
    finishIdleWaiters(ready: true)
    return shouldRunFollowUp
  }

  internal func reset() {
    generation += 1
    syncState = .idle
    lastAutoSyncAt = nil
    needsFollowUpSync = false
    finishIdleWaiters(ready: false)
  }

  /// Registration and the idle check share this actor, so completion cannot be missed.
  internal func idleUpdates(generation expectedGeneration: Int? = nil) -> AsyncStream<Bool> {
    let id = UUID()
    return AsyncStream { continuation in
      guard expectedGeneration == nil || expectedGeneration == self.generation else {
        continuation.yield(false)
        continuation.finish()
        return
      }
      guard case .syncing = syncState else {
        continuation.yield(true)
        continuation.finish()
        return
      }
      idleWaiters[id] = continuation
      continuation.onTermination = { [weak self] _ in
        Task { await self?.removeIdleWaiter(id) }
      }
    }
  }

  private func removeIdleWaiter(_ id: UUID) {
    idleWaiters.removeValue(forKey: id)
  }

  private func finishIdleWaiters(ready: Bool) {
    let waiters = idleWaiters.values
    idleWaiters.removeAll()
    for waiter in waiters {
      waiter.yield(ready)
      waiter.finish()
    }
  }
}

extension SyncReason {
  fileprivate var shouldQueueFollowUp: Bool {
    switch self {
    case .localChange, .manualRefresh, .remoteChange:
      return true

    case .appLaunch, .foreground:
      return false
    }
  }
}