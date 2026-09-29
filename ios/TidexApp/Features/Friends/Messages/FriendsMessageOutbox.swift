import Foundation
import UIKit
import os.log

private let outboxLogger = Logger(subsystem: "com.tidex.app", category: "FriendsMessageOutbox")

/// Durable copies of the image bytes for messages that have not been sent yet.
/// ImageCache lives in Caches and the system can evict it, so the outbox keeps its own files.
struct FriendsPendingAttachmentStore {
  private static let directoryName = "FriendsPendingMessageAttachments"
  private static let appGroupId = "group.no.tidex.app"

  let directory: URL

  init(directory: URL? = nil) {
    self.directory = directory ?? Self.defaultDirectory()
    try? FileManager.default.createDirectory(
      at: self.directory, withIntermediateDirectories: true)
  }

  func save(_ image: ImageAttachment) {
    guard let url = fileURL(for: image.id) else { return }
    do {
      try image.data.write(to: url, options: .atomic)
    } catch {
      outboxLogger.error("Failed to save pending attachment: \(error.localizedDescription)")
    }
  }

  func load(id: String, mediaType: String) -> ImageAttachment? {
    guard let url = fileURL(for: id), let data = try? Data(contentsOf: url), !data.isEmpty else {
      return nil
    }
    return ImageAttachment(id: id, data: data, mediaType: mediaType)
  }

  func delete(id: String) {
    guard let url = fileURL(for: id) else { return }
    try? FileManager.default.removeItem(at: url)
  }

  private func fileURL(for id: String) -> URL? {
    guard !id.isEmpty, !id.contains("/") else { return nil }
    return directory.appendingPathComponent(id, isDirectory: false)
  }

  /// Sits next to the composer draft attachments, under Application Support.
  private static func defaultDirectory() -> URL {
    let fileManager = FileManager.default
    let fallbackBaseURL =
      fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? fileManager.temporaryDirectory
    return FriendsComposerDraftStore.resolvedAttachmentsDirectory(
      appGroupURL: fileManager.containerURL(
        forSecurityApplicationGroupIdentifier: appGroupId),
      fallbackBaseURL: fallbackBaseURL
    )
    .deletingLastPathComponent()
    .appendingPathComponent(directoryName, isDirectory: true)
  }
}

/// Sends queued messages and records the outcome. The open thread and the background drain use
/// the same methods, and one in-flight set keeps them from sending the same message twice.
@MainActor
final class FriendsMessageOutbox {
  enum Disposition: Equatable {
    /// Keep the message queued and try again later.
    case queue
    /// Stop retrying and show the message as failed.
    case fail
  }

  static let shared = FriendsMessageOutbox()
  static let pendingAttachmentPrefix = "local-pending/"
  /// Failures that are not clearly offline are retried this many times before the message fails.
  static let maxUnclassifiedAttempts = 3

  private let service: any FriendsMessagingServiceProviding
  private let repository: FriendsMessagesRepository
  private let pendingStore: FriendsPendingAttachmentStore
  private var inFlightMessageIds: Set<String> = []
  /// In-flight messages the user deleted. They are deleted on the server once the send confirms.
  private var discardedInFlightMessageIds: Set<String> = []
  private var attemptCounts: [String: Int] = [:]
  private var isDraining = false

  init(
    service: (any FriendsMessagingServiceProviding)? = nil,
    repository: FriendsMessagesRepository? = nil,
    pendingStore: FriendsPendingAttachmentStore? = nil
  ) {
    self.service = service ?? FriendsMessagingService.shared
    self.repository = repository ?? .shared
    self.pendingStore = pendingStore ?? FriendsPendingAttachmentStore()
  }

  // MARK: - Drain

  /// Sends every queued message for the user, across all threads and in order per thread.
  /// A second call while a drain is running returns right away.
  func drain(userId: String) async {
    guard !isDraining, !userId.isEmpty else { return }
    isDraining = true
    defer { isDraining = false }

    var blockedThreadIds: Set<String> = []
    for queuedMessage in repository.getQueuedMessages(viewerUserId: userId) {
      guard !blockedThreadIds.contains(queuedMessage.threadId) else { continue }
      // Earlier sends in this loop await, so the user may have deleted or retried this one since.
      guard
        let message = repository.getMessage(id: queuedMessage.id, viewerUserId: userId),
        message.sendState == .sending
      else { continue }
      // Another sender owns this message. Skip the rest of the thread to keep the order.
      guard claim(message.id) else {
        blockedThreadIds.insert(message.threadId)
        continue
      }
      defer { release(message.id) }

      do {
        let sentMessage = try await send(message)
        await confirm(sentMessage, replacing: message, userId: userId)
      } catch {
        let disposition = await recordFailure(error, for: message, userId: userId)
        if Self.isConnectivityError(error) {
          // Offline, so the remaining messages would fail the same way.
          notifyThreadUpdated(message.threadId)
          return
        }
        if disposition == .queue {
          blockedThreadIds.insert(message.threadId)
        }
      }
      notifyThreadUpdated(message.threadId)
    }
  }

