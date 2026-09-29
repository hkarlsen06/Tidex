import SwiftUI

/// The conversation drawn with the chat bubbles, as the reporter saw it: their messages on the right.
struct AdminReportConversation: View {
  let messages: [FriendMessage]
  let report: AdminReport
  let reportedAvatarUrl: String?

  var body: some View {
    VStack(spacing: 0) {
      ForEach(messages.indices, id: \.self) { index in
        row(at: index)
      }
    }
    .padding(.vertical, Spacing.sm)
  }

  private func row(at index: Int) -> some View {
    let message = messages[index]
    let previous = index > 0 ? messages[index - 1] : nil
    let next = index + 1 < messages.count ? messages[index + 1] : nil
    let isCurrentUser = message.senderUserId == report.reporterUserId
    let groupContext = FriendsChatMessageGrouping.context(
      for: message, previous: previous, next: next, viewerUserId: report.reporterUserId)
    return FriendsChatMessageRowContent(
      message: message,
      quotedPreview: quotedPreview(for: message),
      isCurrentUser: isCurrentUser,
      groupContext: groupContext,
      counterpartAvatarUrl: reportedAvatarUrl,
      counterpartAvatarInitials: FriendsChatMessageGrouping.initials(
        from: report.reportedDisplayName),
      isHighlighted: false,
      highlightedAttachmentId: nil,
      visibleMessageText: message.normalizedBody ?? "",
      senderFirstName: nil,
      separatorDate: Self.startsDay(message, after: previous) ? message.createdAt : nil,
      showsSenderLabel: false,
      showsTimestamp: FriendsThreadMessageStatusResolver.shouldShowTimestamp(
        for: message, isCurrentUser: isCurrentUser, groupContext: groupContext,
        messageStatus: nil),
      messageStatus: nil,
      stackingOrder: Double(messages.count - index),
      onRetry: {},
      onShowReactionMenu: { _ in },
      onTapQuotedMessage: {},
      onOpenImageAttachment: { _ in },
      onImageReactionPressChanged: { _, _ in },
      onPrepareImageReaction: { _ in },
      onOpenShiftSnapshot: { _ in },
      onReplySwipe: nil,
      timestampRevealOffset: .constant(0),
      messageFrame: nil
    )
    // Deleted messages stay visible here as evidence, dimmed.
    .opacity(message.deletedAt == nil ? 1 : 0.45)
    .background(message.id == report.messageId ? Color.tidexError.opacity(0.25) : Color.clear)
  }

  private static func startsDay(_ message: FriendMessage, after previous: FriendMessage?) -> Bool {
    guard let previous else { return true }
    return !Calendar.current.isDate(previous.createdAt, inSameDayAs: message.createdAt)
  }

  private func quotedPreview(for message: FriendMessage) -> FriendsChatReplyPreviewModel? {
    guard let quoted = messages.first(where: { $0.id == message.replyToMessageId }) else {
      return nil
    }
    let name =
      quoted.senderUserId == report.reporterUserId
      ? report.reporterDisplayName : report.reportedDisplayName
    return FriendsChatReplyPreviewModel(senderName: name, message: quoted)
  }
}
