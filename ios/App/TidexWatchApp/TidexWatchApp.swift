import SwiftUI

@main
struct TidexWatchApp: App {
    @State private var dataStore = WatchDataStore.shared
    @State private var connectivity = WatchConnectivityManager.shared

    init() {
        // Activate Watch Connectivity on launch
        WatchConnectivityManager.shared.activateSession()
    }

    var body: some Scene {
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

    /// Fetch initial data when app launches
    /// Uses API first, falls back to iPhone if needed
    private func fetchInitialData() async {
        // Small delay to let connectivity activate
        try? await Task.sleep(for: .milliseconds(500))

        // Request refresh (will try API first, then iPhone)
        await MainActor.run {
            WatchConnectivityManager.shared.requestRefresh()
        }
    }
}
