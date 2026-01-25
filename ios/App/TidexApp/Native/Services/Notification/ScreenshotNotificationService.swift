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

    private let urlSession: URLSession

    /// Cooldown tracking to prevent notification spam
    /// Key: sharer ID, Value: last reported timestamp
    private var lastReportedTimestamps: [String: Date] = [:]

    /// Minimum interval between screenshot notifications for the same sharer (5 minutes)
    private let cooldownInterval: TimeInterval = 5 * 60

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        self.urlSession = URLSession(configuration: config)
    }

    /// Reports that the current user took a screenshot of another user's shifts
    /// - Parameter sharerId: The ID of the user whose shifts were screenshotted
    func reportScreenshot(sharerId: String) async throws {
        // Check cooldown to prevent spam
        if let lastReported = lastReportedTimestamps[sharerId] {
            let elapsed = Date().timeIntervalSince(lastReported)
            if elapsed < cooldownInterval {
                logger.info("Screenshot notification skipped - cooldown active (\(Int(cooldownInterval - elapsed))s remaining)")
                return
            }
        }

        // Get auth session
        let session = try await supabase.auth.session
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
        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ScreenshotServiceError.networkError
        }

        switch httpResponse.statusCode {
        case 200, 201:
            // Update cooldown timestamp
            lastReportedTimestamps[sharerId] = Date()
            logger.info("Screenshot reported successfully")
        case 401:
            throw ScreenshotServiceError.notAuthenticated
        case 429:
            // Rate limited - update cooldown anyway
            lastReportedTimestamps[sharerId] = Date()
            logger.warning("Screenshot notification rate limited")
        default:
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            logger.error("Screenshot report failed: \(httpResponse.statusCode) - \(message)")
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
