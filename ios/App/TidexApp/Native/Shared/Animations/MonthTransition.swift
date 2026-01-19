import SwiftUI

// MonthNavigationDirection is defined in MonthSwipeGesture.swift
// This file provides animation utilities for month transitions

// MARK: - Layout Constants

/// Layout constants for the floating MonthPicker above the tab bar
enum MonthPickerLayout {
    /// Horizontal padding for the MonthPicker pill
    /// This value is calculated so the edges of the MonthPicker align with
    /// where a 30pt corner radius "flattens out" on a full-width element
    static let horizontalPadding: CGFloat = 40

    /// Bottom padding between MonthPicker and tab bar
    static let bottomPadding: CGFloat = 8

    /// Height of the MonthPicker pill
    static let height: CGFloat = 56

    /// Corner radius for the glass effect
    static let cornerRadius: CGFloat = 30
}

// MARK: - Month Transition Configuration

/// Configuration for month transition animations
struct MonthTransitionConfig {
    /// Duration of the transition (in seconds)
    let duration: Double
    /// Spring response for the animation
    let springResponse: Double
    /// Spring damping fraction
    let dampingFraction: Double
    /// Horizontal offset for slide transitions
    let slideOffset: CGFloat
    /// Vertical offset for text transitions
    let textOffset: CGFloat
    /// Stagger delay between cards
    let staggerDelay: Double
    /// Whether to use compact vertical layout for month/year
    let isCompact: Bool

    static let `default` = MonthTransitionConfig(
        duration: 0.35,
        springResponse: 0.35,
        dampingFraction: 0.85,
        slideOffset: 60,
        textOffset: 20,
        staggerDelay: 0.05,
        isCompact: false
    )

    static let fast = MonthTransitionConfig(
        duration: 0.25,
        springResponse: 0.25,
        dampingFraction: 0.9,
        slideOffset: 40,
        textOffset: 15,
        staggerDelay: 0.03,
        isCompact: false
    )

    static let compact = MonthTransitionConfig(
        duration: 0.3,
        springResponse: 0.3,
        dampingFraction: 0.85,
        slideOffset: 40,
        textOffset: 15,
        staggerDelay: 0.03,
        isCompact: true
    )
}

// MARK: - Month Transition Effect

/// Represents the animation state for month transitions
struct MonthTransitionPhase: Equatable {
    let year: Int
    let month: Int
    let direction: MonthNavigationDirection?

    var id: String { "\(year)-\(month)" }
}

// MARK: - Card Transition Modifier

/// A view modifier that applies horizontal slide transition to cards
/// Similar to the Next.js calendar grid animation
struct CardTransitionModifier: ViewModifier {
    let phase: MonthTransitionPhase
    let index: Int
    let config: MonthTransitionConfig

    @State private var isAppearing = false

    func body(content: Content) -> some View {
        content
            .opacity(isAppearing ? 1 : 0)
            .offset(x: isAppearing ? 0 : slideOffset)
            .scaleEffect(isAppearing ? 1 : 0.95)
            .onAppear {
                // Stagger the appearance of each card
                let delay = Double(index) * config.staggerDelay
                withAnimation(
                    .spring(response: config.springResponse, dampingFraction: config.dampingFraction)
                    .delay(delay)
                ) {
                    isAppearing = true
                }
            }
            .onChange(of: phase.id) { _, _ in
                // Reset and re-animate on month change
                isAppearing = false
                let delay = Double(index) * config.staggerDelay
                withAnimation(
                    .spring(response: config.springResponse, dampingFraction: config.dampingFraction)
                    .delay(delay)
                ) {
                    isAppearing = true
                }
            }
    }

    private var slideOffset: CGFloat {
        guard let direction = phase.direction else { return 0 }
        return direction == .next ? config.slideOffset : -config.slideOffset
    }
}

// MARK: - Text Transition Modifier

/// A view modifier that applies vertical slide transition to text (month/year labels)
/// Similar to the Next.js MonthPicker vertical animation
struct TextTransitionModifier: ViewModifier {
    let phase: MonthTransitionPhase
    let config: MonthTransitionConfig

    func body(content: Content) -> some View {
        content
            .id(phase.id)
            .transition(textTransition)
            .animation(
                .spring(response: config.springResponse, dampingFraction: config.dampingFraction),
                value: phase.id
            )
    }

