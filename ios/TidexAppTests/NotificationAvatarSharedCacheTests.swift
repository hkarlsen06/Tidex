import Foundation
import UIKit
import XCTest

@testable import Tidex

final class NotificationAvatarSharedCacheTests: XCTestCase {
  func testStoreDefersDiskWorkAndWritesDecodableImage() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let queue = DispatchQueue(label: "NotificationAvatarSharedCacheTests.store")
    let cache = NotificationAvatarSharedCache(directory: directory, queue: queue)
    let image = makeImage()

    queue.suspend()
    cache.store(image, for: try XCTUnwrap(URL(string: "https://example.com/avatar.jpg")))
    let wroteBeforeQueueRan = FileManager.default.fileExists(atPath: directory.path)
    queue.resume()
    queue.sync {}

    XCTAssertFalse(wroteBeforeQueueRan)
    let files = try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: nil)
    XCTAssertEqual(files.count, 1)
    let file = try XCTUnwrap(files.first)
    let restoredImage = try XCTUnwrap(UIImage(data: Data(contentsOf: file)))
    XCTAssertEqual(restoredImage.size, image.size)
  }

  func testRemoveRunsAfterPendingStore() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let queue = DispatchQueue(label: "NotificationAvatarSharedCacheTests.remove")
    let cache = NotificationAvatarSharedCache(directory: directory, queue: queue)
    let url = try XCTUnwrap(URL(string: "https://example.com/avatar.jpg"))

    cache.store(makeImage(), for: url)
    cache.remove(for: url)
    queue.sync {}

    let files = try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: nil)
    XCTAssertTrue(files.isEmpty)
  }

  func testClearKeepsOnlyStoresEnqueuedAfterIt() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let queue = DispatchQueue(label: "NotificationAvatarSharedCacheTests.clear")
    let cache = NotificationAvatarSharedCache(directory: directory, queue: queue)
    let firstURL = try XCTUnwrap(URL(string: "https://example.com/first.jpg"))
    let secondURL = try XCTUnwrap(URL(string: "https://example.com/second.jpg"))
    let image = makeImage()

    cache.store(image, for: firstURL)
    cache.clearAll()
    cache.store(image, for: secondURL)
    queue.sync {}

    let files = try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: nil)
    XCTAssertEqual(files.count, 1)
    cache.remove(for: secondURL)
    queue.sync {}
    let remaining = try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: nil)
    XCTAssertTrue(remaining.isEmpty)
  }

  func testFailedWriteCanBeRetried() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let queue = DispatchQueue(label: "NotificationAvatarSharedCacheTests.retry")
    let cache = NotificationAvatarSharedCache(directory: directory, queue: queue)
    let url = try XCTUnwrap(URL(string: "https://example.com/avatar.jpg"))
    let image = makeImage()
    try Data("Blocks directory creation".utf8).write(to: directory)

    cache.store(image, for: url)
    queue.sync {}
    try FileManager.default.removeItem(at: directory)
    cache.store(image, for: url)
    queue.sync {}

    let files = try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: nil)
    XCTAssertEqual(files.count, 1)
  }

  private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  }

  private func makeImage() -> UIImage {
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    let size = CGSize(width: 40, height: 40)
    return UIGraphicsImageRenderer(size: size, format: format).image { context in
      UIColor.blue.setFill()
      context.fill(CGRect(origin: .zero, size: size))
    }
  }
}
