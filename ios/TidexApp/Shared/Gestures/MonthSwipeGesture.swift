import SwiftUI
import UIKit

// MARK: - Month Navigation Direction

/// Direction of month navigation (used for animations)
enum MonthNavigationDirection: Equatable {
    case previous  // Swipe right → go to previous month
    case next      // Swipe left → go to next month
}

// MARK: - Month Navigation Protocol

/// Protocol for view models that support month navigation via swipe
/// Must be @MainActor since it's typically used with ObservableObject view models
/// Navigation functions are synchronous for instant UI response - data loading happens in background
@MainActor
protocol MonthNavigable: AnyObject {
    /// Current year being displayed
    var displayYear: Int { get }
    /// Current month being displayed (1-12)
    var displayMonth: Int { get }
    /// Whether data is currently loading
    var isLoading: Bool { get }

    /// Navigate to previous month (non-blocking, data loads in background)
    func goToPreviousMonth()
    /// Navigate to next month (non-blocking, data loads in background)
    func goToNextMonth()
}

// MARK: - Swipe Gesture Configuration

/// Configuration for swipe gesture detection
struct SwipeGestureConfig {
    /// Minimum horizontal distance to trigger a swipe (pixels)
    let threshold: CGFloat
    /// Maximum vertical distance before gesture is considered a scroll
    let verticalLimit: CGFloat
    /// Minimum velocity to trigger a "flick" gesture
    let flickVelocity: CGFloat

    static let `default` = SwipeGestureConfig(
        threshold: 50,
        verticalLimit: 50,
        flickVelocity: 300
    )
}

// MARK: - Month Swipe Container

/// Legacy container for horizontal month swipes.
/// Prefer `monthSwipeGesture(...)` for new usage, especially on refreshable surfaces.
struct MonthSwipeContainer<Content: View>: View {
    // MARK: - Properties

    let onSwipeLeft: () -> Void   // Swipe left → next month
    let onSwipeRight: () -> Void  // Swipe right → previous month
    let config: SwipeGestureConfig
    let isEnabled: Bool
    @ViewBuilder let content: () -> Content
    @Environment(\.layoutDirection) private var layoutDirection

    // MARK: - State

    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false

    // MARK: - Initialization

    init(
        onSwipeLeft: @escaping () -> Void,
        onSwipeRight: @escaping () -> Void,
        config: SwipeGestureConfig = .default,
        isEnabled: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.onSwipeLeft = onSwipeLeft
        self.onSwipeRight = onSwipeRight
        self.config = config
        self.isEnabled = isEnabled
        self.content = content
    }

    // MARK: - Computed Properties

    /// Progress towards completing a swipe (0 to 1)
    private var swipeProgress: CGFloat {
        min(abs(dragOffset) / (config.threshold * 2), 1.0)
    }

    /// Opacity based on drag distance (subtle fade as user drags)
    private var dragOpacity: Double {
        isDragging ? 1.0 - (swipeProgress * 0.15) : 1.0
    }

    /// Scale based on drag distance (subtle shrink as user drags)
    private var dragScale: CGFloat {
        isDragging ? 1.0 - (swipeProgress * 0.02) : 1.0
    }

    /// Rotation based on drag direction (subtle tilt)
    private var dragRotation: Double {
        guard isDragging else { return 0 }
        // Max rotation of 1 degree in the drag direction
        return Double(dragOffset / config.threshold) * 0.5
    }

    // Pre-prepared haptic generators for zero latency
    private let swipeHaptic = UIImpactFeedbackGenerator(style: .medium)
    private let thresholdFeedback = UISelectionFeedbackGenerator()

    // MARK: - State for gesture direction lock

    /// Whether we've locked into a horizontal swipe (prevents scroll from taking over)
    @State private var isHorizontalLocked = false

    // MARK: - Body

