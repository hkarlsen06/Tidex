import XCTest

@testable import Tidex

@MainActor
internal final class CelebrationUserIsolationTests: XCTestCase {
  private let firstUserId = "celebration-test-\(UUID().uuidString)"
  private let secondUserId = "celebration-test-\(UUID().uuidString)"
  private let manager = ShiftCompletionCelebrationManager.shared

  override internal func tearDown() async throws {
    manager.resetForUserChange()
    for userId in [firstUserId, secondUserId] {
      UserDefaults.standard.removeObject(forKey: "payday_celebrated.\(userId)")
    }
    try await super.tearDown()
  }

  /// Sign-out removes the tab view while the sheet is closing, so its onDismiss may never run.
  internal func testSignOutDuringCelebrationLetsTheNextAccountCelebrate() {
    manager.celebratePaydayIfNeeded(
      userId: firstUserId, payoutDate: Date(), amount: 1_000, currency: "kr")
    XCTAssertTrue(manager.isSheetPresented)
    manager.isSheetPresented = false

    manager.resetForUserChange()
    XCTAssertNil(manager.celebrationData, "The next account must not see the first one's earnings")

    manager.celebratePaydayIfNeeded(
      userId: secondUserId, payoutDate: Date(), amount: 2_000, currency: "kr")
    XCTAssertTrue(manager.isSheetPresented)
    XCTAssertEqual(manager.celebrationData?.newDisplayValue, 2_000)
  }

  internal func testDismissAfterSignOutStillClosesTheCelebration() {
    manager.celebratePaydayIfNeeded(
      userId: firstUserId, payoutDate: Date(), amount: 1_000, currency: "kr")
    manager.isSheetPresented = false
    XCTAssertNotNil(manager.celebrationData, "The sheet keeps its content while it slides away")

    manager.dismissCelebration(userId: nil)
    XCTAssertNil(manager.celebrationData)
  }
}
