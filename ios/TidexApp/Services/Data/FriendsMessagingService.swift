import Foundation
import UIKit

@MainActor
protocol FriendsMessagingServiceProviding: AnyObject {
  func getOrCreateDirectThread(otherUserId: String) async throws -> FriendThread
  func fetchInboxSyncSnapshotV2(limit: Int, before cursor: FriendThreadCursor?) async throws
    -> FriendInboxSyncSnapshot
  func listThreadMessagesV2(threadId: String, limit: Int, before cursor: FriendMessageCursor?)
    async throws -> FriendThreadMessagesPage
  func fetchThreadSyncSnapshotV2(threadId: String, messageLimit: Int) async throws
    -> FriendThreadSyncSnapshot
  func listThreadEventsV2(threadId: String, afterVersion: Int64, limit: Int) async throws
    -> FriendThreadSyncEventsPage
  func listThreadStates(threadId: String) async throws -> [FriendThreadState]
  /// `senderUserId` is the user the message was written as. The server refuses the send with
  /// `wrongUser` when someone else is signed in now.
  func sendMessage(  // swiftlint:disable:this function_parameter_count
    senderUserId: String,
    threadId: String,
    clientId: String,
    body: String?,
    replyToMessageId: String?,
    attachments: [FriendOutgoingAttachment],
    metadataData: Data?
  ) async throws -> FriendMessage
  func editMessage(messageId: String, body: String) async throws -> FriendMessage
  func deleteMessage(messageId: String) async throws -> FriendThread
  func markThreadRead(threadId: String, throughMessageId: String) async throws -> FriendThreadState
  func setThreadMuted(threadId: String, muted: Bool) async throws -> FriendThreadState
  func setThreadTyping(threadId: String, isTyping: Bool) async throws
  func queueThreadTypingNotification(threadId: String) async throws -> Bool
  func fetchMessageSyncPayloadV2(messageId: String) async throws -> FriendMessage
  func toggleMessageReaction(messageId: String, emoji: String, attachmentId: String?)
    async throws -> FriendMessage
  func createAbuseReport(
    threadId: String,
    reportedUserId: String,
    messageId: String?,
    reason: FriendAbuseReportReason
  ) async throws
  func blockUserPair(otherUserId: String) async throws
  /// Uploads the image and returns the attachment to send. `storagePath` of the result holds
  /// the id of the stored file that `sendMessage` passes on to the server.
  func uploadImageAttachment(threadId: String, image: ImageAttachment) async throws
    -> FriendOutgoingAttachment
  func downloadAttachmentData(path: String) async throws -> Data
}

extension FriendsMessagingServiceProviding {
  // Test doubles that ignore typing inherit this.
  // swiftlint:disable:next async_without_await
  func setThreadTyping(threadId _: String, isTyping _: Bool) async throws {}
}

enum FriendsMessagingServiceError: Error, LocalizedError {
  case notAuthenticated
  case networkError(underlying: Error)
  case decodingError(underlying: Error)
  case httpError(statusCode: Int, message: String?)
  /// The server refused a write the app queued for another account than the one signed in now.
  case wrongUser

  var errorDescription: String? {
    switch self {
    case .notAuthenticated:
      return String(localized: .commonErrorNotAuthenticated)

    case .networkError:
      // The underlying text comes from the system language, so it stays out of app copy.
      return String(localized: .commonErrorGeneric)

    case .decodingError:
      return String(localized: .commonErrorUnexpectedResponse)

    case .httpError(_, let message):
      return message ?? String(localized: .commonErrorGeneric)

    case .wrongUser:
      return String(localized: .commonErrorGeneric)
    }
  }
}

@MainActor
// swiftlint:disable:next type_body_length
final class FriendsMessagingService {
  static let shared = FriendsMessagingService()

  private let api = ConvexAPI.app
  private let urlSession = URLSessionFactory.longRunning

  private init() {}

  /// Lets a dictionary literal of `.string(...)` values pass as an argument, which the generic
  /// parameter of `ConvexAPI.query` can't infer.
  private func params(_ object: JSONObject) -> JSONObject { object }

  func getOrCreateDirectThread(otherUserId: String) async throws -> FriendThread {
    let row: MessagingThreadSummaryRow = try await call {
      try await api.mutation(
        "threads:getOrCreateDirect", params(["other_user_id": .string(otherUserId)]))
    }
    return row.toFriendThread()
  }

