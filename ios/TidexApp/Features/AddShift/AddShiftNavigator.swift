import Observation
import SwiftUI

/// Tracks which tab's navigation stack shows the Add screen.
/// Only one tab shows it at a time, so there is a single draft on screen.
@MainActor
@Observable
internal final class AddShiftNavigator {
  internal static let shared: AddShiftNavigator = .init()

  /// The tab whose stack has the Add screen pushed, if any.
  internal var hostTab: MainTabView.Tab?

  private init() {
    // Singleton.
  }
}

extension View {
  /// Lets the Add screen be pushed onto this tab's navigation stack.
  /// Apply inside the tab's root `NavigationStack`. Pass nil where the view isn't a tab root.
  internal func addShiftDestination(in tab: MainTabView.Tab?) -> some View {
    modifier(AddShiftDestinationModifier(tab: tab))
  }
}

private struct AddShiftDestinationModifier: ViewModifier {
  let tab: MainTabView.Tab?
  @Environment(AppCoordinator.self) private var coordinator
  private let navigator: AddShiftNavigator = .shared

  func body(content: Content) -> some View {
    content
      // Hide the tab bar from the root, like Friends does for chats. Hiding it from the
      // pushed screen instead makes it pop back in only after the back transition ends.
      .toolbar(isPresented.wrappedValue ? .hidden : .automatic, for: .tabBar)
      .navigationDestination(isPresented: isPresented) {
        AddShiftView { createdSingleDates in
          navigator.hostTab = nil
          // On Schedule, highlight the new shifts once the screen pops back.
          if tab == .shifts, let createdSingleDates {
            coordinator.pendingDeepLink = .shifts(
              dates: createdSingleDates.sorted(), shiftIds: nil, action: .highlight)
          }
        }
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
