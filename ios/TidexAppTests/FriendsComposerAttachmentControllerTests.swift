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

  func testProcessingAttachmentGateAllowsOnlyOneActiveSelection() {
    let controller = FriendsComposerAttachmentController(
      recentPhotoProvider: MockRecentPhotoProvider(authorizationState: .authorized, photos: [])
    )

    XCTAssertTrue(controller.beginProcessingAttachment())
    XCTAssertFalse(controller.beginProcessingAttachment())

    controller.finishProcessingAttachment()

    XCTAssertTrue(controller.beginProcessingAttachment())
  }

  func testToggleDrawerOpensImmediatelyWhileInitialPhotosLoad() async {
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

    XCTAssertTrue(controller.isDrawerOpen)
    XCTAssertEqual(controller.recentPhotosState, .loading)

    await toggleTask.value

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

  func testLoadMoreRecentPhotosAppendsNextPageNearEndOfDrawer() async {
    let provider = MockRecentPhotoProvider(
      authorizationState: .authorized,
      photos: (0..<16).map { FriendsComposerRecentPhoto(id: "photo-\($0)", thumbnail: makeImage()) }
    )
    let controller = FriendsComposerAttachmentController(recentPhotoProvider: provider)

    await controller.loadRecentPhotosIfNeeded()
    XCTAssertEqual(controller.recentPhotos.count, 12)

    await controller.loadMoreRecentPhotosIfNeeded(currentPhotoID: "photo-8")

    XCTAssertEqual(controller.recentPhotosState, .loaded)
    XCTAssertEqual(controller.recentPhotos.count, 16)
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

  func loadRecentPhotos(limit: Int, offset: Int, targetSize: CGSize) async
    -> FriendsComposerRecentPhotoPage
  {
    if loadDelayNanoseconds > 0 {
      try? await Task.sleep(nanoseconds: loadDelayNanoseconds)
    }
    await Task.yield()
    let startIndex = min(max(offset, 0), photosValue.count)
    let endIndex = min(startIndex + limit, photosValue.count)
    let page = Array(photosValue[startIndex..<endIndex])
    return FriendsComposerRecentPhotoPage(
      photos: page,
      hasMore: endIndex < photosValue.count,
      nextOffset: endIndex
    )
  }

  func loadImageData(localIdentifier: String) async -> Data? {
    await Task.yield()
    return nil
  }
}