  func fetchInboxSyncSnapshotV2(
    limit: Int = 30,
    before cursor: FriendThreadCursor? = nil
  ) async throws -> FriendInboxSyncSnapshot {
    var args: [String: AnyJSON] = ["limit": .integer(limit)]
    if let cursor {
      args["before_last_message_at"] = .string(ConvexTimestamp.string(from: cursor.lastMessageAt))
      args["before_thread_id"] = .string(cursor.threadId)
    }
    let payload: MessagingInboxRow = try await call {
      try await api.query("threads:inbox", args)
    }
    return payload.toFriendInboxSyncSnapshot()
  }

  func listThreadMessagesV2(
    threadId: String,
    limit: Int = 50,
    before cursor: FriendMessageCursor? = nil
  ) async throws -> FriendThreadMessagesPage {
    var args: [String: AnyJSON] = ["thread_id": .string(threadId), "limit": .integer(limit)]
    if let cursor {
      args["before_created_at"] = .string(ConvexTimestamp.string(from: cursor.createdAt))
      args["before_message_id"] = .string(cursor.messageId)
    }
    let payload: MessagingThreadMessagesPageRow = try await call {
      try await api.query("messages:list", args)
    }
    return payload.toFriendThreadMessagesPage()
  }

  func fetchThreadSyncSnapshotV2(
    threadId: String,
    messageLimit: Int = 50
  ) async throws -> FriendThreadSyncSnapshot {
    let payload: MessagingThreadSnapshotRow = try await call {
      try await api.query(
        "messages:thread",
        params(["thread_id": .string(threadId), "message_limit": .integer(messageLimit)]))
    }
    return payload.toFriendThreadSyncSnapshot()
  }

  /// Message changes after the revision `afterVersion`, from `messages:changes`.
  func listThreadEventsV2(
    threadId: String,
    afterVersion: Int64,
    limit: Int = 100
  ) async throws -> FriendThreadSyncEventsPage {
    let payload: MessagingThreadChangesRow = try await call {
      try await api.query(
        "messages:changes",
        params([
          "thread_id": .string(threadId),
          "after": .integer(Int(afterVersion)),
          "limit": .integer(limit),
        ]))
    }
    return payload.toFriendThreadSyncEventsPage()
  }

  func listThreadStates(threadId: String) async throws -> [FriendThreadState] {
    let rows: [MessagingThreadUserStateRow] = try await call {
      try await api.query("threads:states", params(["thread_id": .string(threadId)]))
    }
    return rows.map { $0.toFriendThreadState() }
  }

  func sendMessage(
    senderUserId: String,
    threadId: String,
    clientId: String,
    body: String?,
    replyToMessageId: String? = nil,
    attachments: [FriendOutgoingAttachment] = [],
    metadataData: Data? = nil
  ) async throws -> FriendMessage {
    let metadata: AnyJSON
    do {
      metadata =
        if let metadataData {
          try AnyJSON.decoder.decode(AnyJSON.self, from: metadataData)
        } else {
          AnyJSON.object([:])
        }
    } catch {
      throw FriendsMessagingServiceError.decodingError(underlying: error)
    }

    let args = SendMessageArgs(
      expectedUserId: senderUserId.lowercased(),
      threadId: threadId,
      clientId: clientId,
      body: body,
      replyToMessageId: replyToMessageId,
      attachments: attachments.map(SendMessageArgs.Attachment.init),
      metadata: metadata
    )
    let row: MessagingMessageRow = try await call {
      try await api.mutation("messages:send", args)
    }
    return row.toFriendMessage()
  }

  func editMessage(messageId: String, body: String) async throws -> FriendMessage {
    let row: MessagingMessageRow = try await call {
      try await api.mutation(
        "messages:edit", params(["message_id": .string(messageId), "body": .string(body)]))
    }
    return row.toFriendMessage()
  }

  func deleteMessage(messageId: String) async throws -> FriendThread {
    let row: MessagingThreadSummaryRow = try await call {
      try await api.mutation("messages:remove", params(["message_id": .string(messageId)]))
    }
    return row.toFriendThread()
  }

