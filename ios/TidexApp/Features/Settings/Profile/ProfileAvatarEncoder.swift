import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Encodes a picked profile picture in the smallest upload format the device supports.
/// Priority is WebP, then HEIC, then the original bytes as JPEG.
enum ProfileAvatarEncoder {
  struct PreparedUpload: Sendable {
    let data: Data
    let contentType: String
    let fileExtension: String
  }

  nonisolated private static let compressionQuality: CGFloat = 0.8

  /// Convert image data to WebP format for smaller file sizes
  /// - Parameter imageData: Source image data (JPEG, PNG, etc.)
  /// - Returns: WebP data or nil if conversion fails
  private nonisolated static func convertToWebP(
    _ imageData: Data,
    quality: CGFloat = compressionQuality
  ) -> Data? {
    guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
      let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
      return nil
    }

    // Check if WebP encoding is supported
    let supportedTypes = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
    let webpSupported = supportedTypes.contains(UTType.webP.identifier)

    if !webpSupported {
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

  /// Convert image data to HEIC format (fallback when WebP unavailable)
  /// HEIC offers ~50% smaller files than JPEG with similar quality
  private nonisolated static func convertToHEIC(
    _ imageData: Data,
    quality: CGFloat = compressionQuality
  ) -> Data? {
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

  /// Prepare image bytes for upload off the main actor.
  /// Keeps UI responsive while running expensive image encoding.
  nonisolated static func prepareUpload(_ imageData: Data) async -> PreparedUpload {
    await Task.detached(priority: .userInitiated) {
      if let webpData = convertToWebP(imageData, quality: compressionQuality) {
        return PreparedUpload(
          data: webpData,
          contentType: "image/webp",
          fileExtension: "webp"
        )
      }
      if let heicData = convertToHEIC(imageData, quality: compressionQuality) {
        // HEIC fallback - ~50% smaller than JPEG, supported since iOS 11
        return PreparedUpload(
          data: heicData,
          contentType: "image/heic",
          fileExtension: "heic"
        )
      }
      // Final fallback to JPEG
      return PreparedUpload(
        data: imageData,
        contentType: "image/jpeg",
        fileExtension: "jpg"
      )
    }.value
  }
}
