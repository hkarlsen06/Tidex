import Foundation
import GoogleSignIn
import SwiftUI
import UIKit

@MainActor
final class AppLifecycleHandler {
    static let shared = AppLifecycleHandler()
    private static let loadingRecoveryDelay: UInt64 = 1_500_000_000 // 1.5 seconds
    private var loadingRecoveryTask: Task<Void, Never>?

    private init() {}

    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            AppearanceManager.shared.applyToWindows()
            // Blur hide is handled by didBecomeActiveNotification (see TidexApp.swift)
            // for synchronous timing, but do a defensive cleanup here too.
            PrivacyBlurManager.hide()
            scheduleLoadingRecoveryIfNeeded()
            BiometricAuthService.shared.handleAppForeground()
            AppCoordinator.shared.handleAppForeground()
            (UIApplication.shared.delegate as? AppDelegate)?.checkAndStartLiveActivityIfNeeded()
            (UIApplication.shared.delegate as? AppDelegate)?.endBackgroundTaskIfNeeded()
        case .inactive:
            loadingRecoveryTask?.cancel()
            loadingRecoveryTask = nil
            // Blur show is handled by willResignActiveNotification (see TidexApp.swift)
            // for synchronous timing before app switcher snapshot.
        case .background:
            loadingRecoveryTask?.cancel()
            loadingRecoveryTask = nil
            BiometricAuthService.shared.handleAppBackground()
            (UIApplication.shared.delegate as? AppDelegate)?.startBackgroundTask()
            // Defensive: ensure blur is shown when entering background.
            // Primary blur is handled by willResignActiveNotification but
            // some transitions may skip .inactive.
            PrivacyBlurManager.showIfNeeded()
        @unknown default:
            break
        }
    }

    private func scheduleLoadingRecoveryIfNeeded() {
        loadingRecoveryTask?.cancel()
        loadingRecoveryTask = nil

        guard AppCoordinator.shared.appState == .loading else { return }

        loadingRecoveryTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: Self.loadingRecoveryDelay)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            guard AppCoordinator.shared.appState == .loading else {
                self?.loadingRecoveryTask = nil
                return
            }

            await AppCoordinator.shared.checkSession()
            self?.loadingRecoveryTask = nil
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