  func markThreadRead(threadId: String, throughMessageId: String) async throws -> FriendThreadState
  {
    let row: MessagingThreadUserStateRow = try await call {
      try await api.mutation(
        "threads:markRead",
        params(["thread_id": .string(threadId), "through_message_id": .string(throughMessageId)]))
    }
    return row.toFriendThreadState()
  }

  func setThreadMuted(threadId: String, muted: Bool) async throws -> FriendThreadState {
    let row: MessagingThreadUserStateRow = try await call {
      try await api.mutation(
        "threads:setMuted", params(["thread_id": .string(threadId), "muted": .bool(muted)]))
    }
    return row.toFriendThreadState()
  }

  func setThreadTyping(threadId: String, isTyping: Bool) async throws {
    let _: ConvexAPI.Ignored = try await call {
      try await api.mutation(
        "threads:setTyping", params(["thread_id": .string(threadId), "typing": .bool(isTyping)]))
    }
  }

  func queueThreadTypingNotification(threadId: String) async throws -> Bool {
    try await call {
      try await api.mutation(
        "threads:queueTypingNotification", params(["thread_id": .string(threadId)]))
    }
  }

  func fetchMessageSyncPayloadV2(messageId: String) async throws -> FriendMessage {
    let row: MessagingMessageRow? = try await call {
      try await api.query("messages:get", params(["message_id": .string(messageId)]))
    }
    guard let row else {
      throw FriendsMessagingServiceError.httpError(statusCode: 404, message: nil)
    }
    return row.toFriendMessage()
  }

  func toggleMessageReaction(
    messageId: String,
    emoji: String,
    attachmentId: String? = nil
  ) async throws -> FriendMessage {
    var args: [String: AnyJSON] = ["message_id": .string(messageId), "emoji": .string(emoji)]
    if let attachmentId {
      args["attachment_id"] = .string(attachmentId)
    }
    let row: MessagingMessageRow = try await call {
      try await api.mutation("messages:toggleReaction", args)
    }
    return row.toFriendMessage()
  }

  func createAbuseReport(
    threadId: String,
    reportedUserId: String,
    messageId: String?,
    reason: FriendAbuseReportReason
  ) async throws {
    var args: [String: AnyJSON] = [
      "thread_id": .string(threadId),
      "reported_user_id": .string(reportedUserId),
      "reason": .string(reason.rawValue),
    ]
    if let messageId {
      args["message_id"] = .string(messageId)
    }
    let _: ConvexAPI.Ignored = try await call {
      try await api.mutation("threads:reportAbuse", args)
    }
  }

  func blockUserPair(otherUserId: String) async throws {
    let _: ConvexAPI.Ignored = try await call {
      try await api.mutation("sharing:blockUser", params(["other_user_id": .string(otherUserId)]))
    }
  }

  // MARK: - Images

  /// The cache key and download path of an attachment, the same string the server puts in the
  /// attachment `url`. The outbox files a just-sent image under it, so the sent message shows
  /// the image without a download.
  nonisolated static func attachmentPath(attachmentId: String) -> String {
    ConvexAPI.configuredSiteURL.appending(path: "attachments/\(attachmentId)").absoluteString
  }

