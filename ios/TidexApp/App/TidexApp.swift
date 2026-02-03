import SwiftUI

@main
struct TidexApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .onOpenURL { url in
                    AppLifecycleHandler.shared.handleOpenURL(url)
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    AppLifecycleHandler.shared.handleUserActivity(activity)
                }
                .onChange(of: scenePhase) { _, newPhase in
                    AppLifecycleHandler.shared.handleScenePhase(newPhase)
                }
        }
    }
}
