import Auth
import Combine
import Foundation
import Supabase
import UIKit
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "FriendsMessagingService")

@MainActor
protocol FriendsMessagingServiceProviding: AnyObject {
  func getOrCreateDirectThread(otherUserId: String) async throws -> FriendThread
  func listMyThreads(limit: Int, before cursor: FriendThreadCursor?) async throws -> [FriendThread]
  func listThreadMessages(threadId: String, limit: Int, before cursor: FriendMessageCursor?)
    async throws -> [FriendMessage]
  func sendMessage(
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
  func fetchUnreadDirectMessageCount(userId: String) async throws -> Int
  func fetchThreadSummary(threadId: String) async throws -> FriendThread
  func fetchThreadState(threadId: String, userId: String) async throws -> FriendThreadState?
  func fetchMessagePayload(messageId: String) async throws -> FriendMessage
  func toggleMessageReaction(messageId: String, emoji: String) async throws -> FriendMessage
  func createAbuseReport(
    threadId: String,
    reportedUserId: String,
    messageId: String?,
    reason: FriendAbuseReportReason
  ) async throws
  func blockUserPair(otherUserId: String) async throws
  func uploadImageAttachment(threadId: String, image: ImageAttachment) async throws
    -> FriendOutgoingAttachment
  func downloadAttachmentData(path: String) async throws -> Data
}

enum FriendsMessagingServiceError: Error, LocalizedError {
  case notAuthenticated
  case networkError(underlying: Error)
  case decodingError(underlying: Error)
  case httpError(statusCode: Int, message: String?)

  var errorDescription: String? {
    switch self {
    case .notAuthenticated:
      return "Not authenticated"
    case .networkError(let error):
      return "Network error: \(error.localizedDescription)"
    case .decodingError(let error):
      return "Failed to decode response: \(error.localizedDescription)"
    case .httpError(let statusCode, let message):
      return "HTTP \(statusCode): \(message ?? "Unknown error")"
    }
  }
}

@MainActor
final class FriendsMessagingService: ObservableObject {
  static let shared = FriendsMessagingService()

  private let storageBucket = "message-attachments"
  private let urlSession = URLSessionFactory.longRunning

  private init() {}

  func getOrCreateDirectThread(otherUserId: String) async throws -> FriendThread {
    let params: [String: AnyJSON] = [
      "p_other_user_id": .string(otherUserId)
    ]

    do {
      _ = try await AuthSessionManager.shared.getSession()

      let row: MessagingThreadSummaryRow =
        try await supabase
        .rpc("get_or_create_direct_thread", params: params)
        .single()
        .execute()
        .value

      return row.toFriendThread()
    } catch let error as FriendsMessagingServiceError {
      throw error
    } catch let error as PostgrestError {
      throw mapRPCError(error)
    } catch let error as AuthError {
      throw mapRPCError(error)
    } catch let error as DecodingError {
      throw FriendsMessagingServiceError.decodingError(underlying: error)
    } catch {
      throw FriendsMessagingServiceError.networkError(underlying: error)
    }
  }

  func listMyThreads(
    limit: Int = 30,
    before cursor: FriendThreadCursor? = nil
  ) async throws -> [FriendThread] {
    var params: [String: AnyJSON] = [
      "p_limit": .integer(limit)
    ]

    if let cursor {
      params["p_before_last_message_at"] = .string(
        cursor.lastMessageAt.toISO8601String())
      params["p_before_thread_id"] = .string(cursor.threadId)
    }

    do {
      _ = try await AuthSessionManager.shared.getSession()

      let rows: [MessagingThreadSummaryRow] =
        try await supabase
        .rpc("list_my_threads", params: params)
        .execute()
        .value

      return rows.map { $0.toFriendThread() }
    } catch let error as PostgrestError {
      throw mapRPCError(error)
    } catch let error as AuthError {
      throw mapRPCError(error)
    } catch let error as DecodingError {
      throw FriendsMessagingServiceError.decodingError(underlying: error)
    } catch {
      throw FriendsMessagingServiceError.networkError(underlying: error)
    }
  }

