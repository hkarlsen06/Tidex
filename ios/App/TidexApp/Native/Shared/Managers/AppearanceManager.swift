import Foundation
import SwiftUI
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

        logger.info("Theme updated to: \(theme.rawValue)")
    }

    /// Load theme from user settings
    /// Called when settings are loaded from the repository
    /// - Parameter themeString: The theme string from user settings
    func loadFromSettings(_ themeString: String?) {
        guard let themeString = themeString,
              let theme = AppTheme(rawValue: themeString) else {
            // Default to system if not set or invalid
            setTheme(.system)
            return
        }

        setTheme(theme)
    }
}
