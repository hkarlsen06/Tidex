// swiftlint:disable:next blanket_disable_command
// swiftlint:disable line_length superfluous_disable_command
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable closure_body_length conditional_returns_on_newline explicit_acl explicit_top_level_acl
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable explicit_type_interface file_name file_types_order multiline_arguments_brackets
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable no_magic_numbers number_separator prefer_condition_list prefer_self_in_static_references
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable required_deinit sorted_enum_cases type_contents_order
import SwiftUI
import UIKit

// MARK: - Month Navigation Direction

/// Direction of month navigation (used for animations)
enum MonthNavigationDirection: Equatable {
  case previous  // Swipe right → go to previous month
  case next  // Swipe left → go to next month
}

// MARK: - Month Navigation Protocol

/// Protocol for view models that support month navigation via swipe
/// Must be @MainActor since it's typically used with @Observable view models
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

// MARK: - View Extension

extension View {
  /// Preferred month swipe API that uses UIKit recognizers under the hood.
  /// Designed to minimize conflicts with vertical scroll/pull-to-refresh gestures.
  func monthSwipeGesture(
    onSwipeLeft: @escaping () -> Void,
    onSwipeRight: @escaping () -> Void,
    threshold: CGFloat = 50,
    edgeExclusion: CGFloat = 0,
    isEnabled: Bool = true
  ) -> some View {
    self.modifier(
      MonthSwipeGestureModifier(
        onSwipeLeft: onSwipeLeft,
        onSwipeRight: onSwipeRight,
        threshold: threshold,
        edgeExclusion: edgeExclusion,
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
  let edgeExclusion: CGFloat
  let isEnabled: Bool
  @Environment(\.layoutDirection) private var layoutDirection

  func body(content: Content) -> some View {
    content
      .background(
        SwipeGestureView(
          onSwipeLeft: onSwipeLeft,
          onSwipeRight: onSwipeRight,
          threshold: threshold,
          edgeExclusion: edgeExclusion,
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
  let edgeExclusion: CGFloat
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
    context.coordinator.edgeExclusion = edgeExclusion
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
      edgeExclusion: edgeExclusion,
      isEnabled: isEnabled,
      isRTL: isRTL
    )
  }

  class Coordinator: NSObject, UIGestureRecognizerDelegate {
    var onSwipeLeft: () -> Void
    var onSwipeRight: () -> Void
    var threshold: CGFloat
    var edgeExclusion: CGFloat
    var isEnabled: Bool
    var isRTL: Bool

    private let horizontalPrecedenceMultiplier: CGFloat = 0.9
    private let flickVelocity: CGFloat = 280
    private let haptic = UIImpactFeedbackGenerator(style: .medium)

    init(
      onSwipeLeft: @escaping () -> Void,
      onSwipeRight: @escaping () -> Void,
      threshold: CGFloat,
      edgeExclusion: CGFloat,
      isEnabled: Bool,
      isRTL: Bool
    ) {
      self.onSwipeLeft = onSwipeLeft
      self.onSwipeRight = onSwipeRight
      self.threshold = threshold
      self.edgeExclusion = edgeExclusion
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

      let location = pan.location(in: view)
      if edgeExclusion > 0 {
        let minX = edgeExclusion
        let maxX = view.bounds.width - edgeExclusion
        guard location.x > minX, location.x < maxX else {
          return false
        }
      }

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
