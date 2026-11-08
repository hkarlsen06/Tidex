import ExyteChat
import ImageIO
import SwiftUI
import UIKit

struct FriendsChatReplyDragValue {
  let location: CGPoint
  let startLocation: CGPoint
  let translation: CGSize
  let velocity: CGSize

  init(
    location: CGPoint,
    startLocation: CGPoint,
    translation: CGSize,
    velocity: CGSize
  ) {
    self.location = location
    self.startLocation = startLocation
    self.translation = translation
    self.velocity = velocity
  }

  init(_ value: DragGesture.Value) {
    self.init(
      location: value.location,
      startLocation: value.startLocation,
      translation: value.translation,
      velocity: value.velocity
    )
  }
}

struct FriendsChatReplyGestureModifier: ViewModifier {
  let isCurrentUser: Bool
  let onChanged: (FriendsChatReplyDragValue) -> Void
  let onEnded: (FriendsChatReplyDragValue) -> Void

  private var direction: FriendsChatReplySwipeDirection {
    isCurrentUser ? .left : .right
  }

  func body(content: Content) -> some View {
    content.overlay {
      FriendsChatHorizontalPanSurface(
        targetKind: .replyPayload(direction: direction),
        minimumDistance: FriendsChatReplySwipeResolver.minimumDistance,
        direction: direction,
        onChanged: onChanged,
        onEnded: onEnded
      )
    }
  }
}

enum FriendsChatGestureTargetKind {
  case replyPayload(direction: FriendsChatReplySwipeDirection)
  case attachmentPhotoCarousel
  case timestampRevealGutter
}

final class FriendsChatGestureTargetView: UIView {
  var kind: FriendsChatGestureTargetKind

  init(kind: FriendsChatGestureTargetKind) {
    self.kind = kind
    super.init(frame: .zero)
    backgroundColor = .clear
    isUserInteractionEnabled = false
  }

  deinit {
    // Required by lint policy for explicit class teardown.
  }

  @available(*, unavailable)
  // swiftlint:disable:next explicit_acl
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // swiftlint:disable:next explicit_acl
  override func point(inside _: CGPoint, with _: UIEvent?) -> Bool {
    false
  }
}

final class FriendsChatDirectionalPanGestureRecognizer: UIPanGestureRecognizer {
  var targetKind: FriendsChatGestureTargetKind?
  var direction: FriendsChatReplySwipeDirection?

  deinit {
    // Required by lint policy for explicit class teardown.
  }
}

struct FriendsChatGestureTargetSurface: UIViewRepresentable {
  let targetKind: FriendsChatGestureTargetKind

  func makeUIView(context _: Context) -> UIView {
    FriendsChatGestureTargetView(kind: targetKind)
  }

  func updateUIView(_ uiView: UIView, context _: Context) {
    if let targetView = uiView as? FriendsChatGestureTargetView {
      targetView.kind = targetKind
    }
  }
}

