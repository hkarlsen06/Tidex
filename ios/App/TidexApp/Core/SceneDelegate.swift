import UIKit
import SwiftUI
import GoogleSignIn

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    /// Privacy blur view shown when app enters background (for app switcher screenshot)
    private var privacyBlurView: UIVisualEffectView?

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

        // Apply cached theme to window AND hosting controller (UIKit level for reliable system appearance following)
        // Using static method to avoid MainActor isolation issues at startup
        // Both window and hostingController need the style set for SwiftUI to properly pick it up
        let cachedStyle = AppearanceManager.cachedUserInterfaceStyle()
        window?.overrideUserInterfaceStyle = cachedStyle
        hostingController.overrideUserInterfaceStyle = cachedStyle

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
        // Re-apply theme to ensure it's correctly set after view hierarchy is fully loaded
        Task { @MainActor in
            AppearanceManager.shared.applyToWindows()
        }

        // Remove privacy blur when becoming active
        hidePrivacyBlur()
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // Called when the scene will move from an active state to an inactive state.
        // Show privacy blur for app switcher screenshot (only if biometric lock is enabled)
        showPrivacyBlur()
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

        // Note: Biometric unlock is handled by AppLockView.task, not here
        // This avoids race conditions with the privacy blur

        // Check for ongoing shifts and start Live Activity if needed
        // This ensures the Live Activity starts even if BGTask didn't fire
        (UIApplication.shared.delegate as? AppDelegate)?.checkAndStartLiveActivityIfNeeded()

        // End background task if returning to foreground before expiration
        (UIApplication.shared.delegate as? AppDelegate)?.endBackgroundTaskIfNeeded()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Use this method to save data, release shared resources, and store scene-specific state.

        // Lock app if biometric lock is enabled
        Task { @MainActor in
            BiometricAuthService.shared.handleAppBackground()
        }

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

    // MARK: - Privacy Blur

    /// Show blur overlay to hide content in app switcher (only if biometric lock is enabled)
    private func showPrivacyBlur() {
        // Only blur if biometric lock is enabled and not currently authenticating
        guard BiometricAuthService.isEnabledStatic else { return }
        guard !BiometricAuthService.isCurrentlyAuthenticating else { return }
        guard privacyBlurView == nil, let window = window else { return }

        let blurEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        let blurView = UIVisualEffectView(effect: blurEffect)
        blurView.frame = window.bounds
        blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        blurView.tag = 999 // Tag for identification

        // Add navy tint overlay to match Tidex brand color
        let navyTint = UIView()
        navyTint.backgroundColor = UIColor(red: 0.008, green: 0.032, blue: 0.090, alpha: 0.6)
        navyTint.frame = blurView.bounds
        navyTint.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        blurView.contentView.addSubview(navyTint)

        window.addSubview(blurView)
        privacyBlurView = blurView
    }

    /// Remove privacy blur when app becomes active
    private func hidePrivacyBlur() {
        privacyBlurView?.removeFromSuperview()
        privacyBlurView = nil
    }

}
