import UIKit
import Capacitor

/// Container view controller that hosts CAPBridgeViewController with a native UITabBar overlay.
///
/// Architecture:
/// - WebView is edge-to-edge (allows CSS env(safe-area-inset-*) to work correctly)
/// - UITabBar is a sibling view positioned at the bottom
/// - Tab bar height is injected into WebView as CSS custom property
///
/// This approach avoids UITabBarController's safe area propagation issues when
/// embedding CAPBridgeViewController as a child.
class TidexContainerViewController: UIViewController, UITabBarDelegate {

    private var webViewController: CAPBridgeViewController!
    private var customTabBar: UITabBar!
    weak var nativeTabBarPlugin: NativeTabBarPlugin?

    // Shared reference for plugin to locate this controller
    static weak var shared: TidexContainerViewController?

    struct TabItem {
        let title: String
        let imageName: String  // SF Symbol
        let route: String
    }

    private let tabDefinitions: [TabItem] = [
        TabItem(title: "Home", imageName: "gauge", route: "/"),
        TabItem(title: "Shifts", imageName: "calendar", route: "/shifts"),
        TabItem(title: "Add", imageName: "plus.circle.fill", route: "/shifts/add"),
        TabItem(title: "Stats", imageName: "chart.bar.xaxis", route: "/stats"),
        TabItem(title: "Share", imageName: "square.and.arrow.up", route: "/sharing")
    ]

    private var selectedIndex: Int = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        TidexContainerViewController.shared = self

        let darkBackground = UIColor(red: 0.008, green: 0.032, blue: 0.090, alpha: 1.0)
        view.backgroundColor = darkBackground

        setupWebView()
        setupTabBar()
        setupSwipeBackGesture()
    }

    private func setupWebView() {
        webViewController = CAPBridgeViewController()

        let darkBackground = UIColor(red: 0.008, green: 0.032, blue: 0.090, alpha: 1.0)
        webViewController.view.backgroundColor = darkBackground

        // Add as child view controller
        addChild(webViewController)
        view.addSubview(webViewController.view)
        webViewController.view.translatesAutoresizingMaskIntoConstraints = false

        // CRITICAL: Edge-to-edge constraints
        // This ensures CSS env(safe-area-inset-top) returns the correct value (~47px for notch)
        // The WebView extends under both status bar and tab bar
        NSLayoutConstraint.activate([
            webViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            webViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        webViewController.didMove(toParent: self)
    }

    private func setupTabBar() {
        customTabBar = UITabBar()
        customTabBar.delegate = self
        customTabBar.translatesAutoresizingMaskIntoConstraints = false

        // Configure appearance - minimal customization to preserve system materials (Liquid Glass on iOS 26)
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        customTabBar.standardAppearance = appearance
        if #available(iOS 15.0, *) {
            customTabBar.scrollEdgeAppearance = appearance
        }

        // Create tab items
        var items: [UITabBarItem] = []
        for (index, tab) in tabDefinitions.enumerated() {
            let item = UITabBarItem(
                title: tab.title,
                image: UIImage(systemName: tab.imageName),
                tag: index
            )
            items.append(item)
        }
        customTabBar.items = items
        customTabBar.selectedItem = items.first

        // Add to view hierarchy AFTER WebView so it's on top
        view.addSubview(customTabBar)

        // Position at bottom edge (tab bar handles its own safe area for home indicator)
        NSLayoutConstraint.activate([
            customTabBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            customTabBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            customTabBar.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    // MARK: - Swipe Back Gesture

    private func setupSwipeBackGesture() {
        let edgePan = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handleSwipeBack(_:)))
        edgePan.edges = .left
        view.addGestureRecognizer(edgePan)
    }

    @objc private func handleSwipeBack(_ gesture: UIScreenEdgePanGestureRecognizer) {
        guard gesture.state == .ended else { return }

        // Trigger browser back navigation in the WebView
        let js = "window.history.back();"
        webViewController.webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    // MARK: - Safe Area & Tab Bar Height Injection

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        injectTabBarHeightToCSS()
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        injectTabBarHeightToCSS()
    }

    private var lastInjectedHeight: CGFloat = 0

    private func injectTabBarHeightToCSS() {
        // Calculate total bottom padding needed: tab bar height (includes its internal safe area handling)
        let tabBarHeight = customTabBar.frame.height

        // Only inject if value changed to avoid unnecessary JS calls
        guard tabBarHeight != lastInjectedHeight, tabBarHeight > 0 else { return }
        lastInjectedHeight = tabBarHeight

        // Inject as CSS custom property
        // CSS can use: padding-bottom: var(--native-tab-bar-height, 49px);
        let js = """
        document.documentElement.style.setProperty('--native-tab-bar-height', '\(tabBarHeight)px');
        """

        webViewController.webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    // MARK: - Plugin Registration with retry

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        attemptPluginRegistration()
    }

    private var pluginRegistrationAttempts = 0
    private let maxPluginRegistrationAttempts = 10

    private func attemptPluginRegistration() {
        // If already registered, done
        if nativeTabBarPlugin != nil { return }

        // Try to get bridge
        if let bridge = webViewController.bridge {
            let plugin = NativeTabBarPlugin()
            plugin.containerController = self
            bridge.registerPluginInstance(plugin)
            self.nativeTabBarPlugin = plugin

            // Inject initial tab bar height now that bridge is ready
            injectTabBarHeightToCSS()
            return
        }

        // Bridge not ready yet - retry with backoff
        pluginRegistrationAttempts += 1
        if pluginRegistrationAttempts < maxPluginRegistrationAttempts {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.attemptPluginRegistration()
            }
        }
    }

    // MARK: - UITabBarDelegate

    func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
        let index = item.tag
        guard index >= 0 && index < tabDefinitions.count else { return }

        let route = tabDefinitions[index].route

        if index == selectedIndex {
            // Re-tapping the same tab - scroll to top instead of navigating
            nativeTabBarPlugin?.handleTabReselection(index: index, route: route)
        } else {
            // Different tab - navigate
            selectedIndex = index
            nativeTabBarPlugin?.handleTabSelection(index: index, route: route)
        }
    }

    // MARK: - Public Methods (called from plugin)

    func setSelectedTabIndex(_ index: Int) {
        guard index >= 0 && index < tabDefinitions.count,
              let items = customTabBar.items,
              index < items.count else { return }

        selectedIndex = index
        customTabBar.selectedItem = items[index]
    }

    func clearSelection() {
        selectedIndex = -1
        customTabBar.selectedItem = nil
    }

    func setTabBadge(index: Int, value: String?) {
        guard index >= 0 && index < tabDefinitions.count,
              let items = customTabBar.items,
              index < items.count else { return }
        items[index].badgeValue = value
    }

    func hideTabBar() {
        guard !customTabBar.isHidden else { return }

        customTabBar.isHidden = true

        // Notify CSS that tab bar is hidden
        let js = """
        document.documentElement.style.setProperty('--native-tab-bar-height', '0px');
        document.documentElement.classList.add('native-tab-bar-hidden');
        """
        webViewController.webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    func showTabBar() {
        guard customTabBar.isHidden else { return }

        customTabBar.isHidden = false

        // Restore tab bar height and remove hidden class
        let tabBarHeight = customTabBar.frame.height
        let js = """
        document.documentElement.style.setProperty('--native-tab-bar-height', '\(tabBarHeight)px');
        document.documentElement.classList.remove('native-tab-bar-hidden');
        """
        webViewController.webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    func getTabBarHeight() -> CGFloat {
        return customTabBar.frame.height
    }
}
