import UIKit
import SwiftUI
import Capacitor

/// Container view controller that hosts CAPBridgeViewController with a native UITabBar overlay.
///
/// Architecture:
/// - WebView is edge-to-edge (allows CSS env(safe-area-inset-*) to work correctly)
/// - UITabBar is a sibling view positioned at the bottom
/// - Tab bar height is injected into WebView as CSS custom property
/// - Splash screen overlay shows LaunchScreen.storyboard content until JS signals ready
/// - Offline screen overlay displays cached shifts when network is unavailable
///
/// This approach avoids UITabBarController's safe area propagation issues when
/// embedding CAPBridgeViewController as a child.
class TidexContainerViewController: UIViewController, UITabBarDelegate, NetworkMonitorDelegate {

    private var webViewController: LocaleAwareBridgeViewController!
    private var customTabBar: UITabBar!
    private var splashView: UIView?
    weak var nativeTabBarPlugin: NativeTabBarPlugin?

    // MARK: - Offline Screen

    private var offlineHostingController: UIHostingController<OfflineScreenView>?
    private(set) var isShowingOfflineScreen: Bool = false

    // Shared reference for plugin to locate this controller
    static weak var shared: TidexContainerViewController?

    struct TabItem {
        let imageName: String  // SF Symbol
        let route: String
    }

    // Tab definitions without titles (titles set based on locale)
    private let tabDefinitions: [TabItem] = [
        TabItem(imageName: "house.fill", route: "/dashboard"),
        TabItem(imageName: "calendar", route: "/shifts"),
        TabItem(imageName: "plus.circle.fill", route: "/shifts/add"),
        TabItem(imageName: "chart.bar.xaxis", route: "/stats"),
        TabItem(imageName: "person.2.fill", route: "/sharing")
    ]

    // Localized tab titles - matches order of tabDefinitions
    // Norwegian translations for "no" locale, English for others
    private static let tabTitlesNorwegian = ["Hjem", "Vakter", "Legg til", "Statistikk", "Venner"]
    private static let tabTitlesEnglish = ["Home", "Shifts", "Add", "Stats", "Friends"]

    /// Get initial tab titles based on device locale.
    /// Uses shared locale detection from LocaleAwareBridgeViewController for consistency.
    private func getInitialTabTitles() -> [String] {
        switch LocaleAwareBridgeViewController.detectDeviceLocale() {
        case .norwegian:
            return Self.tabTitlesNorwegian
        case .english:
            return Self.tabTitlesEnglish
        }
    }

    private var selectedIndex: Int = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        TidexContainerViewController.shared = self

        let darkBackground = UIColor(red: 0.008, green: 0.032, blue: 0.090, alpha: 1.0)
        view.backgroundColor = darkBackground

