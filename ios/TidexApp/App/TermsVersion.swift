import Foundation
import os.log

private let logger = Logger(subsystem: "no.tidex.app", category: "TermsVersion")

/// Terms version management for iOS
/// Fetches the current terms version manifest from marketing, with a hardcoded fallback.
enum TermsVersion {
  /// Base URL for user-facing pages (terms, privacy)
  static let baseURL = APIConfiguration.marketingBaseURL.absoluteString

  /// Fallback terms version date (used when API is unavailable)
  /// Keep this at the latest of terms/privacy as a safety net.
  private static let fallbackVersionDate = "2026-03-15"

  /// Cached version date (fetched from API)
  private static var cachedVersionDate: String?
  private static var lastFetchTime: Date?
  private static let cacheExpiryInterval: TimeInterval = 3600  // 1 hour

  /// Maximum time to wait for terms version API response
  /// Since this runs in the background, we can be more lenient
  private static let requestTimeout: TimeInterval = 10.0

  // MARK: - Public API

  /// Fetch the current terms version date from the API
  /// Uses a cached value if available and not expired
  /// Returns fallback version if API is unavailable (timeout/error)
  static func fetchCurrentVersionDate() async -> String {
    // Check cache first
    if let cached = cachedVersionDate,
      let fetchTime = lastFetchTime,
      Date().timeIntervalSince(fetchTime) < cacheExpiryInterval
    {
      return cached
    }

    // Fetch from API with timeout
    do {
      let url = APIConfiguration.legalVersionURL
      guard url.absoluteString.isEmpty == false else {
        logger.error("Invalid endpoint URL")
        return fallbackVersionDate
      }

      let (data, response) = try await withTimeout(seconds: requestTimeout) {
        try await URLSession.shared.data(from: url)
      }

      guard let httpResponse = response as? HTTPURLResponse,
        httpResponse.statusCode == 200
      else {
        logger.warning("API returned non-200 status")
        return fallbackVersionDate
      }

      let versionResponse = try JSONDecoder().decode(VersionResponse.self, from: data)

      let latestVersionDate = latestVersionDate(
        termsVersionDate: versionResponse.termsVersionDate,
        privacyVersionDate: versionResponse.privacyVersionDate
      )

      // Cache the result
      cachedVersionDate = latestVersionDate
      lastFetchTime = Date()

      return latestVersionDate
    } catch is TimeoutError {
      logger.warning("Request timed out after \(requestTimeout)s. Using fallback.")
      return fallbackVersionDate
    } catch {
      logger.warning("Failed to fetch version: \(error.localizedDescription). Using fallback.")
      return fallbackVersionDate
    }
  }

  // MARK: - Timeout Helper

  private struct TimeoutError: Error {}

  /// Execute an async operation with a timeout
  private static func withTimeout<T>(
    seconds: TimeInterval,
    operation: @escaping () async throws -> T
  ) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
      group.addTask {
        try await operation()
      }

      group.addTask {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        throw TimeoutError()
      }

      // Return the first result (either the operation or timeout)
      // swiftlint:disable:next force_unwrapping
      let result = try await group.next()!
      group.cancelAll()
      return result
    }
  }

  /// Check if the user needs to accept or re-accept terms
  /// - Parameter termsAcceptedAt: ISO date string of when user accepted terms (from user metadata)
  /// - Returns: true if user needs to accept/re-accept terms
  static func needsTermsReAcceptance(_ termsAcceptedAt: String?) -> Bool {
    guard let termsAcceptedAt = termsAcceptedAt, !termsAcceptedAt.isEmpty else {
      // Never accepted terms
      return true
    }

    // Use cached version if available, otherwise use fallback
    // The async fetch happens in AppCoordinator before this is called
    let currentVersionDate = cachedVersionDate ?? fallbackVersionDate

    return compareDates(acceptedAt: termsAcceptedAt, versionDate: currentVersionDate)
  }

  /// Async version that fetches the latest version date first
  static func needsTermsReAcceptanceAsync(_ termsAcceptedAt: String?) async -> Bool {
    guard let termsAcceptedAt = termsAcceptedAt, !termsAcceptedAt.isEmpty else {
      // Never accepted terms
      return true
    }

    let currentVersionDate = await fetchCurrentVersionDate()
    return compareDates(acceptedAt: termsAcceptedAt, versionDate: currentVersionDate)
  }

  // MARK: - Private Helpers

  private static func compareDates(acceptedAt: String, versionDate: String) -> Bool {
    // Parse the ISO date string from user metadata
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    // Try with fractional seconds first, then without
    var acceptedDate: Date?
    acceptedDate = formatter.date(from: acceptedAt)
    if acceptedDate == nil {
      formatter.formatOptions = [.withInternetDateTime]
      acceptedDate = formatter.date(from: acceptedAt)
    }

    // Fallback to simple date parsing if ISO8601 fails
    if acceptedDate == nil {
      let simpleDateFormatter = DateFormatter()
      simpleDateFormatter.dateFormat = "yyyy-MM-dd"
      simpleDateFormatter.timeZone = TimeZone(identifier: "UTC")
      acceptedDate = simpleDateFormatter.date(from: acceptedAt)
    }

    guard let accepted = acceptedDate else {
      // Can't parse date, require re-acceptance
      logger.warning("Could not parse termsAcceptedAt: \(acceptedAt)")
      return true
    }

    // Parse current version date
    let versionFormatter = DateFormatter()
    versionFormatter.dateFormat = "yyyy-MM-dd"
    versionFormatter.timeZone = TimeZone(identifier: "UTC")

    guard let currentVersion = versionFormatter.date(from: versionDate) else {
      // Should never happen with valid date
      logger.error("Could not parse versionDate: \(versionDate)")
      return false
    }

    // User needs to re-accept if their acceptance date is before the current terms version
    return accepted < currentVersion
  }

  private static func latestVersionDate(
    termsVersionDate: String,
    privacyVersionDate: String
  ) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.timeZone = TimeZone(identifier: "UTC")

    guard
      let termsDate = formatter.date(from: termsVersionDate),
      let privacyDate = formatter.date(from: privacyVersionDate)
    else {
      return termsVersionDate
    }

    return privacyDate > termsDate ? privacyVersionDate : termsVersionDate
  }
}

// MARK: - API Response Model

private struct VersionResponse: Decodable {
  let termsVersionDate: String
  let privacyVersionDate: String
}
