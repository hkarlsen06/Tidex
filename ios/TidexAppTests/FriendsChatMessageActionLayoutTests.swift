import CoreGraphics
import XCTest

@testable import Tidex

final class FriendsChatMessageActionLayoutTests: XCTestCase {
  func testPreviewWidthTracksBubbleWidthInsteadOfFullRowWidth() {
    XCTAssertEqual(FriendsChatMessageActionLayout.previewWidth(for: 128), 160)
    XCTAssertEqual(FriendsChatMessageActionLayout.previewWidth(for: 212), 212)
    XCTAssertEqual(FriendsChatMessageActionLayout.previewWidth(for: 420), 296)
  }

  func testActionMenuWidthStaysCompact() {
    XCTAssertEqual(FriendsChatMessageActionLayout.actionMenuWidth(for: 92), 176)
    XCTAssertEqual(FriendsChatMessageActionLayout.actionMenuWidth(for: 160), 192)
    XCTAssertEqual(FriendsChatMessageActionLayout.actionMenuWidth(for: 320), 240)
  }

  func testLocalSourceFrameConvertsGlobalFrameIntoOverlayCoordinates() {
    let sourceFrame = CGRect(x: 178, y: 412, width: 164, height: 74)
    let overlayFrame = CGRect(x: 24, y: 120, width: 360, height: 680)

    XCTAssertEqual(
      FriendsChatMessageActionLayout.localSourceFrame(sourceFrame, in: overlayFrame),
      CGRect(x: 154, y: 292, width: 164, height: 74)
    )
  }
}