    private var textTransition: AnyTransition {
        let direction = phase.direction
        let offset = direction == .next ? config.textOffset : -config.textOffset

        return .asymmetric(
            insertion: .offset(y: offset).combined(with: .opacity),
            removal: .offset(y: -offset).combined(with: .opacity)
        )
    }
}

// MARK: - Staggered Cards Container

/// A container that animates child cards with a horizontal slide effect
/// New content slides in from the appropriate direction based on navigation.
///
/// Note: This implementation uses manual offset animation instead of SwiftUI's
/// .transition() API because transitions evaluate direction for both entering
/// and exiting views using current state, causing bugs when direction changes rapidly.
struct StaggeredCardsContainer<Content: View>: View {
    let phase: MonthTransitionPhase
    let config: MonthTransitionConfig
    @ViewBuilder let content: () -> Content

    /// Current horizontal offset for slide animation
    @State private var xOffset: CGFloat = 0

    /// Track the last phase to detect actual changes
    @State private var lastPhaseId: String = ""

    /// Skip animation on very first render
    @State private var hasInitialized: Bool = false

    /// Container width for slide animations
    @State private var containerWidth: CGFloat = 0

    var body: some View {
        // No ZStack, no .id(), no .transition() - just offset animation
        content()
            .offset(x: xOffset)
            .clipped() // Clip overflow during animation (doesn't affect hit testing)
            .contentShape(Rectangle()) // Ensure gestures can pass through
            .background(
                GeometryReader { geometry in
                    Color.clear.onAppear {
                        containerWidth = geometry.size.width
                    }
                    .onChange(of: geometry.size.width) { _, newWidth in
                        containerWidth = newWidth
                    }
                }
            )
            .onAppear {
                lastPhaseId = phase.id
                xOffset = 0
                // Delay initialization flag to prevent animation on first data load
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    hasInitialized = true
                }
            }
            .onChange(of: phase.id) { oldId, newId in
                // Only animate if we've initialized and phase actually changed
                guard hasInitialized, oldId != newId else {
                    lastPhaseId = newId
                    return
                }

                // Capture direction immediately
                let direction = phase.direction ?? .next

                // Determine entry position:
                // .next (going forward in time): slide in from RIGHT
                // .previous (going back in time): slide in from LEFT
                let startX = direction == .next ? containerWidth : -containerWidth

                // Transaction to ensure immediate position set
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    xOffset = startX
                }

                // Then animate to center
                withAnimation(.spring(response: config.springResponse, dampingFraction: config.dampingFraction)) {
                    xOffset = 0
                }

                lastPhaseId = newId
            }
    }
}

// MARK: - Animated Month Header

/// An animated header showing month and year with vertical text transitions
/// Back to today button is inline between month/year and next button (doesn't affect layout)
/// Supports swipe gestures for month navigation
struct AnimatedMonthHeader: View {
    let monthName: String
    let year: Int
    let phase: MonthTransitionPhase
    let isCurrentMonth: Bool
    let config: MonthTransitionConfig
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onReturnToCurrent: () -> Void
    let isLoading: Bool
    let backToTodayText: String  // Kept for API compatibility, but not used in new design

    @State private var monthScale: CGFloat = 1.0

    // Haptic feedback for swipe
    private let swipeHaptic = UIImpactFeedbackGenerator(style: .medium)

    // Width for side sections to keep center text perfectly centered (default mode only)
    private let defaultSideWidth: CGFloat = 80  // Enough for back button (36) + spacing (8) + nav button (36)

    var body: some View {
        if config.isCompact {
            compactLayout
        } else {
            defaultLayout
        }
    }

    // MARK: - Compact Layout (for Add tab)

    private var compactLayout: some View {
        HStack(spacing: 8) {
            // Previous button
            navigationButton(icon: "chevron.left", action: onPrevious)

            // Month and Year - vertically stacked, centered, takes available space
            VStack(spacing: 0) {
                Text(monthName.capitalized)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.tidexTextPrimary)

                Text(String(year))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.tidexTextSecondary)
            }
            .frame(maxWidth: .infinity)
            .id("month-\(phase.id)")
            .transition(textTransition)
            .scaleEffect(monthScale)
            .animation(
                .spring(response: config.springResponse, dampingFraction: config.dampingFraction),
                value: phase.id
            )
            .onTapGesture {
                guard !isCurrentMonth else { return }
                bounceAndReturn()
            }

