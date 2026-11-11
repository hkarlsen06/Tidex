import Foundation

/// The one invite link waiting for the main app. A link opened while signed out or during
/// onboarding stays here until the confirmation sheet has been shown and closed. Sign-out
/// clears it.
internal enum PendingInviteStore {
  private struct Invite: Codable {
    let inviterId: String
    /// The account that was signed in when the link was opened, or nil when nobody was.
    let openedBy: String?
  }

  private static let key: String = "friends.pendingInvite"

  /// Whether an invite is waiting. Onboarding can use it to skip questions an invite answers.
  internal static var hasPending: Bool {
    UserDefaults.standard.data(forKey: key) != nil
  }

  internal static func save(
    inviterId: String, openedBy userId: String?, defaults: UserDefaults = .standard
  ) {
    guard let data = try? JSONEncoder().encode(Invite(inviterId: inviterId, openedBy: userId))
    else { return }
    defaults.set(data, forKey: key)
  }

  /// The inviter to ask `userId` about. An invite opened by another account is dropped, so it
  /// never reaches someone who did not open it while signed in. One opened while signed out
  /// goes to whoever signs in, who still has to confirm before anything is shared.
  internal static func inviter(for userId: String, defaults: UserDefaults = .standard) -> String? {
    guard let data = defaults.data(forKey: key),
      let invite = try? JSONDecoder().decode(Invite.self, from: data)
    else { return nil }
    guard invite.openedBy == nil || invite.openedBy == userId else {
      clear(defaults: defaults)
      return nil
    }
    return invite.inviterId
  }

  internal static func clear(defaults: UserDefaults = .standard) {
    defaults.removeObject(forKey: key)
  }
}
