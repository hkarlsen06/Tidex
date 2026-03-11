import XCTest

@testable import Tidex

final class FriendsThreadComposerKeyboardLayoutTests: XCTestCase {
  func testDoesNotAttachComposerWhenKeyboardGuideOnlyMatchesBottomSafeArea() {
    XCTAssertFalse(
      FriendsThreadComposerKeyboardLayout.shouldAttachComposerToKeyboard(
        keyboardTop: 810,
        viewBottom: 844,
        bottomSafeAreaInset: 34
      )
    )
  }

  func testAttachesComposerWhenKeyboardOverlapExceedsBottomSafeArea() {
    XCTAssertTrue(
      FriendsThreadComposerKeyboardLayout.shouldAttachComposerToKeyboard(
        keyboardTop: 520,
        viewBottom: 844,
        bottomSafeAreaInset: 34
      )
    )
  }

  func testDoesNotAttachComposerWhenKeyboardGuideSitsOffscreen() {
    XCTAssertFalse(
      FriendsThreadComposerKeyboardLayout.shouldAttachComposerToKeyboard(
        keyboardTop: 844,
        viewBottom: 844,
        bottomSafeAreaInset: 34
      )
    )
  }
}
