import SwiftUI

/// Appearance settings view
/// Allows users to choose between system, light, and dark themes
struct AppearanceSettingsView: View {
    @Environment(\.localization) private var localization
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

                // Current theme info
                currentThemeInfo
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
        }
        .background(Color.tidexBackground)
        .navigationTitle(localization.string("appearance.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.tidexBackground, for: .navigationBar)
        .task {
            await viewModel.loadSettings()
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(localization.string("appearance.title"))
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.tidexTextPrimary)

            Text(localization.string("appearance.subtitle"))
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
            Text(localization.string("appearance.theme.sectionTitle"))
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
            return localization.string("appearance.theme.system")
        case .light:
            return localization.string("appearance.theme.light")
        case .dark:
            return localization.string("appearance.theme.dark")
        }
    }

    private func themeDescription(_ theme: AppTheme) -> String {
        switch theme {
        case .system:
            return localization.string("appearance.theme.systemDescription")
        case .light:
            return localization.string("appearance.theme.lightDescription")
        case .dark:
            return localization.string("appearance.theme.darkDescription")
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
                ? localization.string("appearance.info.dark")
                : localization.string("appearance.info.light")
            return localization.string("appearance.info.systemActive").replacingOccurrences(of: "{mode}", with: currentMode)
        case .light:
            return localization.string("appearance.info.lightActive")
        case .dark:
            return localization.string("appearance.info.darkActive")
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        AppearanceSettingsView()
    }
    .environment(\.localization, LocalizationManager.shared)
}
