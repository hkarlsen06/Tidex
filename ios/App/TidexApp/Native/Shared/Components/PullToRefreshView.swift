import SwiftUI
import UIKit

// MARK: - Pull to Refresh State

/// State machine for pull-to-refresh gesture
enum PullToRefreshState: Equatable {
    case idle
    case pulling(progress: CGFloat)  // 0.0 to 1.0+
    case triggered
    case refreshing
}

// MARK: - Pull to Refresh Configuration

struct PullToRefreshConfig {
    /// Distance to pull before triggering refresh
    let triggerDistance: CGFloat
    /// Height of the refresh indicator area
    let indicatorHeight: CGFloat
    /// Spring response for animations
    let springResponse: Double
    /// Spring damping
    let dampingFraction: Double

    static let `default` = PullToRefreshConfig(
        triggerDistance: 80,
        indicatorHeight: 60,
        springResponse: 0.35,
        dampingFraction: 0.75
    )
}

// MARK: - Pull to Refresh Container

/// A container that adds pull-to-refresh to non-scrollable content
/// Uses a high-priority gesture to ensure vertical pulls are captured before horizontal swipes
struct PullToRefreshContainer<Content: View>: View {

    // MARK: - Properties

    let onRefresh: () async -> Void
    let config: PullToRefreshConfig
    @ViewBuilder let content: () -> Content

    // MARK: - Environment

    @Environment(\.localization) private var localization

    // MARK: - State

    @State private var state: PullToRefreshState = .idle
    @State private var dragOffset: CGFloat = 0
    @State private var gestureActive = false
    @State private var hasTriggeredThresholdHaptic = false
    @State private var hasTriggeredRefreshHaptic = false

    // Pre-prepared haptic generators for zero latency
    private let thresholdHaptic = UIImpactFeedbackGenerator(style: .light)
    private let refreshHaptic = UIImpactFeedbackGenerator(style: .medium)
    private let successHaptic = UINotificationFeedbackGenerator()

    // MARK: - Initialization

    init(
        config: PullToRefreshConfig = .default,
        onRefresh: @escaping () async -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.config = config
        self.onRefresh = onRefresh
        self.content = content
    }

    // MARK: - Computed Properties

    private var pullProgress: CGFloat {
        min(dragOffset / config.triggerDistance, 1.5)
    }

    private var shouldShowIndicator: Bool {
        dragOffset > 10 || state == .refreshing
    }

    private var indicatorOffset: CGFloat {
        switch state {
        case .idle:
            return -config.indicatorHeight
        case .pulling:
            // Rubber band effect - diminishing returns past threshold
            let base = min(dragOffset, config.triggerDistance)
            let excess = max(0, dragOffset - config.triggerDistance)
            return base + (excess * 0.3) - config.indicatorHeight
        case .triggered, .refreshing:
            return 0
        }
    }

    private var contentOffset: CGFloat {
        switch state {
        case .idle:
            return 0
        case .pulling:
            // Rubber band effect
            let base = min(dragOffset, config.triggerDistance)
            let excess = max(0, dragOffset - config.triggerDistance)
            return base + (excess * 0.3)
        case .triggered, .refreshing:
            return config.indicatorHeight
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            // Refresh indicator
            refreshIndicator
                .offset(y: indicatorOffset)
                .opacity(shouldShowIndicator ? 1 : 0)

            // Main content - clipped to prevent visual overflow during pull
            content()
                .offset(y: contentOffset)
        }
        .contentShape(Rectangle())
        .animation(
            .spring(response: config.springResponse, dampingFraction: config.dampingFraction),
            value: state
        )
        // Use simultaneousGesture so it doesn't block child gestures
        // The gesture logic itself filters for vertical-only drags
        .simultaneousGesture(pullGesture)
        .onAppear {
            // Pre-warm haptic generators
            thresholdHaptic.prepare()
            refreshHaptic.prepare()
            successHaptic.prepare()
        }
    }

    // MARK: - Refresh Indicator