    var body: some View {
        content()
            // Make entire content area hit-testable for gestures
            .contentShape(Rectangle())
            // Use simultaneousGesture so vertical drags still reach parent ScrollView
            // (required for native pull-to-refresh in wrappers like PullToRefreshContainer).
            .simultaneousGesture(swipeGesture)
            .onAppear {
                // Pre-warm haptic generators
                swipeHaptic.prepare()
                thresholdFeedback.prepare()
            }
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 10) // Low threshold like Next.js - decide direction early
            .onChanged { value in
                guard isEnabled else { return }

                let horizontal = value.translation.width
                let vertical = abs(value.translation.height)

                // Early direction lock (like Next.js: once horizontal > vertical at 10px, lock it)
                // This must happen very early in the gesture to beat ScrollView
                if !isHorizontalLocked && !isDragging {
                    // At low distances, determine direction
                    if abs(horizontal) > 10 && abs(horizontal) > vertical {
                        // This gesture is horizontal - lock it in
                        isHorizontalLocked = true
                        isDragging = true
                    } else if vertical > 10 {
                        // This gesture is vertical - don't interfere, let scroll handle it
                        return
                    }
                }

                // Only continue if we're locked into horizontal mode
                guard isHorizontalLocked else { return }

                dragOffset = horizontal

                // Haptic feedback when threshold crossed
                if abs(horizontal) >= config.threshold && !hasTriggeredThresholdHaptic {
                    thresholdFeedback.selectionChanged()
                    hasTriggeredThresholdHaptic = true
                    swipeHaptic.prepare()
                } else if abs(horizontal) < config.threshold * 0.8 {
                    hasTriggeredThresholdHaptic = false
                    thresholdFeedback.prepare()
                }
            }
            .onEnded { value in
                guard isEnabled else { return }

                let horizontal = value.translation.width
                let velocity = value.velocity.width

                // Only process if we were in horizontal mode
                let wasHorizontalLocked = isHorizontalLocked

                // Reset state immediately
                isDragging = false
                dragOffset = 0
                isHorizontalLocked = false
                hasTriggeredThresholdHaptic = false

                guard wasHorizontalLocked else { return }

                // Check if threshold exceeded or velocity indicates flick
                let isFlick = abs(velocity) > config.flickVelocity
                let thresholdExceeded = abs(horizontal) > config.threshold

                if thresholdExceeded || isFlick {
                    // Trigger haptic feedback for successful swipe
                    swipeHaptic.impactOccurred()

                    if horizontal > 0 {
                        // Swipe right → previous month
                        effectiveOnSwipeRight()
                    } else {
                        // Swipe left → next month
                        effectiveOnSwipeLeft()
                    }
                }
            }
    }

    // Track if we've already triggered the threshold haptic during this drag
    @State private var hasTriggeredThresholdHaptic = false

    private var effectiveOnSwipeLeft: () -> Void {
        layoutDirection == .rightToLeft ? onSwipeRight : onSwipeLeft
    }

    private var effectiveOnSwipeRight: () -> Void {
        layoutDirection == .rightToLeft ? onSwipeLeft : onSwipeRight
    }
}

// MARK: - Animated Month Content

/// A view that animates content transitions when changing months
struct AnimatedMonthContent<Content: View>: View {
    let year: Int
    let month: Int
    let direction: MonthNavigationDirection?
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .id("\(year)-\(month)")
            .transition(.asymmetric(
                insertion: .move(edge: direction == .next ? .trailing : .leading)
                    .combined(with: .opacity),
                removal: .move(edge: direction == .next ? .leading : .trailing)
                    .combined(with: .opacity)
            ))
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: "\(year)-\(month)")
    }
}

// MARK: - View Extension

extension View {
    /// Legacy month swipe wrapper API.
    /// Prefer `.monthSwipeGesture(...)` for new usage.
    /// - Parameters:
    ///   - onSwipeLeft: Called when user swipes left (go to next month)
    ///   - onSwipeRight: Called when user swipes right (go to previous month)
    ///   - isEnabled: Whether swipe detection is enabled
    /// - Returns: View with swipe gesture support
    @available(*, deprecated, message: "Use .monthSwipeGesture(...) instead")
    func monthSwipeable(
        onSwipeLeft: @escaping () -> Void,
        onSwipeRight: @escaping () -> Void,
        isEnabled: Bool = true
    ) -> some View {
        MonthSwipeContainer(
            onSwipeLeft: onSwipeLeft,
            onSwipeRight: onSwipeRight,
            isEnabled: isEnabled
        ) {
            self
        }
    }

