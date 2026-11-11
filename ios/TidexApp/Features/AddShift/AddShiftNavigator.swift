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

/// Path value for the Add screen.
internal struct AddShiftRoute: Hashable {}

extension View {
  /// Pushes the Add screen as a value of `path`, the path of this tab's root `NavigationStack`,
  /// while the tab hosts it. Use this where a tap opens Add. Pushed through
  /// `navigationDestination(isPresented:)` instead, Add could keep SwiftUI's navigation update
  /// from settling under heavy CPU load, which froze the app.
  internal func addShiftRoute(on tab: MainTabView.Tab, path: Binding<[AddShiftRoute]>) -> some View {
    modifier(AddShiftRouteModifier(tab: tab, path: path))
  }

  /// Lets the Add screen be pushed onto a stack that keeps its own typed path, where only links
  /// open Add. Apply inside the tab's root `NavigationStack`. Pass nil where the view isn't a
  /// tab root. Pass `hidesTabBar` instead of adding another `.toolbar(_:for: .tabBar)` to the same
  /// root. Two of them on the same view conflict, and the chat hide stopped working that way.
  internal func addShiftDestination(in tab: MainTabView.Tab?, hidesTabBar: Bool = false) -> some View {
    modifier(AddShiftDestinationModifier(tab: tab, hidesTabBar: hidesTabBar))
  }
}

private struct AddShiftRouteModifier: ViewModifier {
  let tab: MainTabView.Tab
  @Binding var path: [AddShiftRoute]
  private let navigator: AddShiftNavigator = .shared

  func body(content: Content) -> some View {
    content
      .toolbar(navigator.hostTab == tab ? .hidden : .automatic, for: .tabBar)
      .navigationDestination(for: AddShiftRoute.self) { _ in
        HostedAddShiftView(tab: tab)
      }
      .onChange(of: navigator.hostTab == tab, initial: true) { _, hostsAdd in
        path = hostsAdd ? [AddShiftRoute()] : []
      }
      // Going back empties the path.
      .onChange(of: path.isEmpty) { _, isEmpty in
        if isEmpty, navigator.hostTab == tab {
          navigator.hostTab = nil
        }
      }
  }
}

private struct AddShiftDestinationModifier: ViewModifier {
  let tab: MainTabView.Tab?
  let hidesTabBar: Bool
  private let navigator: AddShiftNavigator = .shared

  func body(content: Content) -> some View {
    content
      // Hide the tab bar from the root, like Friends does for chats. Hiding it from the
      // pushed screen instead makes it pop back in only after the back transition ends.
      .toolbar(hidesTabBar || isPresented.wrappedValue ? .hidden : .automatic, for: .tabBar)
      .navigationDestination(isPresented: isPresented) {
        HostedAddShiftView(tab: tab)
      }
  }

  private var isPresented: Binding<Bool> {
    Binding(
      get: { tab != nil && navigator.hostTab == tab },
      set: { isPresented in
        if !isPresented, navigator.hostTab == tab {
          navigator.hostTab = nil
        }
      }
    )
  }
}

/// The Add screen in a tab's stack. Saving pops it.
private struct HostedAddShiftView: View {
  let tab: MainTabView.Tab?
  @Environment(AppCoordinator.self) private var coordinator

  var body: some View {
    AddShiftView { createdSingleDates in
      AddShiftNavigator.shared.hostTab = nil
      // On Schedule, highlight the new shifts once the screen pops back.
      if tab == .shifts, let createdSingleDates {
        coordinator.pendingDeepLink = .shifts(
          dates: createdSingleDates.sorted(), shiftIds: nil, action: .highlight)
      }
    }
  }
}
