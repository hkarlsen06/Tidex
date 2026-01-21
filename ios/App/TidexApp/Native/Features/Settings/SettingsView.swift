import SwiftUI
import Supabase

/// Settings main menu view
/// Displays a list of settings options matching the web app's settings navigation
struct SettingsView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.localization) private var localization
    @Environment(\.dismiss) private var dismiss

    /// Whether the current user is an admin
    @State private var isAdmin = false
    /// Whether sign out is in progress
    @State private var isSigningOut = false
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
                        SettingsMenuGroup(title: localization.string("settings.group.accountSecurity")) {
                            SettingsMenuItem(
                                icon: "person.circle",
                                title: localization.string("settings.menu.account.label"),
                                description: localization.string("settings.menu.account.description"),
                                action: {
                                    navigationPath.append(SettingsDestination.profile)
                                }
                            )

                            SettingsMenuItem(
                                icon: "lock.shield",
                                title: localization.string("settings.menu.security.label"),
                                description: localization.string("settings.menu.security.description"),
                                action: {
                                    navigationPath.append(SettingsDestination.security)
                                }
                            )

                            SettingsMenuItem(
                                icon: "creditcard",
                                title: localization.string("settings.menu.subscription.label"),
                                description: localization.string("settings.menu.subscription.description"),
                                action: {
                                    navigationPath.append(SettingsDestination.subscription)
                                }
                            )
                        }

                        // Preferences group
                        SettingsMenuGroup(title: localization.string("settings.group.preferences")) {
                            SettingsMenuItem(
                                icon: "bell",
                                title: localization.string("settings.menu.notifications.label"),
                                description: localization.string("settings.menu.notifications.description"),
                                action: {
                                    navigationPath.append(SettingsDestination.notifications)
                                }
                            )

                            SettingsMenuItem(
                                icon: "paintpalette",
                                title: localization.string("settings.menu.appearance.label"),
                                description: localization.string("settings.menu.appearance.description"),
                                action: {
                                    navigationPath.append(SettingsDestination.appearance)
                                }
                            )
                        }

                        // App Settings group
                        SettingsMenuGroup(title: localization.string("settings.group.appSettings")) {
                            SettingsMenuItem(
                                icon: "banknote",
                                title: localization.string("settings.menu.pay.label"),
                                description: localization.string("settings.menu.pay.description"),
                                action: {
                                    navigationPath.append(SettingsDestination.pay)
                                }
                            )
                        }

                        // Data & Support group
                        SettingsMenuGroup(title: localization.string("settings.group.dataSupport")) {
                            SettingsMenuItem(
                                icon: "externaldrive",
                                title: localization.string("settings.menu.data.label"),
                                description: localization.string("settings.menu.data.description"),
                                action: {
                                    navigationPath.append(SettingsDestination.data)
                                }
                            )

                            SettingsMenuItem(
                                icon: "message",
                                title: localization.string("settings.menu.feedback.label"),
                                description: localization.string("settings.menu.feedback.description"),
                                action: {
                                    navigationPath.append(SettingsDestination.feedback)
                                }
                            )
                        }

                        // Admin section (only visible for admins)
                        if isAdmin {
                            SettingsMenuGroup(title: localization.string("settings.group.admin")) {
                                SettingsMenuItem(
                                    icon: "shield.lefthalf.filled.badge.checkmark",
                                    title: localization.string("settings.menu.admin.label"),
                                    description: localization.string("settings.menu.admin.description"),
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

                    // Sign out button
                    signOutButton
                        .padding(.horizontal, 16)
                        .padding(.top, 32)
                        .padding(.bottom, 40)
                }
            }
            .background(Color.tidexBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.tidexBackground, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(localization.string("settings.title"))
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.tidexTextPrimary)

                        Text(localization.string("settings.subtitle"))
                            .font(.system(size: 12))
                            .foregroundColor(.tidexTextSecondary)
                    }
                    .fixedSize()
                }
                .sharedBackgroundVisibility(.hidden)

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(Color.tidexTextMuted)
                    }
                }
            }
            .navigationDestination(for: SettingsDestination.self) { destination in
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
        }
        .task {
            await checkAdminStatus()
        }
    }

    // MARK: - Sign Out Button

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
                     ? localization.string("userMenu.loggingOut")
                     : localization.string("userMenu.logout"))
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color.tidexError)
            .cornerRadius(12)
        }
        .disabled(isSigningOut)
    }

    // MARK: - Actions

    private func checkAdminStatus() async {
        do {
            let session = try await supabase.auth.session
            // Check app_metadata for admin role
            // The role is stored in app_metadata which is set by the backend
            if let appMetadata = session.user.appMetadata["role"],
               case .string(let role) = appMetadata,
               role == "admin" {
                isAdmin = true
            }
        } catch {
            // Silently fail - non-admin is the default
            print("[SettingsView] Could not check admin status: \(error)")
        }
    }

    private func signOut() async {
        isSigningOut = true
        await coordinator.signOut()
        dismiss()
        isSigningOut = false
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

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
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
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.tidexTextMuted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.tidexSurfacePrimary)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .environmentObject(AppCoordinator.shared)
        .environment(\.localization, LocalizationManager.shared)
}
