import UIKit
import SwiftUI
import GoogleSignIn

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        // Use this method to optionally configure and attach the UIWindow to the provided UIWindowScene.
        guard let windowScene = (scene as? UIWindowScene) else { return }

        window = UIWindow(windowScene: windowScene)

        // Set window background to match splash screen and dark theme
        // This prevents white flash during app startup
        let darkBackground = UIColor(red: 0.008, green: 0.032, blue: 0.090, alpha: 1.0)
        window?.backgroundColor = darkBackground

        // Use fully native SwiftUI app
        let rootView = RootView()
        let hostingController = UIHostingController(rootView: rootView)
        hostingController.view.backgroundColor = darkBackground

        window?.rootViewController = hostingController
        window?.makeKeyAndVisible()

        // Handle any URLs passed at launch (OAuth callbacks, deep links)
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

        // Refresh locale in case user changed language in iOS Settings
        Task { @MainActor in
            LocalizationManager.shared.refreshLocale()
        }

        // End background task if returning to foreground before expiration
        (UIApplication.shared.delegate as? AppDelegate)?.endBackgroundTaskIfNeeded()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Use this method to save data, release shared resources, and store scene-specific state.

        // Start a managed background task to give time to finish pending operations
        (UIApplication.shared.delegate as? AppDelegate)?.startBackgroundTask()
    }

    // MARK: - URL Handling

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        // Handle URLs opened while app is running
        guard let urlContext = URLContexts.first else { return }
        handleURL(urlContext.url)
    }

    private func handleURL(_ url: URL) {
        // Handle Google Sign-In callback
        if GIDSignIn.sharedInstance.handle(url) {
            return
        }

        // Handle Supabase auth callbacks (magic links, OAuth redirects)
        if url.scheme == "tidex" || url.host == "login-callback" {
            // The Supabase SDK will handle session exchange automatically
            // when the URL contains auth tokens
            Task { @MainActor in
                await handleSupabaseCallback(url)
            }
            return
        }

        // Handle deep links for app navigation
        handleDeepLink(url)
    }

    /// Handle Supabase OAuth callbacks
    private func handleSupabaseCallback(_ url: URL) async {
        // Supabase client automatically handles the callback URL
        // and exchanges the code for a session when auth state changes
        // The AppCoordinator will pick up the session via authStateChanges
        print("[SceneDelegate] Received auth callback: \(url)")
    }

    /// Handle deep links for navigation
    private func handleDeepLink(_ url: URL) {
        // Parse the URL path and navigate accordingly
        // For now, just log - can be expanded for specific deep link handling
        print("[SceneDelegate] Received deep link: \(url)")
    }

    // MARK: - User Activity (Universal Links)

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        handleUserActivity(userActivity)
    }

    private func handleUserActivity(_ userActivity: NSUserActivity) {
        // Handle Universal Links (e.g., tidex.no/reset-password)
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = userActivity.webpageURL else {
            return
        }

        print("[SceneDelegate] Received Universal Link: \(url)")

        // Parse the path and handle accordingly
        // For auth-related paths, the Supabase SDK handles automatically
        handleDeepLink(url)
    }
}