    /// Preferred month swipe API that uses UIKit recognizers under the hood.
    /// Designed to minimize conflicts with vertical scroll/pull-to-refresh gestures.
    func monthSwipeGesture(
        onSwipeLeft: @escaping () -> Void,
        onSwipeRight: @escaping () -> Void,
        threshold: CGFloat = 50,
        isEnabled: Bool = true
    ) -> some View {
        self.modifier(MonthSwipeGestureModifier(
            onSwipeLeft: onSwipeLeft,
            onSwipeRight: onSwipeRight,
            threshold: threshold,
            isEnabled: isEnabled
        ))
    }
}

// MARK: - Month Swipe Gesture Modifier

/// A gesture modifier that uses UISwipeGestureRecognizer for reliable horizontal
/// swipe detection that doesn't conflict with ScrollView.
///
/// Uses a clever technique: places gesture recognizers on a background view
/// and uses `delaysTouchesBegan = false` so touches are immediately passed
/// to the ScrollView while still allowing swipe recognition.
private struct MonthSwipeGestureModifier: ViewModifier {
    let onSwipeLeft: () -> Void
    let onSwipeRight: () -> Void
    let threshold: CGFloat
    let isEnabled: Bool
    @Environment(\.layoutDirection) private var layoutDirection

    func body(content: Content) -> some View {
        content
            .background(
                SwipeGestureView(
                    onSwipeLeft: onSwipeLeft,
                    onSwipeRight: onSwipeRight,
                    threshold: threshold,
                    isEnabled: isEnabled,
                    isRTL: layoutDirection == .rightToLeft
                )
            )
    }
}

// MARK: - UIKit Swipe Gesture View

/// A UIViewRepresentable that adds a horizontal UIPanGestureRecognizer for month swipes.
/// The view is placed in background and uses userInteractionEnabled = false so it
/// doesn't intercept touches, but gesture recognizers still work because they're
/// added to a parent view that IS in the responder chain.
private struct SwipeGestureView: UIViewRepresentable {
    let onSwipeLeft: () -> Void
    let onSwipeRight: () -> Void
    let threshold: CGFloat
    let isEnabled: Bool
    let isRTL: Bool

    func makeUIView(context: Context) -> SwipeContainerView {
        let view = SwipeContainerView()
        view.backgroundColor = .clear
        view.coordinator = context.coordinator

        // Horizontal pan recognizer with slight precedence bias over vertical scroll.
        let horizontalPan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        horizontalPan.delegate = context.coordinator
        horizontalPan.delaysTouchesBegan = false
        horizontalPan.delaysTouchesEnded = false
        horizontalPan.cancelsTouchesInView = false
        view.addGestureRecognizer(horizontalPan)

        return view
    }

