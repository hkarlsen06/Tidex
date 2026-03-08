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
  /// Key: screenshot target, Value: last reported timestamp
  private var lastReportedTimestamps: [String: Date] = [:]

  /// Tracks in-flight requests to prevent concurrent duplicate reports
  private var inFlightRequests: Set<String> = []

  /// Minimum interval between screenshot notifications for the same sharer (5 minutes)
  private let cooldownInterval: TimeInterval = 5 * 60

  private init() {}

  func reportScreenshot(sharerId: String) async throws {
    try await reportScreenshot(
      targetKey: "shifts:\(sharerId)",
      endpointPath: "/api/sharing/screenshot",
      requestBody: ["sharerId": sharerId]
    )
  }

  func reportChatScreenshot(threadId: String) async throws {
    try await reportScreenshot(
      targetKey: "thread:\(threadId)",
      endpointPath: "/api/friends/chat/screenshot",
      requestBody: ["threadId": threadId]
    )
  }

  private func reportScreenshot(
    targetKey: String,
    endpointPath: String,
    requestBody: [String: Any]
  ) async throws {
    guard !inFlightRequests.contains(targetKey) else {
      logger.info("Screenshot notification skipped - request already in flight for \(targetKey)")
      return
    }

    if let lastReported = lastReportedTimestamps[targetKey] {
      let elapsed = Date().timeIntervalSince(lastReported)
      if elapsed < cooldownInterval {
        logger.info(
          "Screenshot notification skipped - cooldown active (\(Int(self.cooldownInterval - elapsed))s remaining)"
        )
        return
      }
    }

    inFlightRequests.insert(targetKey)
    defer { inFlightRequests.remove(targetKey) }

    lastReportedTimestamps[targetKey] = Date()

    let session: Session
    do {
      session = try await AuthSessionManager.shared.getSession()
    } catch {
      lastReportedTimestamps.removeValue(forKey: targetKey)
      throw error
    }
    let accessToken = session.accessToken

    let url = APIConfiguration.webAppBaseURL.appendingPathComponent(endpointPath)

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

    logger.info("Reporting screenshot notification for \(targetKey)")

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await urlSession.data(for: request)
    } catch {
      lastReportedTimestamps.removeValue(forKey: targetKey)
      throw error
    }

    guard let httpResponse = response as? HTTPURLResponse else {
      lastReportedTimestamps.removeValue(forKey: targetKey)
      throw ScreenshotServiceError.networkError
    }

    switch httpResponse.statusCode {
    case 200, 201:
      logger.info("Screenshot reported successfully")
    case 401:
      lastReportedTimestamps.removeValue(forKey: targetKey)
      throw ScreenshotServiceError.notAuthenticated
    case 429:
      logger.warning("Screenshot notification rate limited")
    default:
      let message = String(data: data, encoding: .utf8) ?? "Unknown error"
      logger.error("Screenshot report failed: \(httpResponse.statusCode) - \(message)")
      lastReportedTimestamps.removeValue(forKey: targetKey)
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