  // MARK: - Shared send path

  /// Claims a message for sending. Returns false when someone else is already sending it.
  func claim(_ messageId: String) -> Bool {
    inFlightMessageIds.insert(messageId).inserted
  }

  func release(_ messageId: String) {
    inFlightMessageIds.remove(messageId)
    discardedInFlightMessageIds.remove(messageId)
  }

  func isSending(_ messageId: String) -> Bool {
    inFlightMessageIds.contains(messageId)
  }

  /// Uploads pending images and calls the send RPC. Does not touch the local store.
  func send(_ message: FriendMessage) async throws -> FriendMessage {
    let outgoingAttachments = try await makeOutgoingAttachments(for: message)
    return try await service.sendMessage(
      threadId: message.threadId,
      clientId: message.clientId,
      body: message.body,
      replyToMessageId: message.replyToMessageId,
      attachments: outgoingAttachments,
      metadataData: message.sendableMetadataData
    )
  }

  /// Replaces the local message with the confirmed one and drops its pending image bytes.
  func confirm(
    _ sentMessage: FriendMessage,
    replacing message: FriendMessage,
    userId: String
  ) async {
    if discardedInFlightMessageIds.remove(message.id) == nil {
      await repository.saveConfirmedMessage(
        sentMessage,
        replacingLocalMessageId: message.id,
        in: message.threadId,
        for: userId
      )
      discardPendingData(for: message)
      // The user can delete it while the save above awaits.
      guard discardedInFlightMessageIds.remove(message.id) != nil else { return }
    }
    await deleteConfirmedMessage(sentMessage, userId: userId)
    discardPendingData(for: message)
  }

  /// Decides whether a failed send stays queued and counts the attempt.
  func disposition(for error: Error, messageId: String) -> Disposition {
    if Self.isConnectivityError(error) {
      return .queue
    }
    if Self.isDefinitiveFailure(error) {
      attemptCounts[messageId] = nil
      return .fail
    }

    let attempts = attemptCounts[messageId, default: 0] + 1
    if attempts >= Self.maxUnclassifiedAttempts {
      attemptCounts[messageId] = nil
      return .fail
    }
    attemptCounts[messageId] = attempts
    return .queue
  }

  /// Stores the queued or failed state for a message whose send threw.
  @discardableResult
  func recordFailure(_ error: Error, for message: FriendMessage, userId: String) async
    -> Disposition
  {
    let outcome = disposition(for: error, messageId: message.id)
    await repository.updateMessageSendState(
      messageId: message.id,
      viewerUserId: userId,
      sendState: outcome == .queue ? .sending : .failed,
      failureMessage: outcome == .queue
        ? String(localized: .friendsChatWaitingForNetwork)
        : String(localized: .friendsChatSendFailed)
    )
    outboxLogger.error("Failed to send queued message: \(error.localizedDescription)")
    return outcome
  }

  /// Drops a message the user deleted before it was sent. If a send is in flight, the message is
  /// deleted on the server when that send confirms.
  func discard(_ message: FriendMessage) {
    if isSending(message.id) {
      discardedInFlightMessageIds.insert(message.id)
    }
    discardPendingData(for: message)
  }

  /// Forgets the retry count and deletes the durable image bytes of a message that will not send.
  func discardPendingData(for message: FriendMessage) {
    attemptCounts[message.id] = nil
    for attachment in message.attachments where Self.isPendingAttachment(attachment) {
      pendingStore.delete(id: attachment.id)
    }
  }

  /// Resets the retry count when the user retries a failed message by hand.
  func resetAttempts(for messageId: String) {
    attemptCounts[messageId] = nil
  }

  private func deleteConfirmedMessage(_ sentMessage: FriendMessage, userId: String) async {
    // Realtime can store the server row before the send returns.
    await repository.deleteMessage(id: sentMessage.id, viewerUserId: userId)
    do {
      let updatedThread = try await service.deleteMessage(messageId: sentMessage.id)
      await repository.saveThread(updatedThread, for: userId)
    } catch {
      // Show the message again so the user sees it was sent and can delete it once more.
      await repository.saveMessages([sentMessage], in: sentMessage.threadId, for: userId)
      outboxLogger.error(
        "Failed to delete a message the user deleted while sending: \(error.localizedDescription)")
    }
    notifyThreadUpdated(sentMessage.threadId)
  }

