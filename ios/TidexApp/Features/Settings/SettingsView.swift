import os.log
import Supabase
import SwiftUI

private let logger = Logger(subsystem: "no.tidex.app", category: "SettingsView")

/// Settings main menu view
/// Displays a list of settings options matching the web app's settings navigation
struct SettingsView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
        @Environment(\.dismiss) private var dismiss

    /// Whether the current user is an admin
    @State private var isAdmin = false
    /// Whether sign out is in progress
    @State private var isSigningOut = false
    /// Whether global sign out is in progress
    @State private var isSigningOutGlobal = false
    /// Whether to show the global sign out confirmation alert
    @State private var showSignOutEverywhereAlert = false
    /// Navigation path for settings subviews
    @State private var navigationPath = NavigationPath()

    /// Settings navigation destinations
    enum SettingsDestination: Hashable {
        case profile
        case security
        case subscription
        case notifications
        case appearance
        case pay
        case data
        case feedback
        case admin
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                VStack(spacing: 0) {
                    // Menu items grouped by category
                    VStack(spacing: 24) {
                        // Account & Security group
                        SettingsMenuGroup(title: String(localized: .settingsGroupAccountSecurity)) {
                            SettingsMenuItem(
                                icon: "person.circle",
                                title: String(localized: .settingsMenuAccountLabel),
                                description: String(localized: .settingsMenuAccountDescription),
                                action: {
                                    navigationPath.append(SettingsDestination.profile)
                                }
                            )

                            SettingsMenuItem(
                                icon: "lock.shield",
                                title: String(localized: .settingsMenuSecurityLabel),
                                description: String(localized: .settingsMenuSecurityDescription),
                                action: {
                                    navigationPath.append(SettingsDestination.security)
                                }
                            )

                            SettingsMenuItem(
                                icon: "creditcard",
                                title: String(localized: .settingsMenuSubscriptionLabel),
                                description: String(localized: .settingsMenuSubscriptionDescription),
                                action: {
                                    navigationPath.append(SettingsDestination.subscription)
                                }
                            )
                        }

                        // Preferences group
                        SettingsMenuGroup(title: String(localized: .settingsGroupPreferences)) {
                            SettingsMenuItem(
                                icon: "bell",
                                title: String(localized: .settingsMenuNotificationsLabel),
                                description: String(localized: .settingsMenuNotificationsDescription),
                                action: {
                                    navigationPath.append(SettingsDestination.notifications)
                                }
                            )

                            SettingsMenuItem(
                                icon: "paintpalette",
                                title: String(localized: .settingsMenuAppearanceLabel),
                                description: String(localized: .settingsMenuAppearanceDescription),
                                action: {
                                    navigationPath.append(SettingsDestination.appearance)
                                }
                            )
                        }

                        // App Settings group
                        SettingsMenuGroup(title: String(localized: .settingsGroupAppSettings)) {
                            SettingsMenuItem(
                                icon: "banknote",
                                title: String(localized: .settingsMenuPayLabel),
                                description: String(localized: .settingsMenuPayDescription),
                                action: {
                                    navigationPath.append(SettingsDestination.pay)
                                }
                            )
                        }

                        // Data & Support group
                        SettingsMenuGroup(title: String(localized: .settingsGroupDataSupport)) {
                            SettingsMenuItem(
                                icon: "externaldrive",
                                title: String(localized: .settingsMenuDataLabel),
                                description: String(localized: .settingsMenuDataDescription),
                                action: {
                                    navigationPath.append(SettingsDestination.data)
                                }
                            )

                            SettingsMenuItem(
                                icon: "message",
                                title: String(localized: .settingsMenuFeedbackLabel),
                                description: String(localized: .settingsMenuFeedbackDescription),
                                action: {
                                    navigationPath.append(SettingsDestination.feedback)
                                }
                            )
                        }

                        // Admin section (only visible for admins)
                        if isAdmin {
                            SettingsMenuGroup(title: String(localized: .settingsGroupAdmin)) {
                                SettingsMenuItem(
                                    icon: "shield.lefthalf.filled.badge.checkmark",
                                    title: String(localized: .settingsMenuAdminLabel),
                                    description: String(localized: .settingsMenuAdminDescription),
                                    iconColor: .tidexWarning,
                                    action: {
                                        navigationPath.append(SettingsDestination.admin)
                                    }
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                    // Sign out buttons
                    VStack(spacing: 12) {
                        signOutButton
                        signOutEverywhereButton
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 32)
                    .padding(.bottom, 40)
                }
            }
            .background(Color.tidexBackground)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text(.settingsTitle)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.tidexTextPrimary)

                        Text(.settingsSubtitle)
                            .font(.system(size: 12))
                            .foregroundColor(.tidexTextSecondary)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color.tidexTextMuted)
                    }
                }
            }
            .navigationDestination(for: SettingsDestination.self) { destination in
                Group {
                    switch destination {
                    case .profile:
                        ProfileSettingsView()
                    case .security:
                        SecuritySettingsView()
                    case .subscription:
                        SubscriptionSettingsView()
                    case .notifications:
                        NotificationSettingsView()
                    case .appearance:
                        AppearanceSettingsView()
                    case .pay:
                        PaySettingsView()
                    case .data:
                        DataSettingsView()
                    case .feedback:
                        FeedbackSettingsView()
                    case .admin:
                        AdminSettingsView()
                    }
                }
                .toolbarRole(.editor)
            }
        }
        .task {
            await checkAdminStatus()
        }
        .alert(
            String(localized: .userMenuLogoutEverywhereConfirmTitle),
            isPresented: $showSignOutEverywhereAlert
        ) {
            Button(String(localized: .userMenuLogoutEverywhereConfirmCancel), role: .cancel) {}
            Button(String(localized: .userMenuLogoutEverywhereConfirmAction), role: .destructive) {
                Task {
                    await signOutGlobal()
                }
            }
        } message: {
            Text(.userMenuLogoutEverywhereConfirmDescription)
        }
    }

    // MARK: - Sign Out Buttons

    /// Sign out from this device only (local scope)
    private var signOutButton: some View {
        Button {
            Task {
                await signOut()
            }
        } label: {
            HStack(spacing: 12) {
                if isSigningOut {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 16, weight: .medium))
                }

                Text(isSigningOut
                     ? String(localized: .userMenuLoggingOut)
                     : String(localized: .userMenuLogout))
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: Spacing.buttonHeight)
            .background(Color.tidexError)
            .cornerRadius(12)
        }
        .disabled(isSigningOut || isSigningOutGlobal)
    }

    /// Sign out from ALL devices (global scope)
    private var signOutEverywhereButton: some View {
        Button {
            showSignOutEverywhereAlert = true
        } label: {
            HStack(spacing: 12) {
                if isSigningOutGlobal {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .tidexTextSecondary))
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: "globe")
                        .font(.system(size: 16, weight: .medium))
                }

                Text(isSigningOutGlobal
                     ? String(localized: .userMenuLogoutEverywhereLoading)
                     : String(localized: .userMenuLogoutEverywhere))
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(.tidexTextSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: Spacing.buttonHeight)
            .background(Color.tidexSurfacePrimary)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.tidexBorder, lineWidth: 1)
            )
        }
        .disabled(isSigningOut || isSigningOutGlobal)
    }

    // MARK: - Actions

    private func checkAdminStatus() async {
        do {
            let session = try await AuthSessionManager.shared.getSession()
            // Check app_metadata for admin role
            // The role is stored in app_metadata which is set by the backend
            if let appMetadata = session.user.appMetadata["role"],
               case .string(let role) = appMetadata,
               role == "admin" {
                isAdmin = true
            }
        } catch {
            // Silently fail - non-admin is the default
            logger.debug("Could not check admin status: \(error.localizedDescription)")
        }
    }

    private func signOut() async {
        isSigningOut = true
        await coordinator.signOut()
        dismiss()
        isSigningOut = false
    }

    private func signOutGlobal() async {
        isSigningOutGlobal = true
        await coordinator.signOutGlobal()
        dismiss()
        isSigningOutGlobal = false
    }
}

// MARK: - Settings Menu Group

/// A group of settings menu items with a section header
struct SettingsMenuGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section header
            Text(title.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.tidexTextMuted)
                .padding(.horizontal, 4)

            // Menu items
            VStack(spacing: 8) {
                content()
            }
        }
    }
}

// MARK: - Settings Menu Item

/// A single settings menu item with icon, title, description, and chevron
struct SettingsMenuItem: View {
    let icon: String
    let title: String
    let description: String
    var iconColor: Color = .tidexBlue
    let action: () -> Void

    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                // Icon
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(iconColor)
                    .frame(width: 32, height: 32)

                // Title and description
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.tidexTextPrimary)

                    Text(description)
                        .font(.system(size: 13))
                        .foregroundColor(.tidexTextSecondary)
                        .lineLimit(1)
                }

                Spacer()

                // Chevron
                Image(systemName: layoutDirection == .rightToLeft ? "chevron.left" : "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.tidexTextMuted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, Spacing.sm)
            .background(Color.tidexSurfacePrimary)
            .cornerRadius(12)
            .tidexCardShadow(cornerRadius: 12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .environmentObject(AppCoordinator.shared)
}
