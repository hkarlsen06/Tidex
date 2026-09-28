import UIKit
import XCTest

@testable import Tidex

@MainActor
final class ProfileAvatarPersistenceTests: XCTestCase {
  func testResizedAvatarImageProducesExactPixelSizeRegardlessOfScreenScale() {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 3
    let source = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 400), format: format)
      .image { context in
        UIColor.red.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 400, height: 400))
      }

    let resized = ProfileSettingsView.resizedAvatarImage(source, to: 192)

    XCTAssertEqual(resized.size, CGSize(width: 192, height: 192))
    XCTAssertEqual(resized.cgImage?.width, 192)
    XCTAssertEqual(resized.cgImage?.height, 192)
  }

  private enum Failure: Error {
    case save
  }

  func testReplacementPersistsBeforeDeletingPreviousAvatar() async throws {
    var operations: [String] = []

    try await ProfileSettingsViewModel.commitAvatarChange(from: "old", to: "new") {
      operations.append("persist")
      return true
    } removeStoredAvatar: { url in
      operations.append("delete \(url)")
    }

    XCTAssertEqual(operations, ["persist", "delete old"])
  }

  func testFailedReplacementPreservesBothFilesWhilePersistenceIsUncertain() async {
    var removedURLs: [String] = []

    do {
      try await ProfileSettingsViewModel.commitAvatarChange(from: "old", to: "new") {
        throw Failure.save
      } removeStoredAvatar: { url in
        removedURLs.append(url)
      }
      XCTFail("The persistence failure must propagate")
    } catch Failure.save {
      XCTAssertTrue(removedURLs.isEmpty)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testMissingSettingsRejectsReplacementAndCleansNewOrphan() async {
    var removedURLs: [String] = []

    do {
      try await ProfileSettingsViewModel.commitAvatarChange(from: "old", to: "new") {
        false
      } removeStoredAvatar: { url in
        removedURLs.append(url)
      }
      XCTFail("Missing settings must not be treated as a successful save")
    } catch LocalStoreWriteError.notFound {
      XCTAssertEqual(removedURLs, ["new"])
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testRemovalPersistsBeforeDeletingStoredAvatar() async throws {
    var operations: [String] = []

    try await ProfileSettingsViewModel.commitAvatarChange(from: "old", to: nil) {
      operations.append("persist")
      return true
    } removeStoredAvatar: { url in
      operations.append("delete \(url)")
    }

    XCTAssertEqual(operations, ["persist", "delete old"])
  }

  func testFailedRemovalPreservesStoredAvatar() async {
    var removedURLs: [String] = []

    do {
      try await ProfileSettingsViewModel.commitAvatarChange(from: "old", to: nil) {
        throw Failure.save
      } removeStoredAvatar: { url in
        removedURLs.append(url)
      }
      XCTFail("The persistence failure must propagate")
    } catch Failure.save {
      XCTAssertTrue(removedURLs.isEmpty)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testUnchangedAvatarIsNeverDeleted() async throws {
    var removedURLs: [String] = []

    try await ProfileSettingsViewModel.commitAvatarChange(from: "same", to: "same") {
      true
    } removeStoredAvatar: { url in
      removedURLs.append(url)
    }

    XCTAssertTrue(removedURLs.isEmpty)
  }
}
