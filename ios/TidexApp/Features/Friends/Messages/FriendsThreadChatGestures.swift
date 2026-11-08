import ExyteChat
import Foundation
import SwiftUI
import UIKit

struct FriendsThreadNavigationGestureBridge: UIViewRepresentable {
  let onNavigateBack: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(onNavigateBack: onNavigateBack)
  }

  // swiftlint:disable:next explicit_acl type_contents_order
  func makeUIView(context _: Context) -> UIView {
    let view = UIView(frame: .zero)
    view.isUserInteractionEnabled = false
    return view
  }

  func updateUIView(_ uiView: UIView, context: Context) {
    context.coordinator.onNavigateBack = onNavigateBack
    DispatchQueue.main.async {
      context.coordinator.configure(from: uiView)
    }
  }

  // swiftlint:disable:next explicit_acl type_contents_order
  static func dismantleUIView(_: UIView, coordinator: Coordinator) {
    coordinator.restore()
  }

  final class Coordinator: NSObject, UIGestureRecognizerDelegate {
    var onNavigateBack: () -> Void
    private weak var contentPopGestureRecognizer: UIGestureRecognizer?
    private weak var originalDelegate: UIGestureRecognizerDelegate?
    private weak var navigationView: UIView?
    private var backgroundBackPanGestureRecognizer: UIPanGestureRecognizer?

    init(onNavigateBack: @escaping () -> Void) {
      self.onNavigateBack = onNavigateBack
    }

    func configure(from view: UIView) {
      guard let navigationController = view.closestNavigationController() else { return }

      guard let recognizer = navigationController.interactiveContentPopGestureRecognizer else {
        installBackgroundBackRecognizerIfNeeded(on: navigationController.view)
        return
      }
      guard contentPopGestureRecognizer !== recognizer else { return }

      restore()
      originalDelegate = recognizer.delegate
      recognizer.delegate = self
      recognizer.isEnabled = true
      contentPopGestureRecognizer = recognizer
      installBackgroundBackRecognizerIfNeeded(on: navigationController.view)
    }

    func restore() {
      if let backgroundBackPanGestureRecognizer, let navigationView {
        navigationView.removeGestureRecognizer(backgroundBackPanGestureRecognizer)
      }
      backgroundBackPanGestureRecognizer = nil
      navigationView = nil

      guard let recognizer = contentPopGestureRecognizer else { return }
      if recognizer.delegate === self {
        recognizer.delegate = originalDelegate
      }
      contentPopGestureRecognizer = nil
      originalDelegate = nil
    }

    private func installBackgroundBackRecognizerIfNeeded(on view: UIView) {
      guard navigationView !== view else { return }

      if let backgroundBackPanGestureRecognizer, let navigationView {
        navigationView.removeGestureRecognizer(backgroundBackPanGestureRecognizer)
      }

      let recognizer =
        backgroundBackPanGestureRecognizer
        ?? UIPanGestureRecognizer(
          target: self,
          action: #selector(handleBackgroundBackPan(_:))
        )
      recognizer.cancelsTouchesInView = false
      recognizer.delaysTouchesBegan = false
      recognizer.delaysTouchesEnded = false
      recognizer.delegate = self
      view.addGestureRecognizer(recognizer)
      backgroundBackPanGestureRecognizer = recognizer
      navigationView = view
    }

    @objc private func handleBackgroundBackPan(_ recognizer: UIPanGestureRecognizer) {
      guard recognizer.state == .ended else { return }

      let translation = recognizer.translation(in: recognizer.view)
      let velocity = recognizer.velocity(in: recognizer.view)
      guard
        FriendsChatPanGestureResolver.shouldTriggerNavigationBack(
          translation: CGSize(width: translation.x, height: translation.y),
          velocity: CGSize(width: velocity.x, height: velocity.y)
        )
      else {
        return
      }

      onNavigateBack()
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
      if gestureRecognizer === backgroundBackPanGestureRecognizer {
        guard let recognizer = gestureRecognizer as? UIPanGestureRecognizer else {
          return true
        }
        let velocity = recognizer.velocity(in: recognizer.view)
        guard
          FriendsChatPanGestureResolver.hasDirectionalHorizontalIntent(
            velocity: CGSize(width: velocity.x, height: velocity.y),
            direction: .right
          )
        else {
          return false
        }

        return startsInChatTableBackground(gestureRecognizer)
      }

      guard gestureRecognizer === contentPopGestureRecognizer else {
        return originalDelegate?.gestureRecognizerShouldBegin?(gestureRecognizer) ?? true
      }

      if originalDelegate?.gestureRecognizerShouldBegin?(gestureRecognizer) == false {
        return false
      }

      if let recognizer = gestureRecognizer as? UIPanGestureRecognizer {
        let velocity = recognizer.velocity(in: recognizer.view)
        guard
          FriendsChatPanGestureResolver.hasDirectionalHorizontalIntent(
            velocity: CGSize(width: velocity.x, height: velocity.y),
            direction: .right
          )
        else {
          return false
        }
      }

      return !startsInNavigationBackExcludedTarget(gestureRecognizer)
    }

    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
      if isBackNavigationRecognizer(gestureRecognizer, competingWith: otherGestureRecognizer) {
        return false
      }

      if gestureRecognizer === backgroundBackPanGestureRecognizer
        || otherGestureRecognizer === backgroundBackPanGestureRecognizer
      {
        return true
      }

      guard gestureRecognizer === contentPopGestureRecognizer else {
        return originalDelegate?.gestureRecognizer?(
          gestureRecognizer,
          shouldRecognizeSimultaneouslyWith: otherGestureRecognizer
        ) ?? true
      }

      return true
    }

    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
      if isBackNavigationRecognizer(gestureRecognizer, competingWith: otherGestureRecognizer) {
        return true
      }

      guard gestureRecognizer === contentPopGestureRecognizer else {
        return originalDelegate?.gestureRecognizer?(
          gestureRecognizer,
          shouldRequireFailureOf: otherGestureRecognizer
        ) ?? false
      }

      return false
    }

    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
      if isRightReplyGesture(gestureRecognizer),
        otherGestureRecognizer === contentPopGestureRecognizer
          || otherGestureRecognizer === backgroundBackPanGestureRecognizer
      {
        return false
      }

      guard gestureRecognizer === contentPopGestureRecognizer else {
        return originalDelegate?.gestureRecognizer?(
          gestureRecognizer,
          shouldBeRequiredToFailBy: otherGestureRecognizer
        ) ?? false
      }

      return false
    }

    private func isBackNavigationRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      competingWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
      (gestureRecognizer === contentPopGestureRecognizer
        || gestureRecognizer === backgroundBackPanGestureRecognizer)
        && isRightReplyGesture(otherGestureRecognizer)
    }

    private func isRightReplyGesture(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
      guard
        let recognizer = gestureRecognizer as? FriendsChatDirectionalPanGestureRecognizer,
        case .replyPayload(direction: .right) = recognizer.targetKind
      else {
        return false
      }

      return recognizer.direction == .right
    }

    private func startsInChatTableBackground(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
      guard let rootView = gestureRecognizer.view else {
        return false
      }
      let location = gestureRecognizer.location(in: rootView)
      guard let tableView = rootView.containingTableView(at: location) else {
        return false
      }
      let tableLocation = gestureRecognizer.location(in: tableView)
      guard tableView.bounds.contains(tableLocation) else {
        return false
      }
      return !isNavigationBackExcludedTarget(rootView.chatGestureTargetKind(at: location))
    }

    private func startsInNavigationBackExcludedTarget(
      _ gestureRecognizer: UIGestureRecognizer
    ) -> Bool {
      guard let rootView = gestureRecognizer.view else {
        return false
      }
      let location = gestureRecognizer.location(in: rootView)
      return isNavigationBackExcludedTarget(rootView.chatGestureTargetKind(at: location))
    }

    private func isNavigationBackExcludedTarget(
      _ targetKind: FriendsChatGestureTargetKind?
    ) -> Bool {
      switch targetKind {
      case .replyPayload(direction: .right), .attachmentPhotoCarousel:
        return true

      case .replyPayload(direction: .left):
        return false

      case .timestampRevealGutter, .none:
        return false
      }
    }
  }
}

