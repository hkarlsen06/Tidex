import Foundation
import os.log

private let logger = Logger(subsystem: "no.tidex.app", category: "TermsVersion")

/// Terms version management for iOS
/// Fetches the current terms version manifest from marketing, with a hardcoded fallback.
enum TermsVersion {
  /// Base URL for user-facing pages (terms, privacy)
  static let baseURL = APIConfiguration.marketingBaseURL.absoluteString

  /// Fallback legal version reference (used when API is unavailable).
  /// Prefer a precise timestamp so same-day legal updates can still trigger re-acceptance.
  private static let fallbackVersionReference = "2026-03-28T00:40:00Z"

  /// Cached version reference (fetched from API)
  private static var cachedVersionReference: String?
  private static var lastFetchTime: Date?
  private static let cacheExpiryInterval: TimeInterval = 3600  // 1 hour

  /// Maximum time to wait for terms version API response
  /// Since this runs in the background, we can be more lenient
  private static let requestTimeout: TimeInterval = 10.0

  // MARK: - Public API

  /// Fetch the current legal version reference from the API
  /// Uses a cached value if available and not expired
  /// Returns fallback version if API is unavailable (timeout/error)
  static func fetchCurrentVersionReference() async -> String {
    // Check cache first
    if let cached = cachedVersionReference,
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
        return fallbackVersionReference
      }

      let (data, response) = try await withTimeout(seconds: requestTimeout) {
        try await URLSession.shared.data(from: url)
      }

      guard let httpResponse = response as? HTTPURLResponse,
        httpResponse.statusCode == 200
      else {
        logger.warning("API returned non-200 status")
        return fallbackVersionReference
      }

      let versionResponse = try JSONDecoder().decode(VersionResponse.self, from: data)

      let latestVersionReference = latestVersionReference(
        termsVersionDate: versionResponse.termsVersionDate,
        privacyVersionDate: versionResponse.privacyVersionDate,
        termsVersionAt: versionResponse.termsVersionAt,
        privacyVersionAt: versionResponse.privacyVersionAt
      )

      // Cache the result
      cachedVersionReference = latestVersionReference
      lastFetchTime = Date()

      return latestVersionReference
    } catch is TimeoutError {
      logger.warning("Request timed out after \(requestTimeout)s. Using fallback.")
      return fallbackVersionReference
    } catch {
      logger.warning("Failed to fetch version: \(error.localizedDescription). Using fallback.")
      return fallbackVersionReference
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
    let currentVersionReference = cachedVersionReference ?? fallbackVersionReference

    return compareDates(acceptedAt: termsAcceptedAt, versionReference: currentVersionReference)
  }

  /// Async version that fetches the latest version date first
  static func needsTermsReAcceptanceAsync(_ termsAcceptedAt: String?) async -> Bool {
    guard let termsAcceptedAt = termsAcceptedAt, !termsAcceptedAt.isEmpty else {
      // Never accepted terms
      return true
    }

    let currentVersionReference = await fetchCurrentVersionReference()
    return compareDates(acceptedAt: termsAcceptedAt, versionReference: currentVersionReference)
  }

  // MARK: - Private Helpers

  private static func compareDates(acceptedAt: String, versionReference: String) -> Bool {
    // Parse the ISO date string from user metadata
    let acceptedDate = parseVersionReference(acceptedAt)
    guard let accepted = acceptedDate else {
      // Can't parse date, require re-acceptance
      logger.warning("Could not parse termsAcceptedAt: \(acceptedAt)")
      return true
    }

    guard let currentVersion = parseVersionReference(versionReference) else {
      // Should never happen with valid date
      logger.error("Could not parse versionReference: \(versionReference)")
      return false
    }

    // User needs to re-accept if their acceptance date is before the current terms version
    return accepted < currentVersion
  }

  private static func latestVersionReference(
    termsVersionDate: String,
    privacyVersionDate: String,
    termsVersionAt: String?,
    privacyVersionAt: String?
  ) -> String {
    let termsReference = termsVersionAt ?? termsVersionDate
    let privacyReference = privacyVersionAt ?? privacyVersionDate

    guard
      let termsDate = parseVersionReference(termsReference),
      let privacyDate = parseVersionReference(privacyReference)
    else {
      return termsVersionDate
    }

    return privacyDate > termsDate ? privacyReference : termsReference
  }

  private static func parseVersionReference(_ value: String) -> Date? {
    let isoFormatter = ISO8601DateFormatter()
    isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    if let date = isoFormatter.date(from: value) {
      return date
    }

    isoFormatter.formatOptions = [.withInternetDateTime]
    if let date = isoFormatter.date(from: value) {
      return date
    }

    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd"
    dateFormatter.timeZone = TimeZone(identifier: "UTC")
    return dateFormatter.date(from: value)
  }
}

// MARK: - API Response Model

private struct VersionResponse: Decodable {
  let termsVersionDate: String
  let privacyVersionDate: String
  let termsVersionAt: String?
  let privacyVersionAt: String?
}
