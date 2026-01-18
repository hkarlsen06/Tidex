import Foundation

/// API configuration loaded from Info.plist
/// Required keys: SUPABASE_URL, SUPABASE_ANON_KEY
enum APIConfiguration {

    // MARK: - Supabase Configuration

    static var supabaseURL: URL {
        guard let urlString = Bundle.main.infoDictionary?["SUPABASE_URL"] as? String,
              let url = URL(string: urlString) else {
            fatalError("SUPABASE_URL not found in Info.plist or invalid URL")
        }
        return url
    }

    static var supabaseAnonKey: String {
        guard let key = Bundle.main.infoDictionary?["SUPABASE_ANON_KEY"] as? String, !key.isEmpty else {
            fatalError("SUPABASE_ANON_KEY not found in Info.plist")
        }
        return key
    }

    // MARK: - Google Sign-In Configuration

    /// iOS Client ID from Google Cloud Console
    /// This is used by the native Google Sign-In SDK
    static let googleiOSClientID = "496501907923-a0sng8rs2gscdu2fdenlq4j2g8vq9gas.apps.googleusercontent.com"

    // MARK: - Web App Configuration

    /// Base URL for the Next.js web app API
    /// Used for endpoints that require server-side processing (e.g., sharing)
    static let webAppBaseURL = URL(string: "https://app.tidex.no")!

    // MARK: - App Configuration

    /// App Group identifier for shared storage with widget
    static let appGroupID = "group.no.tidex.app"

    /// Keychain service identifier
    static let keychainService = "no.tidex.app"

    /// UserDefaults key for locale preference
    static let localeKey = "tidex-locale"
}
