import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "ImageCache")

// MARK: - Image Cache

/// Thread-safe in-memory image cache using NSCache
/// Automatically evicts images under memory pressure
final class ImageCache {
    static let shared = ImageCache()

    private let cache = NSCache<NSString, UIImage>()

    private init() {
        // Configure cache limits
        cache.countLimit = 100  // Max 100 images
        cache.totalCostLimit = 50 * 1024 * 1024  // 50MB max
    }

    func get(for url: URL) -> UIImage? {
        cache.object(forKey: url.absoluteString as NSString)
    }

    func set(_ image: UIImage, for url: URL) {
        // Estimate cost based on image dimensions
        let cost = Int(image.size.width * image.size.height * image.scale * 4)
        cache.setObject(image, forKey: url.absoluteString as NSString, cost: cost)
    }

    func remove(for url: URL) {
        cache.removeObject(forKey: url.absoluteString as NSString)
    }

    func clearAll() {
        cache.removeAllObjects()
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

        // Check cache first
        if let cached = ImageCache.shared.get(for: url) {
            loadedImage = cached
            return
        }

        isLoading = true

        // Fetch from network
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let image = UIImage(data: data) {
                    // Cache the image
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
