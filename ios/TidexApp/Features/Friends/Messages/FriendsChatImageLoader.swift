import ExyteChat
import ImageIO
import SwiftUI
import UIKit

@MainActor
@Observable
final class FriendsChatImageLoader {
  enum Variant {
    case original
    case display(pixelSize: CGSize)
  }

  private(set) var image: UIImage?
  private(set) var isLoading: Bool = false
  private(set) var didFail: Bool = false

  private let variant: Variant

  init(initialImage: UIImage? = nil, variant: Variant = .original) {
    image = initialImage
    self.variant = variant
  }

  deinit {
    // Required by lint policy for explicit class teardown.
  }

  func loadIfNeeded(attachment: FriendMessageAttachment) async {
    if let image {
      self.image = image
      return
    }

    let cacheURL: URL = Self.cacheURL(for: attachment.storagePath, variant: variant)

    if let cached = await cachedImage(for: cacheURL) {
      image = cached
      didFail = false
      return
    }

    if let cached = await originalCachedImageFallback(
      storagePath: attachment.storagePath,
      displayCacheURL: cacheURL
    ) {
      image = cached
      didFail = false
      return
    }

    guard !isLoading else {
      return
    }
    didFail = false
    isLoading = true
    defer { isLoading = false }

    do {
      let data: Data = try await FriendsMessagingService.shared.downloadAttachmentData(
        path: attachment.storagePath
      )
      try Task.checkCancellation()
      guard let loadedImage = await Self.decodeImage(from: data, variant: variant) else {
        return
      }
      try Task.checkCancellation()
      ImageCache.shared.set(loadedImage, for: cacheURL, policy: .messageAttachment)
      image = loadedImage
      didFail = false
    } catch is CancellationError {
      didFail = false
    } catch {
      image = nil
      didFail = true
    }
  }

  private func cachedImage(for cacheURL: URL) async -> UIImage? {
    if let cached = ImageCache.shared.get(for: cacheURL, policy: .messageAttachment) {
      return cached
    }

    return await ImageCache.shared.getFromDisk(for: cacheURL, policy: .messageAttachment)
  }

  private func originalCachedImageFallback(
    storagePath: String,
    displayCacheURL: URL
  ) async -> UIImage? {
    guard case .display = variant else {
      return nil
    }

    let originalCacheURL: URL = Self.cacheURL(for: storagePath, variant: .original)
    guard let cached = await cachedImage(for: originalCacheURL) else {
      return nil
    }
    let displayImage: UIImage = await Self.displayImage(from: cached, variant: variant)
    ImageCache.shared.set(displayImage, for: displayCacheURL, policy: .messageAttachment)
    return displayImage
  }

  nonisolated static func cacheURL(for storagePath: String, variant: Variant = .original) -> URL {
    var components: URLComponents = URLComponents()
    components.scheme = "https"
    components.host = "friends-message-cache.local"
    components.path = "/\(storagePath)"
    switch variant {
    case .original:
      break

    case .display(let pixelSize):
      let width: Int = Int(pixelSize.width.rounded())
      let height: Int = Int(pixelSize.height.rounded())
      components.queryItems = [
        URLQueryItem(name: "variant", value: "display"),
        URLQueryItem(name: "w", value: "\(width)"),
        URLQueryItem(name: "h", value: "\(height)"),
      ]
    }
    return components.url ?? URL(filePath: "/tmp/friends-message-cache-fallback")
  }

  nonisolated private static func decodeImage(from data: Data, variant: Variant) async -> UIImage? {
    await Task.detached(priority: .utility) {
      autoreleasepool {
        switch variant {
        case .original:
          UIImage(data: data)

        case .display(let pixelSize):
          downsampleImage(from: data, pixelSize: pixelSize)
        }
      }
    }.value
  }