  func listThreadMessages(
    threadId: String,
    limit: Int = 50,
    before cursor: FriendMessageCursor? = nil
  ) async throws -> [FriendMessage] {
    var params: [String: AnyJSON] = [
      "p_thread_id": .string(threadId),
      "p_limit": .integer(limit),
    ]

    if let cursor {
      params["p_before_created_at"] = .string(cursor.createdAt.toISO8601String())
      params["p_before_message_id"] = .string(cursor.messageId)
    }

    do {
      _ = try await AuthSessionManager.shared.getSession()

      let rows: [MessagingMessageRow] =
        try await supabase
        .rpc("list_thread_messages", params: params)
        .execute()
        .value

      return rows.map { $0.toFriendMessage() }
    } catch let error as PostgrestError {
      throw mapRPCError(error)
    } catch let error as AuthError {
      throw mapRPCError(error)
    } catch let error as DecodingError {
      throw FriendsMessagingServiceError.decodingError(underlying: error)
    } catch {
      throw FriendsMessagingServiceError.networkError(underlying: error)
    }
  }

  func sendMessage(
    threadId: String,
    clientId: String,
    body: String?,
    replyToMessageId: String? = nil,
    attachments: [FriendOutgoingAttachment] = [],
    metadataData: Data? = nil
  ) async throws -> FriendMessage {
    let payload = try attachments.map { attachment -> AnyJSON in
      let data = try JSONEncoder().encode(attachment)
      return try AnyJSON.decoder.decode(AnyJSON.self, from: data)
    }
    let metadataPayload =
      if let metadataData {
        try AnyJSON.decoder.decode(AnyJSON.self, from: metadataData)
      } else {
        AnyJSON.object([:])
      }

    let params: [String: AnyJSON] = [
      "p_thread_id": .string(threadId),
      "p_client_id": .string(clientId),
      "p_body": body.map(AnyJSON.string) ?? .null,
      "p_reply_to_message_id": replyToMessageId.map(AnyJSON.string) ?? .null,
      "p_attachments": .array(payload),
      "p_metadata": metadataPayload,
    ]

    do {
      _ = try await AuthSessionManager.shared.getSession()

      let row: MessagingMessageRow =
        try await supabase
        .rpc("send_message", params: params)
        .single()
        .execute()
        .value

      return row.toFriendMessage()
    } catch let error as PostgrestError {
      throw mapRPCError(error)
    } catch let error as AuthError {
      throw mapRPCError(error)
    } catch let error as DecodingError {
      throw FriendsMessagingServiceError.decodingError(underlying: error)
    } catch {
      throw FriendsMessagingServiceError.networkError(underlying: error)
    }
  }

  func editMessage(messageId: String, body: String) async throws -> FriendMessage {
    let params: [String: AnyJSON] = [
      "p_message_id": .string(messageId),
      "p_body": .string(body),
    ]

    do {
      _ = try await AuthSessionManager.shared.getSession()

      let row: MessagingMessageRow =
        try await supabase
        .rpc("edit_message", params: params)
        .single()
        .execute()
        .value

      return row.toFriendMessage()
    } catch let error as PostgrestError {
      throw mapRPCError(error)
    } catch let error as AuthError {
      throw mapRPCError(error)
    } catch let error as DecodingError {
      throw FriendsMessagingServiceError.decodingError(underlying: error)
    } catch {
      throw FriendsMessagingServiceError.networkError(underlying: error)
    }
  }

  func deleteMessage(messageId: String) async throws -> FriendThread {
    let params: [String: AnyJSON] = [
      "p_message_id": .string(messageId)
    ]

    do {
      _ = try await AuthSessionManager.shared.getSession()

      let row: MessagingThreadSummaryRow =
        try await supabase
        .rpc("delete_message", params: params)
        .single()
        .execute()
        .value

      return row.toFriendThread()
    } catch let error as PostgrestError {
      throw mapRPCError(error)
    } catch let error as AuthError {
      throw mapRPCError(error)
    } catch let error as DecodingError {
      throw FriendsMessagingServiceError.decodingError(underlying: error)
    } catch {
      throw FriendsMessagingServiceError.networkError(underlying: error)
    }
  }

