import ExyteChat
import Foundation
import SwiftUI
import UIKit

struct FriendsThreadMessageRowProjection {
  let message: FriendMessage
  let index: Int
  let isCurrentUser: Bool
  let groupContext: FriendsChatMessageGroupContext
  let messageStatus: FriendsChatMessageStatus?
  let shouldShowTimestamp: Bool
}

struct FriendsThreadChatProjection {
  struct Input: Equatable {
    let messages: [FriendMessage]
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
      messages: [FriendMessage],
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
      self.messages = messages
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

  // swiftlint:disable:next explicit_acl explicit_type_interface
  static let empty = Self(
    messages: [],
    exyteMessages: [],
    presentedMessageLookup: [:],
    presentedMessageIDs: [],
    presentedMessageIndexLookup: [:],
    imageAttachments: [],
    rowProjectionsByPresentedMessageID: [:],
    typingIndicatorJoinsPrevious: false
  )

  let messages: [FriendMessage]
  let exyteMessages: [ExyteChat.Message]
  let presentedMessageLookup: [String: FriendMessage]
  let presentedMessageIDs: [String]
  let presentedMessageIndexLookup: [String: Int]
  let imageAttachments: [FriendMessageAttachment]
  let rowProjectionsByPresentedMessageID: [String: FriendsThreadMessageRowProjection]
  let typingIndicatorJoinsPrevious: Bool

  // swiftlint:disable:next explicit_acl function_body_length
  static func make(input: Input) -> Self {
    guard !input.messages.isEmpty || input.showsTypingIndicator else {
      return empty
    }

    let latestOutgoingMessageId = FriendsThreadMessageStatusResolver.latestOutgoingMessageId(
      messages: input.messages,
      viewerUserId: input.viewerUserId
    )
    let readReceiptMessageId = FriendsThreadMessageStatusResolver.readReceiptMessageId(
      messages: input.messages,
      viewerUserId: input.viewerUserId,
      counterpartLastReadMessageId: input.counterpartLastReadMessageId,
      counterpartLastReadAt: input.counterpartLastReadAt
    )
    var exyteMessages = FriendsThreadExyteMessageFactory.makeMessages(
      messages: input.messages,
      conversation: .init(
        viewerUserId: input.viewerUserId,
        currentUserDisplayName: input.currentUserDisplayName,
        counterpartDisplayName: input.counterpartDisplayName,
        counterpartAvatarUrl: input.counterpartAvatarUrl,
        quotedMessagesById: input.quotedMessagesById,
        counterpartLastReadMessageId: input.counterpartLastReadMessageId,
        counterpartLastReadAt: input.counterpartLastReadAt,
        showsTypingIndicator: input.showsTypingIndicator,
        typingIndicatorCreatedAt: input.typingIndicatorCreatedAt,
        reactionAttachmentTargets: input.reactionAttachmentTargets
      )
    )

    var presentedMessageLookup: [String: FriendMessage] = [:]
    var presentedMessageIDs: [String] = []
    var presentedMessageIndexLookup: [String: Int] = [:]
    var rowProjectionsByPresentedMessageID: [String: FriendsThreadMessageRowProjection] = [:]
    presentedMessageLookup.reserveCapacity(input.messages.count)
    presentedMessageIDs.reserveCapacity(input.messages.count)
    presentedMessageIndexLookup.reserveCapacity(input.messages.count)
    rowProjectionsByPresentedMessageID.reserveCapacity(input.messages.count)

    let lastMessageIndex = input.messages.indices.last
    for index in input.messages.indices {
      let message = input.messages[index]
      let presentedMessageID = FriendsThreadMessagePresentationID.make(
        for: message,
        viewerUserId: input.viewerUserId
      )
      let previousMessage = index > input.messages.startIndex ? input.messages[index - 1] : nil
      let nextMessage =
        index < input.messages.index(before: input.messages.endIndex)
        ? input.messages[index + 1]
        : nil
      let baseGroupContext = FriendsChatMessageGrouping.context(
        for: message,
        previous: previousMessage,
        next: nextMessage,
        viewerUserId: input.viewerUserId
      )
      let groupContext =
        shouldJoinTypingIndicator(
          message: message,
          index: index,
          lastMessageIndex: lastMessageIndex,
          viewerUserId: input.viewerUserId,
          showsTypingIndicator: input.showsTypingIndicator
        )
        ? baseGroupContext.joiningNext()
        : baseGroupContext
      let isCurrentUser = message.senderUserId == input.viewerUserId
      let messageStatus = FriendsThreadMessageStatusResolver.status(
        for: message,
        viewerUserId: input.viewerUserId,
        latestOutgoingMessageId: latestOutgoingMessageId,
        readReceiptMessageId: readReceiptMessageId
      )

      // Neighbouring messages change the bubble shape without changing this row's own message.
      exyteMessages[index].triggerRedraw = FriendsThreadExyteMessageFactory.redrawToken(
        of: [AnyHashable(exyteMessages[index].triggerRedraw), AnyHashable(groupContext)]
      )

      presentedMessageIDs.append(presentedMessageID)
      presentedMessageLookup[presentedMessageID] = message
      presentedMessageIndexLookup[presentedMessageID] = index
      rowProjectionsByPresentedMessageID[presentedMessageID] = FriendsThreadMessageRowProjection(
        message: message,
        index: index,
        isCurrentUser: isCurrentUser,
        groupContext: groupContext,
        messageStatus: messageStatus,
        shouldShowTimestamp: FriendsThreadMessageStatusResolver.shouldShowTimestamp(
          for: message,
          isCurrentUser: isCurrentUser,
          groupContext: groupContext,
          messageStatus: messageStatus
        )
      )
    }

    return Self(
      messages: input.messages,
      exyteMessages: exyteMessages,
      presentedMessageLookup: presentedMessageLookup,
      presentedMessageIDs: presentedMessageIDs,
      presentedMessageIndexLookup: presentedMessageIndexLookup,
      imageAttachments: FriendsThreadImageGalleryResolver.imageAttachments(
        messages: input.messages),
      rowProjectionsByPresentedMessageID: rowProjectionsByPresentedMessageID,
      typingIndicatorJoinsPrevious: input.messages.last.map {
        shouldJoinTypingIndicator(
          message: $0,
          index: lastMessageIndex,
          lastMessageIndex: lastMessageIndex,
          viewerUserId: input.viewerUserId,
          showsTypingIndicator: input.showsTypingIndicator
        )
      } ?? false
    )
  }

