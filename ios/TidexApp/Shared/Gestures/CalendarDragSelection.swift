import SwiftUI
import UIKit

// MARK: - Drag Selection

/// Long press a day, then drag to select (or deselect, if the first day was selected)
/// every day between it and the finger. Dragging back restores the days it leaves.
struct CalendarDragSelection: Equatable {
  let anchor: String
  var hover: String
  let baseline: Set<String>
  let isSelecting: Bool

  init(anchor: String, baseline: Set<String>) {
    self.anchor = anchor
    hover = anchor
    self.baseline = baseline
    isSelecting = !baseline.contains(anchor)
  }

  /// The baseline with every eligible day from the anchor to the hovered day applied.
  func selection(in days: [CalendarDayInfo], isEligible: (String) -> Bool) -> Set<String> {
    guard let anchorIndex = days.firstIndex(where: { $0.dateISO == anchor }),
      let hoverIndex = days.firstIndex(where: { $0.dateISO == hover })
    else { return baseline }

    let range = days[min(anchorIndex, hoverIndex)...max(anchorIndex, hoverIndex)]
      .compactMap(\.dateISO)
      .filter(isEligible)
    return isSelecting ? baseline.union(range) : baseline.subtracting(range)
  }

  /// Advances `drag` for a long press update over `dateISO` and returns the new selection,
  /// or nil when the selection doesn't change.
  static func update(
    _ drag: inout Self?,
    state: UIGestureRecognizer.State,
    dateISO: String?,
    days: [CalendarDayInfo],
    current: Set<String>,
    isEligible: (String) -> Bool = { _ in true }
  ) -> Set<String>? {
    switch state {
    case .began:
      guard let dateISO else { return nil }
      drag = Self(anchor: dateISO, baseline: current)

    case .changed:
      guard drag != nil, let dateISO, dateISO != drag?.hover else { return nil }
      drag?.hover = dateISO

    default:
      drag = nil
      return nil
    }

    guard let selection = drag?.selection(in: days, isEligible: isEligible), selection != current
    else { return nil }
    return selection
  }

  /// Maps a point in a `CalendarMonthGrid` to its in-month day, ignoring the gaps between cells.
  static func dateISO(at location: CGPoint, gridSize: CGSize, days: [CalendarDayInfo]) -> String? {
    let columnCount = CalendarGridHelper.columnCount
    let spacing = CalendarGridHelper.cellSpacing
    let cellWidth = (gridSize.width - spacing * CGFloat(columnCount - 1)) / CGFloat(columnCount)
    let cellHeight = cellWidth / CalendarGridHelper.cellAspectRatio
    guard cellWidth > 0, location.x >= 0, location.y >= 0 else { return nil }

    let column = Int(location.x / (cellWidth + spacing))
    let row = Int(location.y / (cellHeight + spacing))
    guard column < columnCount,
      location.x - CGFloat(column) * (cellWidth + spacing) <= cellWidth,
      location.y - CGFloat(row) * (cellHeight + spacing) <= cellHeight
    else { return nil }

    let index = row * columnCount + column
    guard days.indices.contains(index), !days[index].isOutsideMonth else { return nil }
    return days[index].dateISO
  }
}

// MARK: - Press Overlay

/// Clear overlay for a calendar grid that reports taps, long press followed by a drag
/// (when `onDragSelect` is set), and horizontal month swipes (when a swipe callback is set).
/// Once the long press begins it wins over scroll and swipe pans,
/// so dragging selects days instead of scrolling or changing month.
struct CalendarDragSelectOverlay: UIViewRepresentable {
  private static let minimumPressDuration: TimeInterval = 0.3

  let onTap: (CGPoint) -> Void
  var onDragSelect: ((UIGestureRecognizer.State, CGPoint) -> Void)?
  var onSwipeLeft: (() -> Void)?
  var onSwipeRight: (() -> Void)?

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

    if onDragSelect != nil {
      let longPressRecognizer = UILongPressGestureRecognizer(
        target: context.coordinator,
        action: #selector(Coordinator.handleLongPress(_:))
      )
      longPressRecognizer.minimumPressDuration = Self.minimumPressDuration
      view.addGestureRecognizer(longPressRecognizer)
      tapRecognizer.require(toFail: longPressRecognizer)
    }

    if onSwipeLeft != nil || onSwipeRight != nil {
      let panRecognizer = UIPanGestureRecognizer(
        target: context.coordinator,
        action: #selector(Coordinator.handlePan(_:))
      )
      panRecognizer.cancelsTouchesInView = false
      panRecognizer.delegate = context.coordinator
      view.addGestureRecognizer(panRecognizer)
    }

    return view
  }

  func updateUIView(_: UIView, context: Context) {
    context.coordinator.onTap = onTap
    context.coordinator.onDragSelect = onDragSelect
    context.coordinator.onSwipeLeft = onSwipeLeft
    context.coordinator.onSwipeRight = onSwipeRight
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(onTap: onTap)
  }

  final class Coordinator: NSObject, UIGestureRecognizerDelegate {
    private static let swipeThreshold: CGFloat = 40
    private static let flickVelocity: CGFloat = 280
    private static let horizontalBias: CGFloat = 1.25

    var onTap: (CGPoint) -> Void
    var onDragSelect: ((UIGestureRecognizer.State, CGPoint) -> Void)?
    var onSwipeLeft: (() -> Void)?
    var onSwipeRight: (() -> Void)?

    init(onTap: @escaping (CGPoint) -> Void) {
      self.onTap = onTap
    }

    @objc
    func handleTap(_ recognizer: UITapGestureRecognizer) {
      guard recognizer.state == .ended, let view = recognizer.view else { return }
      onTap(recognizer.location(in: view))
    }

    @objc
    func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
      guard let view = recognizer.view else { return }
      onDragSelect?(recognizer.state, recognizer.location(in: view))
    }

    @objc
    func handlePan(_ recognizer: UIPanGestureRecognizer) {
      guard recognizer.state == .ended, let view = recognizer.view else { return }

      let translation = recognizer.translation(in: view)
      let isFlick = abs(recognizer.velocity(in: view).x) >= Self.flickVelocity
      guard abs(translation.x) > abs(translation.y),
        isFlick || abs(translation.x) >= Self.swipeThreshold
      else { return }

      Haptics.play(.medium)
      if translation.x < 0 {
        onSwipeLeft?()
      } else {
        onSwipeRight?()
      }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
      guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
      let velocity = pan.velocity(in: pan.view)
      return abs(velocity.x) >= abs(velocity.y) * Self.horizontalBias
    }

    /// Lets parent taps, such as focus dismissal, fire alongside day taps.
    /// The long press and swipe pan stay exclusive.
    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer
    ) -> Bool {
      gestureRecognizer is UITapGestureRecognizer
    }
  }
}