  func markThreadRead(threadId: String, throughMessageId: String) async throws -> FriendThreadState
  {
    let params: [String: AnyJSON] = [
      "p_thread_id": .string(threadId),
      "p_through_message_id": .string(throughMessageId),
    ]

    do {
      _ = try await AuthSessionManager.shared.getSession()

      let row: MessagingThreadUserStateRow =
        try await supabase
        .rpc("mark_thread_read", params: params)
        .single()
        .execute()
        .value

      return row.toFriendThreadState()
    } catch let error as PostgrestError {
      throw mapRPCError(error)
    } catch let error as AuthError {
      throw mapRPCError(error)
    } catch let error as DecodingError {
      throw FriendsMessagingServiceError.decodingError(underlying: error)
    } catch {
      throw FriendsMessagingServiceError.networkError(underlying: error)
    }
  }

  func setThreadMuted(threadId: String, muted: Bool) async throws -> FriendThreadState {
    let params: [String: AnyJSON] = [
      "p_thread_id": .string(threadId),
      "p_muted": .bool(muted),
    ]

    do {
      _ = try await AuthSessionManager.shared.getSession()

      let row: MessagingThreadUserStateRow =
        try await supabase
        .rpc("set_thread_muted", params: params)
        .single()
        .execute()
        .value

      return row.toFriendThreadState()
    } catch let error as PostgrestError {
      throw mapRPCError(error)
    } catch let error as AuthError {
      throw mapRPCError(error)
    } catch let error as DecodingError {
      throw FriendsMessagingServiceError.decodingError(underlying: error)
    } catch {
      throw FriendsMessagingServiceError.networkError(underlying: error)
    }
  }

  func fetchUnreadDirectMessageCount(userId: String) async throws -> Int {
    let params: [String: AnyJSON] = [
      "p_user_id": .string(userId)
    ]

    do {
      _ = try await AuthSessionManager.shared.getSession()

      let count: Int =
        try await supabase
        .rpc("get_unread_direct_message_count", params: params)
        .execute()
        .value

      return max(0, count)
    } catch let error as PostgrestError {
      throw mapRPCError(error)
    } catch let error as AuthError {
      throw mapRPCError(error)
    } catch let error as DecodingError {
      throw FriendsMessagingServiceError.decodingError(underlying: error)
    } catch {
      throw FriendsMessagingServiceError.networkError(underlying: error)
    }
  }

  func fetchThreadSummary(threadId: String) async throws -> FriendThread {
    let params: [String: AnyJSON] = [
      "p_thread_id": .string(threadId)
    ]

    do {
      _ = try await AuthSessionManager.shared.getSession()

      let row: MessagingThreadSummaryRow =
        try await supabase
        .rpc("get_thread_summary", params: params)
        .single()
        .execute()
        .value

      return row.toFriendThread()
    } catch let error as PostgrestError {
      throw mapRPCError(error)
    } catch let error as AuthError {
      throw mapRPCError(error)
    } catch let error as DecodingError {
      throw FriendsMessagingServiceError.decodingError(underlying: error)
    } catch {
      throw FriendsMessagingServiceError.networkError(underlying: error)
    }
  }

  func fetchThreadState(threadId: String, userId: String) async throws -> FriendThreadState? {
    let response: [MessagingThreadUserStateRow] =
      try await supabase
      .from("thread_user_state")
      .select()
      .eq("thread_id", value: threadId)
      .eq("user_id", value: userId)
      .limit(1)
      .execute()
      .value

    return response.first?.toFriendThreadState()
  }

  func fetchMessagePayload(messageId: String) async throws -> FriendMessage {
    let params: [String: AnyJSON] = [
      "p_message_id": .string(messageId)
    ]

    do {
      _ = try await AuthSessionManager.shared.getSession()

      let row: MessagingMessageRow =
        try await supabase
        .rpc("get_message_payload", params: params)
        .single()
        .execute()
        .value

      return row.toFriendMessage()
    } catch let error as PostgrestError {
      throw mapRPCError(error)
    } catch let error as AuthError {
      throw mapRPCError(error)
    } catch let error as DecodingError {
      throw FriendsMessagingServiceError.decodingError(underlying: error)
    } catch {
      throw FriendsMessagingServiceError.networkError(underlying: error)
    }
  }

