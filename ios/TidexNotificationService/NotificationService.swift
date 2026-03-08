import Foundation
import Intents
import UserNotifications
import os

private let logger = Logger(subsystem: "no.tidex.app", category: "NotificationServiceExtension")

final class NotificationService: UNNotificationServiceExtension {
  private var contentHandler: ((UNNotificationContent) -> Void)?
  private var bestAttemptContent: UNMutableNotificationContent?
  private var processingTask: Task<Void, Never>?

  override func didReceive(
    _ request: UNNotificationRequest,
    withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
  ) {
    self.contentHandler = contentHandler

    guard let bestAttemptContent = request.content.mutableCopy() as? UNMutableNotificationContent
    else {
      contentHandler(request.content)
      return
    }

    self.bestAttemptContent = bestAttemptContent
    processingTask?.cancel()
    processingTask = Task { [weak self] in
      guard let self else { return }
      let updatedContent = await enrichedContent(from: request, content: bestAttemptContent)
      guard !Task.isCancelled else { return }
      contentHandler(updatedContent)
    }
  }

  override func serviceExtensionTimeWillExpire() {
    processingTask?.cancel()
    processingTask = nil

    if let contentHandler, let bestAttemptContent {
      contentHandler(bestAttemptContent)
    }
  }

  private func enrichedContent(
    from request: UNNotificationRequest,
    content: UNMutableNotificationContent
  ) async -> UNNotificationContent {
    guard
      let payload = ThreadMessageNotificationPayload(
        userInfo: request.content.userInfo,
        fallbackSenderDisplayName: request.content.title
      )
    else {
      return content
    }

    content.threadIdentifier = payload.threadId

    let senderImage = await fetchSenderImage(from: payload.senderAvatarUrl)
    let sender = INPerson(
      personHandle: INPersonHandle(value: payload.senderUserId, type: .unknown),
      nameComponents: nil,
      displayName: payload.senderDisplayName,
      image: senderImage,
      contactIdentifier: payload.senderUserId,
      customIdentifier: payload.senderUserId
    )

    let intent = INSendMessageIntent(
      recipients: nil,
      outgoingMessageType: .outgoingMessageText,
      content: content.body,
      speakableGroupName: nil,
      conversationIdentifier: payload.threadId,
      serviceName: "Tidex",
      sender: sender,
      attachments: nil
    )
    intent.setImage(senderImage, forParameterNamed: \.sender)

    let interaction = INInteraction(intent: intent, response: nil)
    interaction.direction = .incoming

    do {
      try await donate(interaction)
      return try content.updating(from: intent)
    } catch {
      logger.error(
        "Failed to enrich communication notification: \(error.localizedDescription, privacy: .public)"
      )
      return content
    }
  }

  private func fetchSenderImage(from url: URL?) async -> INImage? {
    guard let url else { return nil }

    do {
      let config = URLSessionConfiguration.ephemeral
      config.timeoutIntervalForRequest = 10
      config.timeoutIntervalForResource = 15
      let session = URLSession(configuration: config)
      defer { session.finishTasksAndInvalidate() }

      let (data, response) = try await session.data(from: url)
      guard let httpResponse = response as? HTTPURLResponse,
        (200..<300).contains(httpResponse.statusCode)
      else {
        return nil
      }
      guard !data.isEmpty else { return nil }
      return INImage(imageData: data)
    } catch {
      logger.error(
        "Failed to download sender avatar: \(error.localizedDescription, privacy: .public)")
      return nil
    }
  }

  private func donate(_ interaction: INInteraction) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      interaction.donate { error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume()
        }
      }
    }
  }
}

private struct ThreadMessageNotificationPayload {
  let threadId: String
  let senderUserId: String
  let senderDisplayName: String
  let senderAvatarUrl: URL?

  init?(userInfo: [AnyHashable: Any], fallbackSenderDisplayName: String) {
    guard let type = userInfo["type"] as? String, type == "thread_message" else { return nil }
    guard let threadId = userInfo["thread_id"] as? String, !threadId.isEmpty else { return nil }
    guard let senderUserId = userInfo["sender_user_id"] as? String, !senderUserId.isEmpty else {
      return nil
    }

    self.threadId = threadId
    self.senderUserId = senderUserId
    self.senderDisplayName =
      (userInfo["sender_name"] as? String)?.nonEmpty
      ?? fallbackSenderDisplayName.nonEmpty
      ?? "Tidex"

    if let avatarURLString = userInfo["sender_avatar_url"] as? String,
      let avatarUrl = URL(string: avatarURLString),
      !avatarURLString.isEmpty
    {
      self.senderAvatarUrl = avatarUrl
    } else {
      self.senderAvatarUrl = nil
    }
  }
}

extension String {
  fileprivate var nonEmpty: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
