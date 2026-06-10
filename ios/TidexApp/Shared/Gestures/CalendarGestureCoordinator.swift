// swiftlint:disable:next blanket_disable_command
// swiftlint:disable line_length superfluous_disable_command
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable conditional_returns_on_newline explicit_acl explicit_top_level_acl explicit_type_interface
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable file_name file_types_order multiline_arguments_brackets no_magic_numbers
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable prefer_condition_list prefer_self_in_static_references required_deinit type_contents_order
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable unused_parameter
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
    case left  // Next month
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

  static let `default` = Self(
    minimumDragDistance: 10,  // Needs some movement to be a drag
    dragUpdateThreshold: 5  // Report updates frequently
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
    let drift = hypot(
      location.x - (dragStartLocation?.x ?? 0),
      location.y - (dragStartLocation?.y ?? 0))

    if !isDragging, drift >= config.minimumDragDistance {
      // Start drag mode
      isDragging = true
      dragHaptic.selectionChanged()
      dragHaptic.prepare()
      actions.onDragStart?(dragStartLocation ?? value.startLocation)
    }

    if isDragging {
      // Report drag updates
      let distFromLast = hypot(
        location.x - (lastReportedLocation?.x ?? 0),
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
    let drift = hypot(
      value.location.x - (dragStartLocation?.x ?? 0),
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

// MARK: - Location-Aware Long Press Gesture Modifier

/// A long-press recognizer that reports the press location without cancelling
/// touches, so parent scroll/swipe gestures can continue to recognize.
struct CalendarLongPressGestureModifier: ViewModifier {
  let onTap: ((CGPoint) -> Void)?
  let onLongPress: ((CGPoint) -> Void)?
  let onSwipeLeft: (() -> Void)?
  let onSwipeRight: (() -> Void)?
  let isEnabled: Bool

  private let tapHaptic = UISelectionFeedbackGenerator()

  func body(content: Content) -> some View {
    content
      .overlay {
        if isEnabled {
          CalendarPressOverlay(
            onTap: { location in
              tapHaptic.selectionChanged()
              tapHaptic.prepare()
              onTap?(location)
            },
            onLongPress: onLongPress,
            onSwipeLeft: onSwipeLeft,
            onSwipeRight: onSwipeRight
          )
          .allowsHitTesting(true)
        }
      }
      .onAppear {
        tapHaptic.prepare()
      }
  }
}

private struct CalendarPressOverlay: UIViewRepresentable {
  let onTap: ((CGPoint) -> Void)?
  let onLongPress: ((CGPoint) -> Void)?
  let onSwipeLeft: (() -> Void)?
  let onSwipeRight: (() -> Void)?

  func makeUIView(context: Context) -> UIView {
    let view = UIView(frame: .zero)
    view.backgroundColor = .clear

    let tapRecognizer = UITapGestureRecognizer(
      target: context.coordinator,
      action: #selector(Coordinator.handleTap(_:))
    )
    tapRecognizer.cancelsTouchesInView = false
    tapRecognizer.delegate = context.coordinator
    view.addGestureRecognizer(tapRecognizer)

    let recognizer = UILongPressGestureRecognizer(
      target: context.coordinator,
      action: #selector(Coordinator.handleLongPress(_:))
    )
    recognizer.minimumPressDuration = 0.5
    recognizer.allowableMovement = 10
    recognizer.cancelsTouchesInView = false
    recognizer.delegate = context.coordinator
    view.addGestureRecognizer(recognizer)

    let panRecognizer = UIPanGestureRecognizer(
      target: context.coordinator,
      action: #selector(Coordinator.handlePan(_:))
    )
    panRecognizer.cancelsTouchesInView = false
    panRecognizer.delegate = context.coordinator
    view.addGestureRecognizer(panRecognizer)

    return view
  }

  func updateUIView(_: UIView, context: Context) {
    context.coordinator.onTap = onTap
    context.coordinator.onLongPress = onLongPress
    context.coordinator.onSwipeLeft = onSwipeLeft
    context.coordinator.onSwipeRight = onSwipeRight
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(
      onTap: onTap,
      onLongPress: onLongPress,
      onSwipeLeft: onSwipeLeft,
      onSwipeRight: onSwipeRight
    )
  }

  final class Coordinator: NSObject, UIGestureRecognizerDelegate {
    var onTap: ((CGPoint) -> Void)?
    var onLongPress: ((CGPoint) -> Void)?
    var onSwipeLeft: (() -> Void)?
    var onSwipeRight: (() -> Void)?

    private let swipeThreshold: CGFloat = 40
    private let flickVelocity: CGFloat = 280
    private let haptic = UIImpactFeedbackGenerator(style: .medium)

    init(
      onTap: ((CGPoint) -> Void)?,
      onLongPress: ((CGPoint) -> Void)?,
      onSwipeLeft: (() -> Void)?,
      onSwipeRight: (() -> Void)?
    ) {
      self.onTap = onTap
      self.onLongPress = onLongPress
      self.onSwipeLeft = onSwipeLeft
      self.onSwipeRight = onSwipeRight
      haptic.prepare()
    }

    @objc
    func handleTap(_ recognizer: UITapGestureRecognizer) {
      guard recognizer.state == .ended, let view = recognizer.view else { return }
      onTap?(recognizer.location(in: view))
    }

    @objc
    func handlePan(_ recognizer: UIPanGestureRecognizer) {
      guard recognizer.state == .ended, let view = recognizer.view else { return }
      guard onSwipeLeft != nil || onSwipeRight != nil else { return }

      let translation = recognizer.translation(in: view)
      let velocity = recognizer.velocity(in: view)
      let horizontal = translation.x
      let vertical = abs(translation.y)
      let isFlick = abs(velocity.x) >= flickVelocity
      let crossedThreshold = abs(horizontal) >= swipeThreshold

      guard abs(horizontal) > vertical, isFlick || crossedThreshold else { return }

      haptic.impactOccurred()
      haptic.prepare()

      if horizontal < 0 {
        onSwipeLeft?()
      } else {
        onSwipeRight?()
      }
    }

    @objc
    func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
      guard recognizer.state == .began, let view = recognizer.view else { return }
      onLongPress?(recognizer.location(in: view))
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
      guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
      guard onSwipeLeft != nil || onSwipeRight != nil else { return false }

      let velocity = pan.velocity(in: pan.view)
      return abs(velocity.x) >= abs(velocity.y) * 0.9
    }

    func gestureRecognizer(
      _: UIGestureRecognizer,
      shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer
    ) -> Bool {
      true
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
    modifier(
      CalendarSelectionGestureModifier(
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
    modifier(
      CalendarTapGestureModifier(
        onTap: onTap,
        isEnabled: isEnabled
      ))
  }

  /// Add location-aware long press handling without blocking parent gestures.
  func calendarPressGestures(
    onTap: ((CGPoint) -> Void)?,
    onLongPress: ((CGPoint) -> Void)?,
    onSwipeLeft: (() -> Void)? = nil,
    onSwipeRight: (() -> Void)? = nil,
    isEnabled: Bool = true
  ) -> some View {
    modifier(
      CalendarLongPressGestureModifier(
        onTap: onTap,
        onLongPress: onLongPress,
        onSwipeLeft: onSwipeLeft,
        onSwipeRight: onSwipeRight,
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
      .modifier(
        CalendarSelectionGestureModifier(
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
    modifier(
      CalendarGestureModifier(
        actions: actions,
        config: config,
        isEnabled: isEnabled
      ))
  }
}
