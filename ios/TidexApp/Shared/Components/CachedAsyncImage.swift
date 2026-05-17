import CryptoKit
import ImageIO
import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "ImageCache")

private enum NotificationAvatarSharedCache {
  private static let appGroupId = "group.no.tidex.app"
  private static let cacheDirectoryName = "NotificationAvatarCache"

  private static var cacheDirectory: URL? {
    guard
      let containerURL = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: appGroupId)
    else {
      return nil
    }

    let directory = containerURL.appendingPathComponent(cacheDirectoryName, isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  static func store(_ image: UIImage, for url: URL) {
    guard let cacheFileURL = cacheFileURL(for: url) else { return }

    let data = image.jpegData(compressionQuality: 0.85) ?? image.pngData()
    guard let data else { return }
    try? data.write(to: cacheFileURL, options: .atomic)
  }

  static func remove(for url: URL) {
    guard let cacheFileURL = cacheFileURL(for: url) else { return }
    try? FileManager.default.removeItem(at: cacheFileURL)
  }

  static func clearAll() {
    guard let directory = cacheDirectory else { return }
    try? FileManager.default.removeItem(at: directory)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  private static func cacheFileURL(for url: URL) -> URL? {
    guard let directory = cacheDirectory else { return nil }
    return directory.appendingPathComponent(fileName(for: url))
  }

  private static func fileName(for url: URL) -> String {
    SHA256.hash(data: Data(url.absoluteString.utf8))
      .compactMap { String(format: "%02x", $0) }
      .joined()
  }
}

// MARK: - Cached Image Wrapper

/// Wrapper class for UIImage that tracks when it was cached for expiration
/// Using a class wrapper because NSCache requires reference types
final class CachedImageWrapper {
  let image: UIImage
  let cachedAt: Date

  init(_ image: UIImage) {
    self.image = image
    self.cachedAt = Date()
  }

  /// Check if the cached image has expired
  /// - Parameter ttl: Time-to-live in seconds
  /// - Returns: True if the image has expired
  func isExpired(ttl: TimeInterval) -> Bool {
    Date().timeIntervalSince(cachedAt) > ttl
  }
}

// MARK: - Image Cache

/// Thread-safe image cache with both in-memory and disk persistence
/// Memory cache (NSCache) provides fast access and auto-evicts under memory pressure
/// Disk cache provides persistence across app restarts
/// Images expire after 1 hour to ensure fresh content when users update their profile pictures
final class ImageCache: @unchecked Sendable {
  static let shared = ImageCache()

  /// Time-to-live for cached images (1 hour)
  private let cacheTTL: TimeInterval = 3600

  private let memoryCache = NSCache<NSString, CachedImageWrapper>()
  private let fileManager = FileManager.default
  private let diskCacheQueue = DispatchQueue(label: "com.tidex.imagecache.disk", qos: .utility)
  private let diskCacheDirectory: URL

  private init() {
    // Configure memory cache limits
    memoryCache.countLimit = 100  // Max 100 images
    memoryCache.totalCostLimit = 50 * 1024 * 1024  // 50MB max

    // Setup disk cache directory
    let cacheDir =
      fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
      ?? fileManager.temporaryDirectory
    if cacheDir == fileManager.temporaryDirectory {
      logger.error("⚠️ Falling back to temporary directory for image cache")
    }
    diskCacheDirectory = cacheDir.appendingPathComponent("ImageCache", isDirectory: true)

    // Create directory if it doesn't exist
    try? fileManager.createDirectory(at: diskCacheDirectory, withIntermediateDirectories: true)
  }

  /// Get image from memory cache if not expired
  func get(for url: URL, maxPixelSize: CGFloat? = nil) -> UIImage? {
    let key = cacheKey(for: url, maxPixelSize: maxPixelSize)
    guard let wrapper = memoryCache.object(forKey: key as NSString) else {
      return nil
    }

    // Check if cached image has expired
    if wrapper.isExpired(ttl: cacheTTL) {
      logger.debug("🕐 Memory cache EXPIRED for: \(url.lastPathComponent)")
      memoryCache.removeObject(forKey: key as NSString)
      return nil
    }

    return wrapper.image
  }

  /// Get image from disk cache if not expired (async)
  func getFromDisk(for url: URL, maxPixelSize: CGFloat? = nil) async -> UIImage? {
    await withCheckedContinuation { continuation in
      diskCacheQueue.async { [weak self] in
        guard let self = self else {
          continuation.resume(returning: nil)
          return
        }

        let filePath = self.diskCachePath(for: url, maxPixelSize: maxPixelSize)
        let exists = self.fileManager.fileExists(atPath: filePath.path)

        if !exists {
          logger.debug("💾 Disk cache MISS for: \(url.lastPathComponent)")
          continuation.resume(returning: nil)
          return
        }

        // Check file modification date for expiration
        do {
          let attributes = try self.fileManager.attributesOfItem(atPath: filePath.path)
          if let modificationDate = attributes[.modificationDate] as? Date {
            let age = Date().timeIntervalSince(modificationDate)
            if age > self.cacheTTL {
              logger.debug("🕐 Disk cache EXPIRED for: \(url.lastPathComponent)")
              // Remove expired file
              try? self.fileManager.removeItem(at: filePath)
              continuation.resume(returning: nil)
              return
            }
          }
        } catch {
          logger.warning("Failed to check disk cache attributes: \(error.localizedDescription)")
        }

        if let data = try? Data(contentsOf: filePath),
          let image = Self.decodedImage(from: data, maxPixelSize: maxPixelSize)
        {
          logger.debug("💾 Disk cache HIT for: \(url.lastPathComponent)")
          // Also populate memory cache
          DispatchQueue.main.async {
            self.setMemoryCache(image, for: url, maxPixelSize: maxPixelSize)
          }
          continuation.resume(returning: image)
        } else {
          logger.warning("💾 Disk cache file exists but failed to load: \(url.lastPathComponent)")
          continuation.resume(returning: nil)
        }
      }
    }
  }

  /// Set image in memory cache only
  private func setMemoryCache(_ image: UIImage, for url: URL, maxPixelSize: CGFloat? = nil) {
    let wrapper = CachedImageWrapper(image)
    let pixelWidth = image.size.width * image.scale
    let pixelHeight = image.size.height * image.scale
    let cost = Int(pixelWidth * pixelHeight * 4)
    let key = cacheKey(for: url, maxPixelSize: maxPixelSize)
    memoryCache.setObject(wrapper, forKey: key as NSString, cost: cost)
  }

  /// Set image in both memory and disk cache
  func set(_ image: UIImage, for url: URL, maxPixelSize: CGFloat? = nil) {
    // Save to memory cache immediately
    setMemoryCache(image, for: url, maxPixelSize: maxPixelSize)

    // Save to disk cache asynchronously
    diskCacheQueue.async { [weak self] in
      guard let self = self else { return }

      let filePath = self.diskCachePath(for: url, maxPixelSize: maxPixelSize)

      // Use JPEG for photos, PNG for images with transparency
      if let data = image.jpegData(compressionQuality: 0.8) {
        do {
          try data.write(to: filePath)
          logger.debug("💾 Saved image to disk: \(url.lastPathComponent) (\(data.count) bytes)")
        } catch {
          logger.error("Failed to write image to disk: \(error.localizedDescription)")
        }
      } else {
        logger.warning("Failed to convert image to JPEG data for: \(url.lastPathComponent)")
      }
    }
  }

  func remove(for url: URL) {
    memoryCache.removeObject(forKey: cacheKey(for: url, maxPixelSize: nil) as NSString)
    NotificationAvatarSharedCache.remove(for: url)

    diskCacheQueue.async { [weak self] in
      guard let self = self else { return }
      guard
        let files = try? self.fileManager.contentsOfDirectory(
          at: self.diskCacheDirectory,
          includingPropertiesForKeys: nil
        )
      else { return }

      let urlPrefix = self.cacheKey(for: url, maxPixelSize: nil)
      for file in files where file.lastPathComponent.hasPrefix(urlPrefix) {
        try? self.fileManager.removeItem(at: file)
      }
    }
  }

  func clearAll() {
    memoryCache.removeAllObjects()
    NotificationAvatarSharedCache.clearAll()

    diskCacheQueue.async { [weak self] in
      guard let self = self else { return }
      try? self.fileManager.removeItem(at: self.diskCacheDirectory)
      try? self.fileManager.createDirectory(
        at: self.diskCacheDirectory, withIntermediateDirectories: true)
    }
  }

  /// Clear expired items from disk cache
  /// Call this periodically or on app launch to clean up stale entries
  func clearExpired() {
    diskCacheQueue.async { [weak self] in
      guard let self = self else { return }

      guard
        let files = try? self.fileManager.contentsOfDirectory(
          at: self.diskCacheDirectory,
          includingPropertiesForKeys: [.contentModificationDateKey]
        )
      else { return }

      var removedCount = 0
      for file in files {
        do {
          let attributes = try self.fileManager.attributesOfItem(atPath: file.path)
          if let modificationDate = attributes[.modificationDate] as? Date {
            let age = Date().timeIntervalSince(modificationDate)
            if age > self.cacheTTL {
              try self.fileManager.removeItem(at: file)
              removedCount += 1
            }
          }
        } catch {
          // Ignore errors for individual files
        }
      }

      if removedCount > 0 {
        logger.info("🧹 Cleared \(removedCount) expired images from disk cache")
      }
    }
  }

  /// Generate a unique filename for the URL using SHA256 hash
  private func diskCachePath(for url: URL, maxPixelSize: CGFloat? = nil) -> URL {
    diskCacheDirectory.appendingPathComponent(cacheKey(for: url, maxPixelSize: maxPixelSize))
  }

  private func cacheKey(for url: URL, maxPixelSize: CGFloat? = nil) -> String {
    let hash = SHA256.hash(data: Data(url.absoluteString.utf8))
    let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()
    guard let maxPixelSize, maxPixelSize > 0 else { return hashString }
    return "\(hashString)-px\(Int(maxPixelSize.rounded(.up)))"
  }

  nonisolated static func decodedImage(from data: Data, maxPixelSize: CGFloat?) -> UIImage? {
    guard let maxPixelSize, maxPixelSize > 0 else {
      return UIImage(data: data)
    }

    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
      return UIImage(data: data)
    }

    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceThumbnailMaxPixelSize: Int(maxPixelSize.rounded(.up)),
    ]

    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    else {
      return UIImage(data: data)
    }

    return UIImage(cgImage: cgImage)
  }
}

