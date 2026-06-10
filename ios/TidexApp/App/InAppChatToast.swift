// swiftlint:disable:next blanket_disable_command
// swiftlint:disable accessibility_label_for_image closure_body_length conditional_returns_on_newline
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable discouraged_none_name explicit_acl explicit_top_level_acl explicit_type_interface
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable file_types_order no_magic_numbers
import SwiftUI

extension Notification.Name {
  static let inAppChatToastRequested = Notification.Name("inAppChatToastRequested")
}

struct InAppChatToastPayload: Equatable, Sendable {
  enum Destination: Equatable, Sendable {
    case friendChat
    case none
  }

  let threadId: String
  let messageId: String?
  let senderUserId: String?
  let typingUserId: String?
  let senderName: String
  let senderAvatarUrl: String?
  let previewText: String
  let destination: Destination

  init(
    threadId: String,
    messageId: String?,
    senderUserId: String?,
    typingUserId: String?,
    senderName: String,
    senderAvatarUrl: String?,
    previewText: String
  ) {
    self.threadId = threadId
    self.messageId = messageId
    self.senderUserId = senderUserId
    self.typingUserId = typingUserId
    self.senderName = senderName
    self.senderAvatarUrl = senderAvatarUrl
    self.previewText = previewText
    self.destination = .friendChat
  }

  init?(
    userInfo: [AnyHashable: Any],
    notificationTitle: String,
    notificationBody: String
  ) {
    guard let type = userInfo["type"] as? String,
      type == "thread_message" || type == "thread_typing" || type == "thread_reaction"
        || type == "thread_screenshot" || type == "shifts_screenshotted"
    else { return nil }

    let threadId = (userInfo["thread_id"] as? String) ?? ""
    guard type == "shifts_screenshotted" || !threadId.isEmpty else { return nil }

    self.threadId = threadId
    self.messageId = userInfo["message_id"] as? String
    self.senderUserId = userInfo["sender_user_id"] as? String
    self.typingUserId = type == "thread_typing" ? self.senderUserId : nil
    self.senderName =
      ((userInfo["sender_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines))
      .flatMap { $0.isEmpty ? nil : $0 }
      ?? notificationTitle
    self.senderAvatarUrl = userInfo["sender_avatar_url"] as? String
    self.previewText = notificationBody.trimmingCharacters(in: .whitespacesAndNewlines)
    self.destination = type == "shifts_screenshotted" ? .none : .friendChat
  }
}

struct InAppChatToastView: View {
  let payload: InAppChatToastPayload
  let onTap: () -> Void
  let onDismiss: () -> Void

  private var senderInitials: String {
    let parts = payload.senderName
      .split(separator: " ")
      .map(String.init)
      .filter { !$0.isEmpty }

    if parts.isEmpty { return "?" }
    if parts.count == 1 { return String(parts[0].prefix(1)).uppercased() }
    return (String(parts[0].prefix(1)) + String(parts[1].prefix(1))).uppercased()
  }

  var body: some View {
    HStack(spacing: Spacing.sm) {
      Button(action: onTap) {
        HStack(spacing: Spacing.sm) {
          AvatarView(
            url: payload.senderAvatarUrl,
            initials: senderInitials,
            size: AvatarView.Size.large
          )

          VStack(alignment: .leading, spacing: Spacing.micro) {
            Text(payload.senderName)
              .font(.tidexBodyMedium)
              .foregroundColor(.tidexTextPrimary)
              .lineLimit(1)

            Text(payload.previewText)
              .font(.tidexSubheadline)
              .foregroundColor(.tidexTextSecondary)
              .lineLimit(2)
              .truncationMode(.tail)
          }

          Spacer(minLength: Spacing.xs)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)

      Button(action: onDismiss) {
        Image(systemName: "xmark")
          .font(.tidexFootnoteStrong)
          .foregroundColor(.tidexTextMuted)
          .frame(width: 36, height: 36)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, Spacing.md)
    .padding(.vertical, Spacing.sm)
    .background(Color.tidexSurfacePrimary.opacity(0.98))
    .overlay(
      RoundedRectangle(cornerRadius: CornerRadius.xxxl, style: .continuous)
        .stroke(Color.tidexBorder, lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xxxl, style: .continuous))
    .shadow(color: Color.black.opacity(0.14), radius: 18, y: 6)
  }
}
