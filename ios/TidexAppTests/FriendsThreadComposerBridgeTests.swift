import XCTest

@testable import Tidex

@MainActor
final class FriendsThreadComposerBridgeTests: XCTestCase {
  func testAddImageAttachmentsDropsDuplicatePayloads() {
    let bridge = FriendsThreadComposerBridge()

    bridge.addImageAttachments([
      ImageAttachment(id: "image-1", data: Data([0x01, 0x02]), mediaType: "image/jpeg"),
      ImageAttachment(id: "image-2", data: Data([0x01, 0x02]), mediaType: "image/jpeg"),
      ImageAttachment(id: "image-3", data: Data([0x03, 0x04]), mediaType: "image/jpeg"),
    ])

    XCTAssertEqual(
      bridge.stagedAttachments,
      [
        .image(ImageAttachment(id: "image-1", data: Data([0x01, 0x02]), mediaType: "image/jpeg")),
        .image(ImageAttachment(id: "image-3", data: Data([0x03, 0x04]), mediaType: "image/jpeg")),
      ]
    )
  }
}
