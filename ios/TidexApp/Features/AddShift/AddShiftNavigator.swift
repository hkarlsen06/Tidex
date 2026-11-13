import Observation
import SwiftUI
import UIKit

/// Tracks which tab's navigation stack shows the Add screen.
/// Only one tab shows it at a time, so there is a single draft on screen.
@MainActor
@Observable
internal final class AddShiftNavigator {
  internal static let shared: AddShiftNavigator = .init()

  /// The tab whose stack has the Add screen pushed, if any.
  internal var hostTab: MainTabView.Tab?

  /// Set by a save. `MainTabView` switches to Schedule, which shares Add's month and highlights
  /// the new shifts, and closes Add in the same update, whichever tab Add was opened on.
  internal var isClosingOnSchedule = false

  @ObservationIgnored private var isPushingWithoutAnimation = false

  private init() {
    // Singleton.
  }

  /// Pushes Add onto `tab` with no slide. The push ignores `Transaction.disablesAnimations`,
  /// so UIKit animations stay off until Add appears, or for a second if it never does.
  internal func presentWithoutAnimation(on tab: MainTabView.Tab) {
    isPushingWithoutAnimation = true
    UIView.setAnimationsEnabled(false)
    hostTab = tab
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
      self?.restoreAnimations()
    }
  }

  /// Called when Add appears. The push has started by then.
  internal func addDidAppear() {
    DispatchQueue.main.async { [weak self] in
      self?.restoreAnimations()
    }
  }

  private func restoreAnimations() {
    guard isPushingWithoutAnimation else { return }
    isPushingWithoutAnimation = false
    UIView.setAnimationsEnabled(true)
  }
}

/// Path value for the Add screen on stacks whose path has no route type of its own.
internal struct AddShiftRoute: Hashable {}

/// A route type that can stand for the Add screen in a typed navigation path.
internal protocol AddShiftPathElement: Hashable {
  static var addShift: Self { get }
}

extension AddShiftRoute: AddShiftPathElement {
  internal static let addShift: AddShiftRoute = .init()
}

/// A navigation path the Add screen can be pushed onto and popped from.
internal protocol AddShiftStackPath: Equatable {
  mutating func pushAddShift()
  mutating func removeLast(_ count: Int)
}

extension Array: AddShiftStackPath where Element: AddShiftPathElement {
  internal mutating func pushAddShift() { append(.addShift) }
}

extension NavigationPath: AddShiftStackPath {
  internal mutating func pushAddShift() { append(AddShiftRoute.addShift) }
}

extension View {
  /// Pushes the Add screen onto `path`, the path of this tab's root `NavigationStack`, while
  /// `tab` hosts it, and stops hosting when the user goes back. The caller registers
  /// `AddShiftScreen` for the pushed value with `navigationDestination(for:)`. Pass nil where
  /// the view isn't a tab root. Pass `hidesTabBar` instead of adding another
  /// `.toolbar(_:for: .tabBar)` to the same root. Two of them on the same view conflict.
  /// Pushed through `navigationDestination(isPresented:)` instead, a screen could keep
  /// SwiftUI's navigation update from settling under heavy CPU load, which froze the app.
  internal func addShiftRoute<Path: AddShiftStackPath>(
    on tab: MainTabView.Tab?, path: Binding<Path>, hidesTabBar: Bool = false
  ) -> some View {
    modifier(AddShiftRouteModifier(tab: tab, hidesTabBar: hidesTabBar, path: path))
  }
}

private struct AddShiftRouteModifier<Path: AddShiftStackPath>: ViewModifier {
  let tab: MainTabView.Tab?
  let hidesTabBar: Bool
  @Binding var path: Path
  /// The path this modifier produced by pushing Add, while this stack shows Add. The Add screen
  /// pushes nothing of its own, so any other path means Add was popped or replaced.
  @State private var pathWithAddShift: Path?
  private let navigator: AddShiftNavigator = .shared

  private var hostsAddShift: Bool { tab != nil && navigator.hostTab == tab }

  func body(content: Content) -> some View {
    content
      // Hide the tab bar from the root, like Friends does for chats. Hiding it from the
      // pushed screen instead makes it pop back in only after the back transition ends.
      .toolbar(hidesTabBar || hostsAddShift ? .hidden : .automatic, for: .tabBar)
      .onChange(of: hostsAddShift, initial: true) { _, hostsAddShift in
        if hostsAddShift, pathWithAddShift == nil {
          path.pushAddShift()
          pathWithAddShift = path
        } else if !hostsAddShift, let pushed = pathWithAddShift {
          pathWithAddShift = nil
          if path == pushed {
            path.removeLast(1)
          }
        }
      }
      // Going back, or a link that replaces the path, ends hosting.
      .onChange(of: path) { _, newPath in
        guard let pushed = pathWithAddShift, newPath != pushed else { return }
        pathWithAddShift = nil
        if navigator.hostTab == tab {
          navigator.hostTab = nil
        }
      }
  }
}

/// The Add screen in a tab's stack. Saving closes it on Schedule.
internal struct AddShiftScreen: View {
  var body: some View {
    AddShiftView {
      AddShiftNavigator.shared.isClosingOnSchedule = true
    }
  }
}
