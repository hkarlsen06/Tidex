import Foundation
import SwiftUI
import UIKit
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "AppearanceManager")

/// Theme options for the app
enum AppTheme: String, CaseIterable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    /// Convert to SwiftUI ColorScheme for .preferredColorScheme modifier
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil // Let system decide
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// Convert to UIKit UIUserInterfaceStyle for window override
    var userInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified // Follow system
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Manager for app-wide appearance settings
/// Handles theme persistence and provides the current color scheme to the app
@MainActor
final class AppearanceManager: ObservableObject {

    // MARK: - Singleton

    static let shared = AppearanceManager()

    // MARK: - Published State

    /// The current theme preference
    @Published private(set) var theme: AppTheme = .system

    /// The color scheme to apply (nil means follow system)
    var colorScheme: ColorScheme? {
        theme.colorScheme
    }

    // MARK: - Private Properties

    /// UserDefaults key for caching theme locally
    private let themeKey = "cachedTheme"
    private static let themeKeyStatic = "cachedTheme"

    // MARK: - Static Methods

    /// Get the cached user interface style without requiring MainActor
    /// Use this in SceneDelegate for initial window setup before the manager is accessed
    static func cachedUserInterfaceStyle() -> UIUserInterfaceStyle {
        if let cachedTheme = UserDefaults.standard.string(forKey: themeKeyStatic),
           let theme = AppTheme(rawValue: cachedTheme) {
            return theme.userInterfaceStyle
        }
        return .unspecified // Default to system
    }

    // MARK: - Initialization

    private init() {
        // Load cached theme from UserDefaults for immediate display
        if let cachedTheme = UserDefaults.standard.string(forKey: themeKey),
           let theme = AppTheme(rawValue: cachedTheme) {
            self.theme = theme
            logger.debug("Loaded cached theme: \(cachedTheme)")
        }
    }

    // MARK: - Public Methods

    /// Update the theme
    /// - Parameter theme: The new theme to apply
    func setTheme(_ theme: AppTheme) {
        guard self.theme != theme else { return }

        self.theme = theme

        // Cache in UserDefaults for quick startup
        UserDefaults.standard.set(theme.rawValue, forKey: themeKey)

        // Apply to all windows (UIKit level is more reliable than SwiftUI .preferredColorScheme)
        applyToWindows()

        logger.info("Theme updated to: \(theme.rawValue)")
    }

    /// Apply the current theme to all app windows and their root view controllers
    /// This uses UIKit's overrideUserInterfaceStyle which properly respects system appearance
    func applyToWindows() {
        let style = theme.userInterfaceStyle
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.overrideUserInterfaceStyle = style
                // Also set on root view controller (UIHostingController) to ensure SwiftUI picks it up
                window.rootViewController?.overrideUserInterfaceStyle = style
                logger.debug("Applied \(self.theme.rawValue) (style: \(String(describing: style.rawValue))) to window and rootVC")
            }
        }
    }

    /// Apply theme to a specific window and its root view controller
    /// Called by SceneDelegate after window creation to apply the cached theme
    func applyToWindow(_ window: UIWindow) {
        let style = theme.userInterfaceStyle
        window.overrideUserInterfaceStyle = style
        window.rootViewController?.overrideUserInterfaceStyle = style
        logger.debug("Applied theme \(self.theme.rawValue) (style: \(String(describing: style.rawValue))) to window")
    }

    /// Load theme from user settings
    /// Called when settings are loaded from the repository
    /// - Parameter themeString: The theme string from user settings
    ///
    /// Note: If the user has a locally cached theme preference (in UserDefaults),
    /// we trust that over the server value since it represents their most recent action.
    /// The local preference will sync to the server in the background.
    func loadFromSettings(_ themeString: String?) {
        // Check if we already have a locally cached theme preference
        let hasCachedPreference = UserDefaults.standard.string(forKey: themeKey) != nil

        if !hasCachedPreference {
            // No local cache - use the server value
            let newTheme: AppTheme
            if let themeString = themeString,
               let parsed = AppTheme(rawValue: themeString) {
                newTheme = parsed
            } else {
                newTheme = .system
            }

            self.theme = newTheme
            UserDefaults.standard.set(newTheme.rawValue, forKey: themeKey)
            logger.info("Theme loaded from settings: \(newTheme.rawValue)")
        }

        // Always apply to windows - the SwiftUI view hierarchy may have reset the window style
        applyToWindows()
    }
}
