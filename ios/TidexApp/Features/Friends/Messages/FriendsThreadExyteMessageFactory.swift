import ExyteChat
import Foundation
import SwiftUI
import UIKit

enum FriendsThreadMessagePresentationID {
  static func make(for message: FriendMessage, viewerUserId: String) -> String {
    message.logicalRowIdentity(viewerUserId: viewerUserId)
  }
}

enum FriendsThreadExyteMessageFactory {
  static let typingIndicatorMessageID = "typing-indicator"

  struct ConversationContext {
    let viewerUserId: String
    let currentUserDisplayName: String
    let counterpartDisplayName: String
    let counterpartAvatarUrl: String?
    let quotedMessagesById: [String: FriendMessage]
    let counterpartLastReadMessageId: String?
    let counterpartLastReadAt: Date?
    let showsTypingIndicator: Bool
    let typingIndicatorCreatedAt: Date
    let reactionAttachmentTargets: [String: String]

    init(
      viewerUserId: String,
      currentUserDisplayName: String,
      counterpartDisplayName: String,
      counterpartAvatarUrl: String?,
      quotedMessagesById: [String: FriendMessage],
      counterpartLastReadMessageId: String?,
      counterpartLastReadAt: Date?,
      showsTypingIndicator: Bool,
      typingIndicatorCreatedAt: Date,
      reactionAttachmentTargets: [String: String] = [:]
    ) {
      self.viewerUserId = viewerUserId
      self.currentUserDisplayName = currentUserDisplayName
      self.counterpartDisplayName = counterpartDisplayName
      self.counterpartAvatarUrl = counterpartAvatarUrl
      self.quotedMessagesById = quotedMessagesById
      self.counterpartLastReadMessageId = counterpartLastReadMessageId
      self.counterpartLastReadAt = counterpartLastReadAt
      self.showsTypingIndicator = showsTypingIndicator
      self.typingIndicatorCreatedAt = typingIndicatorCreatedAt
      self.reactionAttachmentTargets = reactionAttachmentTargets
    }
  }

  struct Context {
    let messagesById: [String: FriendMessage]
    let viewerUserId: String
    let currentUserDisplayName: String
    let counterpartDisplayName: String
    let counterpartAvatarUrl: String?
    let latestOutgoingMessageId: String?
    let readReceiptMessageId: String?
    let reactionAttachmentTargets: [String: String]

    init(
      messagesById: [String: FriendMessage],
      viewerUserId: String,
      currentUserDisplayName: String,
      counterpartDisplayName: String,
      counterpartAvatarUrl: String?,
      latestOutgoingMessageId: String?,
      readReceiptMessageId: String?,
      reactionAttachmentTargets: [String: String] = [:]
    ) {
      self.messagesById = messagesById
      self.viewerUserId = viewerUserId
      self.currentUserDisplayName = currentUserDisplayName
      self.counterpartDisplayName = counterpartDisplayName
      self.counterpartAvatarUrl = counterpartAvatarUrl
      self.latestOutgoingMessageId = latestOutgoingMessageId
      self.readReceiptMessageId = readReceiptMessageId
      self.reactionAttachmentTargets = reactionAttachmentTargets
    }
  }

  static func makeMessages(messages: [FriendMessage], conversation: ConversationContext)
    -> [ExyteChat.Message]
  {
    let latestOutgoingMessageId = FriendsThreadMessageStatusResolver.latestOutgoingMessageId(
      messages: messages,
      viewerUserId: conversation.viewerUserId
    )
    let readReceiptMessageId = FriendsThreadMessageStatusResolver.readReceiptMessageId(
      messages: messages,
      viewerUserId: conversation.viewerUserId,
      counterpartLastReadMessageId: conversation.counterpartLastReadMessageId,
      counterpartLastReadAt: conversation.counterpartLastReadAt
    )
    let context = Context(
      messagesById: Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
        .merging(conversation.quotedMessagesById) { current, _ in current },
      viewerUserId: conversation.viewerUserId,
      currentUserDisplayName: conversation.currentUserDisplayName,
      counterpartDisplayName: conversation.counterpartDisplayName,
      counterpartAvatarUrl: conversation.counterpartAvatarUrl,
      latestOutgoingMessageId: latestOutgoingMessageId,
      readReceiptMessageId: readReceiptMessageId,
      reactionAttachmentTargets: conversation.reactionAttachmentTargets
    )

    var exyteMessages = messages.map { message in
      makeMessage(message, context: context)
    }

    if conversation.showsTypingIndicator {
      exyteMessages.append(
        makeTypingIndicatorMessage(
          context: context, createdAt: conversation.typingIndicatorCreatedAt))
    }

    return exyteMessages
  }

