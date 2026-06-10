import SwiftUI

/// Main content view for the Watch app
/// Displays shift list when data is available, otherwise shows empty state
internal struct ContentView: View {
  @Environment(WatchDataStore.self) private var store: WatchDataStore

  internal var body: some View {
    ShiftListView()
  }
}

#Preview {
  ContentView()
    .environment(WatchDataStore.shared)
    .environment(WatchConnectivityManager.shared)
}
