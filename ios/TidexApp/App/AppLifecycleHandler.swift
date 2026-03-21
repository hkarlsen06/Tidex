import Foundation
import GoogleSignIn
import Intents
import UIKit
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "AppLifecycleHandler")

extension Notification.Name {
  static let tidexDidBecomeActive = Notification.Name("tidexDidBecomeActive")
}

@MainActor
final class AppLifecycleHandler {
  static let shared = AppLifecycleHandler()
  private static let liveActivityRecoveryDelay: UInt64 = 1_000_000_000  // 1 second
  private var liveActivityRecoveryTask: Task<Void, Never>?

  private init() {}

  // MARK: - Lifecycle Handlers (UIKit notification-driven)

  func handleDidBecomeActive() {
    AppearanceManager.shared.applyToWindows()
    PrivacyBlurManager.hide()
    liveActivityRecoveryTask?.cancel()
    liveActivityRecoveryTask = nil
    AppCoordinator.shared.handleAppForeground()
    NotificationCenter.default.post(name: .tidexDidBecomeActive, object: nil)
    Task { @MainActor [weak self] in
      await ClockSessionReconciler.shared.reconcileIfNeeded(referenceDate: Date())
      self?.runForegroundLiveActivityMaintenance()
      self?.scheduleForegroundLiveActivityRecovery()
    }
    // Force SwiftUI to re-evaluate its view tree. UIKit layout calls
    // (setNeedsLayout) don't restart SwiftUI's render loop, but sending
    // objectWillChange on the root ObservableObject does.
    AppCoordinator.shared.objectWillChange.send()
  }

  func handleWillResignActive() {
    liveActivityRecoveryTask?.cancel()
    liveActivityRecoveryTask = nil
    PrivacyBlurManager.showIfNeeded()
  }

  func handleDidEnterBackground() {
    liveActivityRecoveryTask?.cancel()
    liveActivityRecoveryTask = nil
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
    if handleCommunicationActivity(activity) {
      return
    }

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

  private func handleCommunicationActivity(_ activity: NSUserActivity) -> Bool {
    guard activity.activityType == NSStringFromClass(INSendMessageIntent.self) else {
      return false
    }

    let intent = activity.interaction?.intent as? INSendMessageIntent
    let threadId =
      normalizedNonEmpty(intent?.conversationIdentifier)
      ?? normalizedThreadId(from: activity.targetContentIdentifier)

    guard let threadId else {
      logger.error("Received communication activity without a thread identifier")
      return true
    }

    let senderUserId =
      normalizedNonEmpty(intent?.sender?.customIdentifier)
      ?? normalizedNonEmpty(intent?.sender?.contactIdentifier)
      ?? normalizedNonEmpty(intent?.sender?.personHandle?.value)

    logger.info("Resuming communication activity for thread \(threadId, privacy: .private)")

    Task { @MainActor in
      await NotificationService.shared.clearDeliveredFriendChatNotifications(for: threadId)
      AppCoordinator.shared.pendingDeepLink = .friendChat(
        threadId: threadId,
        messageId: nil,
        senderUserId: senderUserId,
        navigationRequestId: UUID()
      )
    }

    return true
  }

  private func normalizedThreadId(from targetContentIdentifier: String?) -> String? {
    guard let targetContentIdentifier = normalizedNonEmpty(targetContentIdentifier) else {
      return nil
    }

    if targetContentIdentifier.hasPrefix("friend-chat:") {
      return normalizedNonEmpty(
        String(targetContentIdentifier.dropFirst("friend-chat:".count))
      )
    }

    return nil
  }

  private func normalizedNonEmpty(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
      !value.isEmpty
    else {
      return nil
    }

    return value
  }
}