// MARK: - Cached Async Image

/// A SwiftUI view that loads and caches images from URLs
/// Uses NSCache for in-memory caching to avoid re-fetching on every render
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
  let url: URL?
  let syncToNotificationServiceCache: Bool
  let maxPixelSize: CGFloat?
  let content: (Image) -> Content
  let placeholder: () -> Placeholder

  @State private var loadedImage: UIImage?
  @State private var isLoading = false
  @State private var loadingTask: Task<Void, Never>?

  init(
    url: URL?,
    syncToNotificationServiceCache: Bool = false,
    maxPixelSize: CGFloat? = nil,
    @ViewBuilder content: @escaping (Image) -> Content,
    @ViewBuilder placeholder: @escaping () -> Placeholder
  ) {
    self.url = url
    self.syncToNotificationServiceCache = syncToNotificationServiceCache
    self.maxPixelSize = maxPixelSize
    self.content = content
    self.placeholder = placeholder
  }

  var body: some View {
    Group {
      if let image = loadedImage {
        content(Image(uiImage: image))
      } else {
        placeholder()
          .onAppear {
            loadImage()
          }
      }
    }
    .onChange(of: url) { _, newUrl in
      // Reset and reload if URL changes
      loadingTask?.cancel()
      isLoading = false
      loadedImage = nil
      loadImage(for: newUrl)
    }
    .onDisappear {
      loadingTask?.cancel()
      loadingTask = nil
      isLoading = false
    }
  }

  private func loadImage() {
    loadImage(for: url)
  }

  private func loadImage(for url: URL?) {
    guard let url else { return }
    guard !isLoading else { return }

    // Check memory cache first (synchronous, fast)
    if let cached = ImageCache.shared.get(for: url, maxPixelSize: maxPixelSize) {
      if syncToNotificationServiceCache {
        NotificationAvatarSharedCache.store(cached, for: url)
      }
      loadedImage = cached
      return
    }

    isLoading = true

    loadingTask = Task {
      // Check disk cache second (async but no network)
      if let diskCached = await ImageCache.shared.getFromDisk(
        for: url,
        maxPixelSize: maxPixelSize
      ) {
        guard !Task.isCancelled else { return }
        if syncToNotificationServiceCache {
          NotificationAvatarSharedCache.store(diskCached, for: url)
        }
        await MainActor.run {
          guard self.url == url else { return }
          loadedImage = diskCached
          isLoading = false
          loadingTask = nil
        }
        return
      }

      // Fetch from network as last resort
      do {
        let (data, _) = try await URLSession.shared.data(from: url)
        guard !Task.isCancelled else { return }
        if let image = ImageCache.decodedImage(from: data, maxPixelSize: maxPixelSize) {
          // Cache the image (memory + disk)
          ImageCache.shared.set(image, for: url, maxPixelSize: maxPixelSize)
          if syncToNotificationServiceCache {
            NotificationAvatarSharedCache.store(image, for: url)
          }

          await MainActor.run {
            guard self.url == url else { return }
            loadedImage = image
            isLoading = false
            loadingTask = nil
          }
        } else {
          await MainActor.run {
            guard self.url == url else { return }
            isLoading = false
            loadingTask = nil
          }
        }
      } catch is CancellationError {
        await MainActor.run {
          guard self.url == url else { return }
          isLoading = false
          loadingTask = nil
        }
      } catch {
        logger.error("Failed to load image: \(error.localizedDescription)")
        await MainActor.run {
          guard self.url == url else { return }
          isLoading = false
          loadingTask = nil
        }
      }
    }
  }
}

// MARK: - Convenience Initializers

extension CachedAsyncImage where Placeholder == EmptyView {
  init(
    url: URL?,
    @ViewBuilder content: @escaping (Image) -> Content
  ) {
    self.init(
      url: url,
      syncToNotificationServiceCache: false,
      content: content,
      placeholder: { EmptyView() }
    )
  }
}

extension CachedAsyncImage
where Content == Image, Placeholder == ProgressView<EmptyView, EmptyView> {
  init(url: URL?) {
    self.init(
      url: url,
      syncToNotificationServiceCache: false,
      content: { $0 },
      placeholder: { ProgressView() }
    )
  }
}
