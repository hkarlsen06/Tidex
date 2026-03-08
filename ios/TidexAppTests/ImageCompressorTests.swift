import UIKit
import XCTest

@testable import Tidex

final class ImageCompressorTests: XCTestCase {
  func testCompressDownscalesLargeChatUploadAndEnforcesByteBudget() throws {
    let image = makeDetailedImage(size: CGSize(width: 3_200, height: 2_400))
    let sourceData = try XCTUnwrap(image.pngData())

    let compressed = try XCTUnwrap(ImageCompressor.compress(sourceData))
    let outputImage = try XCTUnwrap(UIImage(data: compressed.data))

    XCTAssertEqual(compressed.mediaType, "image/jpeg")
    XCTAssertLessThanOrEqual(compressed.data.count, 1_500_000)
    XCTAssertLessThanOrEqual(max(outputImage.size.width, outputImage.size.height), 1_568)
    XCTAssertLessThan(compressed.data.count, sourceData.count)
  }

  func testCompressPreservesSmallImageDimensions() throws {
    let image = makeDetailedImage(size: CGSize(width: 640, height: 480))
    let sourceData = try XCTUnwrap(image.pngData())

    let compressed = try XCTUnwrap(ImageCompressor.compress(sourceData))
    let outputImage = try XCTUnwrap(UIImage(data: compressed.data))

    XCTAssertEqual(outputImage.size.width, 640, accuracy: 1)
    XCTAssertEqual(outputImage.size.height, 480, accuracy: 1)
    XCTAssertFalse(compressed.data.isEmpty)
  }

  private func makeDetailedImage(size: CGSize) -> UIImage {
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    format.opaque = true

    let renderer = UIGraphicsImageRenderer(size: size, format: format)
    return renderer.image { context in
      context.cgContext.setFillColor(UIColor.white.cgColor)
      context.cgContext.fill(CGRect(origin: .zero, size: size))

      let cellSize: CGFloat = 16
      let columnCount = Int(ceil(size.width / cellSize))
      let rowCount = Int(ceil(size.height / cellSize))

      for row in 0..<rowCount {
        for column in 0..<columnCount {
          let hue = CGFloat((row * 37 + column * 17) % 360) / 360
          let saturation = min(0.45 + CGFloat((row + column) % 5) * 0.12, 1)
          let brightness = min(0.4 + CGFloat((row * column) % 7) * 0.08, 1)

          context.cgContext.setFillColor(
            UIColor(
              hue: hue,
              saturation: saturation,
              brightness: brightness,
              alpha: 1
            ).cgColor
          )

          context.cgContext.fill(
            CGRect(
              x: CGFloat(column) * cellSize,
              y: CGFloat(row) * cellSize,
              width: cellSize,
              height: cellSize
            ))
        }
      }
    }
  }
}
