import PhotosUI
import UIKit
import XCTest

@testable import Tidex

@MainActor
final class FriendsComposerAttachmentControllerTests: XCTestCase {
  func testToggleDrawerFlipsOpenState() {
    let controller = FriendsComposerAttachmentController()

    controller.toggleDrawer()
    XCTAssertTrue(controller.isDrawerOpen)

    controller.toggleDrawer()
    XCTAssertFalse(controller.isDrawerOpen)
  }

  func testCompleteAttachmentSelectionClosesDrawerAndCalendar() {
    let controller = FriendsComposerAttachmentController()
    controller.isDrawerOpen = true
    controller.isShowingShiftCalendar = true

    controller.completeAttachmentSelection()

    XCTAssertFalse(controller.isDrawerOpen)
    XCTAssertFalse(controller.isShowingShiftCalendar)
  }

  func testCompleteAttachmentSelectionCanLeaveDrawerOpen() {
    let controller = FriendsComposerAttachmentController()
    controller.isDrawerOpen = true
    controller.isShowingShiftCalendar = true

    controller.completeAttachmentSelection(shouldCloseDrawer: false)

    XCTAssertTrue(controller.isDrawerOpen)
    XCTAssertFalse(controller.isShowingShiftCalendar)
  }

  func testProcessingAttachmentGateAllowsOnlyOneActiveSelection() {
    let controller = FriendsComposerAttachmentController()

    XCTAssertTrue(controller.beginProcessingAttachment())
    XCTAssertFalse(controller.beginProcessingAttachment())

    controller.finishProcessingAttachment()

    XCTAssertTrue(controller.beginProcessingAttachment())
  }

  func testMakeImageAttachmentFromNilPhotoItemReturnsNil() async {
    let controller = FriendsComposerAttachmentController()

    let attachment = await controller.makeImageAttachment(from: nil)

    XCTAssertNil(attachment)
    XCTAssertFalse(controller.isProcessingAttachment)
  }

  func testMakeImageAttachmentFromCapturedImageCompresses() async {
    let controller = FriendsComposerAttachmentController()

    let attachment = await controller.makeImageAttachment(from: makeImage())

    XCTAssertNotNil(attachment)
    XCTAssertFalse(controller.isProcessingAttachment)
  }

  func testReleaseDeselectedPhotosReturnsOnlyDeselectedAttachments() {
    let controller = FriendsComposerAttachmentController()
    controller.recordPickedAttachment("attachment-a", forPickerItemID: "photo-a")
    controller.recordPickedAttachment("attachment-b", forPickerItemID: "photo-b")

    let removed = controller.releaseDeselectedPhotos(selectedPickerItemIDs: ["photo-b"])

    XCTAssertEqual(removed, ["attachment-a"])
    XCTAssertEqual(controller.pickedAttachmentIDs, ["photo-b": "attachment-b"])
  }

  func testReleaseUnstagedPhotosReturnsPhotosToDeselect() {
    let controller = FriendsComposerAttachmentController()
    controller.recordPickedAttachment("attachment-a", forPickerItemID: "photo-a")
    controller.recordPickedAttachment("attachment-b", forPickerItemID: "photo-b")

    // The thumbnail for photo A was removed from the composer.
    let deselected = controller.releaseUnstagedPhotos(stagedAttachmentIDs: ["attachment-b"])

    XCTAssertEqual(deselected, ["photo-a"])
    XCTAssertEqual(controller.pickedAttachmentIDs, ["photo-b": "attachment-b"])
  }

  func testReleaseUnstagedPhotosClearsEverythingAfterSend() {
    let controller = FriendsComposerAttachmentController()
    controller.recordPickedAttachment("attachment-a", forPickerItemID: "photo-a")

    let deselected = controller.releaseUnstagedPhotos(stagedAttachmentIDs: [])

    XCTAssertEqual(deselected, ["photo-a"])
    XCTAssertTrue(controller.pickedAttachmentIDs.isEmpty)
  }

  private func makeImage() -> UIImage {
    UIGraphicsImageRenderer(size: CGSize(width: 12, height: 12)).image { context in
      UIColor.systemBlue.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 12, height: 12))
    }
  }
}
