import ExyteChat
import ImageIO
import SwiftUI
import UIKit

struct ChatShiftSnapshotCard: View {
  let snapshot: FriendShiftSnapshot
  let isCurrentUser: Bool
  var showsOwnerHeader = true
  var topInset: CGFloat = 0
  // swiftlint:disable:next explicit_acl
  var onTap: (() -> Void)?
  @State private var shouldSuppressNextTap: Bool = false

  private var ownerPrimaryTextColor: Color {
    .tidexTextMuted
  }

  @ViewBuilder
  var body: some View {
    if let onTap {
      cardContent
        .contentShape(Rectangle())
        .onLongPressGesture(
          minimumDuration: FriendsThreadAttachmentTapGuard.messageMenuRecognitionDuration,
          maximumDistance: 20,
          perform: {
            shouldSuppressNextTap = true
          },
          onPressingChanged: { _ in }
        )
        .onTapGesture {
          guard !shouldSuppressNextTap else {
            shouldSuppressNextTap = false
            return
          }
          onTap()
        }
        .accessibilityAddTraits(.isButton)
    } else {
      cardContent
    }
  }

  private var cardContent: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      if showsOwnerHeader {
        ownerHeader
          .padding(.horizontal, Spacing.sm)
          .frame(maxWidth: .infinity, alignment: isCurrentUser ? .trailing : .leading)
      }

      SharedShiftRow(
        shift: snapshot.renderableShift,
        isToday: snapshot.shiftDate == todayISO(),
        showEarnings: snapshot.includesEarnings,
        currency: snapshot.currency
      )
    }
    .padding(.top, topInset)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder
  private var ownerHeader: some View {
    HStack(alignment: .center, spacing: Spacing.xs) {
      if isCurrentUser {
        Spacer(minLength: 0)
        ownerName
        ownerAvatar
      } else {
        ownerAvatar
        ownerName
        Spacer(minLength: 0)
      }
    }
  }

  private var ownerAvatar: some View {
    AvatarView(
      url: snapshot.ownerAvatarUrl,
      initials: snapshot.ownerInitials,
      size: AvatarView.Size.small
    )
  }

  private var ownerName: some View {
    Text(snapshot.ownerFirstName)
      .font(.tidexCaptionStrong)
      .foregroundStyle(ownerPrimaryTextColor)
      .lineLimit(1)
  }
}

struct FriendsChatImageView: View {
  let messageId: String
  let attachment: FriendMessageAttachment
  let isCurrentUser: Bool
  let groupContext: FriendsChatMessageGroupContext
  let canOpenAttachment: Bool
  let canReact: Bool
  let isHighlighted: Bool
  let onOpenImageAttachment: (FriendMessageAttachment) -> Void
  let onShowReactionMenu: (String?) -> Void
  let onReactionPressChanged: (FriendMessageAttachment, Bool) -> Void
  let onPrepareReaction: (FriendMessageAttachment) -> Void

  @State private var shouldSuppressNextTap: Bool = false

  var body: some View {
    let onImageTap: (() -> Void)? = canOpenAttachment ? { handleImageTap() } : nil

    FriendsChatImageAttachmentCard(
      attachment: attachment,
      isCurrentUser: isCurrentUser,
      groupContext: groupContext,
      isHighlighted: isHighlighted,
      onTap: onImageTap
    )
    .highPriorityGesture(
      TapGesture(count: 2)
        .onEnded {
          showAttachmentReactionMenu()
        }
    )
    .onLongPressGesture(
      minimumDuration: FriendsThreadAttachmentTapGuard.messageMenuRecognitionDuration,
      maximumDistance: 20,
      perform: {
        shouldSuppressNextTap = true
        guard canReact else { return }
        FriendsThreadAttachmentReactionMenuTarget.set(
          messageId: messageId,
          attachmentId: attachment.id
        )
        onPrepareReaction(attachment)
      },
      onPressingChanged: { isPressing in
        if isPressing, canReact {
          FriendsThreadAttachmentReactionMenuTarget.set(
            messageId: messageId,
            attachmentId: attachment.id
          )
          return
        }
        onReactionPressChanged(attachment, false)
      }
    )
    .onChange(of: canReact) { _, canReact in
      if canReact {
        return
      }
      shouldSuppressNextTap = false
      FriendsThreadAttachmentReactionMenuTarget.clear(
        messageId: messageId,
        attachmentId: attachment.id
      )
      onReactionPressChanged(attachment, false)
    }
    .onAppear {
      if !canOpenAttachment {
        FriendsThreadAttachmentTapSuppressor.suppressNextTap(
          messageId: messageId,
          attachmentId: attachment.id
        )
      }
    }
  }

