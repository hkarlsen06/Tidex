import Foundation
import UIKit
import XCTest

@testable import Tidex

final class ImageCacheInvalidationTests: XCTestCase {
  func testRemoveInvalidatesEveryMemoryVariant() throws {
    let directory = temporaryDirectory()
    let queue = DispatchQueue(label: "ImageCacheInvalidationTests.memory")
    let cache = ImageCache(directory: directory, queue: queue)
    defer {
      queue.sync {}
      try? FileManager.default.removeItem(at: directory)
    }
    let url = try XCTUnwrap(URL(string: "https://example.com/\(UUID().uuidString).jpg"))
    let image = makeImage()

    for policy in [ImageCachePolicy.defaultImage, .messageAttachment] {
      for pixelSize: CGFloat? in [nil, 48, 192] {
        cache.set(image, for: url, maxPixelSize: pixelSize, policy: policy)
        XCTAssertNotNil(cache.get(for: url, maxPixelSize: pixelSize, policy: policy))
      }
    }
    cache.remove(for: url)

    for policy in [ImageCachePolicy.defaultImage, .messageAttachment] {
      for pixelSize: CGFloat? in [nil, 48, 192] {
        XCTAssertNil(cache.get(for: url, maxPixelSize: pixelSize, policy: policy))
      }
    }
  }

  func testRemoveInvalidatesDiskVariantsAndPreservesUnrelatedImages() async throws {
    let directory = temporaryDirectory()
    let queue = DispatchQueue(label: "ImageCacheInvalidationTests.disk")
    let cache = ImageCache(directory: directory, queue: queue)
    defer {
      queue.sync {}
      try? FileManager.default.removeItem(at: directory)
    }
    let url = try XCTUnwrap(URL(string: "https://example.com/\(UUID().uuidString).jpg"))
    let otherURL = try XCTUnwrap(URL(string: "https://example.com/other.jpg"))
    let image = makeImage()

    for policy in [ImageCachePolicy.defaultImage, .messageAttachment] {
      for pixelSize: CGFloat? in [nil, 48, 192] {
        cache.set(image, for: url, maxPixelSize: pixelSize, policy: policy)
      }
    }
    cache.set(image, for: otherURL)
    queue.sync {}
    let originalFiles = try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: nil)
    XCTAssertEqual(originalFiles.count, 7)

    cache.remove(for: url)
    queue.sync {}

    for policy in [ImageCachePolicy.defaultImage, .messageAttachment] {
      for pixelSize: CGFloat? in [nil, 48, 192] {
        let cached = await cache.getFromDisk(for: url, maxPixelSize: pixelSize, policy: policy)
        XCTAssertNil(cached)
      }
    }
    let remainingImage = await cache.getFromDisk(for: otherURL)
    XCTAssertNotNil(remainingImage)
    let remainingFiles = try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: nil)
    XCTAssertEqual(remainingFiles.count, 1)
  }

  @MainActor
  func testPendingDiskPromotionCannotUndoRemoveOrClear() async throws {
    for shouldClearAll in [false, true] {
      let directory = temporaryDirectory()
      let queue = DispatchQueue(label: "ImageCacheInvalidationTests.pendingRead")
      let cache = ImageCache(directory: directory, queue: queue)
      defer {
        queue.sync {}
        try? FileManager.default.removeItem(at: directory)
      }
      let url = try XCTUnwrap(URL(string: "https://example.com/\(UUID().uuidString).jpg"))
      cache.set(makeImage(), for: url, maxPixelSize: 48)
      queue.sync {}

      // Hold the main actor until the disk read has queued its memory promotion.
      // That guarantees invalidation runs before the pending main-queue block.
      let readFinished = DispatchSemaphore(value: 0)
      let readTask = Task.detached {
        let image = await cache.getFromDisk(for: url, maxPixelSize: 48)
        readFinished.signal()
        return image
      }
      XCTAssertEqual(readFinished.wait(timeout: .now() + 2), .success)
      if shouldClearAll {
        cache.clearAll()
      } else {
        cache.remove(for: url)
      }

      await withCheckedContinuation { continuation in
        DispatchQueue.main.async { continuation.resume() }
      }
      let diskImage = await readTask.value
      XCTAssertNotNil(diskImage)
      XCTAssertNil(cache.get(for: url, maxPixelSize: 48))
    }
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
