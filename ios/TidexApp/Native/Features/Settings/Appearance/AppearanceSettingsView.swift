import SwiftUI

/// Appearance settings view
/// Allows users to choose between system, light, and dark themes
struct AppearanceSettingsView: View {
        @Environment(\.colorScheme) private var systemColorScheme
    @StateObject private var viewModel = AppearanceSettingsViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                headerSection

                // Error message
                if let error = viewModel.errorMessage {
                    errorBanner(error)
                }

                // Theme selection
                themeSelectionSection

                // Calendar animation selection
                calendarAnimationSection

                // Current theme info
                currentThemeInfo
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
        }
        .background(Color.tidexBackground)
        .navigationTitle(String(localized: .appearanceTitle))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.tidexBackground, for: .navigationBar)
        .task {
            await viewModel.loadSettings()
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(.appearanceTitle)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.tidexTextPrimary)

            Text(.appearanceSubtitle)
                .font(.subheadline)
                .foregroundColor(.tidexTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16))
                .foregroundColor(.tidexError)

            Text(message)
                .font(.system(size: 14))
                .foregroundColor(.tidexTextPrimary)

            Spacer()

            Button {
                viewModel.clearError()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.tidexTextMuted)
            }
        }
        .padding(12)
        .background(Color.tidexError.opacity(0.1))
        .cornerRadius(8)
    }

    // MARK: - Theme Selection Section

    private var themeSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            Text(.appearanceThemeSectionTitle)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.tidexTextMuted)
                .textCase(.uppercase)

            // Theme options as cards
            VStack(spacing: 12) {
                ForEach(AppTheme.allCases, id: \.self) { theme in
                    themeOptionCard(theme)
                }
            }
        }
    }

    private func themeOptionCard(_ theme: AppTheme) -> some View {
        let isSelected = viewModel.selectedTheme == theme

        return Button {
            viewModel.selectedTheme = theme
        } label: {
            HStack(spacing: 16) {
                // Theme preview
                themePreview(theme)

                // Theme info
                VStack(alignment: .leading, spacing: 2) {
                    Text(themeTitle(theme))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.tidexTextPrimary)

                    Text(themeDescription(theme))
                        .font(.system(size: 13))
                        .foregroundColor(.tidexTextSecondary)
                }

                Spacer()

                // Selection indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.tidexBlue)
                } else {
                    Image(systemName: "circle")
                        .font(.system(size: 24))
                        .foregroundColor(.tidexTextMuted)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.tidexSurfacePrimary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.tidexBlue : Color.clear, lineWidth: 2)
            )
            .tidexCardShadow(cornerRadius: 12)
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
            RoundedRectangle(cornerRadius: 8)
                .fill(isDark ? Color(red: 0.1, green: 0.1, blue: 0.15) : Color(red: 0.95, green: 0.95, blue: 0.97))
                .frame(width: 48, height: 48)

            // Icon
            Image(systemName: themeIcon(theme))
                .font(.system(size: 20, weight: .medium))
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
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            Text(.appearanceCalendarAnimationSectionTitle)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.tidexTextMuted)
                .textCase(.uppercase)

            // Animation style options as cards
            VStack(spacing: 12) {
                ForEach(CalendarAnimationStyle.allCases, id: \.self) { style in
                    animationStyleOptionCard(style)
                }
            }
        }
    }

    private func animationStyleOptionCard(_ style: CalendarAnimationStyle) -> some View {
        let isSelected = viewModel.selectedCalendarAnimationStyle == style

        return Button {
            viewModel.selectedCalendarAnimationStyle = style
        } label: {
            HStack(spacing: 16) {
                // Animation style preview
                animationStylePreview(style)

                // Style info
                VStack(alignment: .leading, spacing: 2) {
                    Text(animationStyleTitle(style))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.tidexTextPrimary)

                    Text(animationStyleDescription(style))
                        .font(.system(size: 13))
                        .foregroundColor(.tidexTextSecondary)
                }

                Spacer()

                // Selection indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.tidexBlue)
                } else {
                    Image(systemName: "circle")
                        .font(.system(size: 24))
                        .foregroundColor(.tidexTextMuted)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.tidexSurfacePrimary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.tidexBlue : Color.clear, lineWidth: 2)
            )
            .tidexCardShadow(cornerRadius: 12)
        }
        .buttonStyle(.plain)
    }

    private func animationStylePreview(_ style: CalendarAnimationStyle) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.tidexBlue.opacity(0.1))
                .frame(width: 48, height: 48)

            Image(systemName: animationStyleIcon(style))
                .font(.system(size: 20, weight: .medium))
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
        VStack(alignment: .leading, spacing: 8) {
            // Info text
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.system(size: 14))
                    .foregroundColor(.tidexTextMuted)

                Text(currentThemeInfoText)
                    .font(.system(size: 13))
                    .foregroundColor(.tidexTextMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    private var currentThemeInfoText: String {
        switch viewModel.selectedTheme {
        case .system:
            let currentMode = systemColorScheme == .dark
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
