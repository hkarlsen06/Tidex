import UIKit
import Capacitor

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        // Use this method to optionally configure and attach the UIWindow to the provided UIWindowScene.
        guard let windowScene = (scene as? UIWindowScene) else { return }

        window = UIWindow(windowScene: windowScene)

        // Set window background to match splash screen and dark theme
        // This prevents white flash between splash screen and WebView load
        let darkBackground = UIColor(red: 0.008, green: 0.032, blue: 0.090, alpha: 1.0)
        window?.backgroundColor = darkBackground

        let containerController = TidexContainerViewController()
        window?.rootViewController = containerController
        window?.makeKeyAndVisible()

        // Handle any URLs passed at launch
        if let urlContext = connectionOptions.urlContexts.first {
            handleURL(urlContext.url)
        }

        // Handle any user activities (Universal Links) passed at launch
        if let userActivity = connectionOptions.userActivities.first {
            handleUserActivity(userActivity)
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Called when the scene is being released by the system.
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Called when the scene has moved from an inactive state to an active state.
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // Called when the scene will move from an active state to an inactive state.
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // Called as part of the transition from the background to the active state.

        // End background task if returning to foreground before expiration
        (UIApplication.shared.delegate as? AppDelegate)?.endBackgroundTaskIfNeeded()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Use this method to save data, release shared resources, and store scene-specific state.

        // Start a managed background task to give Capacitor/plugins time to finish
        // This fixes "Background Task for Coalescing" warning by properly managing the task lifecycle
        (UIApplication.shared.delegate as? AppDelegate)?.startBackgroundTask()
    }

    // MARK: - URL Handling

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        // Handle URLs opened while app is running
        guard let urlContext = URLContexts.first else { return }
        handleURL(urlContext.url)
    }

    private func handleURL(_ url: URL) {
        // Forward to Capacitor's ApplicationDelegateProxy for plugin handling
        _ = ApplicationDelegateProxy.shared.application(
            UIApplication.shared,
            open: url,
            options: [:]
        )
    }

    // MARK: - User Activity (Universal Links)

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        handleUserActivity(userActivity)
    }

    private func handleUserActivity(_ userActivity: NSUserActivity) {
        // Forward to Capacitor's ApplicationDelegateProxy for plugin handling
        _ = ApplicationDelegateProxy.shared.application(
            UIApplication.shared,
            continue: userActivity,
            restorationHandler: { _ in }
        )
    }
}
