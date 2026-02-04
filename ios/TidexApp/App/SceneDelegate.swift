import UIKit

/// Scene delegate for handling UIScene lifecycle events
/// Primarily used for Home Screen quick actions (app icon shortcuts)
class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    // MARK: - Quick Action Types

    private enum QuickActionType: String {
        case add = "no.tidex.app.shortcut.add"
        case friends = "no.tidex.app.shortcut.friends"
        case stats = "no.tidex.app.shortcut.stats"

        var tab: AppCoordinator.QuickActionTab {
            switch self {
            case .add: return .add
            case .friends: return .sharing
            case .stats: return .stats
            }
        }

        var localizedTitle: String {
            switch self {
            case .add: return String(localized: .tabsAdd)
            case .friends: return String(localized: .tabsSharing)
            case .stats: return String(localized: .tabsStats)
            }
        }

        var iconName: String {
            switch self {
            case .add: return "plus.circle.fill"
            case .friends: return "person.2.fill"
            case .stats: return "chart.bar.xaxis"
            }
        }
    }

    // MARK: - UIWindowSceneDelegate

    /// Called when a new scene session is being created (cold start)
    /// Check for shortcut item in connection options
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        // Register dynamic shortcuts with localized titles
        registerDynamicShortcuts()

        // Handle quick action from cold start
        if let shortcutItem = connectionOptions.shortcutItem {
            handleQuickAction(shortcutItem)
        }
    }

    /// Called when user selects a quick action while app is running (warm launch)
    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let handled = handleQuickAction(shortcutItem)
        completionHandler(handled)
    }

    // MARK: - Dynamic Shortcuts

    /// Register dynamic shortcuts with localized titles
    /// Uses existing tab name translations from Localizable.xcstrings
    private func registerDynamicShortcuts() {
        let shortcuts: [UIApplicationShortcutItem] = [
            UIApplicationShortcutItem(
                type: QuickActionType.add.rawValue,
                localizedTitle: QuickActionType.add.localizedTitle,
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: QuickActionType.add.iconName)
            ),
            UIApplicationShortcutItem(
                type: QuickActionType.friends.rawValue,
                localizedTitle: QuickActionType.friends.localizedTitle,
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: QuickActionType.friends.iconName)
            ),
            UIApplicationShortcutItem(
                type: QuickActionType.stats.rawValue,
                localizedTitle: QuickActionType.stats.localizedTitle,
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: QuickActionType.stats.iconName)
            )
        ]

        UIApplication.shared.shortcutItems = shortcuts
    }

    // MARK: - Quick Action Handling

    @discardableResult
    private func handleQuickAction(_ shortcutItem: UIApplicationShortcutItem) -> Bool {
        guard let actionType = QuickActionType(rawValue: shortcutItem.type) else {
            return false
        }

        Task { @MainActor in
            AppCoordinator.shared.pendingDeepLink = .tab(actionType.tab)
        }

        return true
    }
}
