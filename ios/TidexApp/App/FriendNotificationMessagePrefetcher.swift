// swiftlint:disable:next blanket_disable_command
// swiftlint:disable cyclomatic_complexity explicit_acl explicit_enum_raw_value explicit_top_level_acl
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable explicit_type_interface function_body_length let_var_whitespace line_length
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable multiline_arguments_brackets no_magic_numbers prefixed_toplevel_constant
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable required_deinit sorted_enum_cases type_name
import Foundation
import UIKit
import os.log

private let prefetchLogger = Logger(
  subsystem: "com.tidex.app",
  category: "FriendNotificationPrefetch"
)

@MainActor
protocol FriendNotificationMessagePrefetchContextProviding: AnyObject {
  var isImpersonating: Bool { get }
  func currentUserId() async -> String?
}

@MainActor
final class FriendNotificationMessagePrefetchContext:
  FriendNotificationMessagePrefetchContextProviding
{
  static let shared = FriendNotificationMessagePrefetchContext()

  var isImpersonating: Bool {
    ImpersonationManager.shared.isImpersonating
  }

  func currentUserId() async -> String? {
    if let currentUserId = AppCoordinator.shared.getCurrentUserId() {
      return currentUserId
    }

    let session = await AuthSessionManager.shared.getSessionIfAvailable(
      allowProactiveRefresh: false)
    return session?.normalizedUserId
  }
}

enum FriendNotificationMessagePrefetchSkipReason: String, Equatable {
  case missingThreadId
  case missingMessageId
  case missingUserId
  case impersonating
  case alreadyCached
  case deletedMessage
  case mismatchedThread
}

enum FriendNotificationMessagePrefetchOutcome: Equatable {
  case skipped(FriendNotificationMessagePrefetchSkipReason)
  case newData
  case failed

  var backgroundFetchResult: UIBackgroundFetchResult {
    switch self {
    case .newData:
      return .newData

    case .skipped:
      return .noData

    case .failed:
      return .failed
    }
  }
}

@MainActor
final class FriendNotificationMessagePrefetcher {
  static let shared = FriendNotificationMessagePrefetcher()

  private let context: FriendNotificationMessagePrefetchContextProviding
  private let repository: FriendsMessagesRepositoryProviding
  private let service: FriendsMessagingServiceProviding
  private let notificationCenter: NotificationCenter

  init(
    context: FriendNotificationMessagePrefetchContextProviding? = nil,
    repository: FriendsMessagesRepositoryProviding? = nil,
    service: FriendsMessagingServiceProviding? = nil,
    notificationCenter: NotificationCenter = .default
  ) {
    self.context = context ?? FriendNotificationMessagePrefetchContext.shared
    self.repository = repository ?? FriendsMessagesRepository.shared
    self.service = service ?? FriendsMessagingService.shared
    self.notificationCenter = notificationCenter
  }

  func prefetchBackgroundMessage(
    threadId: String?,
    messageId: String?
  ) async -> FriendNotificationMessagePrefetchOutcome {
    let startedAt = Date()
    let outcome = await prefetchMessage(threadId: threadId, messageId: messageId)
    logOutcome(outcome, threadId: threadId, messageId: messageId, startedAt: startedAt)
    return outcome
  }

  func prefetchMessage(
    threadId: String?,
    messageId: String?
  ) async -> FriendNotificationMessagePrefetchOutcome {
    guard
      let normalizedThreadId = threadId?.trimmingCharacters(in: .whitespacesAndNewlines),
      !normalizedThreadId.isEmpty
    else {
      return .skipped(.missingThreadId)
    }

    guard
      let normalizedMessageId = messageId?.trimmingCharacters(in: .whitespacesAndNewlines),
      !normalizedMessageId.isEmpty
    else {
      return .skipped(.missingMessageId)
    }

    if context.isImpersonating {
      return .skipped(.impersonating)
    }

    guard
      let viewerUserId = await context.currentUserId()?.trimmingCharacters(
        in: .whitespacesAndNewlines),
      !viewerUserId.isEmpty
    else {
      return .skipped(.missingUserId)
    }

    let cachedMessage = repository.getMessage(id: normalizedMessageId, viewerUserId: viewerUserId)
    let cachedThread = repository.getThread(id: normalizedThreadId, viewerUserId: viewerUserId)
    let shouldFetchThread =
      cachedThread == nil || cachedThread?.lastMessageId != normalizedMessageId
    let shouldRefreshCachedMessage = cachedMessage != nil && !shouldFetchThread

    do {
      if shouldFetchThread {
        let snapshot = try await service.fetchThreadSyncSnapshotV2(
          threadId: normalizedThreadId,
          messageLimit: 50
        )
        await repository.saveThread(snapshot.thread, for: viewerUserId)
        await repository.saveMessages(snapshot.messages, in: normalizedThreadId, for: viewerUserId)
        await repository.saveThreadState(snapshot.viewerState)
      }

      let fetchedMessage: FriendMessage
      if shouldRefreshCachedMessage {
        // Re-fetch existing messages so reaction/edit notifications can update cached payloads.
        fetchedMessage = try await service.fetchMessageSyncPayloadV2(messageId: normalizedMessageId)
      } else if let cachedMessage = repository.getMessage(
        id: normalizedMessageId, viewerUserId: viewerUserId)
      {
        fetchedMessage = cachedMessage
      } else {
        fetchedMessage = try await service.fetchMessageSyncPayloadV2(messageId: normalizedMessageId)
      }

      guard fetchedMessage.threadId == normalizedThreadId else {
        return .skipped(.mismatchedThread)
      }
      guard fetchedMessage.deletedAt == nil else {
        return .skipped(.deletedMessage)
      }

      await repository.saveMessages([fetchedMessage], in: normalizedThreadId, for: viewerUserId)
      notificationCenter.post(
        name: .friendsThreadDidUpdate,
        object: nil,
        userInfo: ["threadId": normalizedThreadId]
      )
      return .newData
    } catch {
      prefetchLogger.error(
        "Message prefetch failed for thread \(normalizedThreadId, privacy: .private) message \(normalizedMessageId, privacy: .private): \(error.localizedDescription)"
      )
      return .failed
    }
  }

  private func logOutcome(
    _ outcome: FriendNotificationMessagePrefetchOutcome,
    threadId: String?,
    messageId: String?,
    startedAt: Date
  ) {
    let durationMs = Int(Date().timeIntervalSince(startedAt) * 1_000)
    let safeThreadId = threadId ?? "<missing>"
    let safeMessageId = messageId ?? "<missing>"

    switch outcome {
    case .newData:
      prefetchLogger.info(
        "Silent prefetch stored message thread=\(safeThreadId, privacy: .private) message=\(safeMessageId, privacy: .private) duration_ms=\(durationMs)"
      )

    case .skipped(let reason):
      prefetchLogger.info(
        "Silent prefetch skipped reason=\(reason.rawValue, privacy: .public) thread=\(safeThreadId, privacy: .private) message=\(safeMessageId, privacy: .private) duration_ms=\(durationMs)"
      )

    case .failed:
      prefetchLogger.error(
        "Silent prefetch failed thread=\(safeThreadId, privacy: .private) message=\(safeMessageId, privacy: .private) duration_ms=\(durationMs)"
      )
    }
  }
}
