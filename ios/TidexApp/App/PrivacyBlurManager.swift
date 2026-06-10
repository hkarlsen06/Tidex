// swiftlint:disable:next blanket_disable_command
// swiftlint:disable conditional_returns_on_newline explicit_acl explicit_top_level_acl explicit_type_interface
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable no_magic_numbers
import UIKit

@MainActor
enum PrivacyBlurManager {
  private static var privacyBlurView: UIVisualEffectView?

  static func showIfNeeded() {
    guard privacyBlurView == nil else { return }
    guard let window = keyWindow() else { return }

    let blurEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
    let blurView = UIVisualEffectView(effect: blurEffect)
    blurView.frame = window.bounds
    blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    blurView.tag = 999

    let navyTint = UIView()
    navyTint.backgroundColor = UIColor(red: 0.008, green: 0.032, blue: 0.090, alpha: 0.6)
    navyTint.frame = blurView.bounds
    navyTint.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    blurView.contentView.addSubview(navyTint)

    window.addSubview(blurView)
    privacyBlurView = blurView
  }

  static func hide() {
    privacyBlurView?.removeFromSuperview()
    privacyBlurView = nil

    // Defensive cleanup in case the tracked reference was lost across scene transitions.
    for window in allWindows() {
      while let lingeringView = window.viewWithTag(999) {
        lingeringView.removeFromSuperview()
      }
    }
  }

  private static func keyWindow() -> UIWindow? {
    let windows = allWindows()
    return windows.first(where: \.isKeyWindow) ?? windows.first
  }

  private static func allWindows() -> [UIWindow] {
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
  }
}
