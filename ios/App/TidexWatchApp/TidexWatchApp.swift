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
        }
    }
}
