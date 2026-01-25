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

/// A container view that detects horizontal swipes for month navigation
/// Wraps content and triggers navigation on swipe gestures
/// Enhanced with visual feedback during drag (opacity, scale, rotation)
struct MonthSwipeContainer<Content: View>: View {
    // MARK: - Properties

    let onSwipeLeft: () -> Void   // Swipe left → next month
    let onSwipeRight: () -> Void  // Swipe right → previous month
    let config: SwipeGestureConfig
    let isEnabled: Bool
    @ViewBuilder let content: () -> Content

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
            // Use gesture() with exclusive behavior - once we lock horizontal, we own the gesture
            .gesture(swipeGesture)
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
                        onSwipeRight()
                    } else {
                        // Swipe left → next month
                        onSwipeLeft()
                    }
                }
            }
    }

    // Track if we've already triggered the threshold haptic during this drag
    @State private var hasTriggeredThresholdHaptic = false
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
    /// Add month swipe navigation to any view
    /// - Parameters:
    ///   - onSwipeLeft: Called when user swipes left (go to next month)
    ///   - onSwipeRight: Called when user swipes right (go to previous month)
    ///   - isEnabled: Whether swipe detection is enabled
    /// - Returns: View with swipe gesture support
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

    /// Add month swipe gesture directly to a ScrollView using highPriorityGesture
    /// This gives the horizontal swipe gesture priority over ScrollView's pan gesture
    /// Use this instead of MonthSwipeContainer when wrapping a ScrollView
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

    func body(content: Content) -> some View {
        content
            .background(
                SwipeGestureView(
                    onSwipeLeft: onSwipeLeft,
                    onSwipeRight: onSwipeRight,
                    isEnabled: isEnabled
                )
            )
    }
}

// MARK: - UIKit Swipe Gesture View

/// A UIViewRepresentable that adds UISwipeGestureRecognizers for left and right swipes.
/// The view is placed in background and uses userInteractionEnabled = false so it
/// doesn't intercept touches, but gesture recognizers still work because they're
/// added to a parent view that IS in the responder chain.
private struct SwipeGestureView: UIViewRepresentable {
    let onSwipeLeft: () -> Void
    let onSwipeRight: () -> Void
    let isEnabled: Bool

    func makeUIView(context: Context) -> SwipeContainerView {
        let view = SwipeContainerView()
        view.backgroundColor = .clear
        view.coordinator = context.coordinator

        // Left swipe gesture
        let leftSwipe = UISwipeGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleSwipe(_:))
        )
        leftSwipe.direction = .left
        leftSwipe.delaysTouchesBegan = false
        leftSwipe.delaysTouchesEnded = false
        leftSwipe.cancelsTouchesInView = false
        view.addGestureRecognizer(leftSwipe)

        // Right swipe gesture
        let rightSwipe = UISwipeGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleSwipe(_:))
        )
        rightSwipe.direction = .right
        rightSwipe.delaysTouchesBegan = false
        rightSwipe.delaysTouchesEnded = false
        rightSwipe.cancelsTouchesInView = false
        view.addGestureRecognizer(rightSwipe)

        return view
    }

    func updateUIView(_ uiView: SwipeContainerView, context: Context) {
        context.coordinator.onSwipeLeft = onSwipeLeft
        context.coordinator.onSwipeRight = onSwipeRight
        context.coordinator.isEnabled = isEnabled

        // Enable/disable gesture recognizers
        uiView.gestureRecognizers?.forEach { $0.isEnabled = isEnabled }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onSwipeLeft: onSwipeLeft, onSwipeRight: onSwipeRight, isEnabled: isEnabled)
    }

    class Coordinator: NSObject {
        var onSwipeLeft: () -> Void
        var onSwipeRight: () -> Void
        var isEnabled: Bool

        private let haptic = UIImpactFeedbackGenerator(style: .medium)

        init(onSwipeLeft: @escaping () -> Void, onSwipeRight: @escaping () -> Void, isEnabled: Bool) {
            self.onSwipeLeft = onSwipeLeft
            self.onSwipeRight = onSwipeRight
            self.isEnabled = isEnabled
            super.init()
            haptic.prepare()
        }

        @objc func handleSwipe(_ gesture: UISwipeGestureRecognizer) {
            guard isEnabled else { return }

            haptic.impactOccurred()
            haptic.prepare()

            switch gesture.direction {
            case .left:
                onSwipeLeft()
            case .right:
                onSwipeRight()
            default:
                break
            }
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
