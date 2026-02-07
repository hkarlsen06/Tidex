import SwiftUI

/// Appearance settings view
/// Allows users to choose between system, light, and dark themes
struct AppearanceSettingsView: View {
  @Environment(\.colorScheme) private var systemColorScheme
  @StateObject private var viewModel = AppearanceSettingsViewModel()

  var body: some View {
    List {
      // Error message
      if let error = viewModel.errorMessage {
        Section {
          errorBanner(error)
        }
        .listRowBackground(Color.tidexSurfacePrimary)
      }

      // Theme selection
      themeSelectionSection

      // Calendar animation selection
      calendarAnimationSection
    }
    .listStyle(.insetGrouped)
    .scrollContentBackground(.hidden)
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
    Section {
      ForEach(AppTheme.allCases, id: \.self) { theme in
        themeOptionRow(theme)
      }
      .listRowBackground(Color.tidexSurfacePrimary)
    } header: {
      Text(String(localized: .appearanceThemeSectionTitle))
    } footer: {
      currentThemeInfo
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
    }
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
    Section {
      ForEach(CalendarAnimationStyle.allCases, id: \.self) { style in
        animationStyleOptionRow(style)
      }
      .listRowBackground(Color.tidexSurfacePrimary)
    } header: {
      Text(String(localized: .appearanceCalendarAnimationSectionTitle))
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
    }
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
}

// MARK: - Preview

#Preview {
  NavigationStack {
    AppearanceSettingsView()
  }
}
