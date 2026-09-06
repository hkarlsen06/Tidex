// swiftlint:disable:next blanket_disable_command
// swiftlint:disable line_length superfluous_disable_command
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable accessibility_label_for_image closure_body_length conditional_returns_on_newline cyclomatic_complexity
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable explicit_acl explicit_top_level_acl explicit_type_interface file_length
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable function_body_length large_tuple legacy_objc_type multiline_arguments_brackets
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable no_magic_numbers number_separator prefixed_toplevel_constant redundant_self
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable required_deinit shorthand_optional_binding sorted_imports strict_fileprivate
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable type_body_length type_contents_order vertical_whitespace_between_cases
import CryptoKit
import ImageIO
import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "ImageCache")

final class NotificationAvatarSharedCache: @unchecked Sendable {
  static let shared = NotificationAvatarSharedCache(
    directory: FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: "group.no.tidex.app"
    )?.appendingPathComponent("NotificationAvatarCache", isDirectory: true)
  )

  private let directory: URL?
  private let queue: DispatchQueue

  init(
    directory: URL?,
    queue: DispatchQueue = DispatchQueue(label: "com.tidex.notificationavatar.disk", qos: .utility)
  ) {
    self.directory = directory
    self.queue = queue
  }

  func store(_ image: UIImage, for url: URL) {
    queue.async { [self] in
      guard let cacheFileURL = cacheFileURL(for: url) else { return }

      let data = image.jpegData(compressionQuality: 0.85) ?? image.pngData()
      guard let data else { return }
      try? data.write(to: cacheFileURL, options: .atomic)
    }
  }

  func remove(for url: URL) {
    queue.async { [self] in
      guard let cacheFileURL = cacheFileURL(for: url) else { return }
      try? FileManager.default.removeItem(at: cacheFileURL)
    }
  }

  func clearAll() {
    queue.async { [self] in
      guard let directory else { return }
      try? FileManager.default.removeItem(at: directory)
      try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
  }

  private func cacheFileURL(for url: URL) -> URL? {
    guard let directory else { return nil }
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent(fileName(for: url))
  }

  private func fileName(for url: URL) -> String {
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

enum ImageCachePolicy: Equatable {
  case defaultImage
  case messageAttachment

  var ttl: TimeInterval {
    switch self {
    case .defaultImage:
      return 3_600

    case .messageAttachment:
      return 60 * 60 * 24 * 90
    }
  }

  var diskSizeLimit: Int64? {
    switch self {
    case .defaultImage:
      return nil

    case .messageAttachment:
      return 1_000 * 1_024 * 1_024
    }
  }

  fileprivate var cacheKeyPrefix: String? {
    switch self {
    case .defaultImage:
      return nil

    case .messageAttachment:
      return "message-attachment"
    }
  }
}

/// Thread-safe image cache with both in-memory and disk persistence
/// Memory cache (NSCache) provides fast access and auto-evicts under memory pressure
/// Disk cache provides persistence across app restarts
/// Default images expire after 1 hour; message attachments are retained longer because their
/// storage paths are stable and expensive to refetch.
final class ImageCache: @unchecked Sendable {
  static let shared = ImageCache()

  private let memoryCache = NSCache<NSString, CachedImageWrapper>()
  private let memoryCacheLock = NSLock()
  private var invalidationGeneration: UInt64 = 0
  private let fileManager = FileManager.default
  private let diskCacheQueue: DispatchQueue
  private let diskCacheDirectory: URL

  init(
    directory: URL? = nil,
    queue: DispatchQueue = DispatchQueue(label: "com.tidex.imagecache.disk", qos: .utility)
  ) {
    diskCacheQueue = queue
    // Configure memory cache limits
    memoryCache.countLimit = 100  // Max 100 images
    memoryCache.totalCostLimit = 50 * 1_024 * 1_024  // 50MB max

    // Setup disk cache directory
    let cacheDir =
      fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
      ?? fileManager.temporaryDirectory
    if cacheDir == fileManager.temporaryDirectory {
      logger.error("⚠️ Falling back to temporary directory for image cache")
    }
    diskCacheDirectory =
      directory ?? cacheDir.appendingPathComponent("ImageCache", isDirectory: true)

    // Create directory if it doesn't exist
    try? fileManager.createDirectory(at: diskCacheDirectory, withIntermediateDirectories: true)
  }

  /// Get image from memory cache if not expired
  func get(
    for url: URL,
    maxPixelSize: CGFloat? = nil,
    policy: ImageCachePolicy = .defaultImage
  ) -> UIImage? {
    let key = cacheKey(for: url, maxPixelSize: maxPixelSize, policy: policy)
    guard let wrapper = memoryCache.object(forKey: key as NSString) else {
      return nil
    }

    // Check if cached image has expired
    if wrapper.isExpired(ttl: policy.ttl) {
      logger.debug("🕐 Memory cache EXPIRED for: \(url.lastPathComponent)")
      memoryCache.removeObject(forKey: key as NSString)
      return nil
    }

    return wrapper.image
  }

  /// Get image from disk cache if not expired (async)
  func getFromDisk(
    for url: URL,
    maxPixelSize: CGFloat? = nil,
    policy: ImageCachePolicy = .defaultImage
  ) async -> UIImage? {
    let generation = memoryCacheGeneration()
    let image: UIImage? = await withCheckedContinuation { continuation in
      diskCacheQueue.async { [weak self] in
        guard let self else {
          continuation.resume(returning: nil)
          return
        }

        let filePath = diskCachePath(for: url, maxPixelSize: maxPixelSize, policy: policy)
        let exists = fileManager.fileExists(atPath: filePath.path)

        if !exists {
          logger.debug("💾 Disk cache MISS for: \(url.lastPathComponent)")
          continuation.resume(returning: nil)
          return
        }

        // Check file modification date for expiration
        do {
          let attributes = try fileManager.attributesOfItem(atPath: filePath.path)
          if let modificationDate = attributes[.modificationDate] as? Date {
            let age = Date().timeIntervalSince(modificationDate)
            if age > policy.ttl {
              logger.debug("🕐 Disk cache EXPIRED for: \(url.lastPathComponent)")
              // Remove expired file
              try? fileManager.removeItem(at: filePath)
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
            self.memoryCacheLock.lock()
            defer { self.memoryCacheLock.unlock() }
            guard self.invalidationGeneration == generation else { return }
            self.setMemoryCache(image, for: url, maxPixelSize: maxPixelSize, policy: policy)
          }
          continuation.resume(returning: image)
        } else {
          logger.warning("💾 Disk cache file exists but failed to load: \(url.lastPathComponent)")
          continuation.resume(returning: nil)
        }
      }
    }
    // A read may finish while removal or sign-out is clearing the cache.
    guard memoryCacheGeneration() == generation else { return nil }
    return image
  }

  private func memoryCacheGeneration() -> UInt64 {
    memoryCacheLock.lock()
    defer { memoryCacheLock.unlock() }
    return invalidationGeneration
  }

  private func invalidateMemoryCache() {
    memoryCacheLock.lock()
    defer { memoryCacheLock.unlock() }
    invalidationGeneration &+= 1
    memoryCache.removeAllObjects()
  }

  /// Set image in memory cache only
  private func setMemoryCache(
    _ image: UIImage,
    for url: URL,
    maxPixelSize: CGFloat? = nil,
    policy: ImageCachePolicy = .defaultImage
  ) {
    let wrapper = CachedImageWrapper(image)
    let pixelWidth = image.size.width * image.scale
    let pixelHeight = image.size.height * image.scale
    let cost = Int(pixelWidth * pixelHeight * 4)
    let key = cacheKey(for: url, maxPixelSize: maxPixelSize, policy: policy)
    memoryCache.setObject(wrapper, forKey: key as NSString, cost: cost)
  }

  /// Set image in both memory and disk cache
  func set(
    _ image: UIImage,
    for url: URL,
    maxPixelSize: CGFloat? = nil,
    policy: ImageCachePolicy = .defaultImage
  ) {
    // Save to memory cache immediately
    setMemoryCache(image, for: url, maxPixelSize: maxPixelSize, policy: policy)

    // Save to disk cache asynchronously
    diskCacheQueue.async { [weak self] in
      guard let self else { return }

      let filePath = diskCachePath(for: url, maxPixelSize: maxPixelSize, policy: policy)

      // Use JPEG for photos, PNG for images with transparency
      if let data = image.jpegData(compressionQuality: 0.8) {
        do {
          try data.write(to: filePath)
          logger.debug("💾 Saved image to disk: \(url.lastPathComponent) (\(data.count) bytes)")
          trimDiskCacheIfNeeded(for: policy)
        } catch {
          logger.error("Failed to write image to disk: \(error.localizedDescription)")
        }
      } else {
        logger.warning("Failed to convert image to JPEG data for: \(url.lastPathComponent)")
      }
    }
  }

  func remove(for url: URL) {
    // NSCache cannot enumerate keys. Explicit removals are rare, so evict memory
    // entries to invalidate every pixel-size and policy variant of this URL.
    // Unrelated images remain available in the disk cache.
    invalidateMemoryCache()
    NotificationAvatarSharedCache.shared.remove(for: url)

    diskCacheQueue.async { [weak self] in
      guard let self else { return }
      guard
        let files = try? fileManager.contentsOfDirectory(
          at: diskCacheDirectory,
          includingPropertiesForKeys: nil
        )
      else { return }

      let urlPrefixes = [ImageCachePolicy.defaultImage, .messageAttachment].map {
        self.cacheKey(for: url, maxPixelSize: nil, policy: $0)
      }
      for file in files where urlPrefixes.contains(where: file.lastPathComponent.hasPrefix) {
        try? fileManager.removeItem(at: file)
      }
    }
  }

  func clearAll() {
    invalidateMemoryCache()
    NotificationAvatarSharedCache.shared.clearAll()

    diskCacheQueue.async { [weak self] in
      guard let self else { return }
      try? fileManager.removeItem(at: diskCacheDirectory)
      try? fileManager.createDirectory(
        at: diskCacheDirectory, withIntermediateDirectories: true)
    }
  }

  /// Clear expired items from disk cache
  /// Call this periodically or on app launch to clean up stale entries
  func clearExpired() {
    diskCacheQueue.async { [weak self] in
      guard let self else { return }

      guard
        let files = try? fileManager.contentsOfDirectory(
          at: diskCacheDirectory,
          includingPropertiesForKeys: [.contentModificationDateKey]
        )
      else { return }

      var removedCount = 0
      for file in files {
        do {
          let attributes = try fileManager.attributesOfItem(atPath: file.path)
          if let modificationDate = attributes[.modificationDate] as? Date {
            let age = Date().timeIntervalSince(modificationDate)
            if age > cachePolicy(for: file).ttl {
              try fileManager.removeItem(at: file)
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

      trimDiskCacheIfNeeded(for: .messageAttachment)
    }
  }

  /// Generate a unique filename for the URL using SHA256 hash
  private func diskCachePath(
    for url: URL,
    maxPixelSize: CGFloat? = nil,
    policy: ImageCachePolicy = .defaultImage
  ) -> URL {
    diskCacheDirectory.appendingPathComponent(
      cacheKey(for: url, maxPixelSize: maxPixelSize, policy: policy)
    )
  }

  private func cacheKey(
    for url: URL,
    maxPixelSize: CGFloat? = nil,
    policy: ImageCachePolicy = .defaultImage
  ) -> String {
    let hash = SHA256.hash(data: Data(url.absoluteString.utf8))
    var key = hash.compactMap { String(format: "%02x", $0) }.joined()
    if let prefix = policy.cacheKeyPrefix {
      key = "\(prefix)-\(key)"
    }
    guard let maxPixelSize, maxPixelSize > 0 else { return key }
    return "\(key)-px\(Int(maxPixelSize.rounded(.up)))"
  }

  private func cachePolicy(for file: URL) -> ImageCachePolicy {
    file.lastPathComponent.hasPrefix("message-attachment-")
      ? .messageAttachment
      : .defaultImage
  }

  private func trimDiskCacheIfNeeded(for policy: ImageCachePolicy) {
    guard let diskSizeLimit = policy.diskSizeLimit else { return }
    guard
      let files = try? fileManager.contentsOfDirectory(
        at: diskCacheDirectory,
        includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
      )
    else { return }

    var entries: [(url: URL, size: Int64, modificationDate: Date)] = []
    var totalSize: Int64 = 0

    for file in files where cachePolicy(for: file) == policy {
      do {
        let resourceValues = try file.resourceValues(forKeys: [
          .contentModificationDateKey,
          .fileSizeKey,
        ])
        let size = Int64(resourceValues.fileSize ?? 0)
        let modificationDate = resourceValues.contentModificationDate ?? .distantPast
        entries.append((file, size, modificationDate))
        totalSize += size
      } catch {
        continue
      }
    }

    guard totalSize > diskSizeLimit else { return }

    var removedCount = 0
    for entry in entries.sorted(by: { $0.modificationDate < $1.modificationDate }) {
      guard totalSize > diskSizeLimit else { break }
      do {
        try fileManager.removeItem(at: entry.url)
        totalSize -= entry.size
        removedCount += 1
      } catch {
        continue
      }
    }

    if removedCount > 0 {
      logger.info("🧹 Trimmed \(removedCount) message attachment images from disk cache")
    }
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
        NotificationAvatarSharedCache.shared.store(cached, for: url)
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
          NotificationAvatarSharedCache.shared.store(diskCached, for: url)
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
        let pixelSize = maxPixelSize
        let decodeTask = Task.detached(priority: .userInitiated) { () -> UIImage? in
          guard !Task.isCancelled else { return nil }
          return ImageCache.decodedImage(from: data, maxPixelSize: pixelSize)
        }
        let image = await withTaskCancellationHandler {
          await decodeTask.value
        } onCancel: {
          decodeTask.cancel()
        }
        guard !Task.isCancelled else { return }
        if let image {
          // Cache the image (memory + disk)
          ImageCache.shared.set(image, for: url, maxPixelSize: maxPixelSize)
          if syncToNotificationServiceCache {
            NotificationAvatarSharedCache.shared.store(image, for: url)
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
