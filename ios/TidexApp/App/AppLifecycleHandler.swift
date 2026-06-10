// swiftlint:disable:next blanket_disable_command
// swiftlint:disable anonymous_argument_in_multiline_closure conditional_returns_on_newline explicit_acl
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable explicit_top_level_acl explicit_type_interface file_types_order no_direct_print no_empty_block
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable no_magic_numbers prefixed_toplevel_constant required_deinit
import Foundation
import GoogleSignIn
import Intents
import os.log
import UIKit

private let logger = Logger(subsystem: "com.tidex.app", category: "AppLifecycleHandler")

extension Notification.Name {
  static let tidexDidBecomeActive = Notification.Name("tidexDidBecomeActive")
  static let tidexPasswordRecoveryRequested = Notification.Name("tidexPasswordRecoveryRequested")
  static let tidexNavigateToLoginRequested = Notification.Name("tidexNavigateToLoginRequested")
}

@MainActor
final class AppLifecycleHandler {
  static let shared = AppLifecycleHandler()
  private static let liveActivityRecoveryDelay: UInt64 = 1_000_000_000  // 1 second
  private static let foregroundMaintenanceDelay: UInt64 = 350_000_000  // 0.35 seconds
  private var hasHandledInitialActivation = false
  private var foregroundMaintenanceTask: Task<Void, Never>?
  private var liveActivityRecoveryTask: Task<Void, Never>?

  private init() {}

  // MARK: - Lifecycle Handlers (UIKit notification-driven)

  func handleDidBecomeActive() {
    let isInitialActivation = !hasHandledInitialActivation
    hasHandledInitialActivation = true

    AppearanceManager.shared.applyToWindows()
    PrivacyBlurManager.hide()
    liveActivityRecoveryTask?.cancel()
    liveActivityRecoveryTask = nil
    foregroundMaintenanceTask?.cancel()
    NotificationCenter.default.post(name: .tidexDidBecomeActive, object: nil)

    if isInitialActivation {
      // Cold launch already runs the app-launch sync and live activity pass.
      // Avoid stacking foreground storage work onto first activation/render.
      return
    }

    AppCoordinator.shared.handleAppForeground()
    foregroundMaintenanceTask = Task { @MainActor [weak self] in
      guard let self else { return }
      do {
        try await Task.sleep(nanoseconds: Self.foregroundMaintenanceDelay)
      } catch {
        return
      }
      guard !Task.isCancelled else { return }
      await ClockSessionReconciler.shared.reconcileIfNeeded(referenceDate: Date())
      guard !Task.isCancelled else { return }
      await runForegroundLiveActivityMaintenance()
      guard !Task.isCancelled else { return }
      scheduleForegroundLiveActivityRecovery()
      foregroundMaintenanceTask = nil
    }
    // Force SwiftUI to re-evaluate its view tree. UIKit layout calls
    // (setNeedsLayout) don't restart SwiftUI's render loop, but sending
    // objectWillChange on the root ObservableObject does.
    AppCoordinator.shared.objectWillChange.send()
  }

  func handleWillResignActive() {
    foregroundMaintenanceTask?.cancel()
    foregroundMaintenanceTask = nil
    liveActivityRecoveryTask?.cancel()
    liveActivityRecoveryTask = nil
    if SensitiveContentPresentationState.shared.isSensitiveContentVisible {
      PrivacyBlurManager.showIfNeeded()
    }
  }

  func handleDidEnterBackground() {
    foregroundMaintenanceTask?.cancel()
    foregroundMaintenanceTask = nil
    liveActivityRecoveryTask?.cancel()
    liveActivityRecoveryTask = nil
    ((UIApplication.shared.delegate as? AppDelegate) ?? AppDelegate.shared)?.startBackgroundTask()
    // Defensive: ensure blur is shown when entering background.
    if SensitiveContentPresentationState.shared.isSensitiveContentVisible {
      PrivacyBlurManager.showIfNeeded()
    }
  }

  private func runForegroundLiveActivityMaintenance() async {
    guard let appDelegate = (UIApplication.shared.delegate as? AppDelegate) ?? AppDelegate.shared
    else { return }

    // Refresh the App Group snapshot from local storage before reconciling so
    // foreground maintenance does not depend on stale widget storage.
    if let userId = AppCoordinator.shared.getCurrentUserId() {
      await NativeWidgetStorage.refreshWidgetStorageNow(for: userId)
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
      await self?.runForegroundLiveActivityMaintenance()
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

    if url.scheme == "tidex", isAuthCallback {
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
    let callbackParameters = authCallbackParameters(from: url)
    do {
      _ = try await supabase.auth.session(from: url)
      print("[AppLifecycleHandler] Auth callback handled: \(url)")
      if callbackParameters["type"] == "recovery" {
        NotificationCenter.default.post(name: .tidexPasswordRecoveryRequested, object: nil)
      }
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
        typingUserId: nil,
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

  private func authCallbackParameters(from url: URL) -> [String: String] {
    var parameters: [String: String] = [:]

    if let fragment = url.fragment {
      parameters.merge(parseQueryString(fragment)) { _, new in new }
    }

    if let query = url.query {
      parameters.merge(parseQueryString(query)) { _, new in new }
    }

    return parameters
  }

  private func parseQueryString(_ queryString: String) -> [String: String] {
    var parameters: [String: String] = [:]

    for pair in queryString.split(separator: "&") {
      let parts = pair.split(separator: "=", maxSplits: 1)
      guard parts.count == 2 else { continue }

      let key = String(parts[0])
      let value = String(parts[1]).removingPercentEncoding ?? String(parts[1])
      parameters[key] = value
    }

    return parameters
  }
}