  func uploadImageAttachment(threadId: String, image: ImageAttachment) async throws
    -> FriendOutgoingAttachment
  {
    var components = URLComponents(
      url: ConvexAPI.configuredSiteURL.appending(path: "attachments"),
      resolvingAgainstBaseURL: false
    )
    components?.queryItems = [URLQueryItem(name: "thread_id", value: threadId)]
    guard let url = components?.url else {
      throw FriendsMessagingServiceError.networkError(underlying: URLError(.badURL))
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue(image.mediaType, forHTTPHeaderField: "Content-Type")

    // A retry uploads the file again. The server drops uploads that no message claims.
    let data = try await send(request, body: image.data)
    let reply: AttachmentUploadReply
    do {
      reply = try JSONDecoder().decode(AttachmentUploadReply.self, from: data)
    } catch {
      throw FriendsMessagingServiceError.decodingError(underlying: error)
    }

    let dimensions = imageDimensions(from: image.data)
    return FriendOutgoingAttachment(
      attachmentId: image.id,
      storagePath: reply.storageId,
      mimeType: image.mediaType,
      byteSize: Int64(image.data.count),
      width: dimensions.width,
      height: dimensions.height
    )
  }

  /// `path` is the `url` of a message attachment, or the storage path that messages saved before
  /// the move to Convex keep. Both end in the attachment id. The request always goes to the
  /// configured server, so the token never reaches a host that a payload names.
  func downloadAttachmentData(path: String) async throws -> Data {
    let name = (path as NSString).lastPathComponent
    let attachmentId =
      path.hasPrefix("http") ? name : (name as NSString).deletingPathExtension.lowercased()
    var request = URLRequest(
      url: ConvexAPI.configuredSiteURL.appending(path: "attachments/\(attachmentId)"))
    request.httpMethod = "GET"
    return try await send(request)
  }

  // MARK: - Helpers

  // Sends a request to the server's HTTP actions with the user's token. Tries once more with
  // a fresh token when the server answers 401.
  // swiftlint:disable:next cyclomatic_complexity
  private func send(_ request: URLRequest, body: Data? = nil) async throws -> Data {
    var retried = false
    do {
      while true {
        guard let token = try await AuthSessionManager.shared.convexToken(forceRefresh: retried)
        else {
          throw FriendsMessagingServiceError.notAuthenticated
        }
        var authorized = request
        authorized.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let data: Data
        let response: URLResponse
        if let body {
          (data, response) = try await urlSession.upload(for: authorized, from: body)
        } else {
          (data, response) = try await urlSession.data(for: authorized)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
          throw FriendsMessagingServiceError.networkError(underlying: URLError(.badServerResponse))
        }

        if httpResponse.statusCode == 401 {
          if retried { throw FriendsMessagingServiceError.notAuthenticated }
          retried = true
          continue
        }
        guard (200...299).contains(httpResponse.statusCode) else {
          throw FriendsMessagingServiceError.httpError(
            statusCode: httpResponse.statusCode,
            message: String(data: data, encoding: .utf8)
          )
        }
        return data
      }
    } catch let error as FriendsMessagingServiceError {
      throw error
    } catch {
      throw FriendsMessagingServiceError.networkError(underlying: error)
    }
  }

  /// Runs a Convex call and maps what it throws to `FriendsMessagingServiceError`.
  private func call<T>(_ body: () async throws -> T) async throws -> T {
    do {
      return try await body()
    } catch let error as FriendsMessagingServiceError {
      throw error
    } catch ConvexAPI.Failure.notSignedIn {
      throw FriendsMessagingServiceError.notAuthenticated
    } catch let failure as ConvexAPI.Failure where failure.code == "wrong_user" {
      throw FriendsMessagingServiceError.wrongUser
    } catch ConvexAPI.Failure.server(_, let message) {
      throw FriendsMessagingServiceError.httpError(statusCode: 400, message: message)
    } catch ConvexAPI.Failure.badResponse(let status) {
      throw FriendsMessagingServiceError.httpError(statusCode: status, message: nil)
    } catch let error as DecodingError {
      throw FriendsMessagingServiceError.decodingError(underlying: error)
    } catch {
      throw FriendsMessagingServiceError.networkError(underlying: error)
    }
  }

  private func imageDimensions(from data: Data) -> (width: Int?, height: Int?) {
    guard let image = UIImage(data: data) else {
      return (nil, nil)
    }

    return (
      width: Int(image.size.width.rounded()),
      height: Int(image.size.height.rounded())
    )
  }
}

extension FriendsMessagingService: FriendsMessagingServiceProviding {}

// MARK: - Request payloads

private struct SendMessageArgs: Encodable, Sendable {
  let expectedUserId: String
  let threadId: String
  let clientId: String
  let body: String?
  let replyToMessageId: String?
  let attachments: [Attachment]
  let metadata: AnyJSON

  enum CodingKeys: String, CodingKey {
    case expectedUserId = "expected_user_id"
    case threadId = "thread_id"
    case clientId = "client_id"
    case body
    case replyToMessageId = "reply_to_message_id"
    case attachments
    case metadata
  }

  struct Attachment: Encodable, Sendable {
    let attachmentId: String
    let storageId: String
    let mimeType: String
    let byteSize: Int64
    let width: Int?
    let height: Int?

    enum CodingKeys: String, CodingKey {
      case attachmentId = "attachment_id"
      case storageId = "storage_id"
      case mimeType = "mime_type"
      case byteSize = "byte_size"
      case width
      case height
    }

