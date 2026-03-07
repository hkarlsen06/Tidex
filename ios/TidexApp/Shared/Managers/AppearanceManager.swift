import Foundation
import SwiftUI
import UIKit
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "AppearanceManager")

/// Theme options for the app
enum AppTheme: String, CaseIterable {
  case system
  case light
  case dark

  /// Resolve the effective color scheme for launch-time views.
  func resolvedColorScheme(fallback systemColorScheme: ColorScheme) -> ColorScheme {
    switch self {
    case .system: return systemColorScheme
    case .light: return .light
    case .dark: return .dark
    }
  }

  /// Convert to SwiftUI ColorScheme for .preferredColorScheme modifier
  var colorScheme: ColorScheme? {
    switch self {
    case .system: return nil  // Let system decide
    case .light: return .light
    case .dark: return .dark
    }
  }

  /// Convert to UIKit UIUserInterfaceStyle for window override
  var userInterfaceStyle: UIUserInterfaceStyle {
    switch self {
    case .system: return .unspecified  // Follow system
    case .light: return .light
    case .dark: return .dark
    }
  }
}

/// Calendar animation style options
enum CalendarAnimationStyle: String, CaseIterable {
  case horizontal
  case vertical
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

  /// The current calendar animation style
  @Published private(set) var calendarAnimationStyle: CalendarAnimationStyle = .horizontal

  /// The color scheme to apply (nil means follow system)
  var colorScheme: ColorScheme? {
    theme.colorScheme
  }

  // MARK: - Private Properties

  /// UserDefaults key for caching theme locally
  private let themeKey = "cachedTheme"

  /// UserDefaults key for calendar animation style
  private let calendarAnimationStyleKey = "calendarAnimationStyle"

  // MARK: - Initialization

  private init() {
    // Load cached theme from UserDefaults for immediate display
    if let cachedTheme = UserDefaults.standard.string(forKey: themeKey),
      let theme = AppTheme(rawValue: cachedTheme)
    {
      self.theme = theme
      logger.debug("Loaded cached theme: \(cachedTheme)")
    }

    // Load cached calendar animation style
    if let cachedStyle = UserDefaults.standard.string(forKey: calendarAnimationStyleKey),
      let style = CalendarAnimationStyle(rawValue: cachedStyle)
    {
      self.calendarAnimationStyle = style
      logger.debug("Loaded cached calendar animation style: \(cachedStyle)")
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

  /// Update the calendar animation style
  /// - Parameter style: The new animation style to apply
  func setCalendarAnimationStyle(_ style: CalendarAnimationStyle) {
    guard self.calendarAnimationStyle != style else { return }

    self.calendarAnimationStyle = style

    // Cache in UserDefaults
    UserDefaults.standard.set(style.rawValue, forKey: calendarAnimationStyleKey)

    logger.info("Calendar animation style updated to: \(style.rawValue)")
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
        logger.debug(
          "Applied \(self.theme.rawValue) (style: \(String(describing: style.rawValue))) to window and rootVC"
        )
      }
    }
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
        let parsed = AppTheme(rawValue: themeString)
      {
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

  /// Load calendar animation style from user settings
  /// Called when settings are loaded from the repository
  /// - Parameter styleString: The animation style string from user settings
  func loadCalendarAnimationStyleFromSettings(_ styleString: String?) {
    // Check if we already have a locally cached preference
    let hasCachedPreference = UserDefaults.standard.string(forKey: calendarAnimationStyleKey) != nil

    if !hasCachedPreference {
      // No local cache - use the server value
      let newStyle: CalendarAnimationStyle
      if let styleString = styleString,
        let parsed = CalendarAnimationStyle(rawValue: styleString)
      {
        newStyle = parsed
      } else {
        newStyle = .horizontal
      }

      self.calendarAnimationStyle = newStyle
      UserDefaults.standard.set(newStyle.rawValue, forKey: calendarAnimationStyleKey)
      logger.info("Calendar animation style loaded from settings: \(newStyle.rawValue)")
    }
  }
}
