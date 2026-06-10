import Foundation
import os.log

private enum AppearanceSettingsConstants {
  static var logger: Logger {
    Logger(subsystem: "com.tidex.app", category: "AppearanceSettingsViewModel")
  }
}

internal enum StartupTabOption: String, CaseIterable {
  case add
  case home
  case sharing
  case shifts
  case wagey

  internal static let allCases: [Self] = [.home, .shifts, .add, .wagey, .sharing]
}

/// ViewModel for appearance settings
@MainActor
internal final class AppearanceSettingsViewModel: ObservableObject {
  private static let startupTabCacheKey: String = "defaultStartupTab"

  // MARK: - Published State

  /// The currently selected theme
  @Published internal var selectedTheme: AppTheme = .system {
    didSet {
      if oldValue != selectedTheme, !isInitialLoad {
        updateTheme()
      }
    }
  }

  /// The currently selected calendar content color style
  @Published internal var selectedCalendarContentColorStyle: CalendarContentColorStyle = .workplace {
    didSet {
      if oldValue != selectedCalendarContentColorStyle, !isInitialLoad {
        updateCalendarContentColorStyle()
      }
    }
  }

  /// Whether dashboard clock buttons are visible
  @Published internal var showDashboardClockButtons: Bool = true {
    didSet {
      if oldValue != showDashboardClockButtons, !isInitialLoad {
        updateShowDashboardClockButtons()
      }
    }
  }

  /// The default tab to open when launching the app
  @Published internal var selectedStartupTab: StartupTabOption = .home {
    didSet {
      if oldValue != selectedStartupTab, !isInitialLoad {
        updateDefaultStartupTab()
      }
    }
  }

  /// Loading state
  @Published internal var isLoading: Bool = false

  /// Error message
  @Published internal var errorMessage: String?

  // MARK: - Private Properties

  private let settingsRepository = SettingsRepository.shared
  private let appearanceManager = AppearanceManager.shared
  private var userId: String?
  private var isInitialLoad: Bool = true

  // MARK: - Initialization

  internal init() {
    // Default initializer required for SwiftLint's explicit initialization policy.
  }

  // MARK: - Public Methods

  /// Load appearance settings
  internal func loadSettings() async {
    isLoading = true
    errorMessage = nil

    userId = await resolveUserIdForLocalSettings()

    guard let userId else {
      isLoading = false
      return
    }

    // Load settings from repository
    let settings: UserSettings? = settingsRepository.getSettings(for: userId)

    // Update state without triggering saves
    isInitialLoad = true
    if let themeString = settings?.theme,
      let theme = AppTheme(rawValue: themeString)
    {
      selectedTheme = theme
    } else {
      selectedTheme = .system
    }

    let calendarContentStyleRaw: String =
      settings?.effectiveCalendarContentColorStyle
      ?? appearanceManager.calendarContentColorStyle.rawValue
    let calendarContentStyle: CalendarContentColorStyle =
      CalendarContentColorStyle(rawValue: calendarContentStyleRaw) ?? .workplace
    selectedCalendarContentColorStyle = calendarContentStyle
    appearanceManager.setCalendarContentColorStyle(calendarContentStyle)

    showDashboardClockButtons = settings?.effectiveShowDashboardClockButtons ?? true

    let resolvedStartupTabRawValue: String
    if let settings {
      resolvedStartupTabRawValue = settings.effectiveDefaultStartupTab
    } else {
      resolvedStartupTabRawValue =
        UserDefaults.standard.string(forKey: Self.startupTabCacheKey) ?? "home"
    }
    let normalizedStartupTabRawValue: String =
      resolvedStartupTabRawValue == "stats"
      ? StartupTabOption.home.rawValue : resolvedStartupTabRawValue
    selectedStartupTab = StartupTabOption(rawValue: normalizedStartupTabRawValue) ?? .home
    UserDefaults.standard.set(selectedStartupTab.rawValue, forKey: Self.startupTabCacheKey)

    isInitialLoad = false

    isLoading = false
    AppearanceSettingsConstants.logger.info("Loaded appearance settings")
  }

  /// Clear error message
  internal func clearError() {
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
        AppearanceSettingsConstants.logger.info("Using offline user id fallback for appearance settings")
        return offlineUserId
      }

      AppearanceSettingsConstants.logger.error("Failed to get user session: \(error.localizedDescription)")
      return nil
    }
  }

  /// Update theme in repository and apply to app
  private func updateTheme() {
    guard !isInitialLoad, let userId else {
      return
    }

    // Apply immediately to AppearanceManager
    appearanceManager.setTheme(selectedTheme)

    // Save to repository (automatically triggers sync)
    Task {
      do {
        _ = try await settingsRepository.updateSettings(
          for: userId,
          theme: selectedTheme.rawValue
        )

        AppearanceSettingsConstants.logger.info("Updated theme to: \(self.selectedTheme.rawValue)")
      } catch {
        AppearanceSettingsConstants.logger.error("Failed to save theme: \(error.localizedDescription)")
        errorMessage = "Failed to save theme preference"
      }
    }
  }

  /// Update calendar content color style in repository and apply to app
  private func updateCalendarContentColorStyle() {
    guard !isInitialLoad, let userId else {
      return
    }

    appearanceManager.setCalendarContentColorStyle(selectedCalendarContentColorStyle)

    Task {
      do {
        _ = try await settingsRepository.updateSettings(
          for: userId,
          calendarContentColorStyle: selectedCalendarContentColorStyle.rawValue
        )

        AppearanceSettingsConstants.logger.info(
          "Updated calendar content color style to: \(self.selectedCalendarContentColorStyle.rawValue)"
        )
      } catch {
        AppearanceSettingsConstants.logger.error(
          "Failed to save calendar content color style: \(error.localizedDescription)"
        )
        errorMessage = String(localized: .appearanceCalendarContentColorSaveError)
      }
    }
  }

  /// Update dashboard clock button visibility in repository
  private func updateShowDashboardClockButtons() {
    guard !isInitialLoad, let userId else {
      return
    }

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

        AppearanceSettingsConstants.logger.info(
          "Updated dashboard clock button visibility to: \(self.showDashboardClockButtons)"
        )
      } catch {
        AppearanceSettingsConstants.logger.error(
          "Failed to save dashboard clock button visibility: \(error.localizedDescription)"
        )
        errorMessage = "Failed to save dashboard preference"
      }
    }
  }

  /// Update default startup tab in repository
  private func updateDefaultStartupTab() {
    guard !isInitialLoad, let userId else {
      return
    }

    Task {
      do {
        _ = try await settingsRepository.updateSettings(
          for: userId,
          defaultStartupTab: selectedStartupTab.rawValue
        )
        UserDefaults.standard.set(selectedStartupTab.rawValue, forKey: Self.startupTabCacheKey)

        AppearanceSettingsConstants.logger.info("Updated default startup tab to: \(self.selectedStartupTab.rawValue)")
      } catch {
        AppearanceSettingsConstants.logger.error("Failed to save default startup tab: \(error.localizedDescription)")
        errorMessage = "Failed to save startup tab preference"
      }
    }
  }
}
