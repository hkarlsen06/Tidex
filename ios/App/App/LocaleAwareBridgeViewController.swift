import UIKit
import WebKit
import Capacitor

/// A CAPBridgeViewController subclass that pre-sets the locale cookie before WebView loads
/// and handles navigation errors to trigger the native offline screen.
///
/// This ensures the server receives the correct locale on the very first request by:
/// - Setting the `tidex-locale` cookie in both HTTPCookieStorage (sync) and WKWebsiteDataStore (async)
/// - The Next.js proxy reads this cookie and redirects to the correct locale path
///
/// Also monitors for network-related navigation failures and notifies TidexContainerViewController
/// to show the native offline screen instead of the default error page.
///
/// Uses `Locale.preferredLanguages` which respects:
/// - Per-app language setting (iOS Settings > Tidex > Language)
/// - System language preferences
///
/// Note: WKWebView's Accept-Language header does NOT respect per-app language settings,
/// only the system language. That's why we must use cookies for locale detection.
///
/// References:
/// - https://capacitorjs.com/docs/ios/viewcontroller
/// - https://github.com/ionic-team/capacitor/blob/main/ios/Capacitor/Capacitor/CAPBridgeViewController.swift
class LocaleAwareBridgeViewController: CAPBridgeViewController {

    /// Network-related error codes that should trigger the offline screen
    private static let networkErrorCodes: Set<Int> = [
        NSURLErrorNotConnectedToInternet,      // -1009
        NSURLErrorNetworkConnectionLost,       // -1005
        NSURLErrorTimedOut,                    // -1001
        NSURLErrorCannotFindHost,              // -1003
        NSURLErrorCannotConnectToHost,         // -1004
        NSURLErrorDNSLookupFailed,             // -1006
        NSURLErrorSecureConnectionFailed,      // -1200
        NSURLErrorServerCertificateUntrusted,  // -1202
    ]

    /// Cookie name - must match LOCALE_COOKIE in lib/i18n/config.ts
    private static let localeCookieName = "tidex-locale"

    /// Supported app locales - must match lib/i18n/config.ts
    enum AppLocale: String {
        case norwegian = "no"
        case english = "en"

        /// Default locale when no match found
        static let `default`: AppLocale = .norwegian
    }

    /// Detect the appropriate app locale from device settings.
    /// Uses `Locale.preferredLanguages` which correctly reflects per-app language
    /// settings in iOS Settings > Tidex > Language.
    static func detectDeviceLocale() -> AppLocale {
        let preferredLanguage = Locale.preferredLanguages.first ?? "en"

        // Check for Norwegian variants (nb = Bokmål, nn = Nynorsk, no = generic)
        if preferredLanguage.hasPrefix("nb") ||
           preferredLanguage.hasPrefix("nn") ||
           preferredLanguage.hasPrefix("no") {
            return .norwegian
        }

        // Default to English for all other languages
        return .english
    }

    /// Get the server domain from instance configuration.
    /// Returns the host portion of the server URL (e.g., "app.tidex.no" or "192.168.68.62").
    private static func getServerDomain(from config: InstanceConfiguration) -> String {
        if let host = config.serverURL.host {
            return host
        }
        // Fallback to production domain
        return "app.tidex.no"
    }

    /// Create the locale cookie with appropriate settings.
    private static func createLocaleCookie(for domain: String) -> HTTPCookie? {
        let deviceLocale = detectDeviceLocale()

        // Determine if we should use secure cookies
        // Local development uses HTTP, production uses HTTPS
        let isSecure = !isLocalNetworkHost(domain)

        var cookieProperties: [HTTPCookiePropertyKey: Any] = [
            .domain: domain,
            .path: "/",
            .name: localeCookieName,
            .value: deviceLocale.rawValue,
            .expires: Date(timeIntervalSinceNow: 60 * 60 * 24 * 365) // 1 year
        ]

        if isSecure {
            cookieProperties[.secure] = true
        }

        return HTTPCookie(properties: cookieProperties)
    }

