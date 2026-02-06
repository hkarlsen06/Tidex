import Foundation
import Supabase
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "ScreenshotNotificationService")

/// Service for reporting screenshot events to the backend
/// When a user takes a screenshot while viewing another user's shifts,
/// this service notifies the shift owner via push notification
@MainActor
final class ScreenshotNotificationService {
  static let shared = ScreenshotNotificationService()

  /// Shared URLSession from factory (quick timeout: 15s request, 30s resource)
  private let urlSession = URLSessionFactory.quick

  /// Cooldown tracking to prevent notification spam
  /// Key: sharer ID, Value: last reported timestamp
  private var lastReportedTimestamps: [String: Date] = [:]

  /// Tracks in-flight requests to prevent concurrent duplicate reports
  private var inFlightRequests: Set<String> = []

  /// Minimum interval between screenshot notifications for the same sharer (5 minutes)
  private let cooldownInterval: TimeInterval = 5 * 60

  private init() {}

  /// Reports that the current user took a screenshot of another user's shifts
  /// - Parameter sharerId: The ID of the user whose shifts were screenshotted
  func reportScreenshot(sharerId: String) async throws {
    // Check if request is already in flight for this sharer
    guard !inFlightRequests.contains(sharerId) else {
      logger.info("Screenshot notification skipped - request already in flight for sharer")
      return
    }

    // Check cooldown to prevent spam
    if let lastReported = lastReportedTimestamps[sharerId] {
      let elapsed = Date().timeIntervalSince(lastReported)
      if elapsed < cooldownInterval {
        logger.info(
          "Screenshot notification skipped - cooldown active (\(Int(self.cooldownInterval - elapsed))s remaining)"
        )
        return
      }
    }

    // Mark as in-flight BEFORE async operation to prevent race conditions
    inFlightRequests.insert(sharerId)
    defer { inFlightRequests.remove(sharerId) }

    // Update timestamp BEFORE network call to prevent concurrent requests from passing cooldown check
    lastReportedTimestamps[sharerId] = Date()

    // Get auth session (using AuthSessionManager to prevent concurrent refresh race conditions)
    let session: Session
    do {
      session = try await AuthSessionManager.shared.getSession()
    } catch {
      // On auth failure, remove timestamp so retry is possible
      lastReportedTimestamps.removeValue(forKey: sharerId)
      throw error
    }
    let accessToken = session.accessToken

    // Build request
    let url = APIConfiguration.webAppBaseURL.appendingPathComponent("/api/sharing/screenshot")

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let body: [String: Any] = ["sharerId": sharerId]
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    logger.info("Reporting screenshot for sharer \(sharerId)")

    // Execute request
    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await urlSession.data(for: request)
    } catch {
      // On network failure, remove timestamp so retry is possible
      lastReportedTimestamps.removeValue(forKey: sharerId)
      throw error
    }

    guard let httpResponse = response as? HTTPURLResponse else {
      // On response parsing failure, remove timestamp so retry is possible
      lastReportedTimestamps.removeValue(forKey: sharerId)
      throw ScreenshotServiceError.networkError
    }

    switch httpResponse.statusCode {
    case 200, 201:
      // Timestamp already set - keep it for cooldown
      logger.info("Screenshot reported successfully")
    case 401:
      // On auth error, remove timestamp so retry is possible after re-auth
      lastReportedTimestamps.removeValue(forKey: sharerId)
      throw ScreenshotServiceError.notAuthenticated
    case 429:
      // Rate limited - keep timestamp (cooldown is working correctly)
      logger.warning("Screenshot notification rate limited")
    default:
      let message = String(data: data, encoding: .utf8) ?? "Unknown error"
      logger.error("Screenshot report failed: \(httpResponse.statusCode) - \(message)")
      // On server error, remove timestamp so retry is possible
      lastReportedTimestamps.removeValue(forKey: sharerId)
      throw ScreenshotServiceError.httpError(statusCode: httpResponse.statusCode)
    }
  }
}

// MARK: - Errors

enum ScreenshotServiceError: Error, LocalizedError {
  case notAuthenticated
  case networkError
  case httpError(statusCode: Int)

  var errorDescription: String? {
    switch self {
    case .notAuthenticated:
      return "Not authenticated"
    case .networkError:
      return "Network error"
    case .httpError(let code):
      return "HTTP error \(code)"
    }
  }
}
