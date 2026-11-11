import UIKit

/// Invite links, and what happens when a connection between two friends starts.
@MainActor
internal enum FriendInvite {
  /// Opening this asks the opener to share their shifts with `userId`. It names nothing else.
  internal static func link(for userId: String) -> String {
    "https://tidex.no/invite/\(userId)"
  }

  /// Opens the system share sheet with the user's invite link and a short message.
  internal static func presentShareSheet(for userId: String) {
    let text = String(localized: .sharingInviteMessage) + "\n" + link(for: userId)
    let controller = UIActivityViewController(activityItems: [text], applicationActivities: nil)
    controller.completionWithItemsHandler = { _, completed, _, _ in
      // Copy counts too: the user took the link to send it some other way.
      guard completed else { return }
      Task { @MainActor in
        OnboardingFunnelRecorder.shared.record("friend_invite_sent")
        await NotificationService.shared.requestPermissionAndRegister(for: userId)
      }
    }
    guard
      let window = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene })
        .first(where: { $0.activationState == .foregroundActive })?.keyWindow,
      var presenter = window.rootViewController
    else { return }
    while let presented = presenter.presentedViewController {
      presenter = presented
    }
    // iPad shows the sheet as a popover, which needs an anchor.
    controller.popoverPresentationController?.sourceView = presenter.view
    controller.popoverPresentationController?.sourceRect = CGRect(
      x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0, height: 0)
    controller.popoverPresentationController?.permittedArrowDirections = []
    presenter.present(controller, animated: true)
  }

  /// Call after this user starts sharing with someone: by email or username, from an invite,
  /// or by sharing back. A push about the friend sharing back is useful from now on, so this is
  /// when the app asks for notification permission, if it never has.
  internal static func didStartSharing() {
    OnboardingFunnelRecorder.shared.record("friend_added")
    Task {
      await NotificationService.shared.requestPermissionAndRegister(
        for: AppCoordinator.shared.userId)
    }
  }
}