    /// The outgoing attachment keeps the id of the stored file in `storagePath`.
    init(_ attachment: FriendOutgoingAttachment) {
      attachmentId = attachment.attachmentId
      storageId = attachment.storagePath
      mimeType = attachment.mimeType
      byteSize = attachment.byteSize
      width = attachment.width
      height = attachment.height
    }
  }
}

private struct AttachmentUploadReply: Decodable {
  let storageId: String
}

// MARK: - Response payloads

/// A timestamp as Convex sends it, ISO 8601 with milliseconds. The decoders of `ConvexAPI` and of
/// subscriptions have no date strategy, so rows read dates through this type.
struct ConvexTimestamp: Decodable, Equatable, Sendable {
  let date: Date

  init(from decoder: Decoder) throws {
    let string = try decoder.singleValueContainer().decode(String.self)
    guard let date = ISO8601Timestamp.date(from: string) else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: "Invalid timestamp: \(string)"))
    }
    self.date = date
  }

  /// The string a pagination cursor sends. The server compares cursors with the stored
  /// timestamps as text, so it has the same millisecond format.
  static func string(from date: Date) -> String {
    String(ISO8601Timestamp.microsecondString(from: date).dropLast(4)) + "Z"
  }
}

struct MessagingThreadSummaryRow: Decodable {
  let threadId: String
  let kind: String
  let title: String?
  let avatarUrl: String?
  let metadata: AnyJSON?
  let counterpartUserId: String?
  let counterpartDisplayName: String?
  let counterpartProfilePictureUrl: String?
  let counterpartOAuthAvatarUrl: String?
  let lastMessageId: String?
  let lastMessageSenderId: String?
  let lastMessageAt: ConvexTimestamp?
  let lastMessageBody: String?
  let lastMessagePreviewKind: String?
  let lastMessageHasImage: Bool
  let unreadCount: Int
  let muted: Bool
  let createdAt: ConvexTimestamp
  let viewerStateUpdatedAt: ConvexTimestamp?

  enum CodingKeys: String, CodingKey {
    case threadId = "thread_id"
    case kind
    case title
    case avatarUrl = "avatar_url"
    case metadata
    case counterpartUserId = "counterpart_user_id"
    case counterpartDisplayName = "counterpart_display_name"
    case counterpartProfilePictureUrl = "counterpart_profile_picture_url"
    case counterpartOAuthAvatarUrl = "counterpart_oauth_avatar_url"
    case lastMessageId = "last_message_id"
    case lastMessageSenderId = "last_message_sender_id"
    case lastMessageAt = "last_message_at"
    case lastMessageBody = "last_message_body"
    case lastMessagePreviewKind = "last_message_preview_kind"
    case lastMessageHasImage = "last_message_has_image"
    case unreadCount = "unread_count"
    case muted
    case createdAt = "created_at"
    case viewerStateUpdatedAt = "viewer_state_updated_at"
  }

  func toFriendThread() -> FriendThread {
    FriendThread(
      id: threadId,
      kind: FriendThreadKind(rawValue: kind) ?? .direct,
      title: title,
      avatarUrl: avatarUrl,
      metadataData: Self.encode(metadata),
      counterpartUserId: counterpartUserId,
      counterpartDisplayName: counterpartDisplayName,
      counterpartProfilePictureUrl: counterpartProfilePictureUrl,
      counterpartOAuthAvatarUrl: counterpartOAuthAvatarUrl,
      lastMessageId: lastMessageId,
      lastMessageSenderId: lastMessageSenderId,
      lastMessageAt: lastMessageAt?.date,
      lastMessageBody: lastMessageBody,
      lastMessagePreviewKind: lastMessagePreviewKind.flatMap(FriendLastMessagePreviewKind.init),
      lastMessageHasImage: lastMessageHasImage,
      unreadCount: unreadCount,
      muted: muted,
      createdAt: createdAt.date,
      viewerStateUpdatedAt: viewerStateUpdatedAt?.date
    )
  }

  static func encode(_ value: AnyJSON?) -> Data? {
    guard let value else { return nil }
    return try? JSONEncoder().encode(value)
  }
}

