import SwiftUI

/// A compact popover showing per-friend notification toggles
/// Shows up to two toggles depending on the relationship direction:
/// - "Receive from [name]" (mutual/incoming): controls whether you get their shift notifications
/// - "Notify [name] about you" (mutual/outgoing): controls whether they get your shift notifications
struct NotificationTogglesPopover: View {
  let friend: Friend
  let sectionType: FriendSectionType
  let isActionInProgress: Bool
  let onToggleMuted: () -> Void
  let onToggleOwnerMuted: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(.sharingNotificationsTitle)
        .font(.system(size: 15, weight: .semibold))
        .foregroundColor(.tidexTextPrimary)

      // Toggle 1: Receive notifications from them (mutual/incoming only)
      if sectionType == .mutual || sectionType == .incoming {
        toggleRow(
          label: String(localized: .sharingNotificationsReceiveFrom(friend.displayName)),
          isOn: !(friend.sharesWithMe?.isMuted ?? true),
          action: onToggleMuted
        )
      }

      // Toggle 2: They receive notifications about you (mutual/outgoing only)
      if sectionType == .mutual || sectionType == .outgoing {
        toggleRow(
          label: String(localized: .sharingNotificationsNotifyThem(friend.displayName)),
          isOn: !(friend.iShareWith?.ownerMuted ?? true),
          action: onToggleOwnerMuted
        )
      }
    }
    .padding()
    .frame(maxWidth: 300)
    .presentationCompactAdaptation(.popover)
  }

  private func toggleRow(label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
    HStack {
      Text(label)
        .font(.system(size: 14))
        .foregroundColor(.tidexTextSecondary)
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)

      Spacer(minLength: 8)

      Toggle("", isOn: .init(get: { isOn }, set: { _ in action() }))
        .labelsHidden()
        .toggleStyle(SwitchToggleStyle(tint: .tidexBlue))
        .scaleEffect(0.8)
        .disabled(isActionInProgress)
    }
  }
}