  // MARK: - Pending attachments

  /// Keeps the image for display in ImageCache and for sending in the durable store.
  func savePendingImage(_ image: ImageAttachment, storagePath: String) {
    pendingStore.save(image)
    Self.cacheImage(image, for: storagePath)
  }

  func pendingImage(for attachment: FriendMessageAttachment) async -> ImageAttachment? {
    if let stored = pendingStore.load(id: attachment.id, mediaType: attachment.mimeType) {
      return stored
    }

    // Messages queued before the durable store existed only have the cache copy.
    let attachmentId = attachment.id
    let storagePath = attachment.storagePath
    return await Task.detached(priority: .userInitiated) {
      let cacheURL = Self.imageCacheURL(for: storagePath)
      if let cachedImage = ImageCache.shared.get(for: cacheURL, policy: .messageAttachment),
        let data = cachedImage.jpegData(compressionQuality: 0.9)
      {
        return ImageAttachment(id: attachmentId, data: data, mediaType: "image/jpeg")
      }

      if let cachedImage = await ImageCache.shared.getFromDisk(
        for: cacheURL,
        policy: .messageAttachment
      ),
        let data = cachedImage.jpegData(compressionQuality: 0.9)
      {
        return ImageAttachment(id: attachmentId, data: data, mediaType: "image/jpeg")
      }

      return nil
    }.value
  }

  private func makeOutgoingAttachments(for message: FriendMessage) async throws
    -> [FriendOutgoingAttachment]
  {
    var outgoingAttachments: [FriendOutgoingAttachment] = []

    for attachment in message.attachments {
      if Self.isPendingAttachment(attachment) {
        guard let pendingImage = await pendingImage(for: attachment) else {
          throw FriendsThreadViewModel.ActionError.missingPendingAttachment
        }
        let uploadedAttachment = try await service.uploadImageAttachment(
          threadId: message.threadId,
          image: pendingImage
        )
        Self.cacheImage(pendingImage, for: uploadedAttachment.storagePath)
        outgoingAttachments.append(uploadedAttachment)
        continue
      }

      outgoingAttachments.append(
        FriendOutgoingAttachment(
          attachmentId: attachment.id,
          storagePath: attachment.storagePath,
          mimeType: attachment.mimeType,
          byteSize: attachment.byteSize,
          width: attachment.width,
          height: attachment.height
        ))
    }

    return outgoingAttachments
  }

  private func notifyThreadUpdated(_ threadId: String) {
    NotificationCenter.default.post(
      name: .friendsThreadDidUpdate,
      object: nil,
      userInfo: ["threadId": threadId]
    )
  }

  // MARK: - Classification

  static func pendingAttachmentStoragePath(for attachmentId: String) -> String {
    "\(pendingAttachmentPrefix)\(attachmentId)"
  }

  static func isPendingAttachment(_ attachment: FriendMessageAttachment) -> Bool {
    attachment.storagePath.hasPrefix(pendingAttachmentPrefix)
  }

  /// True when the error means the device is offline or the session check timed out.
  static func isConnectivityError(_ error: Error) -> Bool {
    if error is CancellationError {
      return false
    }

    if let serviceError = error as? FriendsMessagingServiceError {
      switch serviceError {
      case .networkError(let underlying):
        return isConnectivityError(underlying)

      case .notAuthenticated, .decodingError, .httpError:
        return false
      }
    }

    if AuthSessionManager.shared.isTransientSessionResolutionError(error) {
      return true
    }

    if let underlyingError = (error as NSError).userInfo[NSUnderlyingErrorKey] as? Error {
      return isConnectivityError(underlyingError)
    }

    return false
  }

  /// Errors where a retry cannot help.
  private static func isDefinitiveFailure(_ error: Error) -> Bool {
    if let serviceError = error as? FriendsMessagingServiceError {
      switch serviceError {
      case .networkError:
        return false

      case .notAuthenticated, .decodingError, .httpError:
        return true
      }
    }

    if case .missingPendingAttachment = error as? FriendsThreadViewModel.ActionError {
      return true
    }

    return false
  }

  // MARK: - Image cache

  nonisolated static func imageCacheURL(for storagePath: String) -> URL {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "friends-message-cache.local"
    components.path = "/\(storagePath)"
    return components.url ?? URL(filePath: "/tmp/friends-message-cache-fallback")
  }

  static func cacheImage(_ image: ImageAttachment, for storagePath: String) {
    guard let uiImage = UIImage(data: image.data) else { return }
    ImageCache.shared.set(
      uiImage,
      for: imageCacheURL(for: storagePath),
      policy: .messageAttachment
    )
  }
}
