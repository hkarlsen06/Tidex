import UIKit

@MainActor
enum PrivacyBlurManager {
    private static var privacyBlurView: UIVisualEffectView?

    static func showIfNeeded() {
        guard BiometricAuthService.isEnabledStatic else { return }
        guard !BiometricAuthService.isCurrentlyAuthenticating else { return }
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
    }

    private static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }
}
