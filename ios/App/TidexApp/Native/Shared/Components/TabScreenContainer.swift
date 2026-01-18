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
struct TabScreenContainer<Content: View, PrincipalContent: View>: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.localization) private var localization

    let title: String
    let showsUserMenu: Bool
    @ViewBuilder let content: () -> Content
    @ViewBuilder let principalContent: () -> PrincipalContent

    init(
        title: String,
        showsUserMenu: Bool = true,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder principalContent: @escaping () -> PrincipalContent
    ) {
        self.title = title
        self.showsUserMenu = showsUserMenu
        self.content = content
        self.principalContent = principalContent
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.tidexBackground
                    .ignoresSafeArea()

                content()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.tidexBackground, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    principalContent()
                }
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

// Convenience initializer for screens that just want a title
extension TabScreenContainer where PrincipalContent == Text {
    init(
        title: String,
        showsUserMenu: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.showsUserMenu = showsUserMenu
        self.content = content
        self.principalContent = {
            Text(title)
                .font(.headline)
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
            .background(Color.tidexBackground)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.tidexBackground, for: .navigationBar)
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
