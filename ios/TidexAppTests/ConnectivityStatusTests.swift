import XCTest

@testable import Tidex

@MainActor
final class ConnectivityStatusTests: XCTestCase {
  func testTransitionDecision() {
    XCTAssertEqual(ConnectivityTransition.between(wasOnline: true, isOnline: false), .wentOffline)
    XCTAssertEqual(ConnectivityTransition.between(wasOnline: false, isOnline: true), .wentOnline)
    XCTAssertEqual(ConnectivityTransition.between(wasOnline: true, isOnline: true), .none)
    XCTAssertEqual(ConnectivityTransition.between(wasOnline: false, isOnline: false), .none)
  }

  func testBackgroundSyncKeepsOfflineStatus() {
    let manager = SyncStatusManager()
    manager.setOffline()
    manager.syncStarted(isBackground: true)
    XCTAssertEqual(manager.status, .offline)
  }

  func testManualSyncReplacesOfflineStatus() {
    let manager = SyncStatusManager()
    manager.setOffline()
    manager.syncStarted()
    XCTAssertEqual(manager.status, .syncing)
  }

  func testSyncSuccessClearsOffline() {
    let manager = SyncStatusManager()
    manager.setOffline()
    manager.syncSucceeded()
    XCTAssertEqual(manager.status, .synced)
  }

  func testConnectivityRestoredClearsOnlyOffline() {
    let manager = SyncStatusManager()
    manager.setOffline()
    manager.connectivityRestored()
    XCTAssertEqual(manager.status, .synced)

    manager.syncFailed(message: "boom")
    manager.connectivityRestored()
    XCTAssertEqual(manager.status, .failed(message: "boom", lastSync: nil))

    manager.syncStarted()
    manager.connectivityRestored()
    XCTAssertEqual(manager.status, .syncing)
  }

  func testMonitorMarksOfflineOnDrop() {
    SyncStatusManager.shared.reset()
    let monitor = ConnectivityMonitor()
    XCTAssertTrue(monitor.isOnline)
    monitor.handle(isOnline: false)
    XCTAssertFalse(monitor.isOnline)
    XCTAssertEqual(SyncStatusManager.shared.status, .offline)
    SyncStatusManager.shared.reset()
  }
}