  func toggleMessageReaction(messageId: String, emoji: String) async throws -> FriendMessage {
    let params: [String: AnyJSON] = [
      "p_message_id": .string(messageId),
      "p_emoji": .string(emoji),
    ]

    do {
      _ = try await AuthSessionManager.shared.getSession()

      let row: MessagingMessageRow =
        try await supabase
        .rpc("toggle_message_reaction", params: params)
        .single()
        .execute()
        .value

      return row.toFriendMessage()
    } catch let error as PostgrestError {
      throw mapRPCError(error)
    } catch let error as AuthError {
      throw mapRPCError(error)
    } catch let error as DecodingError {
      throw FriendsMessagingServiceError.decodingError(underlying: error)
    } catch {
      throw FriendsMessagingServiceError.networkError(underlying: error)
    }
  }

  func createAbuseReport(
    threadId: String,
    reportedUserId: String,
    messageId: String?,
    reason: FriendAbuseReportReason
  ) async throws {
    let params: [String: AnyJSON] = [
      "p_thread_id": .string(threadId),
      "p_reported_user_id": .string(reportedUserId),
      "p_message_id": messageId.map(AnyJSON.string) ?? .null,
      "p_reason": .string(reason.rawValue),
      "p_note": .null,
    ]

    do {
      _ = try await AuthSessionManager.shared.getSession()

      _ =
        try await supabase
        .rpc("create_abuse_report", params: params)
        .execute()
    } catch let error as PostgrestError {
      throw mapRPCError(error)
    } catch let error as AuthError {
      throw mapRPCError(error)
    } catch let error as DecodingError {
      throw FriendsMessagingServiceError.decodingError(underlying: error)
    } catch {
      throw FriendsMessagingServiceError.networkError(underlying: error)
    }
  }

  func blockUserPair(otherUserId: String) async throws {
    let params: [String: AnyJSON] = [
      "p_other_user_id": .string(otherUserId)
    ]

    do {
      _ = try await AuthSessionManager.shared.getSession()

      _ =
        try await supabase
        .rpc("block_user_pair", params: params)
        .execute()
    } catch let error as PostgrestError {
      throw mapRPCError(error)
    } catch let error as AuthError {
      throw mapRPCError(error)
    } catch let error as DecodingError {
      throw FriendsMessagingServiceError.decodingError(underlying: error)
    } catch {
      throw FriendsMessagingServiceError.networkError(underlying: error)
    }
  }

  func uploadImageAttachment(threadId: String, image: ImageAttachment) async throws
    -> FriendOutgoingAttachment
  {
    let session = try await AuthSessionManager.shared.getSession()
    let path =
      "\(threadId)/\(session.normalizedUserId)/\(image.id).\(fileExtension(for: image.mediaType))"

    do {
      try await supabase.storage
        .from(storageBucket)
        .upload(
          path,
          data: image.data,
          options: FileOptions(
            cacheControl: "3600",
            contentType: image.mediaType,
            upsert: false
          )
        )

      let dimensions = imageDimensions(from: image.data)
      return FriendOutgoingAttachment(
        attachmentId: image.id,
        storagePath: path,
        mimeType: image.mediaType,
        byteSize: Int64(image.data.count),
        width: dimensions.width,
        height: dimensions.height
      )
    } catch {
      throw FriendsMessagingServiceError.networkError(underlying: error)
    }
  }

  func downloadAttachmentData(path: String) async throws -> Data {
    let session = try await AuthSessionManager.shared.getSession()
    var request = URLRequest(url: authenticatedStorageURL(bucket: storageBucket, path: path))
    request.httpMethod = "GET"
    request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue(APIConfiguration.supabaseAnonKey, forHTTPHeaderField: "apikey")

    do {
      let (data, response) = try await urlSession.data(for: request)
      guard let httpResponse = response as? HTTPURLResponse else {
        throw FriendsMessagingServiceError.networkError(underlying: URLError(.badServerResponse))
      }

      guard (200...299).contains(httpResponse.statusCode) else {
        throw FriendsMessagingServiceError.httpError(
          statusCode: httpResponse.statusCode,
          message: String(data: data, encoding: .utf8)
        )
      }

      return data
    } catch let error as FriendsMessagingServiceError {
      throw error
    } catch {
      throw FriendsMessagingServiceError.networkError(underlying: error)
    }
  }

