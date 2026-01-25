import SwiftUI

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

/// A modifier that animates a view when it first appears, with optional staggered delay
/// Uses spring animation matching the web app's motion config (stiffness: 300, damping: 30)
/// IMPORTANT: This modifier tracks appearances globally to avoid re-animating on scroll
struct ScrollAppearModifier: ViewModifier {
    let index: Int
    let staggerDelay: Double
    let animateFromBottom: Bool
    let trackingId: String?

    @State private var hasAppeared = false

    // Default stagger of 0.03s matches web app's animation timing
    init(index: Int = 0, staggerDelay: Double = 0.03, animateFromBottom: Bool = true, trackingId: String? = nil) {
        self.index = index
        self.staggerDelay = staggerDelay
        self.animateFromBottom = animateFromBottom
        self.trackingId = trackingId
    }

    func body(content: Content) -> some View {
        // Check global tracker first for instant rendering of already-seen views
        let alreadyTracked = trackingId.map { AppearanceTracker.shared.hasAppeared($0) } ?? false

        content
            .opacity(hasAppeared || alreadyTracked ? 1 : 0)
            .offset(x: hasAppeared || alreadyTracked ? 0 : -30)  // Slide from left like web app
            .onAppear {
                // Skip animation if already tracked globally
                if let id = trackingId, AppearanceTracker.shared.hasAppeared(id) {
                    if !hasAppeared {
                        hasAppeared = true
                    }
                    return
                }

                guard !hasAppeared else { return }

                let delay = Double(index) * staggerDelay
                withAnimation(
                    // Spring matching web: stiffness 300, damping 30 ≈ response 0.25, damping 0.8
                    .spring(response: 0.25, dampingFraction: 0.8)
                    .delay(delay)
                ) {
                    hasAppeared = true
                }

                // Mark as appeared globally to prevent re-animation on scroll
                if let id = trackingId {
                    AppearanceTracker.shared.markAppeared(id)
                }
            }
    }
}

/// A modifier that animates a view with a slide-in effect from the side
struct SlideInModifier: ViewModifier {
    let fromLeading: Bool
    let delay: Double

    @State private var hasAppeared = false

    init(fromLeading: Bool = true, delay: Double = 0) {
        self.fromLeading = fromLeading
        self.delay = delay
    }

    func body(content: Content) -> some View {
        content
            .opacity(hasAppeared ? 1 : 0)
            .offset(x: hasAppeared ? 0 : (fromLeading ? -30 : 30))
            .onAppear {
                guard !hasAppeared else { return }

                withAnimation(
                    .spring(response: 0.35, dampingFraction: 0.85)
                    .delay(delay)
                ) {
                    hasAppeared = true
                }
            }
    }
}

/// A modifier that scales and fades in a view
struct ScaleInModifier: ViewModifier {
    let delay: Double

    @State private var hasAppeared = false

    init(delay: Double = 0) {
        self.delay = delay
    }

    func body(content: Content) -> some View {
        content
            .opacity(hasAppeared ? 1 : 0)
            .scaleEffect(hasAppeared ? 1 : 0.9)
            .onAppear {
                guard !hasAppeared else { return }

                withAnimation(
                    .spring(response: 0.3, dampingFraction: 0.7)
                    .delay(delay)
                ) {
                    hasAppeared = true
                }
            }
    }
}

// MARK: - View Extensions

extension View {
    /// Applies a scroll-triggered appearance animation
    /// - Parameters:
    ///   - index: Index for staggered animation
    ///   - staggerDelay: Delay between each item (default 0.03s)
    ///   - animateFromBottom: Whether to animate from bottom (true) or top (false)
    ///   - trackingId: Optional unique ID to prevent re-animation on scroll (recommended for list items)
    func scrollAppear(
        index: Int = 0,
        staggerDelay: Double = 0.03,
        animateFromBottom: Bool = true,
        trackingId: String? = nil
    ) -> some View {
        modifier(ScrollAppearModifier(
            index: index,
            staggerDelay: staggerDelay,
            animateFromBottom: animateFromBottom,
            trackingId: trackingId
        ))
    }

    /// Applies a slide-in animation from the side
    /// - Parameters:
    ///   - fromLeading: Whether to slide from leading (left) or trailing (right)
    ///   - delay: Animation delay
    func slideIn(fromLeading: Bool = true, delay: Double = 0) -> some View {
        modifier(SlideInModifier(fromLeading: fromLeading, delay: delay))
    }

    /// Applies a scale-in animation
    /// - Parameter delay: Animation delay
    func scaleIn(delay: Double = 0) -> some View {
        modifier(ScaleInModifier(delay: delay))
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: 12) {
            ForEach(0..<10, id: \.self) { index in
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.tidexSurfacePrimary)
                    .frame(height: 80)
                    .overlay(
                        Text("Item \(index)")
                            .foregroundColor(.tidexTextPrimary)
                    )
                    .scrollAppear(index: index)
            }
        }
        .padding()
    }
    .background(Color.tidexBackground)
}