  private func handleImageTap() {
    guard !shouldSuppressNextTap else {
      shouldSuppressNextTap = false
      return
    }
    guard
      !FriendsThreadAttachmentTapSuppressor.consumeSuppressedTap(
        messageId: messageId,
        attachmentId: attachment.id
      )
    else {
      return
    }
    FriendsThreadAttachmentReactionMenuTarget.clear(
      messageId: messageId,
      attachmentId: attachment.id
    )
    onReactionPressChanged(attachment, false)
    onOpenImageAttachment(attachment)
  }

  private func showAttachmentReactionMenu() {
    shouldSuppressNextTap = true
    guard canReact else {
      return
    }
    FriendsThreadAttachmentReactionMenuTarget.set(
      messageId: messageId,
      attachmentId: attachment.id
    )
    onPrepareReaction(attachment)
    onShowReactionMenu(attachment.id)
  }
}

struct FriendsChatReplyPayloadFramePreferenceKey: PreferenceKey {
  static let defaultValue: [String: CGRect] = [:]

  static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
    value.merge(nextValue()) { _, new in new }
  }
}

@MainActor
enum FriendsThreadAttachmentReactionMenuTarget {
  private struct Target {
    let messageId: String
    let attachmentId: String
    let createdAt: Date
  }

  private static var target: Target?
  private static let expirationInterval: TimeInterval = 10

  static func set(messageId: String, attachmentId: String) {
    target = Target(messageId: messageId, attachmentId: attachmentId, createdAt: .now)
  }

  static func clear(messageId: String? = nil, attachmentId: String? = nil) {
    guard let current = target else {
      return
    }
    if let messageId, current.messageId != messageId {
      return
    }
    if let attachmentId, current.attachmentId != attachmentId {
      return
    }
    target = nil
  }

  static func attachmentId(for messageId: String, now: Date = .now) -> String? {
    guard let current = target else {
      return nil
    }
    guard current.messageId == messageId else {
      return nil
    }
    guard now.timeIntervalSince(current.createdAt) <= expirationInterval else {
      target = nil
      return nil
    }
    return current.attachmentId
  }
}

@MainActor
private enum FriendsThreadAttachmentTapSuppressor {
  private static var targets: [String: Date] = [:]
  private static let expirationInterval: TimeInterval = 10

  static func suppressNextTap(messageId: String, attachmentId: String) {
    let key = key(messageId: messageId, attachmentId: attachmentId)
    targets[key] = .now
  }

  static func consumeSuppressedTap(
    messageId: String,
    attachmentId: String,
    now: Date = .now
  ) -> Bool {
    pruneExpired(now: now)

    let key: String = key(messageId: messageId, attachmentId: attachmentId)
    guard targets.removeValue(forKey: key) != nil else {
      return false
    }
    return true
  }

  private static func pruneExpired(now: Date) {
    targets = targets.filter { _, createdAt in
      now.timeIntervalSince(createdAt) <= expirationInterval
    }
  }

  private static func key(messageId: String, attachmentId: String) -> String {
    "\(messageId)#\(attachmentId)"
  }
}