/// The `threads:inbox` result.
struct MessagingInboxRow: Decodable {
  let threads: [MessagingThreadSummaryRow]
  let unreadDirectMessageCount: Int
  let nextCursor: MessagingThreadCursorRow?
  let hasMore: Bool

  enum CodingKeys: String, CodingKey {
    case threads
    case unreadDirectMessageCount = "unread_direct_message_count"
    case nextCursor = "next_cursor"
    case hasMore = "has_more"
  }

  func toFriendInboxSyncSnapshot() -> FriendInboxSyncSnapshot {
    FriendInboxSyncSnapshot(
      threads: threads.map { $0.toFriendThread() },
      unreadDirectMessageCount: unreadDirectMessageCount,
      nextCursor: nextCursor?.toFriendThreadCursor(),
      snapshotVersion: 0,
      retainedFromVersion: 0,
      hasMore: hasMore
    )
  }
}

/// The `messages:thread` result. `latest_revision` is the cursor for `messages:changes`.
struct MessagingThreadSnapshotRow: Decodable {
  let thread: MessagingThreadCoreRow
  let viewerState: MessagingThreadSyncViewerStateRow
  let counterpartState: MessagingThreadCounterpartPresenceRow?
  let messages: [MessagingMessageRow]
  let nextCursor: MessagingMessageCursorRow?
  let latestRevision: Int64
  let hasMore: Bool

  enum CodingKeys: String, CodingKey {
    case thread
    case viewerState = "viewer_state"
    case counterpartState = "counterpart_state"
    case messages
    case nextCursor = "next_cursor"
    case latestRevision = "latest_revision"
    case hasMore = "has_more"
  }

  func toFriendThreadSyncSnapshot() -> FriendThreadSyncSnapshot {
    let friendMessages = messages.map { $0.toFriendMessage() }
    let latestMessage = friendMessages.last
    let counterpartPresence = counterpartState?.toFriendThreadCounterpartPresence()

    let friendThread = FriendThread(
      id: thread.id,
      kind: FriendThreadKind(rawValue: thread.kind) ?? .direct,
      title: thread.title,
      avatarUrl: thread.avatarUrl,
      metadataData: MessagingThreadSummaryRow.encode(thread.metadata),
      counterpartUserId: counterpartPresence?.userId,
      counterpartDisplayName: counterpartPresence?.displayName,
      counterpartProfilePictureUrl: counterpartPresence?.profilePictureUrl,
      counterpartOAuthAvatarUrl: counterpartPresence?.oauthAvatarUrl,
      lastMessageId: latestMessage?.id,
      lastMessageSenderId: latestMessage?.senderUserId,
      lastMessageAt: latestMessage?.createdAt,
      lastMessageBody: latestMessage?.body,
      lastMessagePreviewKind: latestMessage?.previewKind,
      lastMessageHasImage: latestMessage?.hasImageAttachment ?? false,
      unreadCount: viewerState.unreadCount,
      muted: viewerState.muted,
      createdAt: thread.createdAt.date
    )

    return FriendThreadSyncSnapshot(
      thread: friendThread,
      viewerState: viewerState.toFriendThreadState(),
      counterpartPresence: counterpartPresence,
      messages: friendMessages,
      nextCursor: nextCursor?.toFriendMessageCursor(),
      snapshotVersion: latestRevision,
      retainedFromVersion: FriendsMessagingService.revisionCursorMarker,
      hasMore: hasMore
    )
  }
}

/// The `messages:changes` result.
struct MessagingThreadChangesRow: Decodable {
  let messages: [MessagingMessageRow]
  let cursor: Int64
  let done: Bool

  func toFriendThreadSyncEventsPage() -> FriendThreadSyncEventsPage {
    FriendThreadSyncEventsPage(
      requiresSnapshot: false,
      latestVersion: cursor,
      retainedFromVersion: FriendsMessagingService.revisionCursorMarker,
      hasMore: !done,
      events: messages.map { message in
        let version = message.revision ?? cursor
        if message.deletedAt != nil {
          return FriendThreadSyncEvent(
            id: "\(message.id)@\(version)",
            version: version,
            eventType: .messageDeleted,
            message: nil,
            deletedMessageId: message.id
          )
        }
        return FriendThreadSyncEvent(
          id: "\(message.id)@\(version)",
          version: version,
          eventType: .messageUpserted,
          message: message.toFriendMessage(),
          deletedMessageId: nil
        )
      }
    )
  }
}

