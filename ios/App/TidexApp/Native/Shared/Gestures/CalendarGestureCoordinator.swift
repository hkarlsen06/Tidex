import SwiftUI
import UIKit

// MARK: - Calendar Gesture Actions

/// Actions that can be triggered by calendar gestures
struct CalendarGestureActions {
    /// Called when a day is tapped (quick touch and release)
    var onTap: ((CGPoint) -> Void)?
    /// Called when drag starts (for range selection in selection mode)
    var onDragStart: ((CGPoint) -> Void)?
    /// Called when finger moves during drag
    var onDragChanged: ((CGPoint) -> Void)?
    /// Called when finger is lifted after drag
    var onDragEnded: (() -> Void)?

    enum SwipeDirection {
        case left   // Next month
        case right  // Previous month
    }
}

// MARK: - Calendar Gesture Configuration

/// Configuration for calendar gesture timing and thresholds
struct CalendarGestureConfig {
    /// Minimum movement to trigger a drag (vs tap)
    let minimumDragDistance: CGFloat
    /// Minimum movement between drag update callbacks
    let dragUpdateThreshold: CGFloat

    static let `default` = CalendarGestureConfig(
        minimumDragDistance: 10,  // Needs some movement to be a drag
        dragUpdateThreshold: 5    // Report updates frequently
    )
}

// MARK: - Calendar Gesture Modifier (Selection Mode)

/// A view modifier for selection mode gestures.
/// In selection mode: tap to select, drag to select range.
/// No long-press delay needed.
struct CalendarSelectionGestureModifier: ViewModifier {
    let actions: CalendarGestureActions
    let config: CalendarGestureConfig
    let isEnabled: Bool

    // Gesture state
    @State private var isDragging = false
    @State private var dragStartLocation: CGPoint?
    @State private var lastReportedLocation: CGPoint?

    // Haptics
    private let tapHaptic = UISelectionFeedbackGenerator()
    private let dragHaptic = UISelectionFeedbackGenerator()

    func body(content: Content) -> some View {
        // CRITICAL: Only attach the gesture when enabled
        // Otherwise the DragGesture(minimumDistance: 0) intercepts all touches
        // and blocks parent swipe gestures even when we early-return in handlers
        if isEnabled {
            content
                .contentShape(Rectangle())
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { value in
                            handleDragChanged(value)
                        }
                        .onEnded { value in
                            handleDragEnded(value)
                        }
                )
                .onAppear {
                    tapHaptic.prepare()
                    dragHaptic.prepare()
                }
        } else {
            content
        }
    }

    private func handleDragChanged(_ value: DragGesture.Value) {
        let location = value.location

        // First touch - record start
        if dragStartLocation == nil {
            dragStartLocation = value.startLocation
            lastReportedLocation = value.startLocation
            return
        }

        // Check if we've moved enough to be a drag
        let drift = hypot(location.x - (dragStartLocation?.x ?? 0),
                          location.y - (dragStartLocation?.y ?? 0))

        if !isDragging && drift >= config.minimumDragDistance {
            // Start drag mode
            isDragging = true
            dragHaptic.selectionChanged()
            dragHaptic.prepare()
            actions.onDragStart?(dragStartLocation ?? value.startLocation)
        }

        if isDragging {
            // Report drag updates
            let distFromLast = hypot(location.x - (lastReportedLocation?.x ?? 0),
                                     location.y - (lastReportedLocation?.y ?? 0))

            if distFromLast >= config.dragUpdateThreshold {
                lastReportedLocation = location
                dragHaptic.selectionChanged()
                dragHaptic.prepare()
                actions.onDragChanged?(location)
            }
        }
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        let drift = hypot(value.location.x - (dragStartLocation?.x ?? 0),
                          value.location.y - (dragStartLocation?.y ?? 0))

        if isDragging {
            // End drag
            actions.onDragEnded?()
        } else if drift < config.minimumDragDistance {
            // Minimal movement - treat as tap
            tapHaptic.selectionChanged()
            tapHaptic.prepare()
            actions.onTap?(value.startLocation)
        }

        // Reset state
        isDragging = false
        dragStartLocation = nil
        lastReportedLocation = nil
    }
}

// MARK: - Simple Tap Gesture Modifier (Normal Mode)

/// A simple tap gesture for normal mode (when selection mode is off).
/// Just detects taps - no drag handling, so swipes can pass through.
struct CalendarTapGestureModifier: ViewModifier {
    let onTap: ((CGPoint) -> Void)?
    let isEnabled: Bool

    private let tapHaptic = UISelectionFeedbackGenerator()

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onTapGesture { location in
                guard isEnabled else { return }
                tapHaptic.selectionChanged()
                tapHaptic.prepare()
                onTap?(location)
            }
            .onAppear {
                tapHaptic.prepare()
            }
    }
}

// MARK: - View Extensions

extension View {
    /// Add selection mode gestures (tap + drag for range selection)
    func calendarSelectionGestures(
        actions: CalendarGestureActions,
        config: CalendarGestureConfig = .default,
        isEnabled: Bool = true
    ) -> some View {
        modifier(CalendarSelectionGestureModifier(
            actions: actions,
            config: config,
            isEnabled: isEnabled
        ))
    }

    /// Add simple tap gesture for normal mode
    func calendarTapGesture(
        onTap: ((CGPoint) -> Void)?,
        isEnabled: Bool = true
    ) -> some View {
        modifier(CalendarTapGestureModifier(
            onTap: onTap,
            isEnabled: isEnabled
        ))
    }
}

// MARK: - Legacy Support (for compatibility)

/// Legacy modifier that uses the old API
struct CalendarGestureModifier: ViewModifier {
    let actions: CalendarGestureActions
    let config: CalendarGestureConfig
    let isEnabled: Bool

    func body(content: Content) -> some View {
        content
            .modifier(CalendarSelectionGestureModifier(
                actions: actions,
                config: config,
                isEnabled: isEnabled
            ))
    }
}

extension View {
    /// Add calendar gesture handling
    func calendarGestures(
        actions: CalendarGestureActions,
        config: CalendarGestureConfig = .default,
        isEnabled: Bool = true
    ) -> some View {
        modifier(CalendarGestureModifier(
            actions: actions,
            config: config,
            isEnabled: isEnabled
        ))
    }
}
