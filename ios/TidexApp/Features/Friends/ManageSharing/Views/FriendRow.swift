import SwiftUI

// MARK: - Friend Section Type

/// Identifies which section a friend row belongs to
enum FriendSectionType {
  case mutual  // Both share with each other
  case outgoing  // Only I share with them
  case incoming  // Only they share with me
}

// MARK: - Friend Row

/// A row displaying a friend in the sharing management modal.
/// Tapping anywhere on the row opens a menu with all available actions.
/// Block and remove actions are also accessible via swipe gestures on the List row.
struct FriendRow: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  let friend: Friend
  let sectionType: FriendSectionType
  let isActionInProgress: Bool
  var isHighlighted: Bool = false
  let onToggleEarnings: () -> Void
  let onShareBack: () -> Void
  let onToggleMuted: () -> Void
  let onToggleOwnerMuted: () -> Void
  let onToggleBlocked: () -> Void
  let onRemove: () -> Void

  private var nameLayoutDirection: LayoutDirection {
    friend.displayName.isRightToLeft ? .rightToLeft : .leftToRight
  }

  var body: some View {
    Menu {
      notificationSection
      sharingSection
      actionsSection
    } label: {
      rowContent
    }
    .buttonStyle(.plain)
    .disabled(isActionInProgress)
    .opacity(isActionInProgress ? 0.6 : 1.0)
    .background(
      Color.tidexBlue.opacity(isHighlighted ? 0.15 : 0)
        .animation(
          reduceMotion ? nil : .easeInOut(duration: 0.8).repeatCount(3, autoreverses: true),
          value: isHighlighted
        )
    )
  }

  // MARK: - Row Content

  private var rowContent: some View {
    HStack(spacing: Spacing.sm) {
      // Avatar
      avatarView

      // Name and contact info
      VStack(alignment: .leading, spacing: Spacing.micro) {
        Text(friend.displayName)
          .font(.tidexBodyMedium)
          .foregroundColor(.tidexTextPrimary)
          .lineLimit(1)
          .multilineTextAlignment(.leading)

        subtitleView
      }
      .environment(\.layoutDirection, nameLayoutDirection)

      Spacer(minLength: 8)
    }
    .padding(.vertical, Spacing.xxs)
    .contentShape(Rectangle())
  }

  // MARK: - Subtitle

  @ViewBuilder
  private var subtitleView: some View {
    if let contactInfo = friend.contactInfo {
      Text(contactInfo)
        .font(.tidexFootnote)
        .foregroundColor(.tidexTextMuted)
        .lineLimit(1)
    }
  }

  // MARK: - Avatar

  private var avatarView: some View {
    AvatarView(
      url: friend.avatarUrl,
      initials: friend.initials,
      size: AvatarView.Size.medium
    )
    .overlay(alignment: .bottomTrailing) {
      if friend.sharesWithMe?.blocked == true {
        Image(systemName: "eye.slash.fill")
          .font(.system(size: 10))
          .foregroundColor(.white)
          .padding(3)
          .background(Color.tidexError.opacity(0.85))
          .clipShape(Circle())
          .offset(x: 2, y: 2)
      }
    }
  }

  // MARK: - Notification Section

  @ViewBuilder
  private var notificationSection: some View {
    Section(String(localized: .sharingNotificationsTitle)) {
      if sectionType == .mutual || sectionType == .incoming {
        Toggle(
          String(localized: .sharingMenuNotifyMeOfTheirShifts(friend.firstNameOnly)),
          isOn: .init(
            get: { !(friend.sharesWithMe?.isMuted ?? true) },
            set: { _ in onToggleMuted() }
          )
        )
      }

      if sectionType == .mutual || sectionType == .outgoing {
        Toggle(
          String(localized: .sharingMenuNotifyThemOfMyShifts(friend.firstNameOnly)),
          isOn: .init(
            get: { !(friend.iShareWith?.ownerMuted ?? true) },
            set: { _ in onToggleOwnerMuted() }
          )
        )
      }
    }
  }

  // MARK: - Sharing Section

  @ViewBuilder
  private var sharingSection: some View {
    switch sectionType {
    case .mutual, .outgoing:
      Section {
        Toggle(
          String(localized: .sharingMenuShowThemMyEarnings(friend.firstNameOnly)),
          isOn: .init(
            get: { friend.iShareWith?.showEarningsToThem ?? false },
            set: { _ in onToggleEarnings() }
          )
        )
      }
    case .incoming:
      Section {
        Button {
          onShareBack()
        } label: {
          Label(String(localized: .sharingShareBack), systemImage: "arrowshape.turn.up.left")
        }
      }
    }
  }

  // MARK: - Actions Section

  @ViewBuilder
  private var actionsSection: some View {
    Section {
      if sectionType == .mutual || sectionType == .incoming {
        let isBlocked = friend.sharesWithMe?.blocked == true
        Button {
          onToggleBlocked()
        } label: {
          Label(
            String(localized: isBlocked ? .sharingMenuShowShifts : .sharingMenuHideShifts),
            systemImage: isBlocked ? "eye" : "eye.slash"
          )
        }
      }

      Button(role: .destructive) {
        onRemove()
      } label: {
        Label(String(localized: .sharingSwipeRemove), systemImage: "trash")
      }
    }
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
        onToggleOwnerMuted: {},
        onToggleBlocked: {},
        onRemove: {}
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
        onToggleOwnerMuted: {},
        onToggleBlocked: {},
        onRemove: {}
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
        onToggleOwnerMuted: {},
        onToggleBlocked: {},
        onRemove: {}
      )
    }
  }
  .listStyle(.insetGrouped)
}
