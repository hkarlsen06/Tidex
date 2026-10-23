// swiftlint:disable:next blanket_disable_command
// swiftlint:disable anonymous_argument_in_multiline_closure conditional_returns_on_newline explicit_acl
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable explicit_top_level_acl explicit_type_interface file_types_order no_direct_print no_empty_block
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable no_magic_numbers prefixed_toplevel_constant required_deinit
import Foundation
import Intents
import UIKit
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "AppLifecycleHandler")

extension Notification.Name {
  static let tidexDidBecomeActive = Notification.Name("tidexDidBecomeActive")
  static let tidexNavigateToLoginRequested = Notification.Name("tidexNavigateToLoginRequested")
}

@MainActor
final class AppLifecycleHandler {
  static let shared = AppLifecycleHandler()
  private var hasHandledInitialActivation = false
  private var clockSessionReconciliationTask: Task<Void, Never>?
  private var appActivityTask: Task<Void, Never>?

  private init() {}

  // MARK: - Lifecycle Handlers (UIKit notification-driven)

  func handleDidBecomeActive() {
    let isInitialActivation = !hasHandledInitialActivation
    hasHandledInitialActivation = true

    AppearanceManager.shared.applyToWindows()
    PrivacyBlurManager.hide()
    ((UIApplication.shared.delegate as? AppDelegate) ?? AppDelegate.shared)?
      .endBackgroundTaskIfNeeded()
    clockSessionReconciliationTask?.cancel()
    NotificationCenter.default.post(name: .tidexDidBecomeActive, object: nil)

    if !isInitialActivation {
      AppCoordinator.shared.handleAppForeground()
    }
    recordAppActivity()

    clockSessionReconciliationTask = Task { @MainActor [weak self] in
      await ClockSessionReconciler.shared.reconcileIfNeeded(referenceDate: Date())
      self?.clockSessionReconciliationTask = nil
    }
  }

  func handleWillResignActive() {
    AppCoordinator.shared.cancelForegroundWork()
    clockSessionReconciliationTask?.cancel()
    clockSessionReconciliationTask = nil
    if SensitiveContentPresentationState.shared.isSensitiveContentVisible {
      PrivacyBlurManager.showIfNeeded()
    }
  }

  /// Tells the server the user opened the app, for the admin "Last active" time, app info and charts.
  /// Waits briefly first because iOS 26 and later can post didBecomeActive while the device locks.
  private func recordAppActivity() {
    appActivityTask?.cancel()
    appActivityTask = Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(300))
      guard !Task.isCancelled, UIApplication.shared.applicationState == .active,
        await AuthSessionManager.shared.getSessionIfAvailable() != nil
      else { return }
      await AppActivityReporter.record()
    }
  }

  func handleDidEnterBackground() {
    AppCoordinator.shared.cancelForegroundWork()
    clockSessionReconciliationTask?.cancel()
    clockSessionReconciliationTask = nil
    ((UIApplication.shared.delegate as? AppDelegate) ?? AppDelegate.shared)?.startBackgroundTask()
    // Defensive: ensure blur is shown when entering background.
    if SensitiveContentPresentationState.shared.isSensitiveContentVisible {
      PrivacyBlurManager.showIfNeeded()
    }
  }

  // MARK: - URL Handling

  func handleOpenURL(_ url: URL) {
    // Clerk's web sign-in (Google) returns to its own ASWebAuthenticationSession, so only the
    // app's own tidex:// links arrive here.
    if url.scheme == "tidex" {
      handleDeepLink(url)
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
      AppCoordinator.shared.pendingDeepLink = .friendChat(
        threadId: threadId,
        messageId: nil,
        senderUserId: senderUserId,
        typingUserId: nil,
        navigationRequestId: UUID()
      )
      await NotificationService.shared.clearDeliveredFriendChatNotifications(for: threadId)
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