  static func makeMessage(_ message: FriendMessage, context: Context) -> ExyteChat.Message {
    let isCurrentUser = message.senderUserId == context.viewerUserId
    let user = ExyteChat.User(
      id: message.senderUserId,
      name: isCurrentUser ? context.currentUserDisplayName : context.counterpartDisplayName,
      avatarURL: isCurrentUser ? nil : URL(string: context.counterpartAvatarUrl ?? ""),
      isCurrentUser: isCurrentUser
    )

    let replyMessage = message.replyToMessageId
      .flatMap { context.messagesById[$0] }
      .map {
        makeReplyMessage(
          for: $0,
          viewerUserId: context.viewerUserId,
          currentUserDisplayName: context.currentUserDisplayName,
          counterpartDisplayName: context.counterpartDisplayName,
          counterpartAvatarUrl: context.counterpartAvatarUrl
        )
      }

    var exyteMessage = ExyteChat.Message(
      id: FriendsThreadMessagePresentationID.make(for: message, viewerUserId: context.viewerUserId),
      user: user,
      status: exyteStatus(
        for: message,
        viewerUserId: context.viewerUserId,
        latestOutgoingMessageId: context.latestOutgoingMessageId,
        readReceiptMessageId: context.readReceiptMessageId
      ),
      createdAt: message.createdAt,
      text: message.normalizedBody ?? "",
      attachments: [],
      giphyMediaId: exyteMenuMarker(for: message),
      reactions: exyteReactions(
        for: message,
        viewerUserId: context.viewerUserId,
        attachmentId: context.reactionAttachmentTargets[message.id]
      ),
      replyMessage: replyMessage
    )
    exyteMessage.triggerRedraw = redrawToken(for: message, context: context)
    return exyteMessage
  }

  private static func redrawToken(for message: FriendMessage, context: Context) -> UUID {
    redrawToken(
      of: RowRedrawKey(
        message: message,
        quotedMessage: message.replyToMessageId.flatMap { context.messagesById[$0] },
        reactionAttachmentId: context.reactionAttachmentTargets[message.id]
      )
    )
  }

  /// Everything the row renders from the full `FriendMessage` that the Exyte message does not carry.
  private struct RowRedrawKey: Hashable {
    let message: FriendMessage
    let quotedMessage: FriendMessage?
    let reactionAttachmentId: String?
  }

  /// A UUID that changes whenever `value` changes, so Exyte sees the row as updated. The hash is
  /// seeded per process, so compare tokens only within one run.
  static func redrawToken(of value: some Hashable) -> UUID {
    let bits = UInt64(bitPattern: Int64(value.hashValue))
    let bytes = (0..<8).map { UInt8(truncatingIfNeeded: bits >> ($0 * 8)) }
    return UUID(
      uuid: (
        bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
        0, 0, 0, 0, 0, 0, 0, 0
      )
    )
  }

  static func makeTypingIndicatorMessage(context: Context, createdAt: Date) -> ExyteChat.Message {
    ExyteChat.Message(
      id: typingIndicatorMessageID,
      user: ExyteChat.User(
        id: "typing-indicator-user",
        name: context.counterpartDisplayName,
        avatarURL: URL(string: context.counterpartAvatarUrl ?? ""),
        isCurrentUser: false
      ),
      status: nil,
      createdAt: createdAt,
      text: "",
      attachments: [],
      giphyMediaId: nil,
      reactions: [],
      replyMessage: nil
    )
  }

  private static func exyteMenuMarker(for message: FriendMessage) -> String? {
    guard message.shiftSnapshot != nil else {
      return nil
    }
    return FriendsThreadMessageMenuAction.shiftSnapshotForwardMarker
  }

  static func exyteReactions(
    for message: FriendMessage,
    viewerUserId: String,
    attachmentId: String? = nil
  ) -> [ExyteChat.Reaction] {
    let reactions =
      attachmentId
      .flatMap { attachmentId in
        message.attachments.first { $0.id == attachmentId }?.reactions
      } ?? message.reactions

    return reactions.compactMap { reaction in
      guard reaction.viewerHasReacted else {
        return nil
      }
      return ExyteChat.Reaction(
        user: ExyteChat.User(
          id: viewerUserId,
          name: "You",
          avatarURL: nil,
          isCurrentUser: true
        ),
        type: .emoji(reaction.emoji),
        status: .sent
      )
    }
  }

  private static func makeReplyMessage(
    for message: FriendMessage,
    viewerUserId: String,
    currentUserDisplayName: String,
    counterpartDisplayName: String,
    counterpartAvatarUrl: String?
  ) -> ExyteChat.ReplyMessage {
    let isCurrentUser = message.senderUserId == viewerUserId
    let user = ExyteChat.User(
      id: message.senderUserId,
      name: isCurrentUser ? currentUserDisplayName : counterpartDisplayName,
      avatarURL: isCurrentUser ? nil : URL(string: counterpartAvatarUrl ?? ""),
      isCurrentUser: isCurrentUser
    )

    return ExyteChat.ReplyMessage(
      id: FriendsThreadMessagePresentationID.make(for: message, viewerUserId: viewerUserId),
      user: user,
      createdAt: message.createdAt,
      text: message.normalizedBody ?? "",
      attachments: [],
      recording: nil
    )
  }

  private static func exyteStatus(
    for message: FriendMessage,
    viewerUserId: String,
    latestOutgoingMessageId: String?,
    readReceiptMessageId: String?
  ) -> ExyteChat.Message.Status? {
    switch FriendsThreadMessageStatusResolver.status(
      for: message,
      viewerUserId: viewerUserId,
      latestOutgoingMessageId: latestOutgoingMessageId,
      readReceiptMessageId: readReceiptMessageId
    ) {
    case .sending:
      return .sending

    case .delivered:
      return .delivered

    case .read:
      return .readBy([])

    case .failed:
      return .error(
        DraftMessage(
          id: FriendsThreadMessagePresentationID.make(for: message, viewerUserId: viewerUserId),
          text: message.normalizedBody ?? "",
          medias: [],
          giphyMedia: nil,
          recording: nil,
          replyMessage: nil,
          createdAt: message.createdAt
        )
      )

    case .none:
      return nil
    }
  }
}