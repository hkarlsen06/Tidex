import XCTest

@testable import Tidex

@MainActor
internal final class FriendsThreadComposerBridgeTests: XCTestCase {
  internal func testAddImageAttachmentsDropsDuplicatePayloads() {
    let bridge: FriendsThreadComposerBridge = FriendsThreadComposerBridge()

    let attachments: [FriendsComposerAttachmentDraft] = bridge.addImageAttachments(
      [
        ImageAttachment(id: "image-1", data: Data([0x01, 0x02]), mediaType: "image/jpeg"),
        ImageAttachment(id: "image-2", data: Data([0x01, 0x02]), mediaType: "image/jpeg"),
        ImageAttachment(id: "image-3", data: Data([0x03, 0x04]), mediaType: "image/jpeg"),
      ],
      to: []
    )

    XCTAssertEqual(
      attachments,
      [
        .image(ImageAttachment(id: "image-1", data: Data([0x01, 0x02]), mediaType: "image/jpeg")),
        .image(ImageAttachment(id: "image-3", data: Data([0x03, 0x04]), mediaType: "image/jpeg")),
      ]
    )
  }

  internal func testCurrentStagedAttachmentsReflectsLatestProviderValue() {
    let bridge: FriendsThreadComposerBridge = FriendsThreadComposerBridge()
    var stagedAttachments: [FriendsComposerAttachmentDraft] = [
      .image(ImageAttachment(id: "image-1", data: Data([0x01]), mediaType: "image/jpeg"))
    ]
    bridge.stagedAttachmentsProvider = {
      stagedAttachments
    }

    XCTAssertEqual(bridge.currentStagedAttachments(), stagedAttachments)

    stagedAttachments.append(
      .image(ImageAttachment(id: "image-2", data: Data([0x02]), mediaType: "image/jpeg"))
    )

    XCTAssertEqual(bridge.currentStagedAttachments(), stagedAttachments)
  }

  deinit {
    // Required by SwiftLint for XCTestCase subclasses.
  }
}
