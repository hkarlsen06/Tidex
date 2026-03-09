import XCTest

@testable import Tidex

final class FriendsThreadComposerLogicTests: XCTestCase {
  func testCanSendRequiresContentAndNoActiveBlockingState() {
    XCTAssertTrue(
      FriendsThreadComposerLogic.canSend(
        draftText: "Hello",
        hasImage: false,
        isThreadReadOnly: false,
        isSubmitting: false,
        isProcessingImage: false
      )
    )

    XCTAssertFalse(
      FriendsThreadComposerLogic.canSend(
        draftText: "   ",
        hasImage: false,
        isThreadReadOnly: false,
        isSubmitting: false,
        isProcessingImage: false
      )
    )
  }

  func testCanSendAllowsImageOnlyMessage() {
    XCTAssertTrue(
      FriendsThreadComposerLogic.canSend(
        draftText: "",
        hasImage: true,
        isThreadReadOnly: false,
        isSubmitting: false,
        isProcessingImage: false
      )
    )
  }

  func testShouldHideAttachmentButtonForLongFocusedDraftWithoutImage() {
    XCTAssertTrue(
      FriendsThreadComposerLogic.shouldHideAttachmentButton(
        draftText: String(repeating: "a", count: 40),
        isFocused: true,
        hasImage: false
      )
    )
  }

  func testShouldKeepAttachmentButtonVisibleWhenNotFocusedOrImageAttached() {
    XCTAssertFalse(
      FriendsThreadComposerLogic.shouldHideAttachmentButton(
        draftText: String(repeating: "a", count: 40),
        isFocused: false,
        hasImage: false
      )
    )

    XCTAssertFalse(
      FriendsThreadComposerLogic.shouldHideAttachmentButton(
        draftText: String(repeating: "a", count: 40),
        isFocused: true,
        hasImage: true
      )
    )
  }
}