/// The `messages:list` result.
struct MessagingThreadMessagesPageRow: Decodable {
  let messages: [MessagingMessageRow]
  let nextCursor: MessagingMessageCursorRow?
  let hasMore: Bool

  enum CodingKeys: String, CodingKey {
    case messages
    case nextCursor = "next_cursor"
    case hasMore = "has_more"
  }

  func toFriendThreadMessagesPage() -> FriendThreadMessagesPage {
    FriendThreadMessagesPage(
      messages: messages.map { $0.toFriendMessage() },
      nextCursor: nextCursor?.toFriendMessageCursor(),
      hasMore: hasMore
    )
  }
}

struct MessagingThreadCoreRow: Decodable {
  let id: String
  let kind: String
  let title: String?
  let avatarUrl: String?
  let metadata: AnyJSON?
  let createdAt: ConvexTimestamp

  enum CodingKeys: String, CodingKey {
    case id
    case kind
    case title
    case avatarUrl = "avatar_url"
    case metadata
    case createdAt = "created_at"
  }
}

struct MessagingThreadSyncViewerStateRow: Decodable {
  let threadId: String
  let userId: String
  let lastReadMessageId: String?
  let lastReadAt: ConvexTimestamp?
  let unreadCount: Int
  let muted: Bool
  let updatedAt: ConvexTimestamp

  enum CodingKeys: String, CodingKey {
    case threadId = "thread_id"
    case userId = "user_id"
    case lastReadMessageId = "last_read_message_id"
    case lastReadAt = "last_read_at"
    case unreadCount = "unread_count"
    case muted
    case updatedAt = "updated_at"
  }

  func toFriendThreadState() -> FriendThreadState {
    FriendThreadState(
      threadId: threadId,
      userId: userId,
      lastReadMessageId: lastReadMessageId,
      lastReadAt: lastReadAt?.date,
      muted: muted,
      updatedAt: updatedAt.date,
      unreadCount: unreadCount
    )
  }
}

struct MessagingThreadCounterpartPresenceRow: Decodable {
  let userId: String
  let displayName: String?
  let profilePictureUrl: String?
  let oauthAvatarUrl: String?

  enum CodingKeys: String, CodingKey {
    case userId = "user_id"
    case displayName = "display_name"
    case profilePictureUrl = "profile_picture_url"
    case oauthAvatarUrl = "oauth_avatar_url"
  }

  func toFriendThreadCounterpartPresence() -> FriendThreadCounterpartPresence {
    FriendThreadCounterpartPresence(
      userId: userId,
      displayName: displayName,
      profilePictureUrl: profilePictureUrl,
      oauthAvatarUrl: oauthAvatarUrl
    )
  }
}

struct MessagingThreadCursorRow: Decodable {
  let beforeLastMessageAt: ConvexTimestamp
  let beforeThreadId: String

  enum CodingKeys: String, CodingKey {
    case beforeLastMessageAt = "before_last_message_at"
    case beforeThreadId = "before_thread_id"
  }

  func toFriendThreadCursor() -> FriendThreadCursor {
    FriendThreadCursor(lastMessageAt: beforeLastMessageAt.date, threadId: beforeThreadId)
  }
}

struct MessagingMessageCursorRow: Decodable {
  let beforeCreatedAt: ConvexTimestamp
  let beforeMessageId: String

  enum CodingKeys: String, CodingKey {
    case beforeCreatedAt = "before_created_at"
    case beforeMessageId = "before_message_id"
  }

  func toFriendMessageCursor() -> FriendMessageCursor {
    FriendMessageCursor(createdAt: beforeCreatedAt.date, messageId: beforeMessageId)
  }
}

struct MessagingMessageRow: Decodable {
  let id: String
  let threadId: String
  let senderUserId: String
  let messageType: String
  let body: String?
  let clientId: String
  let replyToMessageId: String?
  let createdAt: ConvexTimestamp
  let editedAt: ConvexTimestamp?
  let deletedAt: ConvexTimestamp?
  let metadata: AnyJSON?
  let revision: Int64?
  let attachments: [MessagingAttachmentRow]
  let reactions: [MessagingReactionRow]?