struct FriendsChatHorizontalPanSurface: UIViewRepresentable {
  let targetKind: FriendsChatGestureTargetKind
  let minimumDistance: CGFloat
  let direction: FriendsChatReplySwipeDirection
  let onChanged: (FriendsChatReplyDragValue) -> Void
  let onEnded: (FriendsChatReplyDragValue) -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(
      targetKind: targetKind,
      minimumDistance: minimumDistance,
      direction: direction,
      onChanged: onChanged,
      onEnded: onEnded
    )
  }

  func makeUIView(context: Context) -> UIView {
    let view = FriendsChatGestureTargetView(kind: targetKind)
    context.coordinator.attach(to: view)
    return view
  }

  func updateUIView(_ uiView: UIView, context: Context) {
    if let targetView = uiView as? FriendsChatGestureTargetView {
      targetView.kind = targetKind
    }
    context.coordinator.targetKind = targetKind
    context.coordinator.minimumDistance = minimumDistance
    context.coordinator.direction = direction
    context.coordinator.onChanged = onChanged
    context.coordinator.onEnded = onEnded
    context.coordinator.attach(to: uiView)
  }

  // swiftlint:disable:next type_contents_order
  static func dismantleUIView(_: UIView, coordinator: Coordinator) {
    coordinator.detach()
  }

  final class Coordinator: NSObject, UIGestureRecognizerDelegate {
    var targetKind: FriendsChatGestureTargetKind
    var minimumDistance: CGFloat
    var direction: FriendsChatReplySwipeDirection
    var onChanged: (FriendsChatReplyDragValue) -> Void
    var onEnded: (FriendsChatReplyDragValue) -> Void
    private weak var view: UIView?
    private weak var gestureHostView: UIView?
    private var recognizer: UIPanGestureRecognizer?
    private var hasPassedMinimumDistance: Bool = false

    init(
      targetKind: FriendsChatGestureTargetKind,
      minimumDistance: CGFloat,
      direction: FriendsChatReplySwipeDirection,
      onChanged: @escaping (FriendsChatReplyDragValue) -> Void,
      onEnded: @escaping (FriendsChatReplyDragValue) -> Void
    ) {
      self.targetKind = targetKind
      self.minimumDistance = minimumDistance
      self.direction = direction
      self.onChanged = onChanged
      self.onEnded = onEnded
    }

    func attach(to view: UIView) {
      self.view = view
      installRecognizerIfPossible()

      DispatchQueue.main.async { [weak self, weak view] in
        guard let self, self.view === view else {
          return
        }
        installRecognizerIfPossible()
      }
    }

    func detach() {
      if let recognizer, let gestureHostView {
        gestureHostView.removeGestureRecognizer(recognizer)
      }
      recognizer = nil
      view = nil
      gestureHostView = nil
      hasPassedMinimumDistance = false
    }

    private func installRecognizerIfPossible() {
      guard let view, let hostView = gestureHost(for: view) else {
        return
      }
      guard gestureHostView !== hostView else {
        return
      }

      if let recognizer, let gestureHostView {
        gestureHostView.removeGestureRecognizer(recognizer)
      }

      let panRecognizer: UIPanGestureRecognizer =
        recognizer
        ?? FriendsChatDirectionalPanGestureRecognizer(
          target: self,
          action: #selector(handlePan(_:))
        )
      if let directionalRecognizer = panRecognizer as? FriendsChatDirectionalPanGestureRecognizer {
        directionalRecognizer.targetKind = targetKind
        directionalRecognizer.direction = direction
      }
      panRecognizer.cancelsTouchesInView = false
      panRecognizer.delaysTouchesBegan = false
      panRecognizer.delaysTouchesEnded = false
      panRecognizer.delegate = self
      hostView.addGestureRecognizer(panRecognizer)
      self.recognizer = panRecognizer
      gestureHostView = hostView
    }

    private func gestureHost(for view: UIView) -> UIView? {
      var ancestors: [UIView] = []
      var currentView: UIView? = view.superview
      while let ancestor = currentView {
        ancestors.append(ancestor)
        currentView = ancestor.superview
      }
      return ancestors.first { $0 is UITableViewCell } ?? view.superview
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
      guard let view else {
        return
      }
      let value: FriendsChatReplyDragValue = dragValue(from: recognizer, in: view)

      switch recognizer.state {
      case .began:
        hasPassedMinimumDistance = false
        handleChangedIfReady(value)

      case .changed:
        handleChangedIfReady(value)

      case .ended:
        handleChangedIfReady(value)
        if hasPassedMinimumDistance {
          onEnded(value)
        }
        hasPassedMinimumDistance = false

      case .cancelled, .failed:
        if hasPassedMinimumDistance {
          onEnded(value)
        }
        hasPassedMinimumDistance = false

      case .possible:
        break

      @unknown default:
        if hasPassedMinimumDistance {
          onEnded(value)
        }
        hasPassedMinimumDistance = false
      }
    }

    private func handleChangedIfReady(_ value: FriendsChatReplyDragValue) {
      if !hasPassedMinimumDistance {
        guard
          hypot(value.translation.width, value.translation.height) >= minimumDistance
        else {
          return
        }
        hasPassedMinimumDistance = true
      }

      onChanged(value)
    }

    private func dragValue(
      from recognizer: UIPanGestureRecognizer,
      in view: UIView
    ) -> FriendsChatReplyDragValue {
      let coordinateView: UIView = view.window ?? view
      let translation: CGPoint = recognizer.translation(in: coordinateView)
      let velocity: CGPoint = recognizer.velocity(in: coordinateView)
      let location: CGPoint = recognizer.location(in: coordinateView)
      let startLocation: CGPoint = CGPoint(
        x: location.x - translation.x,
        y: location.y - translation.y
      )

      return FriendsChatReplyDragValue(
        location: location,
        startLocation: startLocation,
        translation: CGSize(width: translation.x, height: translation.y),
        velocity: CGSize(width: velocity.x, height: velocity.y)
      )
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
      guard let recognizer = gestureRecognizer as? UIPanGestureRecognizer, let view else {
        return true
      }
      guard view.bounds.contains(recognizer.location(in: view)) else {
        return false
      }
      let velocity: CGPoint = recognizer.velocity(in: view.window ?? view)
      return FriendsChatPanGestureResolver.hasDirectionalHorizontalIntent(
        velocity: CGSize(width: velocity.x, height: velocity.y),
        direction: direction
      )
    }

    func gestureRecognizer(
      _: UIGestureRecognizer,
      shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer
    ) -> Bool {
      true
    }
  }
}

struct FriendsChatReplySwipeContainer<Content: View, ActionLabel: View>: View {
  let id: String
  let isCurrentUser: Bool
  let offset: CGFloat
  let actionAlignment: Alignment
  let onChanged: (FriendsChatReplyDragValue) -> Void
  let onEnded: (FriendsChatReplyDragValue) -> Void
  @ViewBuilder let content: () -> Content
  @ViewBuilder let actionLabel: () -> ActionLabel

  var body: some View {
    content()
      .background(framePreference)
      .contentShape(Rectangle())
      .modifier(
        FriendsChatReplyGestureModifier(
          isCurrentUser: isCurrentUser,
          onChanged: onChanged,
          onEnded: onEnded
        )
      )
      .overlay(alignment: actionAlignment) {
        actionLabel()
          .offset(x: actionAlignment == .leading ? -48 : 48)
          .allowsHitTesting(false)
      }
      .offset(x: offset)
  }

  private var framePreference: some View {
    GeometryReader { proxy in
      Color.clear.preference(
        key: FriendsChatReplyPayloadFramePreferenceKey.self,
        value: [id: proxy.frame(in: .global)]
      )
    }
  }
}