import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// Utility for compressing images for upload.
/// Supports WebP, HEIC, and JPEG formats with configurable quality.
enum ImageCompressor {

  /// Result of image compression
  struct CompressedImage {
    let data: Data
    let mediaType: String
    let fileExtension: String
  }

  /// Maximum dimension for images sent to Wagey (Claude API recommendation)
  /// Larger images are downscaled to fit within this dimension
  private static let maxDimension: CGFloat = 1568

  /// Default compression quality (0.0 - 1.0)
  private static let defaultQuality: CGFloat = 0.8

  // MARK: - Public API

  /// Compress image data for upload.
  /// Automatically downscales large images and converts to an efficient format.
  /// For API compatibility, always returns JPEG format.
  ///
  /// - Parameters:
  ///   - imageData: Source image data
  ///   - quality: Compression quality (0.0 - 1.0), defaults to 0.8
  /// - Returns: Compressed image with metadata, or nil if compression fails
  static func compress(_ imageData: Data, quality: CGFloat = defaultQuality) -> CompressedImage? {
    guard let image = UIImage(data: imageData) else {
      return nil
    }

    return compress(image, quality: quality)
  }

  /// Compress a UIImage for upload.
  /// Automatically downscales large images and converts to JPEG format.
  ///
  /// - Parameters:
  ///   - image: Source UIImage
  ///   - quality: Compression quality (0.0 - 1.0), defaults to 0.8
  /// - Returns: Compressed image with metadata, or nil if compression fails
  static func compress(_ image: UIImage, quality: CGFloat = defaultQuality) -> CompressedImage? {
    // Downscale if needed
    let scaledImage = downscaleIfNeeded(image)

    // Always use JPEG for Claude API compatibility
    // (Claude supports JPEG, PNG, GIF, WebP - JPEG is most efficient for photos)
    guard let jpegData = scaledImage.jpegData(compressionQuality: quality) else {
      return nil
    }

    return CompressedImage(
      data: jpegData,
      mediaType: "image/jpeg",
      fileExtension: "jpg"
    )
  }

  /// Compress image data using the best available format.
  /// Tries WebP first (smallest), then HEIC, then JPEG as fallback.
  /// Use this for local storage where format flexibility is allowed.
  ///
  /// - Parameters:
  ///   - imageData: Source image data
  ///   - quality: Compression quality (0.0 - 1.0), defaults to 0.8
  /// - Returns: Compressed image with metadata, or nil if compression fails
  static func compressBestFormat(_ imageData: Data, quality: CGFloat = defaultQuality)
    -> CompressedImage? {
    // Try WebP first (best compression)
    if let webpData = convertToWebP(imageData, quality: quality) {
      return CompressedImage(
        data: webpData,
        mediaType: "image/webp",
        fileExtension: "webp"
      )
    }

    // Try HEIC (good compression, iOS native)
    if let heicData = convertToHEIC(imageData, quality: quality) {
      return CompressedImage(
        data: heicData,
        mediaType: "image/heic",
        fileExtension: "heic"
      )
    }

    // Fall back to JPEG
    return compress(imageData, quality: quality)
  }

  // MARK: - Private Helpers

  /// Downscale image if it exceeds the maximum dimension
  private static func downscaleIfNeeded(_ image: UIImage) -> UIImage {
    let size = image.size
    let maxSide = max(size.width, size.height)

    guard maxSide > maxDimension else {
      return image
    }

    let scale = maxDimension / maxSide
    let newSize = CGSize(
      width: size.width * scale,
      height: size.height * scale
    )

    let renderer = UIGraphicsImageRenderer(size: newSize)
    return renderer.image { _ in
      image.draw(in: CGRect(origin: .zero, size: newSize))
    }
  }

  /// Convert image data to WebP format
  private static func convertToWebP(_ imageData: Data, quality: CGFloat) -> Data? {
    guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
      let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
      return nil
    }

    // Check if WebP encoding is supported
    let supportedTypes = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
    guard supportedTypes.contains(UTType.webP.identifier) else {
      return nil
    }

    let webpData = NSMutableData()
    let webpUTType = UTType.webP.identifier as CFString

    guard
      let destination = CGImageDestinationCreateWithData(
        webpData,
        webpUTType,
        1,
        nil
      )
    else {
      return nil
    }

    let options: [CFString: Any] = [
      kCGImageDestinationLossyCompressionQuality: quality
    ]

    CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)

    guard CGImageDestinationFinalize(destination) else {
      return nil
    }

    return webpData as Data
  }

  /// Convert image data to HEIC format
  private static func convertToHEIC(_ imageData: Data, quality: CGFloat) -> Data? {
    guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
      let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
      return nil
    }

    let heicData = NSMutableData()
    let heicUTType = UTType.heic.identifier as CFString

    guard
      let destination = CGImageDestinationCreateWithData(
        heicData,
        heicUTType,
        1,
        nil
      )
    else {
      return nil
    }

    let options: [CFString: Any] = [
      kCGImageDestinationLossyCompressionQuality: quality
    ]

    CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)

    guard CGImageDestinationFinalize(destination) else {
      return nil
    }

    return heicData as Data
  }
}
