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

        // Calendar animation selection
        calendarAnimationSection

        // Startup tab selection
        startupTabSection

        // Dashboard controls
        dashboardControlsSection
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
    settingsSection(
      title: String(localized: .appearanceThemeSectionTitle),
      footer: currentThemeInfo
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
            .font(.body)
            .foregroundColor(.tidexTextPrimary)

          Text(themeDescription(theme))
            .font(.caption)
            .foregroundColor(.secondary)
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
        .fill(
          isDark
            ? Color(red: 0.1, green: 0.1, blue: 0.15) : Color(red: 0.95, green: 0.95, blue: 0.97)
        )
        .frame(width: 48, height: 48)

      // Icon
      Image(systemName: themeIcon(theme))
        .font(.tidexBodyLarge)
        .foregroundColor(isDark ? .white : Color(red: 0.2, green: 0.2, blue: 0.25))
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

  // MARK: - Calendar Animation Section

  private var calendarAnimationSection: some View {
    settingsSection(title: String(localized: .appearanceCalendarAnimationSectionTitle)) {
      ForEach(CalendarAnimationStyle.allCases, id: \.self) { style in
        animationStyleOptionRow(style)
        if style != CalendarAnimationStyle.allCases.last {
          settingsDivider
        }
      }
    }
  }

  private func animationStyleOptionRow(_ style: CalendarAnimationStyle) -> some View {
    let isSelected = viewModel.selectedCalendarAnimationStyle == style

    return Button {
      viewModel.selectedCalendarAnimationStyle = style
    } label: {
      HStack(spacing: Spacing.md) {
        // Animation style preview
        animationStylePreview(style)

        // Style info
        VStack(alignment: .leading, spacing: Spacing.micro) {
          Text(animationStyleTitle(style))
            .font(.body)
            .foregroundColor(.tidexTextPrimary)

          Text(animationStyleDescription(style))
            .font(.caption)
            .foregroundColor(.secondary)
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

  private func animationStylePreview(_ style: CalendarAnimationStyle) -> some View {
    ZStack {
      RoundedRectangle(cornerRadius: CornerRadius.sm)
        .fill(Color.tidexBlue.opacity(0.1))
        .frame(width: 48, height: 48)

      Image(systemName: animationStyleIcon(style))
        .font(.tidexBodyLarge)
        .foregroundColor(.tidexBlue)
    }
  }

  private func animationStyleIcon(_ style: CalendarAnimationStyle) -> String {
    switch style {
    case .horizontal:
      return "arrow.left.arrow.right"
    case .vertical:
      return "arrow.up.arrow.down"
    }
  }

  private func animationStyleTitle(_ style: CalendarAnimationStyle) -> String {
    switch style {
    case .horizontal:
      return String(localized: .appearanceCalendarAnimationHorizontal)
    case .vertical:
      return String(localized: .appearanceCalendarAnimationVertical)
    }
  }

  private func animationStyleDescription(_ style: CalendarAnimationStyle) -> String {
    switch style {
    case .horizontal:
      return String(localized: .appearanceCalendarAnimationHorizontalDescription)
    case .vertical:
      return String(localized: .appearanceCalendarAnimationVerticalDescription)
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
    settingsSection(
      title: String(localized: .appearanceStartupTabSectionTitle),
      footer: Text(String(localized: .appearanceStartupTabSectionDescription))
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
          .font(.body)
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
    settingsSection(title: String(localized: .appearanceDashboardSectionTitle)) {
      Toggle(isOn: $viewModel.showDashboardClockButtons) {
        VStack(alignment: .leading, spacing: Spacing.micro) {
          Text(String(localized: .appearanceDashboardClockButtonsTitle))
            .font(.body)
            .foregroundColor(.tidexTextPrimary)

          Text(String(localized: .appearanceDashboardClockButtonsDescription))
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }
      .tint(.tidexBlue)
    }
  }

  @ViewBuilder
  private func settingsSection<Footer: View, Content: View>(
    title: String,
    footer: Footer,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      Text(title)
        .font(.tidexFootnoteMedium)
        .foregroundColor(.tidexTextSecondary)
        .textCase(.uppercase)
        .padding(.horizontal, Spacing.sm)

      VStack(spacing: 0) {
        content()
      }
      .padding(Spacing.md)
      .background(Color.tidexSurfacePrimary)
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
      .tidexCardShadow(cornerRadius: CornerRadius.lg)

      footer
        .font(.tidexFootnote)
        .foregroundColor(.tidexTextSecondary)
        .padding(.horizontal, Spacing.sm)
    }
  }

  @ViewBuilder
  private func settingsSection<Content: View>(
    title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    settingsSection(title: title, footer: EmptyView(), content: content)
  }

  private var settingsDivider: some View {
    Divider()
      .background(Color.tidexBorderSubtle)
      .padding(.vertical, Spacing.sm)
  }
}

// MARK: - Preview

#Preview {
  NavigationStack {
    AppearanceSettingsView()
  }
}
