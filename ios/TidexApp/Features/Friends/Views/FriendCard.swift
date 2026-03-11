import SwiftUI

/// A card displaying a friend who shares their shifts with the current user
/// Shows their name, avatar, and a preview of their next/active/past shift
struct FriendCard: View {
  let sharer: SharedUser
  let preview: SharerShiftPreview?
  let isSelected: Bool
  let isRefreshing: Bool
  let onChatTap: () -> Void
  let onCalendarTap: () -> Void
  var isCalendarAvailable = true
  var isOpeningMessage = false
  var unreadMessageCount = 0

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: Spacing.sm) {
        Button(action: primaryCardTapAction) {
          CompactFriendIdentityRow(
            sharer: sharer,
            unreadMessageCount: unreadMessageCount
          )
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isOpeningMessage)

        Button(action: onChatTap) {
          Group {
            if isOpeningMessage {
              ProgressView()
                .progressViewStyle(.circular)
                .tint(.tidexTextOnBrand)
            } else {
              Image(systemName: "message")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.tidexTextOnBrand)
            }
          }
          .frame(width: 44, height: 44)
          .tidexGlass(
            shape: .circle,
            tint: .tidexBlue.opacity(0.26),
            interactive: true
          )
        }
        .buttonStyle(.plain)
        .disabled(isOpeningMessage)
        .accessibilityLabel(Text(verbatim: "\(sharer.displayName) chat"))
      }
      .padding(.horizontal, Spacing.md)
      .padding(.vertical, Spacing.sm)

      if let preview = preview, let shift = preview.shift, let status = preview.status {
        Button(action: onCalendarTap) {
          Group {
            if isRefreshing {
              shiftPreviewSkeleton
            } else {
              FriendShiftPreviewStatusCard(shift: shift, status: status)
            }
          }
        }
        .buttonStyle(.plain)
        .disabled(!isCalendarAvailable)
        .padding(.horizontal, Spacing.sm)
        .padding(.bottom, Spacing.sm)
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
    .tidexCardShadow()
  }

  private var primaryCardTapAction: () -> Void {
    isCalendarAvailable ? onCalendarTap : onChatTap
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
    .padding(.vertical, Spacing.sm)
    .background(
      RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
        .fill(Color.tidexSurfacePrimary)
    )
    .tidexCardShadow(.subtle, cornerRadius: CornerRadius.lg)
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
      isSelected: true,
      isRefreshing: false,
      onChatTap: {},
      onCalendarTap: {}
    )
  }
  .padding()
  .background(Color.tidexBackground)
}