  enum CodingKeys: String, CodingKey {
    case id
    case threadId = "thread_id"
    case senderUserId = "sender_user_id"
    case messageType = "message_type"
    case body
    case clientId = "client_id"
    case replyToMessageId = "reply_to_message_id"
    case createdAt = "created_at"
    case editedAt = "edited_at"
    case deletedAt = "deleted_at"
    case metadata
    case revision
    case attachments
    case reactions
  }

  func toFriendMessage() -> FriendMessage {
    FriendMessage(
      id: id,
      threadId: threadId,
      senderUserId: senderUserId,
      messageType: FriendMessageType(rawValue: messageType) ?? .user,
      body: body,
      clientId: clientId.lowercased(),
      replyToMessageId: replyToMessageId,
      createdAt: createdAt.date,
      editedAt: editedAt?.date,
      deletedAt: deletedAt?.date,
      metadataData: Self.encode(metadata),
      attachments: attachments.map { $0.toFriendAttachment() },
      reactions: (reactions ?? []).map { $0.toFriendReaction() },
      sendState: .sent,
      failureMessage: nil
    )
  }

  private static func encode(_ value: AnyJSON?) -> Data? {
    guard let value else { return nil }
    return try? JSONEncoder().encode(value)
  }
}

struct MessagingReactionRow: Decodable {
  let emoji: String
  let count: Int
  let viewerHasReacted: Bool

  enum CodingKeys: String, CodingKey {
    case emoji
    case count
    case viewerHasReacted = "viewer_has_reacted"
  }

  func toFriendReaction() -> FriendMessageReaction {
    FriendMessageReaction(
      emoji: emoji,
      count: count,
      viewerHasReacted: viewerHasReacted
    )
  }
}

struct MessagingAttachmentRow: Decodable {
  let id: String
  let attachmentIndex: Int
  let kind: String
  /// Where the image downloads from, `{CONVEX_SITE_URL}/attachments/<id>`.
  let url: String
  let mimeType: String
  let byteSize: Int64
  let width: Int?
  let height: Int?
  let createdAt: ConvexTimestamp
  let reactions: [MessagingReactionRow]?

  enum CodingKeys: String, CodingKey {
    case id
    case attachmentIndex = "attachment_index"
    case kind
    case url
    case mimeType = "mime_type"
    case byteSize = "byte_size"
    case width
    case height
    case createdAt = "created_at"
    case reactions
  }

  /// The model still has the storage bucket and path of the old server. The URL goes in
  /// `storagePath`, which is also the image cache key.
  func toFriendAttachment() -> FriendMessageAttachment {
    FriendMessageAttachment(
      id: id,
      attachmentIndex: attachmentIndex,
      kind: FriendMessageAttachmentKind(rawValue: kind) ?? .image,
      storageBucket: "attachments",
      storagePath: url,
      mimeType: mimeType,
      byteSize: byteSize,
      width: width,
      height: height,
      createdAt: createdAt.date,
      reactions: (reactions ?? []).map { $0.toFriendReaction() }
    )
  }
}

struct MessagingThreadUserStateRow: Decodable {
  let threadId: String
  let userId: String
  let lastReadMessageId: String?
  let lastReadAt: ConvexTimestamp?
  let muted: Bool
  let updatedAt: ConvexTimestamp
  let unreadCount: Int?

  enum CodingKeys: String, CodingKey {
    case threadId = "thread_id"
    case userId = "user_id"
    case lastReadMessageId = "last_read_message_id"
    case lastReadAt = "last_read_at"
    case muted
    case updatedAt = "updated_at"
    case unreadCount = "unread_count"
  }

  func toFriendThreadState() -> FriendThreadState {
    FriendThreadState(
      threadId: threadId,
      userId: userId,
      lastReadMessageId: lastReadMessageId,
      lastReadAt: lastReadAt?.date,
      muted: muted,
      updatedAt: updatedAt.date,
      unreadCount: unreadCount
    )
  }
}

extension FriendsMessagingService {
  /// Message sync states saved before the move to Convex hold event versions of the old
  /// server. A state with this `retainedFromVersion` holds a Convex revision, and the
  /// coordinator ignores any other, so the first sync after the update loads a full snapshot.
  nonisolated static let revisionCursorMarker: Int64 = -1
}  // swiftlint:disable:this file_length