struct FriendsThreadTimestampRevealGestureBridge: UIViewRepresentable {
  let isEnabled: Bool
  let onChanged: (FriendsChatReplyDragValue) -> Void
  let onEnded: (FriendsChatReplyDragValue) -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(onChanged: onChanged, onEnded: onEnded)
  }

  // swiftlint:disable:next explicit_acl type_contents_order
  func makeUIView(context _: Context) -> UIView {
    let view = UIView(frame: .zero)
    view.isUserInteractionEnabled = false
    return view
  }

  func updateUIView(_ uiView: UIView, context: Context) {
    context.coordinator.isEnabled = isEnabled
    context.coordinator.onChanged = onChanged
    context.coordinator.onEnded = onEnded

    DispatchQueue.main.async {
      context.coordinator.configure(from: uiView)
    }
  }

  // swiftlint:disable:next explicit_acl type_contents_order
  static func dismantleUIView(_: UIView, coordinator: Coordinator) {
    coordinator.restore()
  }

  final class Coordinator: NSObject, UIGestureRecognizerDelegate {
    var isEnabled = true
    var onChanged: (FriendsChatReplyDragValue) -> Void
    var onEnded: (FriendsChatReplyDragValue) -> Void
    private weak var tableView: UITableView?
    private var recognizer: UIPanGestureRecognizer?
    private var hasPassedMinimumDistance = false

    init(
      onChanged: @escaping (FriendsChatReplyDragValue) -> Void,
      onEnded: @escaping (FriendsChatReplyDragValue) -> Void
    ) {
      self.onChanged = onChanged
      self.onEnded = onEnded
    }

    func configure(from view: UIView) {
      guard isEnabled else {
        restore()
        return
      }
      guard let tableView = findChatTableView(from: view) else { return }
      guard tableView !== self.tableView else { return }

      restore()

      let recognizer = FriendsChatDirectionalPanGestureRecognizer(
        target: self,
        action: #selector(handlePan(_:))
      )
      recognizer.targetKind = .timestampRevealGutter
      recognizer.direction = .left
      recognizer.cancelsTouchesInView = false
      recognizer.delaysTouchesBegan = false
      recognizer.delaysTouchesEnded = false
      recognizer.delegate = self
      tableView.addGestureRecognizer(recognizer)

      self.tableView = tableView
      self.recognizer = recognizer
    }

    func restore() {
      if let recognizer, let tableView {
        tableView.removeGestureRecognizer(recognizer)
      }
      recognizer = nil
      tableView = nil
      hasPassedMinimumDistance = false
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
      guard let tableView else { return }
      let value = dragValue(from: recognizer, in: tableView)

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
          FriendsChatPanGestureResolver.hasPassedMinimumDistance(
            translation: value.translation,
            minimumDistance: FriendsChatTimestampRevealResolver.minimumDistance
          )
        else {
          return
        }
        hasPassedMinimumDistance = true
      }

      onChanged(value)
    }

    private func dragValue(
      from recognizer: UIPanGestureRecognizer,
      in tableView: UITableView
    ) -> FriendsChatReplyDragValue {
      let coordinateView = tableView.window ?? tableView
      let translation = recognizer.translation(in: coordinateView)
      let velocity = recognizer.velocity(in: coordinateView)
      let location = recognizer.location(in: coordinateView)
      let startLocation = CGPoint(
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
      guard isEnabled else {
        return false
      }
      guard let recognizer = gestureRecognizer as? UIPanGestureRecognizer, let tableView else {
        return false
      }

      let location = recognizer.location(in: tableView)
      guard tableView.bounds.contains(location) else {
        return false
      }
      guard tableView.indexPathForRow(at: location) == nil else {
        return false
      }

      let velocity = recognizer.velocity(in: tableView.window ?? tableView)
      return FriendsChatPanGestureResolver.hasDirectionalHorizontalIntent(
        velocity: CGSize(width: velocity.x, height: velocity.y),
        direction: .left
      )
    }

    func gestureRecognizer(
      _: UIGestureRecognizer,
      shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer
    ) -> Bool {
      true
    }

    private func findChatTableView(from view: UIView) -> UITableView? {
      let searchRoot = view.window ?? view.nearestRootView()
      let tableViews = searchRoot.descendantViews(ofType: UITableView.self)

      return tableViews.first(where: { candidate in
        guard let delegate = candidate.delegate else {
          return false
        }
        return String(reflecting: type(of: delegate)).contains("UIList")
      }) ?? tableViews.first
    }
  }
}

