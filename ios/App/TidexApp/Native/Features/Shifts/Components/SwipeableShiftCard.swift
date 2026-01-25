import SwiftUI

/// Shared haptic feedback generators for swipeable cards
/// Using shared instances avoids creating new generators for each card (performance)
private enum SwipeHaptics {
    static let impact = UIImpactFeedbackGenerator(style: .medium)
    static let selection = UISelectionFeedbackGenerator()
    private static var isPrepared = false

    static func prepareIfNeeded() {
        guard !isPrepared else { return }
        isPrepared = true
        impact.prepare()
        selection.prepare()
    }
}

/// A swipeable container for shift cards that reveals edit/delete actions
/// Swipe right reveals edit action, swipe left reveals delete action
///
/// ARCHITECTURE: Uses the proven "empty onTapGesture + minimumDistance" pattern
/// from Daniel Saidi (https://danielsaidi.com) and Hacking with Swift forums.
///
/// The key insights:
/// 1. `DragGesture(minimumDistance: 0)` steals ALL touches from ScrollView
/// 2. `minimumDistance: 20` gives ScrollView a chance to recognize vertical scroll first
/// 3. Adding `.onTapGesture {}` triggers Apple's built-in touch delay handling
/// 4. Combined, these allow natural scroll while preserving horizontal swipe detection
struct SwipeableShiftCard<Content: View>: View {
    let content: () -> Content
    let onEdit: () -> Void
    let onDelete: (() -> Void)?

    @State private var offset: CGFloat = 0
    @State private var hasTriggeredHaptic = false

    /// Threshold for triggering action (40% of action width)
    private let actionThreshold: CGFloat = 0.4
    /// Width of the action area
    private let actionWidth: CGFloat = 80

    init(
        onEdit: @escaping () -> Void,
        onDelete: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.onEdit = onEdit
        self.onDelete = onDelete
        self.content = content
    }

    var body: some View {
        ZStack(alignment: .center) {
            // Background actions - positioned behind content
            HStack(spacing: 0) {
                // Left action (Edit) - revealed on swipe right
                editActionBackground
                    .frame(width: actionWidth)
                    .opacity(offset > 0 ? 1 : 0)

                Spacer()

                // Right action (Delete) - revealed on swipe left
                if onDelete != nil {
                    deleteActionBackground
                        .frame(width: actionWidth)
                        .opacity(offset < 0 ? 1 : 0)
                }
            }

            // Main content with offset for swipe animation
            content()
                .offset(x: offset)
        }
        // CRITICAL: Empty onTapGesture enables Apple's built-in touch delay handling
        // Without this, DragGesture captures touches before ScrollView can recognize scroll
        // Source: https://www.hackingwithswift.com/forums/swiftui/a-guide-to-delaying-gestures-in-scrollview/6005
        .onTapGesture { }
        // Use highPriorityGesture with minimumDistance: 20
        // - minimumDistance: 20 gives ScrollView a chance to capture vertical scrolls first
        // - highPriorityGesture ensures we get horizontal drags once they exceed the threshold
        // Source: https://darjeelingsteve.com/articles/Preventing-Scroll-Hijacking-by-DragGestureRecognizer-Inside-ScrollView.html
        .highPriorityGesture(
            DragGesture(minimumDistance: 20)
                .onChanged { value in
                    handleDragChanged(value: value)
                }
                .onEnded { value in
                    handleDragEnded(value: value)
                }
        )
        .onAppear {
            SwipeHaptics.prepareIfNeeded()
        }
    }

    // MARK: - Background Actions