    @ViewBuilder
    private var refreshIndicator: some View {
        HStack(spacing: 12) {
            if state == .refreshing {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .tidexBlue))
                    .scaleEffect(0.9)
            } else {
                // Arrow that rotates as user pulls
                Image(systemName: "arrow.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.tidexBlue)
                    .rotationEffect(.degrees(pullProgress >= 1 ? 180 : 0))
                    .animation(.spring(response: 0.2, dampingFraction: 0.7), value: pullProgress >= 1)
            }

            Text(refreshText)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.tidexTextSecondary)
        }
        .frame(height: config.indicatorHeight)
        .frame(maxWidth: .infinity)
    }

    private var refreshText: String {
        switch state {
        case .idle:
            return ""
        case .pulling(let progress):
            return progress >= 1
                ? localization.string("pullToRefresh.release")
                : localization.string("pullToRefresh.pullDown")
        case .triggered:
            return localization.string("pullToRefresh.release")
        case .refreshing:
            return localization.string("pullToRefresh.refreshing")
        }
    }

    // MARK: - Gesture

    private var pullGesture: some Gesture {
        DragGesture(minimumDistance: 3) // Lower threshold to capture vertical gesture first
            .onChanged { value in
                let verticalDrag = value.translation.height
                let horizontalDrag = abs(value.translation.width)

                // Determine if this is a vertical pull (downward only)
                // Must be predominantly vertical and downward
                let isVerticalPull = verticalDrag > 0 && verticalDrag > horizontalDrag * 1.2

                // If not a valid vertical pull, don't interfere
                guard isVerticalPull else {
                    // Reset if we were pulling but gesture changed direction
                    if gestureActive {
                        resetGesture()
                    }
                    return
                }

                // Ignore if already refreshing
                guard state != .refreshing else { return }

                gestureActive = true
                dragOffset = verticalDrag

                // Update state based on progress
                let currentProgress = min(dragOffset / config.triggerDistance, 1.5)

                if currentProgress >= 1 {
                    state = .triggered

                    // Haptic when threshold first crossed
                    if !hasTriggeredThresholdHaptic {
                        thresholdHaptic.impactOccurred()
                        hasTriggeredThresholdHaptic = true
                        // Prepare for next haptic
                        refreshHaptic.prepare()
                    }
                } else {
                    state = .pulling(progress: currentProgress)
                    // Reset threshold haptic if user pulls back
                    if hasTriggeredThresholdHaptic && currentProgress < 0.9 {
                        hasTriggeredThresholdHaptic = false
                        thresholdHaptic.prepare()
                    }
                }
            }
            .onEnded { _ in
                handleDragEnded()
            }
    }

    // MARK: - Actions

    private func resetGesture() {
        gestureActive = false
        hasTriggeredThresholdHaptic = false
        if state != .refreshing {
            withAnimation(.spring(response: config.springResponse, dampingFraction: config.dampingFraction)) {
                state = .idle
                dragOffset = 0
            }
        }
    }

    private func handleDragEnded() {
        defer {
            gestureActive = false
            hasTriggeredThresholdHaptic = false
            hasTriggeredRefreshHaptic = false
        }

        switch state {
        case .triggered:
            // Start refresh
            state = .refreshing

            // Haptic feedback for refresh start
            refreshHaptic.impactOccurred()
            successHaptic.prepare()

            // Perform refresh
            Task {
                await onRefresh()

                // Success haptic when refresh completes
                await MainActor.run {
                    successHaptic.notificationOccurred(.success)

                    // Complete refresh with animation
                    withAnimation(.spring(response: config.springResponse, dampingFraction: config.dampingFraction)) {
                        state = .idle
                        dragOffset = 0
                    }
                }
            }

        case .pulling, .idle:
            // Cancel - return to idle
            withAnimation(.spring(response: config.springResponse, dampingFraction: config.dampingFraction)) {
                state = .idle
                dragOffset = 0
            }

        case .refreshing:
            // Already refreshing, do nothing
            break
        }
    }
}

// MARK: - View Extension

extension View {
    /// Adds pull-to-refresh functionality to a non-scrollable view
    /// - Parameters:
    ///   - config: Configuration for the pull gesture
    ///   - onRefresh: Async action to perform when refresh is triggered
    /// - Returns: View with pull-to-refresh capability
    func pullToRefresh(
        config: PullToRefreshConfig = .default,
        onRefresh: @escaping () async -> Void
    ) -> some View {
        PullToRefreshContainer(config: config, onRefresh: onRefresh) {
            self
        }
    }
}

// MARK: - Preview

#Preview {
    struct PreviewContainer: View {
        @State private var refreshCount = 0

        var body: some View {
            ZStack {
                Color.tidexBackground
                    .ignoresSafeArea()

                VStack(spacing: 20) {
                    Text("Pull down to refresh")
                        .font(.headline)
                        .foregroundColor(.tidexTextPrimary)

                    Text("Refreshed \(refreshCount) times")
                        .font(.subheadline)
                        .foregroundColor(.tidexTextSecondary)
                }
            }
            .pullToRefresh {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                refreshCount += 1
            }
        }
    }

    return PreviewContainer()
}
