import Foundation
import os.log
import Supabase

private struct ScreenshotRPCResponse: Decodable {
  let success: Bool
}

// MARK: - Errors

internal enum ScreenshotServiceError: Error, LocalizedError {
  case httpError(statusCode: Int)
  case networkError
  case notAuthenticated

  internal var errorDescription: String? {
    switch self {
    case .httpError(let code):
      return "HTTP error \(code)"

    case .networkError:
      return "Network error"

    case .notAuthenticated:
      return "Not authenticated"
    }
  }
}

/// Service for reporting screenshot events to the backend
/// When a user takes a screenshot while viewing another user's shifts,
/// this service notifies the shift owner via push notification
@MainActor
internal final class ScreenshotNotificationService {
  private enum Constants {
    static let cooldownMinutes: TimeInterval = 5
    static let secondsPerMinute: TimeInterval = 60
    static let internalServerErrorStatusCode: Int = 500
  }

  private static let kLogger: Logger = Logger(subsystem: "com.tidex.app", category: "ScreenshotNotificationService")

  internal static let shared: ScreenshotNotificationService = ScreenshotNotificationService()

  /// Cooldown tracking to prevent notification spam
  /// Key: screenshot target, Value: last reported timestamp
  private var lastReportedTimestamps: [String: Date] = [:]

  /// Tracks in-flight requests to prevent concurrent duplicate reports
  private var inFlightRequests: Set<String> = []

  /// Minimum interval between screenshot notifications for the same sharer (5 minutes)
  private let cooldownInterval: TimeInterval = Constants.cooldownMinutes * Constants.secondsPerMinute

  private init() {
    // Singleton.
  }

  internal func reportScreenshot(sharerId: String) async throws {
    try await reportScreenshot(
      targetKey: "shifts:\(sharerId)",
      rpcName: "report_sharing_screenshot",
      params: ["p_sharer_id": .string(sharerId)]
    )
  }

  internal func reportChatScreenshot(threadId: String) async throws {
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
      Self.kLogger.info("Screenshot notification skipped - request already in flight for \(targetKey)")
      return
    }

    if let lastReported = lastReportedTimestamps[targetKey] {
      let elapsed: TimeInterval = Date().timeIntervalSince(lastReported)
      if elapsed < cooldownInterval {
        Self.kLogger.info(
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

    Self.kLogger.info("Reporting screenshot notification for \(targetKey)")
    do {
      let response: ScreenshotRPCResponse = try await executeScreenshotRPC(rpcName: rpcName, params: params)

      guard response.success else {
        lastReportedTimestamps.removeValue(forKey: targetKey)
        throw ScreenshotServiceError.httpError(statusCode: Constants.internalServerErrorStatusCode)
      }
    } catch {
      lastReportedTimestamps.removeValue(forKey: targetKey)
      throw error
    }

    Self.kLogger.info("Screenshot reported successfully")
  }

  private func executeScreenshotRPC(rpcName: String, params: [String: AnyJSON]) async throws -> ScreenshotRPCResponse {
    try await supabase
      .rpc(rpcName, params: params)
      .single()
      .execute()
      .value
  }

  deinit {
    // Singleton.
  }
}
