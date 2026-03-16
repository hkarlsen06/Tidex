import SwiftUI

/// Reusable container for tab screens with common navigation and styling
/// Provides consistent NavigationStack, toolbar, and background across all tabs
///
/// Usage:
/// ```swift
/// TabScreenContainer(title: String(localized: .tabsShifts)) {
///     // Your tab content here
/// }
/// ```
struct TabScreenContainer<
  Content: View, PrincipalContent: View, LeadingContent: View, TrailingContent: View
>: View {
  @EnvironmentObject private var coordinator: AppCoordinator

  let title: String
  let showsUserMenu: Bool
  @ViewBuilder let content: () -> Content
  @ViewBuilder let principalContent: () -> PrincipalContent
  @ViewBuilder let leadingContent: () -> LeadingContent
  @ViewBuilder let trailingContent: () -> TrailingContent

  init(
    title: String,
    showsUserMenu: Bool = true,
    @ViewBuilder content: @escaping () -> Content,
    @ViewBuilder principalContent: @escaping () -> PrincipalContent,
    @ViewBuilder leadingContent: @escaping () -> LeadingContent,
    @ViewBuilder trailingContent: @escaping () -> TrailingContent
  ) {
    self.title = title
    self.showsUserMenu = showsUserMenu
    self.content = content
    self.principalContent = principalContent
    self.leadingContent = leadingContent
    self.trailingContent = trailingContent
  }

  var body: some View {
    NavigationStack {
      ZStack {
        TidexAppBackground()

        content()
      }
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(Color.tidexBackground, for: .navigationBar)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          leadingContent()
        }
        ToolbarItem(placement: .principal) {
          principalContent()
        }
        ToolbarItem(placement: .topBarTrailing) {
          if showsUserMenu {
            UserMenuButton(
              displayName: coordinator.userDisplayName,
              avatarUrl: coordinator.userAvatarUrl
            )
          } else {
            trailingContent()
          }
        }
      }
    }
  }
}

// Convenience initializer for screens that just want a title
extension TabScreenContainer
where PrincipalContent == Text, LeadingContent == EmptyView, TrailingContent == EmptyView {
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
    self.leadingContent = { EmptyView() }
    self.trailingContent = { EmptyView() }
  }
}

// Convenience initializer for screens with custom principal content only
extension TabScreenContainer where LeadingContent == EmptyView, TrailingContent == EmptyView {
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
    self.leadingContent = { EmptyView() }
    self.trailingContent = { EmptyView() }
  }
}

// Convenience initializer for screens with leading and trailing content (no user menu)
extension TabScreenContainer where PrincipalContent == EmptyView {
  init(
    title: String,
    showsUserMenu: Bool = false,
    @ViewBuilder content: @escaping () -> Content,
    @ViewBuilder leadingContent: @escaping () -> LeadingContent,
    @ViewBuilder trailingContent: @escaping () -> TrailingContent
  ) {
    self.title = title
    self.showsUserMenu = showsUserMenu
    self.content = content
    self.principalContent = { EmptyView() }
    self.leadingContent = leadingContent
    self.trailingContent = trailingContent
  }
}

/// Container with built-in pull-to-refresh support
/// Use for tabs that need refresh functionality
struct RefreshableTabScreenContainer<Content: View>: View {
  @EnvironmentObject private var coordinator: AppCoordinator

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
      ZStack {
        TidexAppBackground()

        ScrollView {
          content()
        }
        .refreshable {
          await onRefresh()
        }
      }
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
}
