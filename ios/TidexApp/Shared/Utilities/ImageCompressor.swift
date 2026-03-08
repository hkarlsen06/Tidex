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

  /// Hard cap for chat uploads before base64 expansion.
  private static let maxUploadBytes = 1_500_000

  /// Smallest JPEG quality we'll allow before preferring to shrink dimensions again.
  private static let minimumQuality: CGFloat = 0.45

  /// Additional dimension reduction applied when quality tuning alone is insufficient.
  private static let iterativeDownscaleFactor: CGFloat = 0.85

  /// Prevents over-shrinking tiny images while still giving us room to hit the byte budget.
  private static let minimumDimension: CGFloat = 512

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
    // Always use JPEG for chat API compatibility and predictable preview rendering.
    // The encoder now enforces both a dimension cap and a byte budget.
    guard let jpegData = compressedJPEGData(for: image, preferredQuality: quality) else {
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
    -> CompressedImage?
  {
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

  private static func compressedJPEGData(for image: UIImage, preferredQuality: CGFloat) -> Data? {
    let maxSide = max(image.size.width, image.size.height)
    guard maxSide > 0 else { return nil }

    var currentMaxDimension = min(maxSide, maxDimension)
    var bestAttempt: Data?

    while true {
      let scaledImage = resize(image, maxDimension: currentMaxDimension)

      for quality in compressionQualities(startingAt: preferredQuality) {
        guard let data = scaledImage.jpegData(compressionQuality: quality) else {
          continue
        }

        bestAttempt = data
        if data.count <= maxUploadBytes {
          return data
        }
      }

      guard currentMaxDimension > minimumDimension else {
        break
      }

      let nextDimension = floor(currentMaxDimension * iterativeDownscaleFactor)
      guard nextDimension < currentMaxDimension else {
        break
      }
      currentMaxDimension = max(minimumDimension, nextDimension)
    }

    guard let bestAttempt, bestAttempt.count <= maxUploadBytes else {
      return nil
    }

    return bestAttempt
  }

  private static func compressionQualities(startingAt preferredQuality: CGFloat) -> [CGFloat] {
    let initialQuality = min(max(preferredQuality, minimumQuality), 1)
    var qualities = [initialQuality]
    var currentQuality = initialQuality

    while currentQuality > minimumQuality {
      let nextQuality = max(minimumQuality, currentQuality - 0.1)
      guard nextQuality < currentQuality else { break }
      qualities.append(nextQuality)
      currentQuality = nextQuality
    }

    return qualities
  }

  private static func resize(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
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

    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    format.opaque = false

    let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
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
