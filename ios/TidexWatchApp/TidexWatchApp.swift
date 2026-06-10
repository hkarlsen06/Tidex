import SwiftUI

@main
internal struct TidexWatchApp: App {
  private enum Constants {
    static let connectivityActivationDelayMilliseconds: Int = 500
  }

  @State private var dataStore: WatchDataStore = .shared
  @State private var connectivity: WatchConnectivityManager = .shared

  internal var body: some Scene {
    WindowGroup {
      ContentView()
        .environment(dataStore)
        .environment(connectivity)
        .task {
          // Fetch data on launch (API first, iPhone fallback)
          await fetchInitialData()
        }
    }
  }

  internal init() {
    // Activate Watch Connectivity on launch
    WatchConnectivityManager.shared.activateSession()
  }

  /// Fetch initial data when app launches
  /// Uses API first, falls back to iPhone if needed
  private func fetchInitialData() async {
    // Small delay to let connectivity activate
    try? await Task.sleep(for: .milliseconds(Constants.connectivityActivationDelayMilliseconds))

    // Request refresh (will try API first, then iPhone)
    await MainActor.run {
      WatchConnectivityManager.shared.requestRefresh()
    }
  }
}