  nonisolated private static func downsampleImage(from data: Data, pixelSize: CGSize) -> UIImage? {
    let targetPixelSize: CGSize = normalizedPixelSize(pixelSize)
    let maxPixelSize: CGFloat = max(targetPixelSize.width, targetPixelSize.height)
    guard maxPixelSize > 0 else {
      return UIImage(data: data)
    }
    guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil) else {
      return UIImage(data: data)
    }
    let thumbnailMaxPixelSize: Int = thumbnailMaxPixelSize(
      for: imageSource,
      targetPixelSize: targetPixelSize
    )

    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceThumbnailMaxPixelSize: thumbnailMaxPixelSize,
    ]

    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary)
    else {
      return UIImage(data: data)
    }

    return UIImage(cgImage: cgImage)
  }

  nonisolated private static func displayImage(from image: UIImage, variant: Variant) async
    -> UIImage
  {
    await Task.detached(priority: .utility) {
      autoreleasepool {
        resizedDisplayImage(from: image, variant: variant)
      }
    }.value
  }

  nonisolated private static func resizedDisplayImage(from image: UIImage, variant: Variant)
    -> UIImage
  {
    guard case .display(let pixelSize) = variant else {
      return image
    }
    let targetPixelSize: CGSize = normalizedPixelSize(pixelSize)
    guard max(targetPixelSize.width, targetPixelSize.height) > 0 else {
      return image
    }

    let sourcePixelWidth: CGFloat = image.size.width * image.scale
    let sourcePixelHeight: CGFloat = image.size.height * image.scale
    let sourcePixelSize: CGSize = CGSize(width: sourcePixelWidth, height: sourcePixelHeight)
    let resizedPixelSize: CGSize = coverPixelSize(
      for: sourcePixelSize,
      targetPixelSize: targetPixelSize
    )
    guard resizedPixelSize != sourcePixelSize else {
      return image
    }

    let format: UIGraphicsImageRendererFormat = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = false

    return UIGraphicsImageRenderer(size: resizedPixelSize, format: format).image { _ in
      image.draw(in: CGRect(origin: .zero, size: resizedPixelSize))
    }
  }

  nonisolated private static func normalizedPixelSize(_ pixelSize: CGSize) -> CGSize {
    CGSize(
      width: max(0, pixelSize.width.rounded(.up)),
      height: max(0, pixelSize.height.rounded(.up))
    )
  }

  nonisolated private static func thumbnailMaxPixelSize(
    for imageSource: CGImageSource,
    targetPixelSize: CGSize
  ) -> Int {
    guard
      let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil)
        as? [CFString: Any],
      let pixelWidth = cgFloatProperty(kCGImagePropertyPixelWidth, in: properties),
      let pixelHeight = cgFloatProperty(kCGImagePropertyPixelHeight, in: properties)
    else {
      return Int(max(1, max(targetPixelSize.width, targetPixelSize.height)).rounded(.up))
    }

    let sourcePixelSize: CGSize = orientedPixelSize(
      width: pixelWidth,
      height: pixelHeight,
      properties: properties
    )
    let resizedPixelSize: CGSize = coverPixelSize(
      for: sourcePixelSize,
      targetPixelSize: targetPixelSize
    )
    return Int(max(resizedPixelSize.width, resizedPixelSize.height).rounded(.up))
  }

  nonisolated private static func orientedPixelSize(
    width: CGFloat,
    height: CGFloat,
    properties: [CFString: Any]
  ) -> CGSize {
    let orientation: Int? = intProperty(kCGImagePropertyOrientation, in: properties)
    if let orientation, [5, 6, 7, 8].contains(orientation) {
      return CGSize(width: height, height: width)
    }
    return CGSize(width: width, height: height)
  }

  nonisolated private static func cgFloatProperty(
    _ key: CFString,
    in properties: [CFString: Any]
  ) -> CGFloat? {
    if let number = properties[key] as? NSNumber {
      return CGFloat(truncating: number)
    }
    return properties[key] as? CGFloat
  }

  nonisolated private static func intProperty(
    _ key: CFString,
    in properties: [CFString: Any]
  ) -> Int? {
    if let number = properties[key] as? NSNumber {
      return number.intValue
    }
    return properties[key] as? Int
  }

  nonisolated private static func coverPixelSize(
    for sourcePixelSize: CGSize,
    targetPixelSize: CGSize
  ) -> CGSize {
    let sourceWidth: CGFloat = sourcePixelSize.width
    let sourceHeight: CGFloat = sourcePixelSize.height
    let targetWidth: CGFloat = targetPixelSize.width
    let targetHeight: CGFloat = targetPixelSize.height
    guard sourceWidth > 0, sourceHeight > 0, targetWidth > 0, targetHeight > 0 else {
      return sourcePixelSize
    }

    let scale: CGFloat = min(1, max(targetWidth / sourceWidth, targetHeight / sourceHeight))
    guard scale < 1 else {
      return sourcePixelSize
    }

    return CGSize(
      width: max(1, (sourceWidth * scale).rounded(.up)),
      height: max(1, (sourceHeight * scale).rounded(.up))
    )
  }
}