    private static func isLocalNetworkHost(_ domain: String) -> Bool {
        let lowercased = domain.lowercased()
        if lowercased == "localhost" || lowercased == "127.0.0.1" {
            return true
        }

        let parts = lowercased.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else {
            return false
        }

        // 10.0.0.0/8
        if parts[0] == 10 {
            return true
        }

        // 172.16.0.0/12
        if parts[0] == 172, (16...31).contains(parts[1]) {
            return true
        }

        // 192.168.0.0/16
        if parts[0] == 192, parts[1] == 168 {
            return true
        }

        return false
    }

    /// Override webViewConfiguration to set up the cookie before the WebView is created.
    ///
    /// This method is called during loadView(), before the WebView makes any requests.
    /// We set the cookie in both:
    /// 1. HTTPCookieStorage.shared (synchronous, shared with URLSession)
    /// 2. WKWebsiteDataStore (async, WKWebView specific)
    ///
    /// The synchronous HTTPCookieStorage set ensures the cookie is available immediately,
    /// while the WKWebsiteDataStore set ensures WKWebView picks it up.
    override open func webViewConfiguration(for instanceConfiguration: InstanceConfiguration) -> WKWebViewConfiguration {
        // Get the parent's configuration first
        let config = super.webViewConfiguration(for: instanceConfiguration)

        let domain = Self.getServerDomain(from: instanceConfiguration)

        guard let cookie = Self.createLocaleCookie(for: domain) else {
            print("[LocaleAwareBridgeViewController] Failed to create locale cookie")
            return config
        }

        // Set cookie synchronously in the shared cookie storage
        // This ensures it's available immediately for the first request
        HTTPCookieStorage.shared.setCookie(cookie)
        print("[LocaleAwareBridgeViewController] Set locale cookie (sync): \(cookie.value) for domain: \(domain)")

        // Also set in WKWebsiteDataStore for WKWebView
        // Use non-persistent data store if that's what the config uses, otherwise use the config's store
        config.websiteDataStore.httpCookieStore.setCookie(cookie) {
            print("[LocaleAwareBridgeViewController] Set locale cookie (async): \(cookie.value) for domain: \(domain)")
        }

        return config
    }

    // MARK: - View Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        // Set ourselves as the navigation delegate to catch load errors
        // Note: CAPBridgeViewController may have its own delegate handling,
        // but we can intercept errors here
        webView?.navigationDelegate = self
    }
}

// MARK: - WKNavigationDelegate

extension LocaleAwareBridgeViewController: WKNavigationDelegate {

    /// Called when a navigation fails before the page starts loading
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleNavigationError(error)
    }

    /// Called when a navigation fails after the page starts loading
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleNavigationError(error)
    }

    /// Handle navigation errors - show offline screen for network errors
    private func handleNavigationError(_ error: Error) {
        let nsError = error as NSError

        // Log the full error for debugging
        print("[LocaleAwareBridge] Navigation error: domain=\(nsError.domain) code=\(nsError.code) desc=\(nsError.localizedDescription)")

        // Check if this is a network-related error
        guard nsError.domain == NSURLErrorDomain else {
            print("[LocaleAwareBridge] Non-network error - ignoring")
            return
        }

        // Ignore cancelled requests (happens during normal navigation)
        if nsError.code == NSURLErrorCancelled {
            print("[LocaleAwareBridge] Request cancelled - ignoring")
            return
        }

        if Self.networkErrorCodes.contains(nsError.code) {
            print("[LocaleAwareBridge] Network error detected - showing offline screen")
            TidexContainerViewController.shared?.showOfflineScreen()
        } else {
            print("[LocaleAwareBridge] URL error not in whitelist - ignoring")
        }
    }

    // MARK: - Passthrough delegates to preserve Capacitor functionality

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        // Let Capacitor handle this
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("[LocaleAwareBridge] didFinish - URL: \(webView.url?.absoluteString ?? "nil")")

        // Navigation succeeded - hide offline screen if showing
        // Note: Splash is hidden by JS calling NativeSplash.hide() after tab bar renders
        if TidexContainerViewController.shared?.isShowingOfflineScreen == true {
            print("[LocaleAwareBridge] Navigation succeeded - hiding offline screen")
            TidexContainerViewController.shared?.hideOfflineScreen()
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Allow all navigations
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        // Allow all responses
        decisionHandler(.allow)
    }
}
