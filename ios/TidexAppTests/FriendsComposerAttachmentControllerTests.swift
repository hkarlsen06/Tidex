import PhotosUI
import UIKit
import XCTest

@testable import Tidex

@MainActor
final class FriendsComposerAttachmentControllerTests: XCTestCase {
  func testLoadRecentPhotosSetsLoadedStateWhenPhotosAvailable() async {
    let provider = MockRecentPhotoProvider(
      authorizationState: .authorized,
      photos: [FriendsComposerRecentPhoto(id: "photo-1", thumbnail: makeImage())]
    )
    let controller = FriendsComposerAttachmentController(recentPhotoProvider: provider)

    await controller.loadRecentPhotosIfNeeded()

    XCTAssertEqual(controller.recentPhotosState, .loaded)
    XCTAssertEqual(controller.recentPhotos.count, 1)
  }

  func testLoadRecentPhotosSetsDeniedStateWhenAccessUnavailable() async {
    let provider = MockRecentPhotoProvider(authorizationState: .denied, photos: [])
    let controller = FriendsComposerAttachmentController(recentPhotoProvider: provider)

    await controller.loadRecentPhotosIfNeeded()

    XCTAssertEqual(controller.recentPhotosState, .denied)
    XCTAssertTrue(controller.recentPhotos.isEmpty)
  }

  func testCompleteAttachmentSelectionClosesDrawerAndCalendar() {
    let controller = FriendsComposerAttachmentController(
      recentPhotoProvider: MockRecentPhotoProvider(authorizationState: .authorized, photos: [])
    )
    controller.isDrawerOpen = true
    controller.isShowingShiftCalendar = true

    controller.completeAttachmentSelection()

    XCTAssertFalse(controller.isDrawerOpen)
    XCTAssertFalse(controller.isShowingShiftCalendar)
  }

  func testToggleDrawerWaitsForInitialRecentPhotosBeforeOpening() async {
    let provider = MockRecentPhotoProvider(
      authorizationState: .authorized,
      photos: [FriendsComposerRecentPhoto(id: "photo-1", thumbnail: makeImage())],
      loadDelayNanoseconds: 50_000_000
    )
    let controller = FriendsComposerAttachmentController(recentPhotoProvider: provider)

    let toggleTask = Task {
      await controller.toggleDrawer()
    }

    await Task.yield()

    XCTAssertTrue(controller.isPreparingDrawer)
    XCTAssertFalse(controller.isDrawerOpen)

    await toggleTask.value

    XCTAssertFalse(controller.isPreparingDrawer)
    XCTAssertTrue(controller.isDrawerOpen)
    XCTAssertEqual(controller.recentPhotosState, .loaded)
    XCTAssertEqual(controller.recentPhotos.count, 1)
  }

  func testToggleDrawerOpensImmediatelyWhenRecentPhotosAlreadyCached() async {
    let provider = MockRecentPhotoProvider(
      authorizationState: .authorized,
      photos: [FriendsComposerRecentPhoto(id: "photo-1", thumbnail: makeImage())]
    )
    let controller = FriendsComposerAttachmentController(recentPhotoProvider: provider)

    await controller.loadRecentPhotosIfNeeded()
    await controller.toggleDrawer()

    XCTAssertFalse(controller.isPreparingDrawer)
    XCTAssertTrue(controller.isDrawerOpen)
  }

  func testToggleDrawerRechecksDeniedPhotoAccessAfterPermissionChanges() async {
    let provider = MockRecentPhotoProvider(authorizationState: .denied, photos: [])
    let controller = FriendsComposerAttachmentController(recentPhotoProvider: provider)

    await controller.toggleDrawer()
    XCTAssertEqual(controller.recentPhotosState, .denied)
    XCTAssertTrue(controller.isDrawerOpen)

    controller.closeDrawer()
    provider.authorizationStateValue = .authorized
    provider.photosValue = [FriendsComposerRecentPhoto(id: "photo-1", thumbnail: makeImage())]

    await controller.toggleDrawer()

    XCTAssertEqual(controller.recentPhotosState, .loaded)
    XCTAssertEqual(controller.recentPhotos.count, 1)
    XCTAssertTrue(controller.isDrawerOpen)
  }

  private func makeImage() -> UIImage {
    UIGraphicsImageRenderer(size: CGSize(width: 12, height: 12)).image { context in
      UIColor.systemBlue.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 12, height: 12))
    }
  }
}

private final class MockRecentPhotoProvider: FriendsComposerRecentPhotoProviding {
  var authorizationStateValue: FriendsComposerPhotoAuthorizationState
  var photosValue: [FriendsComposerRecentPhoto]
  private let loadDelayNanoseconds: UInt64

  init(
    authorizationState: FriendsComposerPhotoAuthorizationState,
    photos: [FriendsComposerRecentPhoto],
    loadDelayNanoseconds: UInt64 = 0
  ) {
    self.authorizationStateValue = authorizationState
    self.photosValue = photos
    self.loadDelayNanoseconds = loadDelayNanoseconds
  }

  func authorizationState() -> FriendsComposerPhotoAuthorizationState {
    authorizationStateValue
  }

  func requestAuthorization() async -> FriendsComposerPhotoAuthorizationState {
    await Task.yield()
    return authorizationStateValue
  }

  func loadRecentPhotos(limit: Int, targetSize: CGSize) async -> [FriendsComposerRecentPhoto] {
    if loadDelayNanoseconds > 0 {
      try? await Task.sleep(nanoseconds: loadDelayNanoseconds)
    }
    await Task.yield()
    return Array(photosValue.prefix(limit))
  }

  func loadImageData(localIdentifier: String) async -> Data? {
    await Task.yield()
    return nil
  }
}