  private func mapRPCError(_ error: Error) -> FriendsMessagingServiceError {
    if error is AuthError {
      return .notAuthenticated
    }

    if let postgrestError = error as? PostgrestError {
      let message = postgrestError.message
      let lowercasedMessage = message.lowercased()
      let code = (postgrestError.code ?? "").uppercased()

      if code == "PGRST301"
        || lowercasedMessage.contains("jwt")
        || lowercasedMessage.contains("unauthorized")
      {
        return .notAuthenticated
      }

      return .httpError(statusCode: 400, message: message)
    }

    if let decodingError = error as? DecodingError {
      return .decodingError(underlying: decodingError)
    }

    logger.error("Friends messaging RPC failed: \(error.localizedDescription)")
    return .networkError(underlying: error)
  }

  private func fileExtension(for mimeType: String) -> String {
    switch mimeType {
    case "image/webp":
      return "webp"
    case "image/heic":
      return "heic"
    case "image/heif":
      return "heif"
    case "image/png":
      return "png"
    default:
      return "jpg"
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

  private func authenticatedStorageURL(bucket: String, path: String) -> URL {
    var url = APIConfiguration.supabaseURL
      .appendingPathComponent("storage")
      .appendingPathComponent("v1")
      .appendingPathComponent("object")
      .appendingPathComponent("authenticated")
      .appendingPathComponent(bucket)

    for component in path.split(separator: "/") {
      url.appendPathComponent(String(component))
    }

    return url
  }
}

extension FriendsMessagingService: FriendsMessagingServiceProviding {}

private struct MessagingThreadSummaryRow: Decodable {
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
  let lastMessageAt: Date?
  let lastMessageBody: String?
  let lastMessagePreviewKind: String?
  let lastMessageHasImage: Bool
  let unreadCount: Int
  let muted: Bool
  let createdAt: Date

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
      lastMessageAt: lastMessageAt,
      lastMessageBody: lastMessageBody,
      lastMessagePreviewKind: lastMessagePreviewKind.flatMap(FriendLastMessagePreviewKind.init),
      lastMessageHasImage: lastMessageHasImage,
      unreadCount: unreadCount,
      muted: muted,
      createdAt: createdAt
    )
  }

  private static func encode(_ value: AnyJSON?) -> Data? {
    guard let value else { return nil }
    return try? JSONEncoder().encode(value)
  }
}

private struct MessagingMessageRow: Decodable {
  let id: String
  let threadId: String
  let senderUserId: String
  let messageType: String
  let body: String?
  let clientId: String
  let replyToMessageId: String?
  let createdAt: Date
  let editedAt: Date?
  let deletedAt: Date?
  let metadata: AnyJSON?
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
      createdAt: createdAt,
      editedAt: editedAt,
      deletedAt: deletedAt,
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

private struct MessagingReactionRow: Decodable {
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

private struct MessagingAttachmentRow: Decodable {
  let id: String
  let attachmentIndex: Int
  let kind: String
  let storageBucket: String
  let storagePath: String
  let mimeType: String
  let byteSize: Int64
  let width: Int?
  let height: Int?
  let createdAt: Date

  enum CodingKeys: String, CodingKey {
    case id
    case attachmentIndex = "attachment_index"
    case kind
    case storageBucket = "storage_bucket"
    case storagePath = "storage_path"
    case mimeType = "mime_type"
    case byteSize = "byte_size"
    case width
    case height
    case createdAt = "created_at"
  }

  func toFriendAttachment() -> FriendMessageAttachment {
    FriendMessageAttachment(
      id: id,
      attachmentIndex: attachmentIndex,
      kind: FriendMessageAttachmentKind(rawValue: kind) ?? .image,
      storageBucket: storageBucket,
      storagePath: storagePath,
      mimeType: mimeType,
      byteSize: byteSize,
      width: width,
      height: height,
      createdAt: createdAt
    )
  }
}

struct MessagingThreadUserStateRow: Decodable {
  let threadId: String
  let userId: String
  let lastReadMessageId: String?
  let lastReadAt: Date?
  let muted: Bool
  let updatedAt: Date

  enum CodingKeys: String, CodingKey {
    case threadId = "thread_id"
    case userId = "user_id"
    case lastReadMessageId = "last_read_message_id"
    case lastReadAt = "last_read_at"
    case muted
    case updatedAt = "updated_at"
  }

  func toFriendThreadState() -> FriendThreadState {
    FriendThreadState(
      threadId: threadId,
      userId: userId,
      lastReadMessageId: lastReadMessageId,
      lastReadAt: lastReadAt,
      muted: muted,
      updatedAt: updatedAt
    )
  }
}
