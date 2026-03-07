import SwiftUI

@main
struct TidexApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  /// UIKit notification publishers for lifecycle events.
  /// Using UIKit notifications instead of @Environment(\.scenePhase) avoids a known
  /// SwiftUI bug where the view tree stops updating after scene phase transitions
  /// (e.g. returning from the system screenshot editor).
  private let didBecomeActive = NotificationCenter.default
    .publisher(for: UIApplication.didBecomeActiveNotification)
  private let willResignActive = NotificationCenter.default
    .publisher(for: UIApplication.willResignActiveNotification)
  private let didEnterBackground = NotificationCenter.default
    .publisher(for: UIApplication.didEnterBackgroundNotification)

  var body: some Scene {
    WindowGroup {
      RootView()
        .overlay {
          WindowAppearanceConfigurator()
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
        }
        .onOpenURL { url in
          AppLifecycleHandler.shared.handleOpenURL(url)
        }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
          AppLifecycleHandler.shared.handleUserActivity(activity)
        }
        .onReceive(didBecomeActive) { _ in
          AppLifecycleHandler.shared.handleDidBecomeActive()
        }
        .onReceive(willResignActive) { _ in
          AppLifecycleHandler.shared.handleWillResignActive()
        }
        .onReceive(didEnterBackground) { _ in
          AppLifecycleHandler.shared.handleDidEnterBackground()
        }
    }
  }
}
