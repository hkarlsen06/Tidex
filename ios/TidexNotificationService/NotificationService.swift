import CryptoKit
import Foundation
import Intents
import UserNotifications
import os

private let logger = Logger(subsystem: "no.tidex.app", category: "NotificationServiceExtension")
private let avatarFetchBudget = Duration.milliseconds(250)

private enum SenderAvatarLoader {
  private static let appGroupId = "group.no.tidex.app"
  private static let sharedCacheDirectoryName = "NotificationAvatarCache"
  static let inMemoryCache = NSCache<NSURL, INImage>()
  static let urlCache = URLCache(
    memoryCapacity: 4 * 1024 * 1024,
    diskCapacity: 20 * 1024 * 1024,
    diskPath: "TidexNotificationAvatarCache"
  )
  static let session: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.requestCachePolicy = .useProtocolCachePolicy
    configuration.timeoutIntervalForRequest = 1
    configuration.timeoutIntervalForResource = 1
    configuration.waitsForConnectivity = false
    configuration.urlCache = urlCache
    return URLSession(configuration: configuration)
  }()

  private static var sharedCacheDirectory: URL? {
    guard
      let containerURL = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: appGroupId)
    else {
      return nil
    }

    let directory = containerURL.appendingPathComponent(sharedCacheDirectoryName, isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  static func cachedImage(for request: URLRequest, url: URL) -> INImage? {
    if let image = inMemoryCache.object(forKey: url as NSURL) {
      logger.debug(
        "Sender avatar cache hit (memory) for \(url.absoluteString, privacy: .private(mask: .hash))"
      )
      return image
    }

    if let sharedCachedImage = sharedCachedImage(for: url) {
      logger.debug(
        "Sender avatar cache hit (shared) for \(url.absoluteString, privacy: .private(mask: .hash))"
      )
      return sharedCachedImage
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

  static func fetchImage(for url: URL) async -> INImage? {
    let request = URLRequest(
      url: url,
      cachePolicy: .useProtocolCachePolicy,
      timeoutInterval: 1
    )

    do {
      let (data, response) = try await session.data(for: request)
      guard let httpResponse = response as? HTTPURLResponse,
        (200..<300).contains(httpResponse.statusCode)
      else {
        return nil
      }

      urlCache.storeCachedResponse(CachedURLResponse(response: response, data: data), for: request)
      storeSharedImageData(data, for: url)
      return makeImage(from: data, url: url)
    } catch is CancellationError {
      return nil
    } catch {
      logger.debug(
        "Sender avatar fetch failed for \(url.absoluteString, privacy: .private(mask: .hash)): \(error.localizedDescription, privacy: .public)"
      )
      return nil
    }
  }

  private static func sharedCachedImage(for url: URL) -> INImage? {
    guard let fileURL = sharedCacheFileURL(for: url),
      let data = try? Data(contentsOf: fileURL)
    else {
      return nil
    }

    return makeImage(from: data, url: url)
  }

  private static func storeSharedImageData(_ data: Data, for url: URL) {
    guard let fileURL = sharedCacheFileURL(for: url) else { return }
    try? data.write(to: fileURL, options: .atomic)
  }

  private static func sharedCacheFileURL(for url: URL) -> URL? {
    guard let directory = sharedCacheDirectory else { return nil }
    return directory.appendingPathComponent(fileName(for: url))
  }

  private static func fileName(for url: URL) -> String {
    SHA256.hash(data: Data(url.absoluteString.utf8))
      .compactMap { String(format: "%02x", $0) }
      .joined()
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
    if let messageCreatedAt = payload.messageCreatedAt {
      logger.debug(
        "Notification start lag \(Self.elapsedMilliseconds(since: messageCreatedAt), privacy: .public) ms for type \(payload.type, privacy: .public)"
      )
    }
    content.threadIdentifier = payload.threadId
    if #available(iOS 15.0, *) {
      content.targetContentIdentifier = payload.targetContentIdentifier
    }

    let senderImage = await loadSenderImage(from: payload.senderAvatarUrl)
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
      let contentUpdateStartedAt = Date()
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
        "Notification content updated in \(Self.elapsedMilliseconds(since: contentUpdateStartedAt), privacy: .public) ms"
      )
      donateBestEffort(interaction)
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
      timeoutInterval: 1
    )

    return SenderAvatarLoader.cachedImage(for: request, url: url)
  }

  private func loadSenderImage(from url: URL?) async -> INImage? {
    guard let url else { return nil }
    let startedAt = Date()

    let request = URLRequest(
      url: url,
      cachePolicy: .returnCacheDataDontLoad,
      timeoutInterval: 1
    )

    if let cachedImage = SenderAvatarLoader.cachedImage(for: request, url: url) {
      logger.debug(
        "Sender avatar resolved from cache in \(Self.elapsedMilliseconds(since: startedAt), privacy: .public) ms"
      )
      return cachedImage
    }

    let fetchedImage = await withTaskGroup(of: INImage?.self, returning: INImage?.self) { group in
      group.addTask {
        await SenderAvatarLoader.fetchImage(for: url)
      }
      group.addTask {
        try? await Task.sleep(for: avatarFetchBudget)
        return nil
      }

      let result = await group.next() ?? nil
      group.cancelAll()
      return result
    }
    logger.debug(
      "Sender avatar fetch result hit=\(fetchedImage != nil, privacy: .public) duration=\(Self.elapsedMilliseconds(since: startedAt), privacy: .public) ms"
    )
    return fetchedImage
  }

  private func donateBestEffort(_ interaction: INInteraction) {
    Task.detached(priority: .utility) {
      let donationStartedAt = Date()
      do {
        try await Self.donate(interaction)
        logger.debug(
          "Notification donation completed in \(Self.elapsedMilliseconds(since: donationStartedAt), privacy: .public) ms"
        )
      } catch {
        logger.error(
          "Notification donation failed after \(Self.elapsedMilliseconds(since: donationStartedAt), privacy: .public) ms: \(error.localizedDescription, privacy: .public)"
        )
      }
    }
  }

  private static func donate(_ interaction: INInteraction) async throws {
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
  let messageCreatedAt: Date?

  private static let iso8601Formatter = ISO8601DateFormatter()

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
    self.messageCreatedAt = Self.date(from: userInfo["message_created_at"] as? String)
  }

  private static let supportedTypes: Set<String> = [
    "thread_message",
    "thread_screenshot",
    "shifts_screenshotted",
  ]

  private static func date(from iso8601: String?) -> Date? {
    guard let iso8601, !iso8601.isEmpty else { return nil }
    return iso8601Formatter.date(from: iso8601)
  }
}

extension String {
  fileprivate var nonEmpty: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