        setupWebView()
        setupTabBar()
        setupSwipeBackGesture()
        setupSplashScreen()
        setupNetworkMonitoring()
    }

    // MARK: - Network Monitoring

    private func setupNetworkMonitoring() {
        NetworkMonitor.shared.delegate = self
        NetworkMonitor.shared.startMonitoring()
    }

    /// Called when network connectivity changes
    func networkStatusDidChange(isConnected: Bool) {
        if isConnected && isShowingOfflineScreen {
            print("[TidexContainer] Network restored - hiding offline screen and reloading")
            hideOfflineScreen()
            reloadWebView()
        }
    }

    // MARK: - Offline Screen Management

    /// Minimum time splash must be shown during retry (prevents jarring flash)
    private var splashMinimumDisplayTime: Date?

    /// Show the native offline screen with cached shifts
    func showOfflineScreen() {
        // Always hide splash first - prevents it from showing through after retry fails
        // This handles the case where the app launched offline (splash was never hidden by JS)
        if splashView != nil {
            hideSplash(duration: 0)
        }

        // If we're in a retry and splash minimum time hasn't elapsed, delay showing offline screen
        if let minTime = splashMinimumDisplayTime {
            let remaining = minTime.timeIntervalSinceNow
            if remaining > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + remaining) { [weak self] in
                    self?.splashMinimumDisplayTime = nil
                    self?.showOfflineScreen()
                }
                return
            }
            splashMinimumDisplayTime = nil
        }

        guard !isShowingOfflineScreen else { return }

        let locale: String
        switch LocaleAwareBridgeViewController.detectDeviceLocale() {
        case .norwegian:
            locale = "no"
        case .english:
            locale = "en"
        }

        let offlineView = OfflineScreenView(
            locale: locale,
            onRetry: { [weak self] in
                self?.handleOfflineRetry()
            }
        )

        let hostingController = UIHostingController(rootView: offlineView)
        hostingController.view.frame = view.bounds
        hostingController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        hostingController.view.alpha = 0

        // Add on top of everything (including tab bar)
        view.addSubview(hostingController.view)

        // Animate in
        UIView.animate(withDuration: 0.2) {
            hostingController.view.alpha = 1
        }

        addChild(hostingController)
        hostingController.didMove(toParent: self)

        offlineHostingController = hostingController
        isShowingOfflineScreen = true

        print("[TidexContainer] Showing offline screen")
    }

    /// Hide the offline screen with animation
    func hideOfflineScreen() {
        guard isShowingOfflineScreen, let hostingController = offlineHostingController else { return }

        UIView.animate(withDuration: 0.2, animations: {
            hostingController.view.alpha = 0
        }, completion: { _ in
            hostingController.willMove(toParent: nil)
            hostingController.view.removeFromSuperview()
            hostingController.removeFromParent()
            self.offlineHostingController = nil
            self.isShowingOfflineScreen = false
            print("[TidexContainer] Hid offline screen")
        })
    }

    /// Handle manual retry from offline screen
    private func handleOfflineRetry() {
        // Hide offline screen and show splash during retry attempt
        // This gives visual feedback that something is happening

        // Remove offline screen immediately (no animation) so splash can show
        if let hostingController = offlineHostingController {
            hostingController.willMove(toParent: nil)
            hostingController.view.removeFromSuperview()
            hostingController.removeFromParent()
            offlineHostingController = nil
        }
        isShowingOfflineScreen = false

        // Set minimum splash display time (300ms) to prevent jarring flash on fast failure
        splashMinimumDisplayTime = Date().addingTimeInterval(0.3)

        showSplash()
        reloadWebView()
    }

    /// Reload the WebView by loading the server URL
    /// Note: webView.reload() doesn't work if the initial load failed (nothing to reload)
    /// so we load the server URL directly from the Capacitor bridge config
    private func reloadWebView() {
        guard let bridge = webViewController.bridge,
              let webView = webViewController.webView else {
            print("[TidexContainer] Cannot reload - bridge or webView not available")
            return
        }

        let serverURL = bridge.config.serverURL
        print("[TidexContainer] Reloading WebView with URL: \(serverURL)")
        webView.load(URLRequest(url: serverURL))
    }

    private func setupWebView() {
        webViewController = LocaleAwareBridgeViewController()

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
        // Remove the top separator line (hairline border) that iOS 18 shows by default
        appearance.shadowColor = .clear
        appearance.shadowImage = UIImage()
        customTabBar.standardAppearance = appearance
        if #available(iOS 15.0, *) {
            customTabBar.scrollEdgeAppearance = appearance
        }

        // Create tab items with locale-appropriate initial titles
        let initialTitles = getInitialTabTitles()
        var items: [UITabBarItem] = []
        for (index, tab) in tabDefinitions.enumerated() {
            let isCenterTab = index == 2  // Add tab (plus icon)
            let title = isCenterTab ? nil : (index < initialTitles.count ? initialTitles[index] : "")

            // Use larger icon for center tab
            let image: UIImage?
            if isCenterTab {
                let config = UIImage.SymbolConfiguration(pointSize: 28, weight: .medium)
                image = UIImage(systemName: tab.imageName, withConfiguration: config)
            } else {
                image = UIImage(systemName: tab.imageName)
            }

            let item = UITabBarItem(
                title: title,
                image: image,
                tag: index
            )

            // Shift center tab icon down to fill the space where title would be
            if isCenterTab {
                item.imageInsets = UIEdgeInsets(top: 6, left: 0, bottom: -6, right: 0)
            }

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

        // Start with tab bar hidden - it will be shown when entering (app) routes
        // This prevents the tab bar from flashing on login/onboarding screens
        customTabBar.isHidden = true
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
            // Register NativeTabBar plugin
            let tabBarPlugin = NativeTabBarPlugin()
            tabBarPlugin.containerController = self
            bridge.registerPluginInstance(tabBarPlugin)
            self.nativeTabBarPlugin = tabBarPlugin

            // Register NativeSplash plugin
            let splashPlugin = NativeSplashPlugin()
            bridge.registerPluginInstance(splashPlugin)

            // Register ShiftActivity plugin for Live Activities
            let shiftActivityPlugin = ShiftActivityPlugin()
            bridge.registerPluginInstance(shiftActivityPlugin)

            // Register DocumentShare plugin for PDF/CSV export
            let documentSharePlugin = DocumentSharePlugin()
            bridge.registerPluginInstance(documentSharePlugin)

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

    /// Update tab bar titles dynamically from the web layer.
    ///
    /// Note: Currently unused. Tab titles are set at launch based on iOS device locale
    /// (via `Locale.preferredLanguages` in `LocaleAwareBridgeViewController`).
    /// This method is kept for potential future use cases where dynamic title updates
    /// from JavaScript might be needed (e.g., runtime language switching without app restart).
    ///
    /// - Parameter titles: Array of title strings matching the order of `tabDefinitions`
    func setTabTitles(_ titles: [String]) {
        guard let items = customTabBar.items else { return }
        for (index, title) in titles.enumerated() {
            guard index < items.count else { break }
            items[index].title = title
        }
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

    // MARK: - Splash Screen

    private func setupSplashScreen() {
        // Load the LaunchScreen storyboard and instantiate its view controller
        guard let launchStoryboard = UIStoryboard(name: "LaunchScreen", bundle: nil).instantiateInitialViewController() else {
            return
        }

        let splash = launchStoryboard.view!
        splash.frame = view.bounds
        splash.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        // Add on top of everything
        view.addSubview(splash)
        splashView = splash
    }

    /// Hide the splash screen with animation
    /// - Parameters:
    ///   - duration: Fade out duration in seconds
    ///   - completion: Called when animation completes
    func hideSplash(duration: TimeInterval = 0.2, completion: (() -> Void)? = nil) {
        guard let splash = splashView else {
            completion?()
            return
        }

        UIView.animate(withDuration: duration, animations: {
            splash.alpha = 0
        }, completion: { _ in
            splash.removeFromSuperview()
            self.splashView = nil
            completion?()
        })
    }

    /// Show the splash screen (rarely needed, but available)
    func showSplash() {
        guard splashView == nil else { return }
        setupSplashScreen()
    }

    /// Check if splash screen is currently visible
    func isSplashVisible() -> Bool {
        return splashView != nil && splashView?.alpha ?? 0 > 0
    }
}
