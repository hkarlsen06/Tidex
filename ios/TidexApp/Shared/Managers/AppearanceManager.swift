// swiftlint:disable:next blanket_disable_command
// swiftlint:disable line_length superfluous_disable_command
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable conditional_returns_on_newline explicit_acl explicit_enum_raw_value explicit_top_level_acl
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable explicit_type_interface prefixed_toplevel_constant required_deinit shorthand_optional_binding
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable sorted_enum_cases sorted_imports switch_case_on_newline type_contents_order
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

/// Calendar content color options
enum CalendarContentColorStyle: String, CaseIterable {
  case workplace
  case monochrome

  var usesWorkplaceColors: Bool {
    self == .workplace
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

  /// The current calendar content color style
  @Published private(set) var calendarContentColorStyle: CalendarContentColorStyle = .workplace

  /// The color scheme to apply (nil means follow system)
  var colorScheme: ColorScheme? {
    theme.colorScheme
  }

  // MARK: - Private Properties

  /// UserDefaults key for caching theme locally
  private let themeKey = "cachedTheme"

  /// UserDefaults key for calendar content color style
  private let calendarContentColorStyleKey = "calendarContentColorStyle"

  // MARK: - Initialization

  private init() {
    // Load cached theme from UserDefaults for immediate display
    if let cachedTheme = UserDefaults.standard.string(forKey: themeKey),
      let theme = AppTheme(rawValue: cachedTheme)
    {
      self.theme = theme
      logger.debug("Loaded cached theme: \(cachedTheme)")
    }

    if let cachedStyle = UserDefaults.standard.string(forKey: calendarContentColorStyleKey),
      let style = CalendarContentColorStyle(rawValue: cachedStyle)
    {
      self.calendarContentColorStyle = style
      logger.debug("Loaded cached calendar content color style: \(cachedStyle)")
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

  /// Update the calendar content color style
  /// - Parameter style: The new color style to apply
  func setCalendarContentColorStyle(_ style: CalendarContentColorStyle) {
    guard self.calendarContentColorStyle != style else { return }

    self.calendarContentColorStyle = style
    UserDefaults.standard.set(style.rawValue, forKey: calendarContentColorStyleKey)

    logger.info("Calendar content color style updated to: \(style.rawValue)")
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
      if let themeString,
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

  /// Load calendar content color style from user settings
  /// Called when settings are loaded from the repository
  /// - Parameter styleString: The color style string from user settings
  func loadCalendarContentColorStyleFromSettings(_ styleString: String?) {
    let hasCachedPreference =
      UserDefaults.standard.string(forKey: calendarContentColorStyleKey) != nil

    if !hasCachedPreference {
      let newStyle: CalendarContentColorStyle
      if let styleString,
        let parsed = CalendarContentColorStyle(rawValue: styleString)
      {
        newStyle = parsed
      } else {
        newStyle = .workplace
      }

      self.calendarContentColorStyle = newStyle
      UserDefaults.standard.set(newStyle.rawValue, forKey: calendarContentColorStyleKey)
      logger.info("Calendar content color style loaded from settings: \(newStyle.rawValue)")
    }
  }
}
