import Foundation
import GoogleSignIn
import UIKit
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "AppLifecycleHandler")

@MainActor
final class AppLifecycleHandler {
  static let shared = AppLifecycleHandler()
  private static let loadingRecoveryDelay: UInt64 = 1_500_000_000  // 1.5 seconds
  private static let liveActivityRecoveryDelay: UInt64 = 1_000_000_000  // 1 second
  private var loadingRecoveryTask: Task<Void, Never>?
  private var liveActivityRecoveryTask: Task<Void, Never>?

  private init() {}

  // MARK: - Lifecycle Handlers (UIKit notification-driven)

  func handleDidBecomeActive() {
    AppearanceManager.shared.applyToWindows()
    PrivacyBlurManager.hide()
    scheduleLoadingRecoveryIfNeeded()
    liveActivityRecoveryTask?.cancel()
    liveActivityRecoveryTask = nil
    BiometricAuthService.shared.handleAppForeground()
    AppCoordinator.shared.handleAppForeground()
    Task { @MainActor [weak self] in
      await ClockSessionReconciler.shared.reconcileIfNeeded(referenceDate: Date())
      self?.runForegroundLiveActivityMaintenance()
      self?.scheduleForegroundLiveActivityRecovery()
    }
    // Force SwiftUI to re-evaluate its view tree. UIKit layout calls
    // (setNeedsLayout) don't restart SwiftUI's render loop, but sending
    // objectWillChange on the root ObservableObject does.
    AppCoordinator.shared.objectWillChange.send()

    // Diagnostic: log window state on next run loop to detect blank-screen conditions
    DispatchQueue.main.async {
      for scene in UIApplication.shared.connectedScenes {
        guard let windowScene = scene as? UIWindowScene else { continue }
        for (i, window) in windowScene.windows.enumerated() {
          let rootVC = window.rootViewController
          let rootView = rootVC?.view
          logger.info(
            "[didBecomeActive] window[\(i)] isKey=\(window.isKeyWindow) hidden=\(rootView?.isHidden ?? true) alpha=\(rootView?.alpha ?? 0) frame=\(String(describing: rootView?.frame)) subviews=\(rootView?.subviews.count ?? 0)"
          )
        }
      }
    }
  }

  func handleWillResignActive() {
    loadingRecoveryTask?.cancel()
    loadingRecoveryTask = nil
    liveActivityRecoveryTask?.cancel()
    liveActivityRecoveryTask = nil
    PrivacyBlurManager.showIfNeeded()
  }

  func handleDidEnterBackground() {
    loadingRecoveryTask?.cancel()
    loadingRecoveryTask = nil
    liveActivityRecoveryTask?.cancel()
    liveActivityRecoveryTask = nil
    BiometricAuthService.shared.handleAppBackground()
    ((UIApplication.shared.delegate as? AppDelegate) ?? AppDelegate.shared)?.startBackgroundTask()
    // Defensive: ensure blur is shown when entering background.
    PrivacyBlurManager.showIfNeeded()
  }

  private func runForegroundLiveActivityMaintenance() {
    guard let appDelegate = (UIApplication.shared.delegate as? AppDelegate) ?? AppDelegate.shared
    else { return }

    // Refresh the App Group snapshot from local storage before reconciling so
    // foreground maintenance does not depend on stale widget storage.
    if let userId = AppCoordinator.shared.getCurrentUserId() {
      NativeWidgetStorage.updateWidgetStorage(for: userId)
    } else {
      appDelegate.checkAndStartLiveActivityIfNeeded()
    }

    appDelegate.endBackgroundTaskIfNeeded()
  }

  private func scheduleForegroundLiveActivityRecovery() {
    liveActivityRecoveryTask?.cancel()
    liveActivityRecoveryTask = Task { @MainActor [weak self] in
      do {
        try await Task.sleep(nanoseconds: Self.liveActivityRecoveryDelay)
      } catch {
        return
      }

      guard !Task.isCancelled else { return }
      await ClockSessionReconciler.shared.reconcileIfNeeded(referenceDate: Date())
      self?.runForegroundLiveActivityMaintenance()
      self?.liveActivityRecoveryTask = nil
    }
  }

  // MARK: - Loading Recovery

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

      // Reset the auth update flag in case a previous check is stuck,
      // otherwise checkSession → checkTermsAndUpdateState silently returns.
      AppCoordinator.shared.resetAuthUpdateFlag()
      await AppCoordinator.shared.checkSession()
      self?.loadingRecoveryTask = nil
    }
  }

  // MARK: - URL Handling

  func handleOpenURL(_ url: URL) {
    if GIDSignIn.sharedInstance.handle(url) {
      return
    }

    let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    let isAuthCallback =
      url.host == "login-callback"
      || queryItems.contains(where: {
        $0.name == "code" || $0.name == "access_token" || $0.name == "refresh_token"
      })

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
      let url = activity.webpageURL
    else {
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
