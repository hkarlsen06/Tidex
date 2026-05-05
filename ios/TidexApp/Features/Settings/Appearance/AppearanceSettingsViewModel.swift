import Foundation
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "AppearanceSettingsViewModel")

enum StartupTabOption: String, CaseIterable {
  case home
  case shifts
  case add
  case wagey
  case sharing
}

/// ViewModel for appearance settings
@MainActor
final class AppearanceSettingsViewModel: ObservableObject {
  private static let startupTabCacheKey = "defaultStartupTab"

  // MARK: - Published State

  /// The currently selected theme
  @Published var selectedTheme: AppTheme = .system {
    didSet {
      if oldValue != selectedTheme && !isInitialLoad {
        updateTheme()
      }
    }
  }

  /// The currently selected calendar animation style
  @Published var selectedCalendarAnimationStyle: CalendarAnimationStyle = .horizontal {
    didSet {
      if oldValue != selectedCalendarAnimationStyle && !isInitialLoad {
        updateCalendarAnimationStyle()
      }
    }
  }

  /// Whether dashboard clock buttons are visible
  @Published var showDashboardClockButtons: Bool = true {
    didSet {
      if oldValue != showDashboardClockButtons && !isInitialLoad {
        updateShowDashboardClockButtons()
      }
    }
  }

  /// The default tab to open when launching the app
  @Published var selectedStartupTab: StartupTabOption = .home {
    didSet {
      if oldValue != selectedStartupTab && !isInitialLoad {
        updateDefaultStartupTab()
      }
    }
  }

  /// Loading state
  @Published var isLoading: Bool = false

  /// Error message
  @Published var errorMessage: String?

  // MARK: - Private Properties

  private let settingsRepository = SettingsRepository.shared
  private let appearanceManager = AppearanceManager.shared
  private var userId: String?
  private var isInitialLoad = true

  // MARK: - Initialization

  init() {}

  // MARK: - Public Methods

  /// Load appearance settings
  func loadSettings() async {
    isLoading = true
    errorMessage = nil

    userId = await resolveUserIdForLocalSettings()

    guard let userId = userId else {
      isLoading = false
      return
    }

    // Load settings from repository
    let settings = settingsRepository.getSettings(for: userId)

    // Update state without triggering saves
    isInitialLoad = true
    if let themeString = settings?.theme,
      let theme = AppTheme(rawValue: themeString)
    {
      selectedTheme = theme
    } else {
      selectedTheme = .system
    }

    // Load calendar animation style from settings (synced from server)
    if let styleString = settings?.calendar_animation_style,
      let style = CalendarAnimationStyle(rawValue: styleString)
    {
      selectedCalendarAnimationStyle = style
      // Also update AppearanceManager to match
      appearanceManager.setCalendarAnimationStyle(style)
    } else {
      selectedCalendarAnimationStyle = .horizontal
    }

    showDashboardClockButtons = settings?.effectiveShowDashboardClockButtons ?? true

    let resolvedStartupTabRawValue: String
    if let settings {
      resolvedStartupTabRawValue = settings.effectiveDefaultStartupTab
    } else {
      resolvedStartupTabRawValue =
        UserDefaults.standard.string(forKey: Self.startupTabCacheKey) ?? "home"
    }
    let normalizedStartupTabRawValue =
      resolvedStartupTabRawValue == "stats"
      ? StartupTabOption.home.rawValue : resolvedStartupTabRawValue
    selectedStartupTab = StartupTabOption(rawValue: normalizedStartupTabRawValue) ?? .home
    UserDefaults.standard.set(selectedStartupTab.rawValue, forKey: Self.startupTabCacheKey)

    isInitialLoad = false

    isLoading = false
    logger.info("Loaded appearance settings")
  }

  /// Clear error message
  func clearError() {
    errorMessage = nil
  }

  // MARK: - Private Methods

  private func resolveUserIdForLocalSettings() async -> String? {
    do {
      return try await AuthSessionManager.shared.getUserId()
    } catch {
      if AuthSessionManager.shared.isTransientSessionResolutionError(error),
        let offlineUserId = AuthSessionManager.shared.offlineUserIdFallback()
      {
        logger.info("Using offline user id fallback for appearance settings")
        return offlineUserId
      }

      logger.error("Failed to get user session: \(error.localizedDescription)")
      return nil
    }
  }

  /// Update theme in repository and apply to app
  private func updateTheme() {
    guard !isInitialLoad, let userId = userId else { return }

    // Apply immediately to AppearanceManager
    appearanceManager.setTheme(selectedTheme)

    // Save to repository (automatically triggers sync)
    Task {
      do {
        _ = try await settingsRepository.updateSettings(
          for: userId,
          theme: selectedTheme.rawValue
        )

        logger.info("Updated theme to: \(self.selectedTheme.rawValue)")
      } catch {
        logger.error("Failed to save theme: \(error.localizedDescription)")
        errorMessage = "Failed to save theme preference"
      }
    }
  }

  /// Update calendar animation style in repository and apply to app
  private func updateCalendarAnimationStyle() {
    guard !isInitialLoad, let userId = userId else { return }

    // Apply immediately to AppearanceManager
    appearanceManager.setCalendarAnimationStyle(selectedCalendarAnimationStyle)

    // Save to repository (automatically triggers sync)
    Task {
      do {
        _ = try await settingsRepository.updateSettings(
          for: userId,
          calendarAnimationStyle: selectedCalendarAnimationStyle.rawValue
        )

        logger.info(
          "Updated calendar animation style to: \(self.selectedCalendarAnimationStyle.rawValue)")
      } catch {
        logger.error("Failed to save calendar animation style: \(error.localizedDescription)")
        errorMessage = "Failed to save animation preference"
      }
    }
  }

  /// Update dashboard clock button visibility in repository
  private func updateShowDashboardClockButtons() {
    guard !isInitialLoad, let userId = userId else { return }

    Task {
      do {
        _ = try await settingsRepository.updateSettings(
          for: userId,
          showDashboardClockButtons: showDashboardClockButtons
        )

        NotificationCenter.default.post(
          name: .dashboardClockButtonsVisibilityDidChange,
          object: nil,
          userInfo: ["isVisible": self.showDashboardClockButtons]
        )

        logger.info(
          "Updated dashboard clock button visibility to: \(self.showDashboardClockButtons)")
      } catch {
        logger.error(
          "Failed to save dashboard clock button visibility: \(error.localizedDescription)")
        errorMessage = "Failed to save dashboard preference"
      }
    }
  }

  /// Update default startup tab in repository
  private func updateDefaultStartupTab() {
    guard !isInitialLoad, let userId = userId else { return }

    Task {
      do {
        _ = try await settingsRepository.updateSettings(
          for: userId,
          defaultStartupTab: selectedStartupTab.rawValue
        )
        UserDefaults.standard.set(selectedStartupTab.rawValue, forKey: Self.startupTabCacheKey)

        logger.info("Updated default startup tab to: \(self.selectedStartupTab.rawValue)")
      } catch {
        logger.error("Failed to save default startup tab: \(error.localizedDescription)")
        errorMessage = "Failed to save startup tab preference"
      }
    }
  }
}
