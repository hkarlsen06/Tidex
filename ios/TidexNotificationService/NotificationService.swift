import Foundation
import Intents
import UserNotifications
import os

private let logger = Logger(subsystem: "no.tidex.app", category: "NotificationServiceExtension")

private enum SenderAvatarLoader {
  static let inMemoryCache = NSCache<NSURL, INImage>()
  static let urlCache = URLCache(
    memoryCapacity: 4 * 1024 * 1024,
    diskCapacity: 20 * 1024 * 1024,
    diskPath: "TidexNotificationAvatarCache"
  )

  static func cachedImage(for request: URLRequest, url: URL) -> INImage? {
    if let image = inMemoryCache.object(forKey: url as NSURL) {
      logger.debug(
        "Sender avatar cache hit (memory) for \(url.absoluteString, privacy: .private(mask: .hash))"
      )
      return image
    }

    guard let response = urlCache.cachedResponse(for: request) else {
      logger.debug(
        "Sender avatar cache miss for \(url.absoluteString, privacy: .private(mask: .hash))")
      return nil
    }

    logger.debug(
      "Sender avatar cache hit (disk) for \(url.absoluteString, privacy: .private(mask: .hash))")
    return makeImage(from: response.data, url: url)
  }

  private static func makeImage(from data: Data, url: URL) -> INImage? {
    guard !data.isEmpty else { return nil }
    let image = INImage(imageData: data)
    inMemoryCache.setObject(image, forKey: url as NSURL)
    return image
  }
}

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
    let startedAt = Date()

    guard
      let payload = CommunicationNotificationPayload(
        userInfo: request.content.userInfo,
        fallbackSenderDisplayName: request.content.title
      )
    else {
      return content
    }

    logger.debug("Enriching notification for type \(payload.type, privacy: .public)")
    content.threadIdentifier = payload.threadId
    if #available(iOS 15.0, *) {
      content.targetContentIdentifier = payload.targetContentIdentifier
    }

    let senderImage = fetchSenderImage(from: payload.senderAvatarUrl)
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
      conversationIdentifier: payload.conversationIdentifier,
      serviceName: "Tidex",
      sender: sender,
      attachments: nil
    )
    intent.setImage(senderImage, forParameterNamed: \.sender)

    let interaction = INInteraction(intent: intent, response: nil)
    interaction.direction = .incoming

    do {
      try await donate(interaction)
      let updatedContent = try content.updating(from: intent)
      guard
        let mutableUpdatedContent = updatedContent.mutableCopy() as? UNMutableNotificationContent
      else {
        return updatedContent
      }

      mutableUpdatedContent.threadIdentifier = payload.threadId

      if #available(iOS 15.0, *) {
        mutableUpdatedContent.targetContentIdentifier = payload.targetContentIdentifier
      }

      logger.debug(
        "Notification enrichment completed in \(Self.elapsedMilliseconds(since: startedAt), privacy: .public) ms"
      )
      return mutableUpdatedContent
    } catch {
      logger.error(
        "Failed to enrich communication notification: \(error.localizedDescription, privacy: .public)"
      )
      return content
    }
  }

  private func fetchSenderImage(from url: URL?) -> INImage? {
    guard let url else { return nil }

    let request = URLRequest(
      url: url,
      cachePolicy: .returnCacheDataDontLoad,
      timeoutInterval: 3
    )

    return SenderAvatarLoader.cachedImage(for: request, url: url)
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

  private static func elapsedMilliseconds(since startedAt: Date) -> Int {
    Int(Date().timeIntervalSince(startedAt) * 1000)
  }
}

private struct CommunicationNotificationPayload {
  let type: String
  let conversationIdentifier: String
  let threadId: String
  let senderUserId: String
  let senderDisplayName: String
  let senderAvatarUrl: URL?
  let targetContentIdentifier: String

  init?(userInfo: [AnyHashable: Any], fallbackSenderDisplayName: String) {
    guard let type = userInfo["type"] as? String else { return nil }
    guard Self.supportedTypes.contains(type) else { return nil }

    let senderUserId =
      (userInfo["sender_user_id"] as? String)?.nonEmpty
      ?? (userInfo["screenshotter_id"] as? String)?.nonEmpty
    guard let senderUserId else { return nil }

    let threadId =
      (userInfo["thread_id"] as? String)?.nonEmpty
      ?? "notification:\(type):\(senderUserId)"

    self.type = type
    self.threadId = threadId
    self.conversationIdentifier = threadId
    self.senderUserId = senderUserId
    self.senderDisplayName =
      (userInfo["sender_name"] as? String)?.nonEmpty
      ?? (userInfo["screenshotter_name"] as? String)?.nonEmpty
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

    self.targetContentIdentifier = "friend-chat:\(threadId)"
  }

  private static let supportedTypes: Set<String> = [
    "thread_message",
    "thread_screenshot",
    "shifts_screenshotted",
  ]
}

extension String {
  fileprivate var nonEmpty: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
