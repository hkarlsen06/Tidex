import Auth
import Foundation
import os.log
import Supabase
import UIKit

private let logger = Logger(subsystem: "com.tidex.app", category: "FriendsMessagingService")

@MainActor
protocol FriendsMessagingServiceProviding: AnyObject {
  func getOrCreateDirectThread(otherUserId: String) async throws -> FriendThread
  func listMyThreads(limit: Int, before cursor: FriendThreadCursor?) async throws -> [FriendThread]
  func fetchInboxSyncSnapshotV2(limit: Int, before cursor: FriendThreadCursor?) async throws
    -> FriendInboxSyncSnapshot
  func listInboxEventsV2(afterVersion: Int64, limit: Int) async throws -> FriendInboxSyncEventsPage
  func listThreadMessages(threadId: String, limit: Int, before cursor: FriendMessageCursor?)
    async throws -> [FriendMessage]
  func listThreadMessagesV2(threadId: String, limit: Int, before cursor: FriendMessageCursor?)
    async throws -> FriendThreadMessagesPage
  func fetchThreadSyncSnapshotV2(threadId: String, messageLimit: Int) async throws
    -> FriendThreadSyncSnapshot
  func listThreadEventsV2(threadId: String, afterVersion: Int64, limit: Int) async throws
    -> FriendThreadSyncEventsPage
  func listThreadStates(threadId: String) async throws -> [FriendThreadState]
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
  func queueThreadTypingNotification(threadId: String) async throws -> Bool
  func fetchUnreadDirectMessageCount(userId: String) async throws -> Int
  func fetchThreadSummary(threadId: String) async throws -> FriendThread
  func fetchThreadState(threadId: String, userId: String) async throws -> FriendThreadState?
  func fetchMessagePayload(messageId: String) async throws -> FriendMessage
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
      return String(localized: .commonErrorNotAuthenticated)

    case .networkError(let error):
      return String(localized: .commonErrorNetwork(error.localizedDescription))

    case .decodingError:
      return String(localized: .commonErrorUnexpectedResponse)

    case .httpError(_, let message):
      return message ?? String(localized: .commonErrorGeneric)
    }
  }
}

@MainActor
// swiftlint:disable:next type_body_length
final class FriendsMessagingService {
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