  private static func shouldJoinTypingIndicator(
    message: FriendMessage,
    index: Int?,
    lastMessageIndex: Int?,
    viewerUserId: String,
    showsTypingIndicator: Bool,
    now: Date = .now
  ) -> Bool {
    guard showsTypingIndicator else {
      return false
    }
    guard message.senderUserId != viewerUserId else {
      return false
    }
    guard message.messageType == .user, message.deletedAt == nil else {
      return false
    }
    guard index == lastMessageIndex else {
      return false
    }
    return now.timeIntervalSince(message.createdAt) <= FriendsChatMessageGrouping.maximumGap
  }
}

@MainActor
final class FriendsThreadChatProjectionStore {
  private var cachedInput: FriendsThreadChatProjection.Input?
  private var cachedProjection: FriendsThreadChatProjection = .empty

  func projection(for input: FriendsThreadChatProjection.Input) -> FriendsThreadChatProjection {
    guard cachedInput != input else {
      return cachedProjection
    }
    cachedInput = input
    cachedProjection = FriendsThreadChatProjection.make(input: input)
    return cachedProjection
  }
}

enum FriendsThreadExyteHighlightRedrawResolver {
  private static let redrawMarker = "\u{2060}"

  static func applyingHighlightMarker(
    to messages: [ExyteChat.Message],
    highlightedPresentedMessageID: String?
  ) -> [ExyteChat.Message] {
    messages.map { message in
      guard message.id == highlightedPresentedMessageID else {
        return message
      }
      var highlightedMessage = message
      highlightedMessage.attributedText += AttributedString(redrawMarker)
      return highlightedMessage
    }
  }

  static func isHighlighted(_ message: ExyteChat.Message) -> Bool {
    String(message.attributedText.characters).hasSuffix(redrawMarker)
  }

  static func visibleText(for message: ExyteChat.Message) -> String {
    let text = String(message.attributedText.characters)
    guard isHighlighted(message) else {
      return text
    }
    return String(text.dropLast(redrawMarker.count))
  }
}

enum FriendsThreadHighlightRefreshResolver {
  static func shouldRefreshRows(
    force: Bool,
    highlightedPresentedMessageID: String?,
    lastHighlightedPresentedMessageID: String?
  ) -> Bool {
    force || highlightedPresentedMessageID != lastHighlightedPresentedMessageID
  }
}