            // Next button
            navigationButton(icon: "chevron.right", action: onNext)

            // Back-to-today button (outside the main picker area)
            Button(action: onReturnToCurrent) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.tidexBlue)
                    .frame(width: 36, height: 36)
                    .background(Color.tidexBlue.opacity(0.1))
                    .clipShape(Circle())
            }
            .opacity(isCurrentMonth ? 0 : 1)
            .disabled(isCurrentMonth)
        }
        .contentShape(Rectangle())
        .gesture(swipeGesture)
        .onAppear { swipeHaptic.prepare() }
    }

    // MARK: - Default Layout (for Dashboard/Shifts)

    private var defaultLayout: some View {
        HStack(spacing: 0) {
            // Left section: Previous button (fixed width to match right side)
            HStack {
                navigationButton(icon: "chevron.left", action: onPrevious)
                Spacer()
            }
            .frame(width: defaultSideWidth)

            Spacer()

            // Center section: Month and Year (horizontal)
            HStack(spacing: 6) {
                Text(monthName.capitalized)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.tidexTextPrimary)

                Text(String(year))
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.tidexTextSecondary)
            }
            .id("month-\(phase.id)")
            .transition(textTransition)
            .scaleEffect(monthScale)
            .animation(
                .spring(response: config.springResponse, dampingFraction: config.dampingFraction),
                value: phase.id
            )
            .onTapGesture {
                guard !isCurrentMonth else { return }
                bounceAndReturn()
            }

            Spacer()

            // Right section: Back-to-today button + Next button
            HStack(spacing: 8) {
                Button(action: onReturnToCurrent) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.tidexBlue)
                        .frame(width: 36, height: 36)
                        .background(Color.tidexBlue.opacity(0.1))
                        .clipShape(Circle())
                }
                .opacity(isCurrentMonth ? 0 : 1)
                .disabled(isCurrentMonth)

                navigationButton(icon: "chevron.right", action: onNext)
            }
            .frame(width: defaultSideWidth)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .gesture(swipeGesture)
        .onAppear { swipeHaptic.prepare() }
    }

    // MARK: - Shared Helpers

    private func bounceAndReturn() {
        withAnimation(.spring(response: 0.15, dampingFraction: 0.5)) {
            monthScale = 0.95
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                monthScale = 1.0
            }
        }
        onReturnToCurrent()
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = abs(value.translation.height)

                guard abs(horizontal) > vertical else { return }

                swipeHaptic.impactOccurred()

                if horizontal > 0 {
                    onPrevious()
                } else {
                    onNext()
                }
            }
    }

    // MARK: - Subviews

    @ViewBuilder
    private func navigationButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.tidexBlue)
                .frame(width: 36, height: 36)
                .background(Color.tidexBlue.opacity(0.1))
                .clipShape(Circle())
        }
        // Navigation is always enabled - data loading happens in background
        // Visual feedback via subtle opacity when loading
        .opacity(isLoading ? 0.7 : 1.0)
    }

    // MARK: - Transitions

    private var textTransition: AnyTransition {
        let direction = phase.direction
        let offset = direction == .next ? config.textOffset : -config.textOffset

        return .asymmetric(
            insertion: .offset(y: offset).combined(with: .opacity),
            removal: .offset(y: -offset).combined(with: .opacity)
        )
    }
}

// MARK: - View Extensions

extension View {
    /// Applies a card transition animation for month changes
    /// - Parameters:
    ///   - phase: The current month transition phase
    ///   - index: The card index (for staggered animation)
    ///   - config: Animation configuration
    func cardTransition(
        phase: MonthTransitionPhase,
        index: Int = 0,
        config: MonthTransitionConfig = .default
    ) -> some View {
        modifier(CardTransitionModifier(phase: phase, index: index, config: config))
    }

    /// Applies a text transition animation for month changes
    func textTransition(
        phase: MonthTransitionPhase,
        config: MonthTransitionConfig = .default
    ) -> some View {
        modifier(TextTransitionModifier(phase: phase, config: config))
    }
}

// Preview disabled - requires full app context with MonthNavigationDirection
// See MainTabView.swift for usage examples
