import SwiftUI

// MARK: - Friend Section Type

/// Identifies which section a friend row belongs to
enum FriendSectionType {
  case mutual  // Both share with each other
  case outgoing  // Only I share with them
  case incoming  // Only they share with me

  var relationshipStatus: String {
    switch self {
    case .mutual:
      return String(localized: .sharingRelationshipMutual)
    case .outgoing:
      return String(localized: .sharingRelationshipOutgoingOnly)
    case .incoming:
      return String(localized: .sharingRelationshipIncomingOnly)
    }
  }
}

enum FriendSharingRemovalAction: CaseIterable, Hashable {
  case stopSharingMyShifts
  case stopSeeingTheirShifts

  static func availableActions(for sectionType: FriendSectionType) -> [FriendSharingRemovalAction] {
    switch sectionType {
    case .mutual:
      return [.stopSharingMyShifts, .stopSeeingTheirShifts]
    case .outgoing:
      return [.stopSharingMyShifts]
    case .incoming:
      return [.stopSeeingTheirShifts]
    }
  }

  var title: String {
    switch self {
    case .stopSharingMyShifts:
      return String(localized: .sharingActionStopSharingMyShifts)
    case .stopSeeingTheirShifts:
      return String(localized: .sharingActionStopSeeingTheirShifts)
    }
  }

  var systemImage: String {
    switch self {
    case .stopSharingMyShifts:
      return "person.crop.circle.badge.minus"
    case .stopSeeingTheirShifts:
      return "eye.slash"
    }
  }

  func confirmationTitle(friendName: String) -> String {
    switch self {
    case .stopSharingMyShifts:
      return Self.localizedFormat("sharing.confirm.stopSharingMyShifts.title", friendName)
    case .stopSeeingTheirShifts:
      return Self.localizedFormat("sharing.confirm.stopSeeingTheirShifts.title", friendName)
    }
  }

  func confirmationMessage(friendName: String, sectionType: FriendSectionType) -> String {
    switch (self, sectionType) {
    case (.stopSharingMyShifts, .mutual):
      return Self.localizedFormat("sharing.confirm.stopSharingMyShifts.mutual", friendName)
    case (.stopSharingMyShifts, .outgoing):
      return Self.localizedFormat("sharing.confirm.stopSharingMyShifts.outgoingOnly", friendName)
    case (.stopSeeingTheirShifts, .mutual):
      return Self.localizedFormat("sharing.confirm.stopSeeingTheirShifts.mutual", friendName)
    case (.stopSeeingTheirShifts, .incoming):
      return Self.localizedFormat("sharing.confirm.stopSeeingTheirShifts.incomingOnly", friendName)
    case (.stopSharingMyShifts, .incoming), (.stopSeeingTheirShifts, .outgoing):
      return confirmationTitle(friendName: friendName)
    }
  }

  static func localizedFormat(_ key: String, _ argument: String) -> String {
    let format = String(localized: String.LocalizationValue(key), table: "Localizable")
    return String.localizedStringWithFormat(format, argument)
  }
}

// MARK: - Friend Row

