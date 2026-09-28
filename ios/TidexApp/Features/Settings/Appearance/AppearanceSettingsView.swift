import SwiftUI

/// Appearance settings view
/// Allows users to choose between system, light, and dark themes
struct AppearanceSettingsView: View {
  @Environment(\.colorScheme) private var systemColorScheme
  @State private var viewModel = AppearanceSettingsViewModel()

  var body: some View {
    Form {
      Group {
        // Error message
        if let error = viewModel.errorMessage {
          ErrorBanner(message: error, onDismiss: { viewModel.clearError() })
        }

        // Theme selection
        themeSelectionSection

        // Startup tab selection
        startupTabSection

        // Dashboard controls
        dashboardControlsSection

        // Calendar content color selection
        calendarContentColorSection
      }
      .listRowBackground(Color.tidexSurfacePrimary)
    }
    .tidexListBackground()
    .navigationTitle(String(localized: .appearanceTitle))
    .navigationBarTitleDisplayMode(.inline)
    .task {
      await viewModel.loadSettings()
    }
  }

  // MARK: - Theme Selection Section

  private var themeSelectionSection: some View {
    Section {
      Picker(selection: $viewModel.selectedTheme) {
        ForEach(AppTheme.allCases, id: \.self) { theme in
          themeOptionRow(theme).tag(theme)
        }
      } label: {
        EmptyView()
      }
      .pickerStyle(.inline)
    } header: {
      Text(String(localized: .appearanceThemeSectionTitle))
    } footer: {
      currentThemeInfo
    }
  }

  private func themeOptionRow(_ theme: AppTheme) -> some View {
    HStack(spacing: Spacing.md) {
      // Theme preview
      themePreview(theme)

      // Theme info
      VStack(alignment: .leading, spacing: Spacing.micro) {
        Text(themeTitle(theme))
          .font(.tidexBodyMedium)
          .foregroundColor(.tidexTextPrimary)

        Text(themeDescription(theme))
          .font(.tidexFootnote)
          .foregroundColor(.tidexTextSecondary)
      }
    }
    .padding(.vertical, Spacing.xs)
  }

  private func themePreview(_ theme: AppTheme) -> some View {
    // Determine which color scheme to show in preview
    let previewScheme: ColorScheme = {
      switch theme {
      case .system:
        return systemColorScheme

      case .light:
        return .light

      case .dark:
        return .dark
      }
    }()

    let isDark = previewScheme == .dark

    return ZStack {
      // Background
      RoundedRectangle(cornerRadius: CornerRadius.sm)
        .fill(isDark ? Color.tidexDarkSurfacePrimary : Color.tidexLightSurfaceSecondary)
        .frame(width: 48, height: 48)

      // Icon
      Image(systemName: themeIcon(theme))
        .font(.tidexBodyLarge)
        .foregroundColor(isDark ? .tidexDarkTextPrimary : .tidexLightTextPrimary)
    }
  }

  private func themeIcon(_ theme: AppTheme) -> String {
    switch theme {
    case .system:
      return "circle.lefthalf.filled"

    case .light:
      return "sun.max.fill"

    case .dark:
      return "moon.fill"
    }
  }

  private func themeTitle(_ theme: AppTheme) -> String {
    switch theme {
    case .system:
      return String(localized: .appearanceThemeSystem)

    case .light:
      return String(localized: .appearanceThemeLight)

    case .dark:
      return String(localized: .appearanceThemeDark)
    }
  }

  private func themeDescription(_ theme: AppTheme) -> String {
    switch theme {
    case .system:
      return String(localized: .appearanceThemeSystemDescription)

    case .light:
      return String(localized: .appearanceThemeLightDescription)

    case .dark:
      return String(localized: .appearanceThemeDarkDescription)
    }
  }

  // MARK: - Calendar Content Color Section

  private var calendarContentColorSection: some View {
    Section(String(localized: .appearanceCalendarContentColorSectionTitle)) {
      Picker(selection: $viewModel.selectedCalendarContentColorStyle) {
        ForEach(CalendarContentColorStyle.allCases, id: \.self) { style in
          calendarContentColorOptionRow(style).tag(style)
        }
      } label: {
        EmptyView()
      }
      .pickerStyle(.inline)
    }
  }

  private func calendarContentColorOptionRow(_ style: CalendarContentColorStyle) -> some View {
    HStack(spacing: Spacing.md) {
      calendarContentColorPreview(style)

      VStack(alignment: .leading, spacing: Spacing.micro) {
        Text(calendarContentColorTitle(style))
          .font(.tidexBodyMedium)
          .foregroundColor(.tidexTextPrimary)

        Text(calendarContentColorDescription(style))
          .font(.tidexFootnote)
          .foregroundColor(.tidexTextSecondary)
      }
    }
    .padding(.vertical, Spacing.xs)
  }

