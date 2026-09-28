import SwiftUI

/// Appearance settings view
/// Theme, calendar colors, dashboard controls and the startup tab.
struct AppearanceSettingsView: View {
  @Environment(\.colorScheme) private var systemColorScheme
  @State private var viewModel = AppearanceSettingsViewModel()

  var body: some View {
    Form {
      Group {
        if let error = viewModel.errorMessage {
          ErrorBanner(message: error, onDismiss: { viewModel.clearError() })
        }

        themeSection
        calendarContentColorSection
        dashboardControlsSection
        startupTabSection
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

  // MARK: - Theme

  private var themeSection: some View {
    Section {
      HStack(alignment: .top, spacing: Spacing.sm) {
        ForEach(AppTheme.allCases, id: \.self) { theme in
          choiceTile(
            title: themeTitle(theme),
            isSelected: viewModel.selectedTheme == theme
          ) {
            viewModel.selectedTheme = theme
          } preview: {
            themePreview(theme)
          }
        }
      }
      .padding(.vertical, Spacing.xs)
    } header: {
      Text(String(localized: .appearanceThemeSectionTitle))
    } footer: {
      Text(currentThemeInfoText)
    }
  }

  @ViewBuilder
  private func themePreview(_ theme: AppTheme) -> some View {
    switch theme {
    case .system:
      // Left half light, right half dark, like the system appearance picker.
      miniScreen(isDark: false)
        .overlay {
          miniScreen(isDark: true)
            .mask {
              HStack(spacing: 0) {
                Color.clear
                Color.black
              }
            }
        }

    case .light:
      miniScreen(isDark: false)

    case .dark:
      miniScreen(isDark: true)
    }
  }

  /// A small drawing of an app screen in fixed light or dark colors.
  private func miniScreen(isDark: Bool) -> some View {
    let surface = isDark ? Color.tidexDarkSurfacePrimary : Color.tidexLightSurfacePrimary
    let text = isDark ? Color.tidexDarkTextPrimary : Color.tidexLightTextPrimary
    let blue = isDark ? Color.tidexDarkBlue : Color.tidexLightBlue

    return VStack(alignment: .leading, spacing: 5) {
      Capsule()
        .fill(text.opacity(0.85))
        .frame(width: 30, height: 5)

      RoundedRectangle(cornerRadius: 5, style: .continuous)
        .fill(surface)
        .frame(height: 26)
        .overlay(alignment: .leading) {
          Capsule()
            .fill(blue)
            .frame(width: 22, height: 5)
            .padding(.leading, 6)
        }

      RoundedRectangle(cornerRadius: 5, style: .continuous)
        .fill(surface)
        .frame(height: 18)
    }
    .padding(8)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(isDark ? Color.tidexDarkBackgroundColor : Color.tidexLightBackground)
  }

  private func themeTitle(_ theme: AppTheme) -> String {
    switch theme {
    case .system: String(localized: .appearanceThemeSystem)
    case .light: String(localized: .appearanceThemeLight)
    case .dark: String(localized: .appearanceThemeDark)
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

  // MARK: - Calendar Colors

  private var calendarContentColorSection: some View {
    Section {
      HStack(alignment: .top, spacing: Spacing.sm) {
        ForEach(CalendarContentColorStyle.allCases, id: \.self) { style in
          choiceTile(
            title: calendarContentColorTitle(style),
            isSelected: viewModel.selectedCalendarContentColorStyle == style
          ) {
            viewModel.selectedCalendarContentColorStyle = style
          } preview: {
            calendarPreview(style)
          }
        }
      }
      .padding(.vertical, Spacing.xs)
    } header: {
      Text(String(localized: .appearanceCalendarContentColorSectionTitle))
    } footer: {
      Text(calendarContentColorDescription(viewModel.selectedCalendarContentColorStyle))
    }
  }

  /// A small calendar week with shift blocks in job colors or in the text color.
  private func calendarPreview(_ style: CalendarContentColorStyle) -> some View {
    let jobColors: [Color] = [.tidexBlue, .tidexPurple, .tidexSuccess, .tidexWarning]
    let filledDays: [Int: Int] = [0: 0, 1: 1, 3: 0, 4: 2, 6: 3, 8: 1, 9: 0, 11: 2]

    return LazyVGrid(
      columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4),
      spacing: 4
    ) {
      ForEach(0..<12, id: \.self) { day in
        RoundedRectangle(cornerRadius: 3, style: .continuous)
          .fill(
            filledDays[day].map { jobIndex in
              style == .workplace ? jobColors[jobIndex] : Color.tidexTextPrimary
            } ?? Color.tidexTextMuted.opacity(0.18)
          )
          .frame(height: 12)
      }
    }
    .padding(8)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.tidexSurfaceSecondary)
  }

  private func calendarContentColorTitle(_ style: CalendarContentColorStyle) -> String {
    switch style {
    case .workplace: String(localized: .appearanceCalendarContentColorWorkplace)
    case .monochrome: String(localized: .appearanceCalendarContentColorMonochrome)
    }
  }

  private func calendarContentColorDescription(_ style: CalendarContentColorStyle) -> String {
    switch style {
    case .workplace: String(localized: .appearanceCalendarContentColorWorkplaceDescription)
    case .monochrome: String(localized: .appearanceCalendarContentColorMonochromeDescription)
    }
  }

  // MARK: - Choice Tile

  /// A tappable preview with a title and a selection mark, used for theme and calendar colors.
  private func choiceTile<Preview: View>(
    title: String,
    isSelected: Bool,
    action: @escaping () -> Void,
    @ViewBuilder preview: () -> Preview
  ) -> some View {
    Button(action: action) {
      VStack(spacing: Spacing.xs) {
        preview()
          .frame(height: 84)
          .frame(maxWidth: .infinity)
          .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
          .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
              .strokeBorder(
                isSelected ? Color.tidexBlue : Color.tidexBorder,
                lineWidth: isSelected ? 2 : 1
              )
          }

        Text(title)
          .font(.tidexFootnoteMedium)
          .foregroundColor(.tidexTextPrimary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)

        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
          .font(.tidexBody)
          .foregroundColor(isSelected ? .tidexBlue : .tidexTextMuted)
      }
      .frame(maxWidth: .infinity)
      .contentShape(Rectangle())
    }
    // Plain style keeps each tile its own tap target inside the shared form row.
    .buttonStyle(.plain)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(title))
    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
  }

  // MARK: - Dashboard

  private var dashboardControlsSection: some View {
    Section {
      Toggle(isOn: $viewModel.showDashboardClockButtons) {
        Text(.appearanceDashboardClockButtonsTitle)
      }
      .tint(.tidexBlue)
    } header: {
      Text(String(localized: .appearanceDashboardSectionTitle))
    } footer: {
      Text(.appearanceDashboardClockButtonsDescription)
    }
  }

  // MARK: - Startup Tab

  private var startupTabSection: some View {
    Section {
      Picker(selection: $viewModel.selectedStartupTab) {
        ForEach(StartupTabOption.allCases, id: \.self) { tab in
          Label(startupTabTitle(tab), systemImage: startupTabIcon(tab))
            .tag(tab)
        }
      } label: {
        Text(.appearanceStartupTabSectionTitle)
      }
      .pickerStyle(.menu)
      .tint(.tidexTextSecondary)
    } footer: {
      Text(.appearanceStartupTabSectionDescription)
    }
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
}

// MARK: - Preview

#Preview {
  NavigationStack {
    AppearanceSettingsView()
  }
}