extension UIView {
  fileprivate func closestNavigationController() -> UINavigationController? {
    sequence(first: self as UIResponder?, next: { $0?.next })
      .first { $0 is UINavigationController } as? UINavigationController
  }

  fileprivate func containsChatGestureTarget(at point: CGPoint) -> Bool {
    chatGestureTargetKind(at: point) != nil
  }

  fileprivate func chatGestureTargetKind(at point: CGPoint) -> FriendsChatGestureTargetKind? {
    for subview in subviews.reversed() {
      guard !subview.isHidden, subview.alpha > 0.01 else { continue }

      let convertedPoint = subview.convert(point, from: self)
      if let targetView = subview as? FriendsChatGestureTargetView,
        targetView.bounds.contains(convertedPoint)
      {
        return targetView.kind
      }

      if subview.bounds.contains(convertedPoint) || !subview.clipsToBounds {
        if let kind = subview.chatGestureTargetKind(at: convertedPoint) {
          return kind
        }
      }
    }

    return nil
  }

  fileprivate func containingTableView(at point: CGPoint) -> UITableView? {
    for subview in subviews.reversed() {
      guard !subview.isHidden, subview.alpha > 0.01 else { continue }

      let convertedPoint = subview.convert(point, from: self)
      if let tableView = subview as? UITableView, tableView.bounds.contains(convertedPoint) {
        return tableView
      }

      if subview.bounds.contains(convertedPoint) || !subview.clipsToBounds {
        if let tableView = subview.containingTableView(at: convertedPoint) {
          return tableView
        }
      }
    }

    return nil
  }
}