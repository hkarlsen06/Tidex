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
      rpcName: "report_sharing_screenshot",
      params: ["p_sharer_id": .string(sharerId)]
    )
  }

  func reportChatScreenshot(threadId: String) async throws {
    try await reportScreenshot(
      targetKey: "thread:\(threadId)",
      rpcName: "report_thread_screenshot",
      params: ["p_thread_id": .string(threadId)]
    )
  }

  private func reportScreenshot(
    targetKey: String,
    rpcName: String,
    params: [String: AnyJSON]
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

    do {
      _ = try await AuthSessionManager.shared.getSession()
    } catch {
      lastReportedTimestamps.removeValue(forKey: targetKey)
      throw error
    }

    logger.info("Reporting screenshot notification for \(targetKey)")
    do {
      struct ScreenshotRPCResponse: Decodable {
        let success: Bool
      }

      let response: ScreenshotRPCResponse =
        try await supabase
        .rpc(rpcName, params: params)
        .single()
        .execute()
        .value

      guard response.success else {
        lastReportedTimestamps.removeValue(forKey: targetKey)
        throw ScreenshotServiceError.httpError(statusCode: 500)
      }
    } catch {
      lastReportedTimestamps.removeValue(forKey: targetKey)
      throw error
    }

    logger.info("Screenshot reported successfully")
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
