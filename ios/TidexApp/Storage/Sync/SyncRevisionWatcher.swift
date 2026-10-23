import Combine
import Foundation
import os.log

private let logger = Logger(subsystem: "no.tidex.app", category: "SyncRevisionWatcher")

/// Subscribes to `sync:revisions`, the newest server revision of each synced table, and pulls
/// the tables that passed the local cursor. Changes made on another device or by the server
/// then reach the screens within a second while the app is open. The screens still read the
/// local store, so the app keeps working offline.
@MainActor
final class SyncRevisionWatcher {
  static let shared = SyncRevisionWatcher()

  private static let retryDelay: Duration = .seconds(10)

  private var userId: String?
  private var subscription: AnyCancellable?
  private var retryTask: Task<Void, Never>?

  private init() {}

  /// Starts the watch for this user. Does nothing when it already runs for them.
  func start(userId: String) async {
    if self.userId == userId, subscription != nil || retryTask != nil { return }
    stop()
    self.userId = userId
    await subscribe(userId: userId)
  }

  func stop() {
    userId = nil
    subscription = nil
    retryTask?.cancel()
    retryTask = nil
  }

  private func subscribe(userId: String) async {
    guard await ConvexRealtime.shared.signIn() else {
      scheduleRetry(userId: userId)
      return
    }
    // Signed out or switched user while the sign-in ran.
    guard self.userId == userId else { return }

    subscription = ConvexRealtime.shared.subscribe(
      to: "sync:revisions",
      onUpdate: { [weak self] (revisions: [String: Double]) in
        self?.pullChangedTables(revisions, userId: userId)
      },
      onFailure: { [weak self] error in
        logger.warning("Revision watch ended: \(error.localizedDescription)")
        self?.subscription = nil
        self?.scheduleRetry(userId: userId)
      }
    )
    if subscription == nil { scheduleRetry(userId: userId) }
  }

  private func scheduleRetry(userId: String) {
    guard self.userId == userId, retryTask == nil else { return }
    retryTask = Task { [weak self] in
      try? await Task.sleep(for: Self.retryDelay)
      guard let self, !Task.isCancelled, self.userId == userId else { return }
      retryTask = nil
      await subscribe(userId: userId)
    }
  }

  private func pullChangedTables(_ revisions: [String: Double], userId: String) {
    guard self.userId == userId else { return }
    let storeActor = LocalStore.shared.storeActor
    Task {
      let state = try? await storeActor.syncStateCopy(userId: userId)
      let changed = SyncTable.allCases.filter { table in
        Int64(revisions[table.tableName] ?? 0) > (state?.cursor(for: table) ?? 0)
      }
      guard !changed.isEmpty, self.userId == userId else { return }
      await SyncCoordinator.shared.sync(reason: .remoteChange, userId: userId, tables: changed)
    }
  }
}
