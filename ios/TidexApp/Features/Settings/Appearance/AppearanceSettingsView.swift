import SwiftUI

/// Appearance settings view
/// Allows users to choose between system, light, and dark themes
struct AppearanceSettingsView: View {
  @Environment(\.colorScheme) private var systemColorScheme
  @StateObject private var viewModel = AppearanceSettingsViewModel()

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Spacing.lg) {
        // Error message
        if let error = viewModel.errorMessage {
          errorBanner(error)
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
      .padding(.horizontal, Spacing.md)
      .padding(.vertical, Spacing.lg)
    }
    .background(Color.tidexBackground)
    .navigationTitle(String(localized: .appearanceTitle))
    .navigationBarTitleDisplayMode(.inline)
    .task {
      await viewModel.loadSettings()
    }
  }

  // MARK: - Error Banner

  private func errorBanner(_ message: String) -> some View {
    HStack(spacing: Spacing.sm) {
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.tidexBody)
        .foregroundColor(.tidexError)

      Text(message)
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextPrimary)

      Spacer()

      Button {
        viewModel.clearError()
      } label: {
        Image(systemName: "xmark")
          .font(.tidexCaption)
          .foregroundColor(.tidexTextMuted)
      }
    }
    .padding(Spacing.sm)
    .background(Color.tidexError.opacity(0.1))
    .cornerRadius(CornerRadius.sm)
  }

  // MARK: - Theme Selection Section

  private var themeSelectionSection: some View {
    TidexSettingsSection(
      title: String(localized: .appearanceThemeSectionTitle),
      footer: { currentThemeInfo }
    ) {
      ForEach(AppTheme.allCases, id: \.self) { theme in
        themeOptionRow(theme)
        if theme != AppTheme.allCases.last {
          settingsDivider
        }
      }
    }
  }

  private func themeOptionRow(_ theme: AppTheme) -> some View {
    let isSelected = viewModel.selectedTheme == theme

    return Button {
      viewModel.selectedTheme = theme
    } label: {
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

        Spacer()

        // Selection indicator
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
          .font(.system(size: 24))
          .foregroundColor(isSelected ? .tidexBlue : .tidexTextMuted)
      }
      .padding(.vertical, Spacing.xs)
    }
    .buttonStyle(.plain)
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
    TidexSettingsSection(title: String(localized: .appearanceCalendarContentColorSectionTitle)) {
      ForEach(CalendarContentColorStyle.allCases, id: \.self) { style in
        calendarContentColorOptionRow(style)
        if style != CalendarContentColorStyle.allCases.last {
          settingsDivider
        }
      }
    }
  }

  private func calendarContentColorOptionRow(_ style: CalendarContentColorStyle) -> some View {
    let isSelected = viewModel.selectedCalendarContentColorStyle == style

    return Button {
      viewModel.selectedCalendarContentColorStyle = style
    } label: {
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

        Spacer()

        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
          .font(.system(size: 24))
          .foregroundColor(isSelected ? .tidexBlue : .tidexTextMuted)
      }
      .padding(.vertical, Spacing.xs)
    }
    .buttonStyle(.plain)
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
    TidexSettingsSection(
      title: String(localized: .appearanceStartupTabSectionTitle),
      footer: { Text(String(localized: .appearanceStartupTabSectionDescription)) }
    ) {
      ForEach(StartupTabOption.allCases, id: \.self) { tab in
        startupTabRow(tab)
        if tab != StartupTabOption.allCases.last {
          settingsDivider
        }
      }
    }
  }

  private func startupTabRow(_ tab: StartupTabOption) -> some View {
    let isSelected = viewModel.selectedStartupTab == tab

    return Button {
      viewModel.selectedStartupTab = tab
    } label: {
      HStack(spacing: Spacing.md) {
        ZStack {
          RoundedRectangle(cornerRadius: CornerRadius.sm)
            .fill(Color.tidexBlue.opacity(0.1))
            .frame(width: 40, height: 40)

          Image(systemName: startupTabIcon(tab))
            .font(.tidexBody)
            .foregroundColor(.tidexBlue)
        }

        Text(startupTabTitle(tab))
          .font(.tidexBodyMedium)
          .foregroundColor(.tidexTextPrimary)

        Spacer()

        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
          .font(.system(size: 24))
          .foregroundColor(isSelected ? .tidexBlue : .tidexTextMuted)
      }
      .padding(.vertical, Spacing.xs)
    }
    .buttonStyle(.plain)
  }

  private func startupTabTitle(_ tab: StartupTabOption) -> String {
    switch tab {
    case .home:
      return String(localized: .tabsHome)
    case .shifts:
      return String(localized: .tabsShifts)
    case .add:
      return String(localized: .tabsAdd)
    case .wagey:
      return String(localized: .tabsWagey)
    case .sharing:
      return String(localized: .tabsSharing)
    }
  }

  private func startupTabIcon(_ tab: StartupTabOption) -> String {
    switch tab {
    case .home:
      return "speedometer"
    case .shifts:
      return "calendar"
    case .add:
      return "plus.circle.fill"
    case .wagey:
      return "sparkles"
    case .sharing:
      return "person.2.fill"
    }
  }

  // MARK: - Dashboard Controls

  private var dashboardControlsSection: some View {
    TidexSettingsSection(title: String(localized: .appearanceDashboardSectionTitle)) {
      Toggle(isOn: $viewModel.showDashboardClockButtons) {
        VStack(alignment: .leading, spacing: Spacing.micro) {
          Text(String(localized: .appearanceDashboardClockButtonsTitle))
            .font(.tidexBodyMedium)
            .foregroundColor(.tidexTextPrimary)

          Text(String(localized: .appearanceDashboardClockButtonsDescription))
            .font(.tidexFootnote)
            .foregroundColor(.tidexTextSecondary)
        }
      }
      .tint(.tidexBlue)
    }
  }

  private var settingsDivider: some View {
    TidexSettingsDivider()
  }
}

// MARK: - Preview

#Preview {
  NavigationStack {
    AppearanceSettingsView()
  }
}
