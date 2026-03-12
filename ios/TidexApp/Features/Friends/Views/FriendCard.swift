import SwiftUI

enum FriendCardMessageState: Equatable {
  case outgoingSending
  case outgoingSent
  case outgoingOpened
  case outgoingFailed
  case incomingUnread
  case incomingOpened
}

struct FriendCardMessagePreview: Equatable {
  let text: String
  let timestamp: Date
  let state: FriendCardMessageState
}

/// A card displaying a friend who shares their shifts with the current user
/// Shows their name, avatar, and a preview of their next/active/past shift
struct FriendCard: View {
  let sharer: SharedUser
  let preview: SharerShiftPreview?
  let messagePreview: FriendCardMessagePreview?
  let isSelected: Bool
  let isRefreshing: Bool
  let onChatTap: () -> Void
  let onCalendarTap: () -> Void
  var isCalendarAvailable = true
  var isOpeningMessage = false
  var unreadMessageCount = 0

  private let actionButtonSize: CGFloat = 44

  var body: some View {
    ZStack(alignment: .topTrailing) {
      VStack(spacing: 0) {
        HStack(spacing: Spacing.sm) {
          Button(action: onChatTap) {
            CompactFriendIdentityRow(
              sharer: sharer,
              unreadMessageCount: unreadMessageCount,
              messagePreview: messagePreview
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .allowsHitTesting(!isOpeningMessage)
          .accessibilityLabel(Text(verbatim: "\(sharer.displayName) chat"))
          .accessibilityHint(Text(.friendsChatMessageAction))

          if isCalendarAvailable {
            Color.clear
              .frame(width: actionButtonSize, height: actionButtonSize)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.sm)
        .padding(.bottom, Spacing.sm + 2)

        if let preview = preview, let shift = preview.shift, let status = preview.status {
          VStack(spacing: 0) {
            Rectangle()
              .fill(Color.tidexBorderSubtle.opacity(0.7))
              .frame(height: 1)
              .padding(.horizontal, Spacing.md)
              .padding(.bottom, Spacing.xxs)

            Group {
              if isRefreshing {
                shiftPreviewSkeleton
              } else {
                FriendShiftPreviewStatusCard(shift: shift, status: status, embedded: true)
              }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.bottom, Spacing.sm)
          }
          .contentShape(Rectangle())
          .onTapGesture(perform: onChatTap)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .allowsHitTesting(!isOpeningMessage)

      if isCalendarAvailable {
        Button(action: onCalendarTap) {
          Image(systemName: "calendar")
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.tidexBlue)
            .frame(width: actionButtonSize, height: actionButtonSize)
            .tidexGlass(
              shape: .circle,
              tint: .tidexBlue.opacity(0.14),
              interactive: true,
              disabled: isOpeningMessage
            )
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!isOpeningMessage)
        .padding(.top, Spacing.sm)
        .padding(.trailing, Spacing.md)
        .accessibilityLabel(Text(.tabsShifts))
      }
    }
    .background(
      RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous)
        .fill(isSelected ? Color.tidexBlue.opacity(0.1) : Color.tidexSurfacePrimary)
    )
    .overlay(
      RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous)
        .strokeBorder(
          isSelected ? Color.tidexBlue : Color.clear,
          lineWidth: 2
        )
    )
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous))
    .tidexCardShadow()
  }

  /// Skeleton placeholder for shift preview while refreshing
  private var shiftPreviewSkeleton: some View {
    HStack(spacing: Spacing.sm) {
      // Date and time skeleton
      VStack(alignment: .leading, spacing: Spacing.xxs) {
        RoundedRectangle(cornerRadius: CornerRadius.xxs)
          .fill(Color.tidexTextMuted.opacity(0.3))
          .frame(width: 140, height: 14)

        RoundedRectangle(cornerRadius: CornerRadius.xxs)
          .fill(Color.tidexTextMuted.opacity(0.2))
          .frame(width: 90, height: 13)
      }

      Spacer()

      // Status badge skeleton
      RoundedRectangle(cornerRadius: CornerRadius.sm)
        .fill(Color.tidexTextMuted.opacity(0.2))
        .frame(width: 70, height: 24)
    }
    .padding(.horizontal, Spacing.sm)
    .padding(.vertical, Spacing.xs)
    .shimmer(duration: 1.2)
  }
}

// MARK: - Empty State

/// Shown when no one has shared shifts with the user
struct FriendsListEmptyState: View {
  var onAddFriend: (() -> Void)?

  var body: some View {
    VStack(spacing: Spacing.md) {
      Image(systemName: "person.2.slash")
        .font(.system(size: 48))
        .foregroundColor(.tidexTextMuted)

      Text(.sharingNoSharers)
        .font(.tidexBodyMedium)
        .foregroundColor(.tidexTextPrimary)

      Text(.sharingNoSharersDescription)
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextMuted)
        .multilineTextAlignment(.center)
        .padding(.horizontal, Spacing.xl)

      if let onAddFriend {
        Button(action: onAddFriend) {
          HStack(spacing: Spacing.xxxs) {
            Image(systemName: "plus")
              .font(.tidexLabelStrong)
            Text(.sharingAddFriend)
              .font(.tidexLabelStrong)
          }
          .foregroundColor(.tidexTextOnBrand)
          .padding(.horizontal, Spacing.mlg)
          .padding(.vertical, Spacing.xsm)
          .background(Color.tidexBlue)
          .cornerRadius(CornerRadius.md)
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.top, Spacing.xxs)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(.vertical, 80)
  }
}

#Preview {
  VStack(spacing: Spacing.md) {
    FriendCard(
      sharer: SharedUser(
        id: "1",
        email: "john@example.com",
        phone: nil,
        firstName: "John Doe",
        profilePictureUrl: nil,
        oauthAvatarUrl: nil,
        sharedAt: "2025-01-01",
        showEarnings: true,
        hidden: false
      ),
      preview: nil,
      messagePreview: FriendCardMessagePreview(
        text: "Can you cover Friday?",
        timestamp: Date().addingTimeInterval(-900),
        state: .incomingUnread
      ),
      isSelected: false,
      isRefreshing: false,
      onChatTap: {},
      onCalendarTap: {}
    )

    FriendCard(
      sharer: SharedUser(
        id: "2",
        email: "jane@example.com",
        phone: nil,
        firstName: "Jane",
        profilePictureUrl: nil,
        oauthAvatarUrl: nil,
        sharedAt: "2025-01-01",
        showEarnings: false,
        hidden: false
      ),
      preview: nil,
      messagePreview: FriendCardMessagePreview(
        text: "I opened the shift snapshot",
        timestamp: Date().addingTimeInterval(-7200),
        state: .outgoingOpened
      ),
      isSelected: true,
      isRefreshing: false,
      onChatTap: {},
      onCalendarTap: {}
    )
  }
  .padding()
  .background(Color.tidexBackground)
}