/// A row displaying a friend in the sharing management modal.
/// Tapping anywhere on the row opens a menu with all available actions.
struct FriendRow: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  let friend: Friend
  let sectionType: FriendSectionType
  let isActionInProgress: Bool
  let isHiddenInFriendsTab: Bool
  let areServerActionsUnavailable: Bool
  let isHideActionDisabled: Bool
  var isHighlighted: Bool = false
  let onToggleEarnings: () -> Void
  let onShareBack: () -> Void
  let onToggleMuted: () -> Void
  let onToggleOwnerMuted: () -> Void
  let onToggleHidden: () -> Void
  let onBlock: () -> Void
  let onRemove: (FriendSharingRemovalAction) -> Void

  private var nameLayoutDirection: LayoutDirection {
    friend.displayName.isRightToLeft ? .rightToLeft : .leftToRight
  }

  var body: some View {
    Menu {
      sharingSection
      notificationSection
      visibilitySection
      destructiveSection
    } label: {
      rowContent
    }
    .buttonStyle(.plain)
    .disabled(isActionInProgress)
    .opacity(isActionInProgress ? 0.6 : 1.0)
    .accessibilityLabel(
      FriendSharingRemovalAction.localizedFormat(
        "sharing.accessibility.moreActions",
        friend.displayName
      )
    )
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

      // Name, relationship, and contact info
      VStack(alignment: .leading, spacing: Spacing.micro) {
        Text(friend.displayName)
          .font(.tidexBodyMedium)
          .foregroundColor(.tidexTextPrimary)
          .lineLimit(1)
          .multilineTextAlignment(.leading)

        subtitleView
      }
      .environment(\.layoutDirection, nameLayoutDirection)
      .layoutPriority(1)

      Spacer(minLength: 8)

      Image(systemName: "ellipsis.circle")
        .font(.tidexBodyMedium)
        .foregroundColor(.tidexTextMuted)
        .accessibilityHidden(true)
    }
    .padding(.vertical, Spacing.xxs)
    .contentShape(Rectangle())
  }

  // MARK: - Subtitle

  @ViewBuilder
  private var subtitleView: some View {
    Text(sectionType.relationshipStatus)
      .font(.tidexFootnote)
      .foregroundColor(.tidexTextMuted)
      .lineLimit(1)
      .minimumScaleFactor(0.88)
      .multilineTextAlignment(.leading)

    if let contactInfo = friend.contactInfo {
      Text(contactInfo)
        .font(.tidexFootnote)
        .foregroundColor(.tidexTextMuted)
        .lineLimit(1)
        .multilineTextAlignment(.leading)
    }
  }

  // MARK: - Avatar

  private var avatarView: some View {
    AvatarView(
      url: friend.avatarUrl,
      initials: friend.initials,
      size: 52
    )
    .overlay(alignment: .bottomTrailing) {
      if isHiddenInFriendsTab {
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
      if areServerActionsUnavailable {
        Text(String(localized: "sharing.offline.actionsUnavailable", table: "Localizable"))
      }

      if sectionType == .mutual || sectionType == .incoming {
        Toggle(
          isOn: .init(
            get: { !(friend.sharesWithMe?.isMuted ?? true) },
            set: { _ in onToggleMuted() }
          )
        ) {
          Label(
            String(localized: .sharingMenuNotifyMeOfTheirShifts(friend.firstNameOnly)),
            systemImage: "bell"
          )
        }
        .disabled(areServerActionsUnavailable)
      }

      if sectionType == .mutual || sectionType == .outgoing {
        Toggle(
          isOn: .init(
            get: { !(friend.iShareWith?.ownerMuted ?? true) },
            set: { _ in onToggleOwnerMuted() }
          )
        ) {
          Label(
            String(localized: .sharingMenuNotifyThemOfMyShifts(friend.firstNameOnly)),
            systemImage: "bell.badge"
          )
        }
        .disabled(areServerActionsUnavailable)
      }
    }
  }

  // MARK: - Sharing Section

  @ViewBuilder
  private var sharingSection: some View {
    Section(String(localized: .sharingMenuSectionSharing)) {
      if sectionType == .mutual || sectionType == .outgoing {
        Toggle(
          isOn: .init(
            get: { friend.iShareWith?.showEarningsToThem ?? false },
            set: { _ in onToggleEarnings() }
          )
        ) {
          Label(
            String(localized: .sharingMenuShowThemMyEarnings(friend.firstNameOnly)),
            systemImage: "banknote"
          )
        }
        .disabled(areServerActionsUnavailable)
      }

      if sectionType == .incoming {
        Button {
          onShareBack()
        } label: {
          Label(String(localized: .sharingShareBack), systemImage: "arrowshape.turn.up.left")
        }
        .disabled(areServerActionsUnavailable)
      }
    }
  }

  // MARK: - Visibility Section

  @ViewBuilder
  private var visibilitySection: some View {
    Section(String(localized: .sharingMenuSectionVisibility)) {
      Button {
        onToggleHidden()
      } label: {
        Label(
          String(
            localized: isHiddenInFriendsTab
              ? .sharingActionShowInFriendsList : .sharingActionHideFromFriendsList),
          systemImage: isHiddenInFriendsTab ? "eye" : "eye.slash"
        )
      }
      .disabled(isHideActionDisabled)
    }
  }

  // MARK: - Destructive Section

  @ViewBuilder
  private var destructiveSection: some View {
    Section(String(localized: .sharingMenuSectionSafety)) {
      ForEach(FriendSharingRemovalAction.availableActions(for: sectionType), id: \.self) {
        removalAction in
        Button(role: .destructive) {
          onRemove(removalAction)
        } label: {
          Label(removalAction.title, systemImage: removalAction.systemImage)
        }
        .disabled(areServerActionsUnavailable)
      }

      Button(role: .destructive) {
        onBlock()
      } label: {
        Label(String(localized: .friendsChatBlockUser), systemImage: "hand.raised.fill")
      }
      .disabled(areServerActionsUnavailable)
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
          username: "ole",
          firstName: "Ole Karlsen",
          profilePictureUrl: nil,
          oauthAvatarUrl: nil,
          sharesWithMe: Friend.SharesWithMe(
            hidden: false,
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
        isHiddenInFriendsTab: false,
        areServerActionsUnavailable: false,
        isHideActionDisabled: false,
        onToggleEarnings: {},
        onShareBack: {},
        onToggleMuted: {},
        onToggleOwnerMuted: {},
        onToggleHidden: {},
        onBlock: {},
        onRemove: { _ in }
      )
    }

    Section(header: Text("I share with")) {
      FriendRow(
        friend: Friend(
          id: "2",
          email: "kari@example.com",
          phone: nil,
          username: "kari",
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
        isHiddenInFriendsTab: false,
        areServerActionsUnavailable: false,
        isHideActionDisabled: false,
        onToggleEarnings: {},
        onShareBack: {},
        onToggleMuted: {},
        onToggleOwnerMuted: {},
        onToggleHidden: {},
        onBlock: {},
        onRemove: { _ in }
      )
    }

    Section(header: Text("Shares with me")) {
      FriendRow(
        friend: Friend(
          id: "3",
          email: "lisa@example.com",
          phone: nil,
          username: nil,
          firstName: "Lisa Olsen",
          profilePictureUrl: nil,
          oauthAvatarUrl: nil,
          sharesWithMe: Friend.SharesWithMe(
            hidden: false,
            showEarningsToMe: false,
            sharedAt: "2025-01-01",
            notificationFrequency: .muted
          ),
          iShareWith: nil
        ),
        sectionType: .incoming,
        isActionInProgress: false,
        isHiddenInFriendsTab: false,
        areServerActionsUnavailable: true,
        isHideActionDisabled: true,
        onToggleEarnings: {},
        onShareBack: {},
        onToggleMuted: {},
        onToggleOwnerMuted: {},
        onToggleHidden: {},
        onBlock: {},
        onRemove: { _ in }
      )
    }
  }
  .listStyle(.insetGrouped)
}
