import XCTest

@testable import Tidex

@MainActor
final class TemporaryClockSessionStoreTests: XCTestCase {
  private func makeDefaults(suiteName: String) -> UserDefaults {
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      preconditionFailure("Failed to create UserDefaults suite: \(suiteName)")
    }
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
  }

  func testSaveAndLoadRoundTrip() {
    let suiteName = "TemporaryClockSessionStoreTests.roundtrip"
    let defaults = makeDefaults(suiteName: suiteName)
    let store = TemporaryClockSessionStore(defaults: defaults)

    let startedAt = Date.fromDateAndTime("2026-03-02", time: "08:00") ?? Date()
    let session = TemporaryClockSession(
      id: "session-1",
      userId: "user-1",
      jobId: "job-1",
      startedAt: startedAt,
      createdAt: startedAt
    )

    store.save(session)

    XCTAssertEqual(store.activeSession(for: "user-1"), session)
  }

  func testClearRemovesOnlySpecifiedUserSession() {
    let suiteName = "TemporaryClockSessionStoreTests.clear"
    let defaults = makeDefaults(suiteName: suiteName)
    let store = TemporaryClockSessionStore(defaults: defaults)

    let now = Date()
    store.save(
      TemporaryClockSession(id: "one", userId: "user-1", jobId: nil, startedAt: now, createdAt: now)
    )
    store.save(
      TemporaryClockSession(id: "two", userId: "user-2", jobId: nil, startedAt: now, createdAt: now)
    )

    store.clear(for: "user-1")

    XCTAssertNil(store.activeSession(for: "user-1"))
    XCTAssertEqual(store.activeSession(for: "user-2")?.id, "two")
  }
}