  func fetchInboxSyncSnapshotV2(
    limit: Int = 30,
    before cursor: FriendThreadCursor? = nil
  ) async throws -> FriendInboxSyncSnapshot {
    var params: [String: AnyJSON] = [
      "p_limit": .integer(limit)
    ]

    if let cursor {
      params["p_before_last_message_at"] = .string(cursor.lastMessageAt.toISO8601String())
      params["p_before_thread_id"] = .string(cursor.threadId)
    }

    do {
      _ = try await AuthSessionManager.shared.getSession()

      let payload: MessagingInboxSyncSnapshotV2Row =
        try await supabase
        .rpc("get_inbox_sync_snapshot_v2", params: params)
        .single()
        .execute()
        .value

      return payload.toFriendInboxSyncSnapshot()
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

  func listInboxEventsV2(
    afterVersion: Int64,
    limit: Int = 100
  ) async throws -> FriendInboxSyncEventsPage {
    let params: [String: AnyJSON] = [
      "p_after_version": .integer(Int(afterVersion)),
      "p_limit": .integer(limit),
    ]

    do {
      _ = try await AuthSessionManager.shared.getSession()

      let payload: MessagingInboxSyncEventsPageV2Row =
        try await supabase
        .rpc("list_inbox_events_v2", params: params)
        .single()
        .execute()
        .value

      return try payload.toFriendInboxSyncEventsPage()
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

  func listThreadMessagesV2(
    threadId: String,
    limit: Int = 50,
    before cursor: FriendMessageCursor? = nil
  ) async throws -> FriendThreadMessagesPage {
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

      let payload: MessagingThreadMessagesPageV2Row =
        try await supabase
        .rpc("list_thread_messages_v2", params: params)
        .single()
        .execute()
        .value

      return payload.toFriendThreadMessagesPage()
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

  func fetchThreadSyncSnapshotV2(
    threadId: String,
    messageLimit: Int = 50
  ) async throws -> FriendThreadSyncSnapshot {
    let params: [String: AnyJSON] = [
      "p_thread_id": .string(threadId),
      "p_message_limit": .integer(messageLimit),
    ]

    do {
      _ = try await AuthSessionManager.shared.getSession()

      let payload: MessagingThreadSyncSnapshotV2Row =
        try await supabase
        .rpc("get_thread_sync_snapshot_v2", params: params)
        .single()
        .execute()
        .value

      return payload.toFriendThreadSyncSnapshot()
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

  func listThreadEventsV2(
    threadId: String,
    afterVersion: Int64,
    limit: Int = 100
  ) async throws -> FriendThreadSyncEventsPage {
    let params: [String: AnyJSON] = [
      "p_thread_id": .string(threadId),
      "p_after_version": .integer(Int(afterVersion)),
      "p_limit": .integer(limit),
    ]

    do {
      _ = try await AuthSessionManager.shared.getSession()

      let payload: MessagingThreadSyncEventsPageV2Row =
        try await supabase
        .rpc("list_thread_events_v2", params: params)
        .single()
        .execute()
        .value

      return try payload.toFriendThreadSyncEventsPage()
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

  func listThreadStates(threadId: String) async throws -> [FriendThreadState] {
    do {
      _ = try await AuthSessionManager.shared.getSession()

      let response: [MessagingThreadUserStateRow] =
        try await supabase
        .from("thread_user_state")
        .select()
        .eq("thread_id", value: threadId)
        .execute()
        .value

      return response.map { $0.toFriendThreadState() }
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

  func queueThreadTypingNotification(threadId: String) async throws -> Bool {
    let params: [String: AnyJSON] = [
      "p_thread_id": .string(threadId)
    ]

    do {
      _ = try await AuthSessionManager.shared.getSession()

      return try await supabase
        .rpc("queue_thread_typing_notification", params: params)
        .execute()
        .value as Bool
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

  func fetchMessageSyncPayloadV2(messageId: String) async throws -> FriendMessage {
    let params: [String: AnyJSON] = [
      "p_message_id": .string(messageId)
    ]

    do {
      _ = try await AuthSessionManager.shared.getSession()

      let row: MessagingMessageRow =
        try await supabase
        .rpc("get_message_sync_payload_v2", params: params)
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

  func toggleMessageReaction(
    messageId: String,
    emoji: String,
    attachmentId: String? = nil
  ) async throws -> FriendMessage {
    var params: [String: AnyJSON] = [
      "p_message_id": .string(messageId),
      "p_emoji": .string(emoji),
    ]
    if let attachmentId {
      params["p_attachment_id"] = .string(attachmentId)
    }

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
    } catch {
      // The path is unique per attachment. A duplicate means an earlier attempt uploaded
      // it before the send RPC failed, so the retry can reuse it. upsert: true would need
      // an UPDATE policy on storage.objects that this bucket doesn't have.
      if let failure = Self.attachmentUploadFailure(error) {
        throw failure
      }
    }

    let dimensions = imageDimensions(from: image.data)
    return FriendOutgoingAttachment(
      attachmentId: image.id,
      storagePath: path,
      mimeType: image.mediaType,
      byteSize: Int64(image.data.count),
      width: dimensions.width,
      height: dimensions.height
    )
  }

  /// Maps an attachment upload error. Returns nil when the object already exists.
  /// Only transport errors become `.networkError`, so server rejections reach the
  /// failed state instead of waiting for the network forever.
  nonisolated static func attachmentUploadFailure(_ error: Error) -> Error? {
    if let storageError = error as? StorageError {
      if storageError.statusCode == "409" || storageError.error?.lowercased() == "duplicate" {
        return nil
      }
      return FriendsMessagingServiceError.httpError(
        statusCode: Int(storageError.statusCode ?? "") ?? 0,
        message: storageError.message
      )
    }
    if error is URLError {
      return FriendsMessagingServiceError.networkError(underlying: error)
    }
    return error
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

  static func encode(_ value: AnyJSON?) -> Data? {
    guard let value else { return nil }
    return try? JSONEncoder().encode(value)
  }
}

private struct MessagingInboxSyncSnapshotV2Row: Decodable {
  let threads: [MessagingThreadSummaryRow]
  let unreadDirectMessageCount: Int
  let nextCursor: MessagingThreadCursorRow?
  let snapshotVersion: Int64
  let retainedFromVersion: Int64
  let hasMore: Bool

  enum CodingKeys: String, CodingKey {
    case threads
    case unreadDirectMessageCount = "unread_direct_message_count"
    case nextCursor = "next_cursor"
    case snapshotVersion = "snapshot_version"
    case retainedFromVersion = "retained_from_version"
    case hasMore = "has_more"
  }

  func toFriendInboxSyncSnapshot() -> FriendInboxSyncSnapshot {
    FriendInboxSyncSnapshot(
      threads: threads.map { $0.toFriendThread() },
      unreadDirectMessageCount: unreadDirectMessageCount,
      nextCursor: nextCursor?.toFriendThreadCursor(),
      snapshotVersion: snapshotVersion,
      retainedFromVersion: retainedFromVersion,
      hasMore: hasMore
    )
  }
}

private struct MessagingInboxSyncEventsPageV2Row: Decodable {
  let requiresSnapshot: Bool
  let latestVersion: Int64
  let retainedFromVersion: Int64
  let hasMore: Bool
  let events: [MessagingInboxSyncEventRow]

  enum CodingKeys: String, CodingKey {
    case requiresSnapshot = "requires_snapshot"
    case latestVersion = "latest_version"
    case retainedFromVersion = "retained_from_version"
    case hasMore = "has_more"
    case events
  }

  func toFriendInboxSyncEventsPage() throws -> FriendInboxSyncEventsPage {
    try FriendInboxSyncEventsPage(
      requiresSnapshot: requiresSnapshot,
      latestVersion: latestVersion,
      retainedFromVersion: retainedFromVersion,
      hasMore: hasMore,
      events: events.map { try $0.toFriendInboxSyncEvent() }
    )
  }
}

private struct MessagingThreadSyncSnapshotV2Row: Decodable {
  let thread: MessagingThreadCoreRow
  let viewerState: MessagingThreadSyncViewerStateRow
  let counterpartState: MessagingThreadCounterpartPresenceRow?
  let messages: [MessagingMessageRow]
  let nextCursor: MessagingMessageCursorRow?
  let snapshotVersion: Int64
  let retainedFromVersion: Int64
  let hasMore: Bool

  enum CodingKeys: String, CodingKey {
    case thread
    case viewerState = "viewer_state"
    case counterpartState = "counterpart_state"
    case messages
    case nextCursor = "next_cursor"
    case snapshotVersion = "snapshot_version"
    case retainedFromVersion = "retained_from_version"
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
      createdAt: thread.createdAt
    )

    return FriendThreadSyncSnapshot(
      thread: friendThread,
      viewerState: viewerState.toFriendThreadState(),
      counterpartPresence: counterpartPresence,
      messages: friendMessages,
      nextCursor: nextCursor?.toFriendMessageCursor(),
      snapshotVersion: snapshotVersion,
      retainedFromVersion: retainedFromVersion,
      hasMore: hasMore
    )
  }
}

private struct MessagingThreadSyncEventsPageV2Row: Decodable {
  let requiresSnapshot: Bool
  let latestVersion: Int64
  let retainedFromVersion: Int64
  let hasMore: Bool
  let events: [MessagingThreadSyncEventRow]

  enum CodingKeys: String, CodingKey {
    case requiresSnapshot = "requires_snapshot"
    case latestVersion = "latest_version"
    case retainedFromVersion = "retained_from_version"
    case hasMore = "has_more"
    case events
  }

  func toFriendThreadSyncEventsPage() throws -> FriendThreadSyncEventsPage {
    try FriendThreadSyncEventsPage(
      requiresSnapshot: requiresSnapshot,
      latestVersion: latestVersion,
      retainedFromVersion: retainedFromVersion,
      hasMore: hasMore,
      events: events.map { try $0.toFriendThreadSyncEvent() }
    )
  }
}

private struct MessagingThreadMessagesPageV2Row: Decodable {
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

private struct MessagingThreadCoreRow: Decodable {
  let id: String
  let kind: String
  let title: String?
  let avatarUrl: String?
  let metadata: AnyJSON?
  let createdAt: Date

  enum CodingKeys: String, CodingKey {
    case id
    case kind
    case title
    case avatarUrl = "avatar_url"
    case metadata
    case createdAt = "created_at"
  }
}

private struct MessagingThreadSyncViewerStateRow: Decodable {
  let threadId: String
  let userId: String
  let lastReadMessageId: String?
  let lastReadAt: Date?
  let unreadCount: Int
  let muted: Bool
  let updatedAt: Date

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
      lastReadAt: lastReadAt,
      muted: muted,
      updatedAt: updatedAt
    )
  }
}

private struct MessagingThreadCounterpartPresenceRow: Decodable {
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

private struct MessagingThreadCursorRow: Decodable {
  let beforeLastMessageAt: Date
  let beforeThreadId: String

  enum CodingKeys: String, CodingKey {
    case beforeLastMessageAt = "before_last_message_at"
    case beforeThreadId = "before_thread_id"
  }

  func toFriendThreadCursor() -> FriendThreadCursor {
    FriendThreadCursor(lastMessageAt: beforeLastMessageAt, threadId: beforeThreadId)
  }
}

private struct MessagingInboxSyncEventRow: Decodable {
  let id: String
  let version: Int64
  let threadId: String?
  let eventType: String
  let payload: AnyJSON?

  enum CodingKeys: String, CodingKey {
    case id
    case version
    case threadId = "thread_id"
    case eventType = "event_type"
    case payload
  }

  func toFriendInboxSyncEvent() throws -> FriendInboxSyncEvent {
    guard let resolvedEventType = FriendInboxSyncEvent.EventType(rawValue: eventType) else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: [], debugDescription: "Unsupported inbox event type: \(eventType)")
      )
    }

    let thread: FriendThread? =
      if resolvedEventType == .threadUpserted, let payload {
        try Self.decode(payload, as: MessagingThreadSummaryRow.self).toFriendThread()
      } else {
        nil
      }

    return FriendInboxSyncEvent(
      id: id,
      version: version,
      threadId: threadId,
      eventType: resolvedEventType,
      thread: thread
    )
  }

  private static func decode<T: Decodable>(_ value: AnyJSON, as type: T.Type) throws -> T {
    let data: Data = try kCanonicalJSONEncoder.encode(value)
    return try kSyncJSONDecoder.decode(type, from: data)
  }
}

private struct MessagingThreadSyncEventRow: Decodable {
  let id: String
  let version: Int64
  let eventType: String
  let payload: AnyJSON?

  enum CodingKeys: String, CodingKey {
    case id
    case version
    case eventType = "event_type"
    case payload
  }

  func toFriendThreadSyncEvent() throws -> FriendThreadSyncEvent {
    guard let resolvedEventType = FriendThreadSyncEvent.EventType(rawValue: eventType) else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: [], debugDescription: "Unsupported thread event type: \(eventType)")
      )
    }

    let message: FriendMessage?
    let deletedMessageId: String?

    switch resolvedEventType {
    case .messageUpserted:
      guard let payload else {
        throw DecodingError.valueNotFound(
          AnyJSON.self,
          .init(codingPath: [], debugDescription: "Missing message payload for message_upserted")
        )
      }
      message = try Self.decode(payload, as: MessagingMessageRow.self).toFriendMessage()
      deletedMessageId = nil

    case .messageDeleted:
      guard let payload else {
        throw DecodingError.valueNotFound(
          AnyJSON.self,
          .init(codingPath: [], debugDescription: "Missing tombstone payload for message_deleted")
        )
      }
      let tombstone = try Self.decode(payload, as: MessagingDeletedMessageRow.self)
      message = nil
      deletedMessageId = tombstone.id
    }

    return FriendThreadSyncEvent(
      id: id,
      version: version,
      eventType: resolvedEventType,
      message: message,
      deletedMessageId: deletedMessageId
    )
  }

  private static func decode<T: Decodable>(_ value: AnyJSON, as type: T.Type) throws -> T {
    let data: Data = try kCanonicalJSONEncoder.encode(value)
    return try kSyncJSONDecoder.decode(type, from: data)
  }
}

private struct MessagingMessageCursorRow: Decodable {
  let beforeCreatedAt: Date
  let beforeMessageId: String

  enum CodingKeys: String, CodingKey {
    case beforeCreatedAt = "before_created_at"
    case beforeMessageId = "before_message_id"
  }

  func toFriendMessageCursor() -> FriendMessageCursor {
    FriendMessageCursor(createdAt: beforeCreatedAt, messageId: beforeMessageId)
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

private struct MessagingDeletedMessageRow: Decodable {
  let id: String
  let threadId: String
  let deletedAt: Date

  enum CodingKeys: String, CodingKey {
    case id
    case threadId = "thread_id"
    case deletedAt = "deleted_at"
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
  let reactions: [MessagingReactionRow]?

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
    case reactions
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
      createdAt: createdAt,
      reactions: (reactions ?? []).map { $0.toFriendReaction() }
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
}  // swiftlint:disable:this file_length
