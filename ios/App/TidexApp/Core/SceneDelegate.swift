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

        // Trigger sync on foreground (interval-guarded by SyncCoordinator)
        Task { @MainActor in
            AppCoordinator.shared.handleAppForeground()
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

        // Check if this is an auth callback (contains code/token in query or is login-callback)
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let isAuthCallback = url.host == "login-callback" ||
            queryItems.contains(where: { $0.name == "code" || $0.name == "access_token" || $0.name == "refresh_token" })

        if url.scheme == "tidex" && isAuthCallback {
            // Handle Supabase auth callbacks (magic links, OAuth redirects)
            Task { @MainActor in
                await handleSupabaseCallback(url)
            }
            return
        }

        // Handle deep links for app navigation (tidex://sharing, tidex://shifts, etc.)
        if url.scheme == "tidex" {
            handleDeepLink(url)
            return
        }
    }

    /// Handle Supabase OAuth callbacks
    private func handleSupabaseCallback(_ url: URL) async {
        do {
            _ = try await supabase.auth.session(from: url)
            print("[SceneDelegate] Auth callback handled: \(url)")
        } catch {
            print("[SceneDelegate] Auth callback failed: \(error)")
        }
    }

    /// Handle deep links for navigation
    /// Delegates to AppCoordinator which stores pendingDeepLink for views to consume
    private func handleDeepLink(_ url: URL) {
        print("[SceneDelegate] Received deep link: \(url)")
        Task { @MainActor in
            AppCoordinator.shared.handleDeepLink(url)
        }
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
