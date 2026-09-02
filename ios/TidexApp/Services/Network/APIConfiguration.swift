import Foundation
import os.log

private let logger = Logger(subsystem: "no.tidex.app", category: "APIConfiguration")

/// Errors that can occur when loading API configuration
enum APIConfigurationError: Error, LocalizedError {
  case missingSupabaseURL
  case invalidSupabaseURL(String)
  case missingSupabaseAnonKey

  var errorDescription: String? {
    switch self {
    case .missingSupabaseURL:
      return "SUPABASE_URL not found in Info.plist"

    case .invalidSupabaseURL(let urlString):
      return "Invalid SUPABASE_URL in Info.plist: \(urlString)"

    case .missingSupabaseAnonKey:
      return "SUPABASE_ANON_KEY not found in Info.plist"
    }
  }
}

/// API configuration loaded from Info.plist
/// Required keys: SUPABASE_URL, SUPABASE_ANON_KEY
enum APIConfiguration {

  // MARK: - Supabase Configuration

  private static func staticURL(_ string: String) -> URL {
    guard let url = URL(string: string) else {
      preconditionFailure("Invalid static URL: \(string)")
    }
    return url
  }

  /// Cached Supabase URL - loaded once at app startup
  /// Falls back to production URL if Info.plist is misconfigured (should never happen in release builds)
  static let supabaseURL: URL = {
    guard let urlString = Bundle.main.infoDictionary?["SUPABASE_URL"] as? String else {
      logger.error("SUPABASE_URL not found in Info.plist - using fallback")
      return staticURL("https://api.tidex.no")
    }
    guard let url = URL(string: urlString) else {
      logger.error("Invalid SUPABASE_URL in Info.plist: \(urlString) - using fallback")
      return staticURL("https://api.tidex.no")
    }
    return url
  }()

  /// Cached Supabase anon key - loaded once at app startup
  /// Falls back to empty string if missing (auth will fail gracefully)
  static let supabaseAnonKey: String = {
    guard let key = Bundle.main.infoDictionary?["SUPABASE_ANON_KEY"] as? String, !key.isEmpty else {
      logger.error("SUPABASE_ANON_KEY not found in Info.plist")
      return ""
    }
    return key
  }()

  // MARK: - Google Sign-In Configuration

  /// iOS Client ID from Google Cloud Console
  /// This is used by the native Google Sign-In SDK
  static let googleiOSClientID =
    "496501907923-a0sng8rs2gscdu2fdenlq4j2g8vq9gas.apps.googleusercontent.com"

  // MARK: - Marketing Configuration

  /// Public marketing site used for support and legal documents.
  static let marketingBaseURL = staticURL("https://tidex.no")
  static let supportURL = marketingBaseURL.appendingPathComponent("support")
  static let legalVersionURL = marketingBaseURL.appendingPathComponent("legal/version.json")

  // MARK: - App Configuration

  /// App Group identifier for shared storage with widget
  static let appGroupID = "group.no.tidex.app"

  /// Keychain service identifier
  static let keychainService = "no.tidex.app"

  /// UserDefaults key for locale preference
  static let localeKey = "tidex-locale"
}