    func updateUIView(_ uiView: SwipeContainerView, context: Context) {
        context.coordinator.onSwipeLeft = onSwipeLeft
        context.coordinator.onSwipeRight = onSwipeRight
        context.coordinator.threshold = threshold
        context.coordinator.isEnabled = isEnabled
        context.coordinator.isRTL = isRTL

        // Enable/disable gesture recognizers
        uiView.gestureRecognizers?.forEach { $0.isEnabled = isEnabled }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onSwipeLeft: onSwipeLeft,
            onSwipeRight: onSwipeRight,
            threshold: threshold,
            isEnabled: isEnabled,
            isRTL: isRTL
        )
    }

    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onSwipeLeft: () -> Void
        var onSwipeRight: () -> Void
        var threshold: CGFloat
        var isEnabled: Bool
        var isRTL: Bool

        private let horizontalPrecedenceMultiplier: CGFloat = 0.9
        private let flickVelocity: CGFloat = 280
        private let haptic = UIImpactFeedbackGenerator(style: .medium)

        init(
            onSwipeLeft: @escaping () -> Void,
            onSwipeRight: @escaping () -> Void,
            threshold: CGFloat,
            isEnabled: Bool,
            isRTL: Bool
        ) {
            self.onSwipeLeft = onSwipeLeft
            self.onSwipeRight = onSwipeRight
            self.threshold = threshold
            self.isEnabled = isEnabled
            self.isRTL = isRTL
            super.init()
            haptic.prepare()
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard isEnabled else { return }
            guard gesture.state == .ended else { return }
            guard let view = gesture.view else { return }

            let translationX = gesture.translation(in: view).x
            let velocityX = gesture.velocity(in: view).x
            let effectiveThreshold = max(20, threshold * 0.8)
            let isFlick = abs(velocityX) >= flickVelocity
            let crossedThreshold = abs(translationX) >= effectiveThreshold

            guard isFlick || crossedThreshold else { return }

            let directionX = abs(translationX) > 6 ? translationX : velocityX
            guard directionX != 0 else { return }

            haptic.impactOccurred()
            haptic.prepare()

            if directionX < 0 {
                if isRTL { onSwipeRight() } else { onSwipeLeft() }
            } else {
                if isRTL { onSwipeLeft() } else { onSwipeRight() }
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard isEnabled else { return false }
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            guard let view = pan.view else { return false }

            let velocity = pan.velocity(in: view)
            let absHorizontal = abs(velocity.x)
            let absVertical = abs(velocity.y)

            // Stronger precedence: near-diagonal drags can still start month navigation.
            return absHorizontal >= absVertical * horizontalPrecedenceMultiplier
        }
    }
}

// MARK: - Swipe Container View

/// A UIView that adds its gesture recognizers to the parent view's window
/// once it's added to the view hierarchy. This allows swipe gestures to be
/// recognized without blocking the ScrollView's pan gesture.
private class SwipeContainerView: UIView {
    weak var coordinator: SwipeGestureView.Coordinator?
    private var addedToWindow = false

    override func didMoveToWindow() {
        super.didMoveToWindow()

        guard !addedToWindow, window != nil else { return }
        addedToWindow = true

        // Find the parent ScrollView and add gesture recognizers to it
        // This allows both swipe and scroll to work together
        if let scrollView = findScrollView() {
            // Move gesture recognizers to the scroll view
            gestureRecognizers?.forEach { gesture in
                removeGestureRecognizer(gesture)
                scrollView.addGestureRecognizer(gesture)
                // Give month navigation precedence over vertical pan/refresh.
                // The custom pan recognizer rejects clearly vertical drags in shouldBegin,
                // so pull-to-refresh remains responsive.
                scrollView.panGestureRecognizer.require(toFail: gesture)
            }
        }
    }

    private func findScrollView() -> UIScrollView? {
        var view: UIView? = superview
        while let current = view {
            if let scrollView = current as? UIScrollView {
                return scrollView
            }
            view = current.superview
        }
        return nil
    }
}

// MARK: - Preview

#Preview {
    struct PreviewContainer: View {
        @State private var month = 1
        @State private var year = 2025

        var body: some View {
            ZStack {
                Color.tidexBackground
                    .ignoresSafeArea()

                MonthSwipeContainer(
                    onSwipeLeft: {
                        withAnimation {
                            if month == 12 {
                                month = 1
                                year += 1
                            } else {
                                month += 1
                            }
                        }
                    },
                    onSwipeRight: {
                        withAnimation {
                            if month == 1 {
                                month = 12
                                year -= 1
                            } else {
                                month -= 1
                            }
                        }
                    }
                ) {
                    VStack(spacing: 20) {
                        Text("Swipe left/right")
                            .font(.headline)
                            .foregroundColor(.tidexTextPrimary)

                        Text("\(monthName(month)) \(year)")
                            .font(.title)
                            .foregroundColor(.tidexBlue)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }

        private func monthName(_ month: Int) -> String {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM"
            var components = DateComponents()
            components.month = month
            components.day = 1
            let date = Calendar.current.date(from: components) ?? Date()
            return formatter.string(from: date)
        }
    }

    return PreviewContainer()
}