  private func calendarContentColorPreview(_ style: CalendarContentColorStyle) -> some View {
    ZStack {
      RoundedRectangle(cornerRadius: CornerRadius.sm)
        .fill(calendarContentColorPreviewBackground(style))
        .frame(width: 48, height: 48)

      Image(systemName: calendarContentColorIcon(style))
        .font(.tidexBodyLarge)
        .foregroundColor(calendarContentColorPreviewForeground(style))
    }
  }

  private func calendarContentColorPreviewBackground(_ style: CalendarContentColorStyle) -> Color {
    switch style {
    case .workplace:
      return Color.tidexPurple.opacity(0.12)

    case .monochrome:
      return Color.tidexSurfaceSecondary
    }
  }

  private func calendarContentColorPreviewForeground(_ style: CalendarContentColorStyle) -> Color {
    switch style {
    case .workplace:
      return .tidexPurple

    case .monochrome:
      return .tidexTextPrimary
    }
  }

  private func calendarContentColorIcon(_ style: CalendarContentColorStyle) -> String {
    switch style {
    case .workplace:
      return "paintpalette.fill"

    case .monochrome:
      return "circle.lefthalf.filled"
    }
  }

  private func calendarContentColorTitle(_ style: CalendarContentColorStyle) -> String {
    switch style {
    case .workplace:
      return String(localized: .appearanceCalendarContentColorWorkplace)

    case .monochrome:
      return String(localized: .appearanceCalendarContentColorMonochrome)
    }
  }

  private func calendarContentColorDescription(_ style: CalendarContentColorStyle) -> String {
    switch style {
    case .workplace:
      return String(localized: .appearanceCalendarContentColorWorkplaceDescription)

    case .monochrome:
      return String(localized: .appearanceCalendarContentColorMonochromeDescription)
    }
  }

  // MARK: - Current Theme Info

  private var currentThemeInfo: some View {
    HStack(spacing: Spacing.xs) {
      Image(systemName: "info.circle")
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextMuted)

      Text(currentThemeInfoText)
        .font(.tidexFootnote)
        .foregroundColor(.tidexTextMuted)
    }
  }

  private var currentThemeInfoText: String {
    switch viewModel.selectedTheme {
    case .system:
      let currentMode =
        systemColorScheme == .dark
        ? String(localized: .appearanceInfoDark)
        : String(localized: .appearanceInfoLight)
      return String(localized: .appearanceInfoSystemActive(currentMode))

    case .light:
      return String(localized: .appearanceInfoLightActive)

    case .dark:
      return String(localized: .appearanceInfoDarkActive)
    }
  }

  // MARK: - Startup Tab

  private var startupTabSection: some View {
    Section {
      Picker(selection: $viewModel.selectedStartupTab) {
        ForEach(StartupTabOption.allCases, id: \.self) { tab in
          startupTabRow(tab).tag(tab)
        }
      } label: {
        EmptyView()
      }
      .pickerStyle(.inline)
    } header: {
      Text(String(localized: .appearanceStartupTabSectionTitle))
    } footer: {
      Text(.appearanceStartupTabSectionDescription)
    }
  }

  private func startupTabRow(_ tab: StartupTabOption) -> some View {
    HStack(spacing: Spacing.md) {
      ZStack {
        RoundedRectangle(cornerRadius: CornerRadius.sm)
          .fill(Color.tidexBlue.opacity(0.1))
          .frame(width: 40, height: 40)

        Image(systemName: startupTabIcon(tab))
          .font(.tidexBody)
          .foregroundColor(.tidexBlue)
          .accessibilityHidden(true)
      }

      Text(startupTabTitle(tab))
        .font(.tidexBodyMedium)
        .foregroundColor(.tidexTextPrimary)
    }
    .padding(.vertical, Spacing.xs)
  }

  private func startupTabTitle(_ tab: StartupTabOption) -> String {
    switch tab {
    case .home:
      return String(localized: .tabsHome)

    case .shifts:
      return String(localized: .tabsShifts)

    case .sharing:
      return String(localized: .tabsSharing)
    }
  }

  private func startupTabIcon(_ tab: StartupTabOption) -> String {
    switch tab {
    case .home:
      return "house.fill"

    case .shifts:
      return "calendar"

    case .sharing:
      return "person.2.fill"
    }
  }

  // MARK: - Dashboard Controls

  private var dashboardControlsSection: some View {
    Section(String(localized: .appearanceDashboardSectionTitle)) {
      Toggle(isOn: $viewModel.showDashboardClockButtons) {
        VStack(alignment: .leading, spacing: Spacing.micro) {
          Text(.appearanceDashboardClockButtonsTitle)
            .font(.tidexBodyMedium)
            .foregroundColor(.tidexTextPrimary)

          Text(.appearanceDashboardClockButtonsDescription)
            .font(.tidexFootnote)
            .foregroundColor(.tidexTextSecondary)
        }
      }
      .tint(.tidexBlue)
    }
  }
}

// MARK: - Preview

#Preview {
  NavigationStack {
    AppearanceSettingsView()
  }
}
