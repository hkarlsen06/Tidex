import XCTest

@testable import Tidex

final class FriendsChatViewportAnchorTests: XCTestCase {
  func testShouldMaintainBottomAnchorWhenInitialScrollCompletedAndPinned() {
    XCTAssertTrue(
      FriendsChatViewportAnchor.shouldMaintainBottomAnchor(
        didInitialScroll: true,
        wasPinnedToBottom: true,
        hasUserAdjustedViewport: true,
        hasPendingTargetedScroll: false
      )
    )
  }

  func testShouldMaintainBottomAnchorOnFirstKeyboardOpenBeforeUserScrolls() {
    XCTAssertTrue(
      FriendsChatViewportAnchor.shouldMaintainBottomAnchor(
        didInitialScroll: true,
        wasPinnedToBottom: false,
        hasUserAdjustedViewport: false,
        hasPendingTargetedScroll: false
      )
    )
  }

  func testShouldNotMaintainBottomAnchorDuringTargetedScroll() {
    XCTAssertFalse(
      FriendsChatViewportAnchor.shouldMaintainBottomAnchor(
        didInitialScroll: true,
        wasPinnedToBottom: true,
        hasUserAdjustedViewport: false,
        hasPendingTargetedScroll: true
      )
    )
  }
}