    private var editActionBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.tidexBlue)

            VStack(spacing: 4) {
                Image(systemName: "pencil")
                    .font(.system(size: 20, weight: .medium))
                Text("Edit")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(.white)
            .opacity(editContentOpacity)
            .scaleEffect(editActionScale)
        }
    }

    private var deleteActionBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.tidexError)

            VStack(spacing: 4) {
                Image(systemName: "trash")
                    .font(.system(size: 20, weight: .medium))
                Text("Delete")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(.white)
            .opacity(deleteContentOpacity)
            .scaleEffect(deleteActionScale)
        }
    }

    // MARK: - Computed Properties

    private var editContentOpacity: Double {
        guard offset > 0 else { return 0 }
        return min(Double(offset) / Double(actionWidth * 0.6), 1.0)
    }

    private var editActionScale: CGFloat {
        guard offset > 0 else { return 0.7 }
        let progress = min(offset / actionWidth, 1.0)
        return 0.7 + (progress * 0.3)
    }

    private var deleteContentOpacity: Double {
        guard offset < 0 else { return 0 }
        return min(Double(abs(offset)) / Double(actionWidth * 0.6), 1.0)
    }

    private var deleteActionScale: CGFloat {
        guard offset < 0 else { return 0.7 }
        let progress = min(abs(offset) / actionWidth, 1.0)
        return 0.7 + (progress * 0.3)
    }

    // MARK: - Gesture Handlers

    private func handleDragChanged(value: DragGesture.Value) {
        let horizontal = value.translation.width
        let vertical = abs(value.translation.height)

        // Only respond to horizontal drags (minimumDistance: 20 already filtered out small moves)
        // If the user is dragging more vertically than horizontally, ignore (let scroll handle it)
        guard abs(horizontal) > vertical else { return }

        let canSwipeLeft = onDelete != nil
        var newOffset = horizontal

        // Restrict direction based on available actions
        if !canSwipeLeft && horizontal < 0 {
            newOffset = 0
        }

        // Clamp to action width with rubber-band effect beyond
        if abs(newOffset) > actionWidth {
            let excess = abs(newOffset) - actionWidth
            let sign: CGFloat = newOffset > 0 ? 1 : -1
            newOffset = sign * (actionWidth + excess * 0.3)
        }

        offset = newOffset

        // Haptic feedback at threshold
        let thresholdOffset = actionWidth * actionThreshold
        let crossedThreshold = abs(offset) >= thresholdOffset

        if crossedThreshold && !hasTriggeredHaptic {
            hasTriggeredHaptic = true
            SwipeHaptics.impact.impactOccurred()
            SwipeHaptics.impact.prepare()
        } else if !crossedThreshold && hasTriggeredHaptic {
            hasTriggeredHaptic = false
            SwipeHaptics.selection.prepare()
        }
    }

    private func handleDragEnded(value: DragGesture.Value) {
        let wasSwipingRight = offset > 0
        let wasSwipingLeft = offset < 0
        let finalOffset = offset

        // Reset haptic state
        hasTriggeredHaptic = false

        // If no meaningful offset, nothing to do
        guard finalOffset != 0 else { return }

        let thresholdOffset = actionWidth * actionThreshold
        let velocity = value.velocity.width

        // Check if we should trigger action based on position OR velocity
        let fullySwipedRight = wasSwipingRight && (finalOffset >= thresholdOffset || velocity > 300)
        let fullySwipedLeft = wasSwipingLeft && (abs(finalOffset) >= thresholdOffset || velocity < -300)

        // Animate back to center
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            offset = 0
        }

        // Trigger actions
        if fullySwipedRight {
            SwipeHaptics.impact.impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                onEdit()
            }
        } else if fullySwipedLeft && onDelete != nil {
            SwipeHaptics.impact.impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                onDelete?()
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            ForEach(0..<10, id: \.self) { index in
                SwipeableShiftCard(
                    onEdit: { print("Edit \(index)") },
                    onDelete: { print("Delete \(index)") }
                ) {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color.tidexSurfacePrimary)
                        .frame(height: 100)
                        .overlay(
                            Text("Swipe card \(index)")
                                .foregroundColor(.tidexTextPrimary)
                        )
                }
            }
        }
        .padding()
    }
    .background(Color.tidexBackground)
}
