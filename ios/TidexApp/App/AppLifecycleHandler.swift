import Foundation
import GoogleSignIn
import SwiftUI
import UIKit

@MainActor
final class AppLifecycleHandler {
    static let shared = AppLifecycleHandler()

    private init() {}

    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            AppearanceManager.shared.applyToWindows()
            PrivacyBlurManager.hide()
            AppCoordinator.shared.handleAppForeground()
            (UIApplication.shared.delegate as? AppDelegate)?.checkAndStartLiveActivityIfNeeded()
            (UIApplication.shared.delegate as? AppDelegate)?.endBackgroundTaskIfNeeded()
        case .inactive:
            PrivacyBlurManager.showIfNeeded()
        case .background:
            BiometricAuthService.shared.handleAppBackground()
            (UIApplication.shared.delegate as? AppDelegate)?.startBackgroundTask()
            PrivacyBlurManager.showIfNeeded()
        @unknown default:
            break
        }
    }

    func handleOpenURL(_ url: URL) {
        if GIDSignIn.sharedInstance.handle(url) {
            return
        }

        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let isAuthCallback = url.host == "login-callback" ||
            queryItems.contains(where: { $0.name == "code" || $0.name == "access_token" || $0.name == "refresh_token" })

        if url.scheme == "tidex" && isAuthCallback {
            Task { @MainActor in
                await handleSupabaseCallback(url)
            }
            return
        }

        if url.scheme == "tidex" {
            handleDeepLink(url)
            return
        }
    }

    func handleUserActivity(_ activity: NSUserActivity) {
        guard activity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = activity.webpageURL else {
            return
        }

        print("[AppLifecycleHandler] Received Universal Link: \(url)")
        handleDeepLink(url)
    }

    private func handleSupabaseCallback(_ url: URL) async {
        do {
            _ = try await supabase.auth.session(from: url)
            print("[AppLifecycleHandler] Auth callback handled: \(url)")
        } catch {
            print("[AppLifecycleHandler] Auth callback failed: \(error)")
        }
    }

    private func handleDeepLink(_ url: URL) {
        print("[AppLifecycleHandler] Received deep link: \(url)")
        Task { @MainActor in
            AppCoordinator.shared.handleDeepLink(url)
        }
    }
}
