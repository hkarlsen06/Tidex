import SwiftUI
import CryptoKit
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "ImageCache")

// MARK: - Image Cache

/// Thread-safe image cache with both in-memory and disk persistence
/// Memory cache (NSCache) provides fast access and auto-evicts under memory pressure
/// Disk cache provides persistence across app restarts
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()

    private let memoryCache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    private let diskCacheQueue = DispatchQueue(label: "com.tidex.imagecache.disk", qos: .utility)
    private let diskCacheDirectory: URL

    private init() {
        // Configure memory cache limits
        memoryCache.countLimit = 100  // Max 100 images
        memoryCache.totalCostLimit = 50 * 1024 * 1024  // 50MB max

        // Setup disk cache directory
        let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        diskCacheDirectory = cacheDir.appendingPathComponent("ImageCache", isDirectory: true)

        // Create directory if it doesn't exist
        try? fileManager.createDirectory(at: diskCacheDirectory, withIntermediateDirectories: true)
    }

    /// Get image from memory cache
    func get(for url: URL) -> UIImage? {
        memoryCache.object(forKey: url.absoluteString as NSString)
    }

    /// Get image from disk cache (async)
    func getFromDisk(for url: URL) async -> UIImage? {
        await withCheckedContinuation { continuation in
            diskCacheQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: nil)
                    return
                }

                let filePath = self.diskCachePath(for: url)
                let exists = self.fileManager.fileExists(atPath: filePath.path)

                if !exists {
                    logger.debug("💾 Disk cache MISS for: \(url.lastPathComponent)")
                    continuation.resume(returning: nil)
                    return
                }

                if let data = try? Data(contentsOf: filePath),
                   let image = UIImage(data: data) {
                    logger.debug("💾 Disk cache HIT for: \(url.lastPathComponent)")
                    // Also populate memory cache
                    DispatchQueue.main.async {
                        self.setMemoryCache(image, for: url)
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
    private func setMemoryCache(_ image: UIImage, for url: URL) {
        let cost = Int(image.size.width * image.size.height * image.scale * 4)
        memoryCache.setObject(image, forKey: url.absoluteString as NSString, cost: cost)
    }

    /// Set image in both memory and disk cache
    func set(_ image: UIImage, for url: URL) {
        // Save to memory cache immediately
        setMemoryCache(image, for: url)

        // Save to disk cache asynchronously
        diskCacheQueue.async { [weak self] in
            guard let self = self else { return }

            let filePath = self.diskCachePath(for: url)

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
        memoryCache.removeObject(forKey: url.absoluteString as NSString)

        diskCacheQueue.async { [weak self] in
            guard let self = self else { return }
            let filePath = self.diskCachePath(for: url)
            try? self.fileManager.removeItem(at: filePath)
        }
    }

    func clearAll() {
        memoryCache.removeAllObjects()

        diskCacheQueue.async { [weak self] in
            guard let self = self else { return }
            try? self.fileManager.removeItem(at: self.diskCacheDirectory)
            try? self.fileManager.createDirectory(at: self.diskCacheDirectory, withIntermediateDirectories: true)
        }
    }

    /// Generate a unique filename for the URL using SHA256 hash
    private func diskCachePath(for url: URL) -> URL {
        let hash = SHA256.hash(data: Data(url.absoluteString.utf8))
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()
        return diskCacheDirectory.appendingPathComponent(hashString)
    }
}

// MARK: - Cached Async Image

/// A SwiftUI view that loads and caches images from URLs
/// Uses NSCache for in-memory caching to avoid re-fetching on every render
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let content: (Image) -> Content
    let placeholder: () -> Placeholder

    @State private var loadedImage: UIImage?
    @State private var isLoading = false

    init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
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
            loadedImage = nil
            loadImage()
        }
    }

    private func loadImage() {
        guard let url = url else { return }
        guard !isLoading else { return }

        // Check memory cache first (synchronous, fast)
        if let cached = ImageCache.shared.get(for: url) {
            loadedImage = cached
            return
        }

        isLoading = true

        Task {
            // Check disk cache second (async but no network)
            if let diskCached = await ImageCache.shared.getFromDisk(for: url) {
                await MainActor.run {
                    loadedImage = diskCached
                    isLoading = false
                }
                return
            }

            // Fetch from network as last resort
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let image = UIImage(data: data) {
                    // Cache the image (memory + disk)
                    ImageCache.shared.set(image, for: url)

                    await MainActor.run {
                        loadedImage = image
                        isLoading = false
                    }
                } else {
                    await MainActor.run {
                        isLoading = false
                    }
                }
            } catch {
                logger.error("Failed to load image: \(error.localizedDescription)")
                await MainActor.run {
                    isLoading = false
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
        self.init(url: url, content: content, placeholder: { EmptyView() })
    }
}

extension CachedAsyncImage where Content == Image, Placeholder == ProgressView<EmptyView, EmptyView> {
    init(url: URL?) {
        self.init(
            url: url,
            content: { $0 },
            placeholder: { ProgressView() }
        )
    }
}
