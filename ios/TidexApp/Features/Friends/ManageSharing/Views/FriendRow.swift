import SwiftUI

// MARK: - Friend Section Type

/// Identifies which section a friend row belongs to
enum FriendSectionType {
  case mutual  // Both share with each other
  case outgoing  // Only I share with them
  case incoming  // Only they share with me
}

// MARK: - Friend Row

/// A row displaying a friend in the sharing management modal
/// Shows an inline bell icon for notification toggles, plus earnings toggle or share back button.
/// Block and remove actions are accessed via swipe gestures on the List row.
struct FriendRow: View {
  let friend: Friend
  let sectionType: FriendSectionType
  let isActionInProgress: Bool
  var isHighlighted: Bool = false
  let onToggleEarnings: () -> Void
  let onShareBack: () -> Void
  let onToggleMuted: () -> Void
  let onToggleOwnerMuted: () -> Void

  @State private var showNotificationPopover = false

  private var nameLayoutDirection: LayoutDirection {
    friend.displayName.isRightToLeft ? .rightToLeft : .leftToRight
  }

  var body: some View {
    HStack(spacing: 12) {
      // Avatar
      avatarView

      // Name and contact info
      VStack(alignment: .leading, spacing: 2) {
        Text(friend.displayName)
          .font(.system(size: 16, weight: .medium))
          .foregroundColor(.tidexTextPrimary)
          .lineLimit(1)
          .multilineTextAlignment(.leading)

        subtitleView
      }
      .environment(\.layoutDirection, nameLayoutDirection)

      Spacer(minLength: 8)

      // Bell icon + primary action
      actionButtons
        .layoutPriority(1)
    }
    .padding(.vertical, 4)
    .opacity(isActionInProgress ? 0.6 : 1.0)
    .background(
      Color.tidexBlue.opacity(isHighlighted ? 0.15 : 0)
        .animation(
          .easeInOut(duration: 0.8).repeatCount(3, autoreverses: true), value: isHighlighted)
    )
  }

  // MARK: - Subtitle

  @ViewBuilder
  private var subtitleView: some View {
    let hasContact = friend.contactInfo != nil
    let isBlocked = friend.sharesWithMe?.blocked == true

    if hasContact || isBlocked {
      HStack(spacing: 4) {
        if let contactInfo = friend.contactInfo {
          Text(contactInfo)
            .font(.system(size: 13))
            .foregroundColor(.tidexTextMuted)
            .lineLimit(1)
        }

        if isBlocked {
          Image(systemName: "eye.slash.fill")
            .font(.system(size: 10))
            .foregroundColor(.red.opacity(0.7))
        }
      }
      .multilineTextAlignment(.leading)
    }
  }

  // MARK: - Avatar

  private var avatarView: some View {
    AvatarView(
      url: friend.avatarUrl,
      initials: friend.initials,
      size: AvatarView.Size.medium
    )
  }

  // MARK: - Inline Actions

  @ViewBuilder
  private var actionButtons: some View {
    HStack(spacing: 4) {
      bellButton

      switch sectionType {
      case .mutual, .outgoing:
        earningsToggle
      case .incoming:
        shareBackButton
      }
    }
  }

  // MARK: - Bell Button

  private var bellButton: some View {
    Button {
      showNotificationPopover.toggle()
    } label: {
      Image(systemName: bellIconName)
        .font(.system(size: 15))
        .foregroundColor(bellIconColor)
        .frame(width: 28, height: 28)
    }
    .buttonStyle(PlainButtonStyle())
    .popover(isPresented: $showNotificationPopover) {
      NotificationTogglesPopover(
        friend: friend,
        sectionType: sectionType,
        isActionInProgress: isActionInProgress,
        onToggleMuted: onToggleMuted,
        onToggleOwnerMuted: onToggleOwnerMuted
      )
    }
  }

  private var bellIconName: String {
    let viewerMuted = friend.sharesWithMe?.isMuted ?? false
    let ownerMuted = friend.iShareWith?.ownerMuted ?? false
    if viewerMuted || ownerMuted {
      return "bell.slash"
    }
    return "bell"
  }

  private var bellIconColor: Color {
    let viewerMuted = friend.sharesWithMe?.isMuted ?? false
    let ownerMuted = friend.iShareWith?.ownerMuted ?? false
    if viewerMuted || ownerMuted {
      return .tidexTextMuted
    }
    return .tidexBlue
  }

  private var earningsToggle: some View {
    Toggle(
      "",
      isOn: .init(
        get: { friend.iShareWith?.showEarningsToThem ?? false },
        set: { _ in onToggleEarnings() }
      )
    )
    .labelsHidden()
    .toggleStyle(SwitchToggleStyle(tint: .tidexBlue))
    .scaleEffect(0.8)
    .disabled(isActionInProgress)
  }

  private var shareBackButton: some View {
    Button(action: onShareBack) {
      Text(.sharingShareBack)
        .font(.system(size: 12, weight: .medium))
        .foregroundColor(.white)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 6)
        .background(Color.tidexBlue)
        .cornerRadius(6)
    }
    .buttonStyle(PlainButtonStyle())
    .disabled(isActionInProgress)
  }
}

// MARK: - Preview

#Preview {
  List {
    Section(header: Text("Mutual")) {
      FriendRow(
        friend: Friend(
          id: "1",
          email: "ole@example.com",
          phone: nil,
          firstName: "Ole Hansen Kristensen-Karlsen",
          profilePictureUrl: nil,
          oauthAvatarUrl: nil,
          sharesWithMe: Friend.SharesWithMe(
            blocked: false,
            showEarningsToMe: true,
            sharedAt: "2025-01-01",
            notificationFrequency: .instant
          ),
          iShareWith: Friend.IShareWith(
            showEarningsToThem: true,
            sharedAt: "2025-01-01"
          )
        ),
        sectionType: .mutual,
        isActionInProgress: false,
        onToggleEarnings: {},
        onShareBack: {},
        onToggleMuted: {},
        onToggleOwnerMuted: {}
      )
    }

    Section(header: Text("I share with")) {
      FriendRow(
        friend: Friend(
          id: "2",
          email: "kari@example.com",
          phone: nil,
          firstName: "Kari Berg",
          profilePictureUrl: nil,
          oauthAvatarUrl: nil,
          sharesWithMe: nil,
          iShareWith: Friend.IShareWith(
            showEarningsToThem: false,
            sharedAt: "2025-01-01"
          )
        ),
        sectionType: .outgoing,
        isActionInProgress: false,
        onToggleEarnings: {},
        onShareBack: {},
        onToggleMuted: {},
        onToggleOwnerMuted: {}
      )
    }

    Section(header: Text("Shares with me")) {
      FriendRow(
        friend: Friend(
          id: "3",
          email: "lisa@example.com",
          phone: nil,
          firstName: "Lisa Olsen",
          profilePictureUrl: nil,
          oauthAvatarUrl: nil,
          sharesWithMe: Friend.SharesWithMe(
            blocked: false,
            showEarningsToMe: false,
            sharedAt: "2025-01-01",
            notificationFrequency: .muted
          ),
          iShareWith: nil
        ),
        sectionType: .incoming,
        isActionInProgress: false,
        onToggleEarnings: {},
        onShareBack: {},
        onToggleMuted: {},
        onToggleOwnerMuted: {}
      )
    }
  }
  .listStyle(.insetGrouped)
}
