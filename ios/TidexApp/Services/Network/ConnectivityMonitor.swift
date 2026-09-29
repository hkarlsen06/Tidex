import Foundation
import Network
import Observation

/// What a network path update means for the app.
enum ConnectivityTransition: Equatable {
  case none
  case wentOnline
  case wentOffline

  static func between(wasOnline: Bool, isOnline: Bool) -> ConnectivityTransition {
    switch (wasOnline, isOnline) {
    case (false, true): return .wentOnline
    case (true, false): return .wentOffline
    default: return .none
    }
  }
}

/// Watches network reachability. Marks the sync indicator offline when the path drops
/// and asks AppCoordinator to sync when it comes back.
@MainActor
@Observable
final class ConnectivityMonitor {
  static let shared = ConnectivityMonitor()

  /// True until the first path update says otherwise.
  private(set) var isOnline = true

  /// Paths flap, so wait this long before treating a reconnect as real.
  private static let restoreDebounce: Duration = .seconds(1.5)

  @ObservationIgnored private var monitorTask: Task<Void, Never>?
  @ObservationIgnored private var restoreTask: Task<Void, Never>?

  init() {}

  func start() {
    guard monitorTask == nil else { return }
    monitorTask = Task { [weak self] in
      for await path in NWPathMonitor() {
        self?.handle(isOnline: path.status == .satisfied)
      }
    }
  }

  func handle(isOnline newValue: Bool) {
    let transition = ConnectivityTransition.between(wasOnline: isOnline, isOnline: newValue)
    isOnline = newValue
    switch transition {
    case .none:
      break
    case .wentOffline:
      restoreTask?.cancel()
      SyncStatusManager.shared.setOffline()
    case .wentOnline:
      restoreTask?.cancel()
      restoreTask = Task { [weak self] in
        try? await Task.sleep(for: Self.restoreDebounce)
        guard !Task.isCancelled, self?.isOnline == true else { return }
        SyncStatusManager.shared.connectivityRestored()
        await AppCoordinator.shared.handleConnectivityRestored()
      }
    }
  }
}
