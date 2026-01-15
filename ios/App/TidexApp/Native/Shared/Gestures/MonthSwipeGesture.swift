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
        verticalLimit: 100,
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

    // MARK: - Body

    var body: some View {
        content()
            // Make entire content area hit-testable for gestures
            .contentShape(Rectangle())
            // No visual effects during drag - let the card transition handle all animation
            // This prevents "angled" entry when swipe gesture effects combine with transitions
            // Use simultaneousGesture so pull-to-refresh (highPriorityGesture) takes precedence
            .simultaneousGesture(swipeGesture)
            .onAppear {
                // Pre-warm haptic generators
                swipeHaptic.prepare()
                thresholdFeedback.prepare()
            }
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 20) // Higher threshold - let vertical gestures win
            .onChanged { value in
                guard isEnabled else { return }

                let horizontal = value.translation.width
                let vertical = abs(value.translation.height)

                // Only accept predominantly horizontal gestures
                // Must be much more horizontal than vertical to avoid conflicts
                let isHorizontal = abs(horizontal) > vertical * 2.0

                if isHorizontal && vertical < config.verticalLimit {
                    isDragging = true
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
                } else if isDragging {
                    // Gesture changed direction, cancel
                    isDragging = false
                    dragOffset = 0
                    hasTriggeredThresholdHaptic = false
                }
            }
            .onEnded { value in
                guard isEnabled else { return }

                let horizontal = value.translation.width
                let vertical = abs(value.translation.height)
                let velocity = value.velocity.width

                // Reset state immediately (no animation - let card transition handle it)
                isDragging = false
                dragOffset = 0

                // Reset threshold haptic tracking
                hasTriggeredThresholdHaptic = false

                // Only process if predominantly horizontal
                guard vertical < config.verticalLimit else { return }
                guard abs(horizontal) > vertical * 2.0 else { return }

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
