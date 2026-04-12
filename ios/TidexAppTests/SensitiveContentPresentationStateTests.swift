import XCTest

@testable import Tidex

@MainActor
final class SensitiveContentPresentationStateTests: XCTestCase {
  override func tearDown() {
    SensitiveContentPresentationState.shared.setVisibleContext(nil)
    super.tearDown()
  }

  func testClearingDifferentOwnerDoesNotRemoveActiveContext() {
    let activeOwnerId = UUID()
    SensitiveContentPresentationState.shared.setVisibleContext(
      .friendThread(threadId: "thread-a", ownerId: activeOwnerId)
    )

    SensitiveContentPresentationState.shared.clearVisibleContextIfOwnedByFriendThread(UUID())

    XCTAssertEqual(SensitiveContentPresentationState.shared.activeFriendThreadId, "thread-a")
  }

  func testClearingMatchingOwnerRemovesActiveContext() {
    let ownerId = UUID()
    SensitiveContentPresentationState.shared.setVisibleContext(
      .friendThread(threadId: "thread-a", ownerId: ownerId)
    )

    SensitiveContentPresentationState.shared.clearVisibleContextIfOwnedByFriendThread(ownerId)

    XCTAssertNil(SensitiveContentPresentationState.shared.activeFriendThreadId)
  }
}
