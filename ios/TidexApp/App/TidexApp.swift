import SwiftUI

@main
struct TidexApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    /// UIKit notification publishers for privacy blur.
    /// Using these instead of ScenePhase ensures the blur is applied/removed synchronously
    /// before the app switcher captures its screenshot.
    private let willResignActive = NotificationCenter.default
        .publisher(for: UIApplication.willResignActiveNotification)
    private let didBecomeActive = NotificationCenter.default
        .publisher(for: UIApplication.didBecomeActiveNotification)

    var body: some Scene {
        WindowGroup {
            RootView()
                .onOpenURL { url in
                    AppLifecycleHandler.shared.handleOpenURL(url)
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    AppLifecycleHandler.shared.handleUserActivity(activity)
                }
                .task(id: scenePhase) {
                    AppLifecycleHandler.shared.handleScenePhase(scenePhase)
                }
                .onReceive(willResignActive) { _ in
                    PrivacyBlurManager.showIfNeeded()
                }
                .onReceive(didBecomeActive) { _ in
                    PrivacyBlurManager.hide()
                }
        }
    }
}
