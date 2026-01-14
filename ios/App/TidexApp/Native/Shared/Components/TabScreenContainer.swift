import SwiftUI

/// Reusable container for tab screens with common navigation and styling
/// Provides consistent NavigationStack, toolbar, and background across all tabs
///
/// Usage:
/// ```swift
/// TabScreenContainer(title: localization.string("tabs.shifts")) {
///     // Your tab content here
/// }
/// ```
struct TabScreenContainer<Content: View>: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.localization) private var localization

    let title: String
    let showsUserMenu: Bool
    @ViewBuilder let content: () -> Content

    init(
        title: String,
        showsUserMenu: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.showsUserMenu = showsUserMenu
        self.content = content
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.tidexLaunchBackground
                    .ignoresSafeArea()

                content()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.tidexLaunchBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                if showsUserMenu {
                    ToolbarItem(placement: .topBarTrailing) {
                        UserMenuButton(
                            displayName: coordinator.userDisplayName,
                            avatarUrl: coordinator.userAvatarUrl
                        )
                    }
                }
            }
        }
    }
}

/// Container with built-in pull-to-refresh support
/// Use for tabs that need refresh functionality
struct RefreshableTabScreenContainer<Content: View>: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.localization) private var localization

    let title: String
    let showsUserMenu: Bool
    let onRefresh: () async -> Void
    @ViewBuilder let content: () -> Content

    init(
        title: String,
        showsUserMenu: Bool = true,
        onRefresh: @escaping () async -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.showsUserMenu = showsUserMenu
        self.onRefresh = onRefresh
        self.content = content
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                content()
            }
            .refreshable {
                await onRefresh()
            }
            .background(Color.tidexLaunchBackground)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.tidexLaunchBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                if showsUserMenu {
                    ToolbarItem(placement: .topBarTrailing) {
                        UserMenuButton(
                            displayName: coordinator.userDisplayName,
                            avatarUrl: coordinator.userAvatarUrl
                        )
                    }
                }
            }
        }
    }
}

#Preview("TabScreenContainer") {
    TabScreenContainer(title: "Test Tab") {
        Text("Tab Content")
            .foregroundColor(.tidexTextPrimary)
    }
    .environmentObject(AppCoordinator.shared)
    .environment(\.localization, LocalizationManager.shared)
}
