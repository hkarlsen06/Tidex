/// Global tracker for which views have already appeared
/// Uses a simple LRU cache to avoid unbounded memory growth
/// Reset this when navigating to a new month to allow fresh animations
final class AppearanceTracker {
  static let shared = AppearanceTracker()

  private var appearedIds = Set<String>()
  private var accessOrder: [String] = []
  private let maxTracked = 200

  private init() {}

  func hasAppeared(_ id: String) -> Bool {
    return appearedIds.contains(id)
  }

  func markAppeared(_ id: String) {
    if appearedIds.insert(id).inserted {
      accessOrder.append(id)
      // Evict oldest if over limit
      while appearedIds.count > maxTracked {
        if let oldest = accessOrder.first {
          accessOrder.removeFirst()
          appearedIds.remove(oldest)
        }
      }
    }
  }

  /// Reset the tracker (call when changing months or on pull-to-refresh)
  func reset() {
    appearedIds.removeAll()
    accessOrder.removeAll()
  }
}
