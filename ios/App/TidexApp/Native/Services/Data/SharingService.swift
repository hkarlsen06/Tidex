import Foundation
import Supabase
import Auth
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "SharingService")

// MARK: - API Response Types

/// Response from /api/sharing/sharers endpoint
private struct SharersAPIResponse: Codable {
    let sharers: [SharerData]

    struct SharerData: Codable {
        let id: String
        let email: String?
        let phone: String?
        let firstName: String?
        let profilePictureUrl: String?
        let oauthAvatarUrl: String?
        let sharedAt: String
        let showEarnings: Bool
        let blocked: Bool
    }
}

/// Response from /api/sharing/previews endpoint
private struct PreviewsAPIResponse: Codable {
    let previews: [PreviewData]

    struct PreviewData: Codable {
        let sharerId: String
        let shift: SharedShiftData?
        let status: String?
        let showEarnings: Bool
    }
}

// MARK: - Shift Preview

/// Preview of a sharer's next/active/past shift
struct SharerShiftPreview: Equatable {
    let sharerId: String
    let shift: SharedShiftData?
    let status: ShiftPreviewStatus?
    let showEarnings: Bool
}

/// Status of a shift preview
enum ShiftPreviewStatus: String {
    case active
    case upcoming
    case past
}

// MARK: - Errors

enum SharingServiceError: Error, LocalizedError {
    case notAuthenticated
    case networkError(underlying: Error)
    case decodingError(underlying: Error)
    case httpError(statusCode: Int, message: String?)
    case noShareAccess

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .httpError(let code, let message):
            return "HTTP \(code): \(message ?? "Unknown error")"
        case .noShareAccess:
            return "No access to shared shifts"
        }
    }
}

// MARK: - Cached Preview

/// Cached shift preview with timestamp
private struct CachedPreview {
    let preview: SharerShiftPreview
    let cachedAt: Date
}

// MARK: - Sharing Service

/// Service for fetching shared shifts and sharers
/// Uses Supabase for sharer list and Next.js API for shared shifts
@MainActor
final class SharingService: ObservableObject {
    static let shared = SharingService()

    @Published private(set) var sharers: [SharedUser] = []
    @Published private(set) var isLoadingSharers = false
    @Published private(set) var isLoadingShifts = false
    @Published private(set) var error: Error?

    private let urlSession: URLSession

    /// Cache for shift previews (by sharer ID)
    private var previewCache: [String: CachedPreview] = [:]

    /// Cache validity duration (5 minutes)
    private let previewCacheValiditySeconds: TimeInterval = 5 * 60

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.urlSession = URLSession(configuration: config)
    }

    /// Get cached preview if still valid
    func getCachedPreview(for sharerId: String) -> SharerShiftPreview? {
        guard let cached = previewCache[sharerId] else { return nil }
        let age = Date().timeIntervalSince(cached.cachedAt)
        guard age < previewCacheValiditySeconds else {
            previewCache.removeValue(forKey: sharerId)
            return nil
        }
        return cached.preview
    }

    /// Clear all preview cache
    func clearPreviewCache() {
        previewCache.removeAll()
    }

    // MARK: - Sharer List (via Next.js API)

    /// Fetch users who have shared their shifts with the current user
    /// Uses Next.js API endpoint which has access to admin client for user profile data
    func fetchSharers(for userId: String) async throws -> [SharedUser] {
        isLoadingSharers = true
        error = nil
        defer { isLoadingSharers = false }

        do {
            // Get the current session token
            let session = try await supabase.auth.session
            let accessToken = session.accessToken

            // Build URL for sharers endpoint
            let url = APIConfiguration.webAppBaseURL.appendingPathComponent("/api/sharing/sharers")

            // Build request with auth header
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            logger.info("Fetching sharers from \(url.absoluteString)")

            // Execute request
            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw SharingServiceError.networkError(underlying: URLError(.badServerResponse))
            }

            // Handle HTTP errors
            switch httpResponse.statusCode {
            case 200:
                break // Success
            case 401:
                throw SharingServiceError.notAuthenticated
            default:
                let message = String(data: data, encoding: .utf8)
                throw SharingServiceError.httpError(statusCode: httpResponse.statusCode, message: message)
            }

            // Decode response
            let decoder = JSONDecoder()
            let apiResponse: SharersAPIResponse
            do {
                apiResponse = try decoder.decode(SharersAPIResponse.self, from: data)
            } catch {
                logger.error("Failed to decode sharers response: \(error)")
                throw SharingServiceError.decodingError(underlying: error)
            }

            // Map to SharedUser
            let users = apiResponse.sharers.map { sharer in
                SharedUser(
                    id: sharer.id,
                    email: sharer.email,
                    phone: sharer.phone,
                    firstName: sharer.firstName,
                    profilePictureUrl: sharer.profilePictureUrl,
                    oauthAvatarUrl: sharer.oauthAvatarUrl,
                    sharedAt: sharer.sharedAt,
                    showEarnings: sharer.showEarnings,
                    blocked: sharer.blocked
                )
            }

            sharers = users
            logger.info("Loaded \(users.count) sharers for user")
            return users

        } catch let error as SharingServiceError {
            self.error = error
            throw error
        } catch is CancellationError {
            // Re-throw cancellation without wrapping
            throw CancellationError()
        } catch {
            let wrappedError = SharingServiceError.networkError(underlying: error)
            self.error = wrappedError
            throw wrappedError
        }
    }

    // MARK: - Shared Shifts (via Next.js API)

    /// Fetch shared shifts from the Next.js API
    /// This endpoint handles share verification and payroll computation
    func fetchSharedShifts(
        ownerId: String,
        year: Int,
        month: Int
    ) async throws -> SharedShiftsResponse {
        isLoadingShifts = true
        error = nil
        defer { isLoadingShifts = false }

        do {
            // Get the current session token
            let session = try await supabase.auth.session
            let accessToken = session.accessToken

            // Build URL
            var components = URLComponents(
                url: APIConfiguration.webAppBaseURL.appendingPathComponent("/api/sharing"),
                resolvingAgainstBaseURL: false
            )!
            components.queryItems = [
                URLQueryItem(name: "ownerId", value: ownerId),
                URLQueryItem(name: "year", value: String(year)),
                URLQueryItem(name: "month", value: String(month))
            ]

            guard let url = components.url else {
                throw SharingServiceError.networkError(underlying: URLError(.badURL))
            }

            // Build request with auth header
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            logger.info("Fetching shared shifts from \(url.absoluteString)")

            // Execute request
            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw SharingServiceError.networkError(underlying: URLError(.badServerResponse))
            }

            // Handle HTTP errors
            switch httpResponse.statusCode {
            case 200:
                break // Success
            case 401:
                throw SharingServiceError.notAuthenticated
            case 404:
                throw SharingServiceError.noShareAccess
            default:
                let message = String(data: data, encoding: .utf8)
                throw SharingServiceError.httpError(statusCode: httpResponse.statusCode, message: message)
            }

            // Decode response
            let decoder = JSONDecoder()
            do {
                let result = try decoder.decode(SharedShiftsResponse.self, from: data)
                logger.info("Loaded \(result.shifts.count) shared shifts for month \(year)-\(month)")
                return result
            } catch {
                logger.error("Failed to decode shared shifts: \(error)")
                throw SharingServiceError.decodingError(underlying: error)
            }

        } catch let error as SharingServiceError {
            self.error = error
            throw error
        } catch {
            let wrappedError = SharingServiceError.networkError(underlying: error)
            self.error = wrappedError
            throw wrappedError
        }
    }

    // MARK: - Shift Previews (via Next.js API)

    /// Fetch shift previews for all sharers
    /// Returns the most relevant shift (active > upcoming > past) for each sharer
    /// Uses cache for recently fetched previews (5 minute validity)
    func fetchShiftPreviews(sharerIds: [String], forceRefresh: Bool = false) async throws -> [SharerShiftPreview] {
        guard !sharerIds.isEmpty else { return [] }

        // Check cache first (unless force refresh)
        var cachedPreviews: [SharerShiftPreview] = []
        var uncachedIds: [String] = []

        if !forceRefresh {
            for sharerId in sharerIds {
                if let cached = getCachedPreview(for: sharerId) {
                    cachedPreviews.append(cached)
                } else {
                    uncachedIds.append(sharerId)
                }
            }

            // If all are cached, return immediately
            if uncachedIds.isEmpty {
                logger.info("Returning \(cachedPreviews.count) cached shift previews")
                return cachedPreviews
            }
        } else {
            uncachedIds = sharerIds
        }

        do {
            // Get the current session token
            let session = try await supabase.auth.session
            let accessToken = session.accessToken

            // Build URL - only fetch uncached IDs
            var components = URLComponents(
                url: APIConfiguration.webAppBaseURL.appendingPathComponent("/api/sharing/previews"),
                resolvingAgainstBaseURL: false
            )!
            components.queryItems = [
                URLQueryItem(name: "sharerIds", value: uncachedIds.joined(separator: ","))
            ]

            guard let url = components.url else {
                throw SharingServiceError.networkError(underlying: URLError(.badURL))
            }

            // Build request with auth header
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            logger.info("Fetching \(uncachedIds.count) shift previews from API (cached: \(cachedPreviews.count))")

            // Execute request
            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw SharingServiceError.networkError(underlying: URLError(.badServerResponse))
            }

            // Handle HTTP errors
            switch httpResponse.statusCode {
            case 200:
                break // Success
            case 401:
                throw SharingServiceError.notAuthenticated
            default:
                let message = String(data: data, encoding: .utf8)
                throw SharingServiceError.httpError(statusCode: httpResponse.statusCode, message: message)
            }

            // Decode response
            let decoder = JSONDecoder()
            do {
                let apiResponse = try decoder.decode(PreviewsAPIResponse.self, from: data)
                let now = Date()
                let freshPreviews = apiResponse.previews.map { preview in
                    SharerShiftPreview(
                        sharerId: preview.sharerId,
                        shift: preview.shift,
                        status: preview.status.flatMap { ShiftPreviewStatus(rawValue: $0) },
                        showEarnings: preview.showEarnings
                    )
                }

                // Cache the fresh previews
                for preview in freshPreviews {
                    previewCache[preview.sharerId] = CachedPreview(preview: preview, cachedAt: now)
                }

                // Merge cached + fresh and return
                let allPreviews = cachedPreviews + freshPreviews
                logger.info("Loaded \(freshPreviews.count) fresh + \(cachedPreviews.count) cached shift previews")
                return allPreviews
            } catch {
                logger.error("Failed to decode shift previews: \(error)")
                throw SharingServiceError.decodingError(underlying: error)
            }

        } catch let error as SharingServiceError {
            // If we have cached data, return it even on error
            if !cachedPreviews.isEmpty {
                logger.warning("API error, returning \(cachedPreviews.count) cached previews")
                return cachedPreviews
            }
            throw error
        } catch {
            // If we have cached data, return it even on error
            if !cachedPreviews.isEmpty {
                logger.warning("Network error, returning \(cachedPreviews.count) cached previews")
                return cachedPreviews
            }
            throw SharingServiceError.networkError(underlying: error)
        }
    }

    // MARK: - Friends Management (via Next.js API)

    /// Fetch all friends (bidirectional relationships) and share capacity
    /// Used by the sharing management modal
    func fetchAllFriends() async throws -> (friends: [Friend], capacity: ShareCapacity) {
        do {
            logger.info("Starting fetchAllFriends...")

            let session: Session
            do {
                session = try await supabase.auth.session
                logger.info("Got session, token expires at: \(session.expiresAt)")
            } catch {
                logger.error("Failed to get session: \(error.localizedDescription)")
                throw SharingServiceError.notAuthenticated
            }

            let accessToken = session.accessToken
            let url = APIConfiguration.webAppBaseURL.appendingPathComponent("/api/sharing/friends")

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            logger.info("Fetching all friends from \(url.absoluteString)")

            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                logger.error("Response was not HTTPURLResponse")
                throw SharingServiceError.networkError(underlying: URLError(.badServerResponse))
            }

            logger.info("HTTP status: \(httpResponse.statusCode), data size: \(data.count) bytes")

            switch httpResponse.statusCode {
            case 200:
                break
            case 401:
                logger.error("Got 401 Unauthorized")
                throw SharingServiceError.notAuthenticated
            default:
                let message = String(data: data, encoding: .utf8)
                logger.error("HTTP error \(httpResponse.statusCode): \(message ?? "no message")")
                throw SharingServiceError.httpError(statusCode: httpResponse.statusCode, message: message)
            }

            let decoder = JSONDecoder()
            do {
                let apiResponse = try decoder.decode(FriendsAPIResponse.self, from: data)
                logger.info("Loaded \(apiResponse.friends.count) friends (capacity: \(apiResponse.capacity.currentCount)/\(apiResponse.capacity.limit))")
                return (apiResponse.friends, apiResponse.capacity)
            } catch let decodingError as DecodingError {
                // Log detailed decoding error info
                switch decodingError {
                case .keyNotFound(let key, let context):
                    logger.error("Decoding error - key not found: '\(key.stringValue)' at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                case .typeMismatch(let type, let context):
                    logger.error("Decoding error - type mismatch: expected \(type) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                case .valueNotFound(let type, let context):
                    logger.error("Decoding error - value not found: \(type) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                case .dataCorrupted(let context):
                    logger.error("Decoding error - data corrupted at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                @unknown default:
                    logger.error("Decoding error - unknown: \(decodingError)")
                }
                // Also log raw response for debugging
                if let rawString = String(data: data, encoding: .utf8) {
                    logger.error("Raw response (first 500 chars): \(String(rawString.prefix(500)))")
                }
                throw SharingServiceError.decodingError(underlying: decodingError)
            } catch {
                logger.error("Failed to decode friends response: \(error)")
                throw SharingServiceError.decodingError(underlying: error)
            }

        } catch let error as SharingServiceError {
            logger.error("SharingServiceError in fetchAllFriends: \(error.localizedDescription)")
            throw error
        } catch {
            logger.error("Unexpected error in fetchAllFriends: \(error.localizedDescription)")
            throw SharingServiceError.networkError(underlying: error)
        }
    }

    // MARK: - Share Management Actions

    /// Action types for the manage endpoint
    enum ManageAction: String, Encodable {
        case createShare
        case removeShare
        case removeSharer
        case toggleEarnings
        case blockSharer
        case unblockSharer
        case shareBack
        case toggleMuted
    }

    /// Generic method to call the /api/sharing/manage endpoint
    private func performManageAction(
        action: ManageAction,
        identifier: String? = nil,
        recipientId: String? = nil,
        ownerId: String? = nil,
        showEarnings: Bool? = nil,
        muted: Bool? = nil
    ) async throws {
        let session = try await supabase.auth.session
        let accessToken = session.accessToken

        let url = APIConfiguration.webAppBaseURL.appendingPathComponent("/api/sharing/manage")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Build request body
        var body: [String: Any] = ["action": action.rawValue]
        if let identifier = identifier { body["identifier"] = identifier }
        if let recipientId = recipientId { body["recipientId"] = recipientId }
        if let ownerId = ownerId { body["ownerId"] = ownerId }
        if let showEarnings = showEarnings { body["showEarnings"] = showEarnings }
        if let muted = muted { body["muted"] = muted }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        logger.info("Performing manage action: \(action.rawValue)")

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SharingServiceError.networkError(underlying: URLError(.badServerResponse))
        }

        // Decode response to check for errors
        let decoder = JSONDecoder()
        let result = try decoder.decode(ManageActionResponse.self, from: data)

        if !result.success {
            let errorMessage = result.error ?? "Unknown error"
            logger.error("Manage action failed: \(errorMessage)")
            throw SharingServiceError.httpError(statusCode: httpResponse.statusCode, message: errorMessage)
        }

        logger.info("Manage action \(action.rawValue) succeeded")
    }

    /// Create a new share by email or phone
    /// Requires API for user lookup, limit checks, and notifications
    func createShare(identifier: String, showEarnings: Bool = false) async throws {
        try await performManageAction(
            action: .createShare,
            identifier: identifier,
            showEarnings: showEarnings
        )
    }

    /// Remove a share (revoke recipient's access to my shifts)
    /// Owner can delete directly via Supabase (RLS allows this)
    func removeShare(recipientId: String) async throws {
        let session = try await supabase.auth.session
        let userId = session.normalizedUserId

        logger.info("Removing share for recipient \(recipientId)")

        try await supabase
            .from("shift_shares")
            .delete()
            .eq("owner_id", value: userId)
            .eq("viewer_id", value: recipientId)
            .execute()

        logger.info("Successfully removed share")
    }

    /// Remove a sharer from my friends list (as the viewer)
    /// Viewer can delete directly via Supabase (RLS allows this)
    func removeSharer(ownerId: String) async throws {
        let session = try await supabase.auth.session
        let userId = session.normalizedUserId

        logger.info("Removing sharer \(ownerId) from friends list")

        try await supabase
            .from("shift_shares")
            .delete()
            .eq("owner_id", value: ownerId)
            .eq("viewer_id", value: userId)
            .execute()

        logger.info("Successfully removed sharer")
    }

    /// Toggle earnings visibility for a share recipient
    /// Owner can update show_earnings directly via Supabase (RLS allows this)
    func toggleShareEarnings(recipientId: String, showEarnings: Bool) async throws {
        let session = try await supabase.auth.session
        let userId = session.normalizedUserId

        logger.info("Toggling earnings visibility for recipient \(recipientId) to \(showEarnings)")

        try await supabase
            .from("shift_shares")
            .update(["show_earnings": showEarnings])
            .eq("owner_id", value: userId)
            .eq("viewer_id", value: recipientId)
            .execute()

        logger.info("Successfully toggled earnings visibility")
    }

    /// Block a sharer (hide their shifts from my list)
    /// Viewer can update blocked directly via Supabase (RLS allows this)
    func blockSharer(ownerId: String) async throws {
        let session = try await supabase.auth.session
        let userId = session.normalizedUserId

        logger.info("Blocking sharer \(ownerId)")

        try await supabase
            .from("shift_shares")
            .update(["blocked": true])
            .eq("owner_id", value: ownerId)
            .eq("viewer_id", value: userId)
            .execute()

        logger.info("Successfully blocked sharer")
    }

    /// Unblock a sharer (restore their shifts to my list)
    /// Viewer can update blocked directly via Supabase (RLS allows this)
    func unblockSharer(ownerId: String) async throws {
        let session = try await supabase.auth.session
        let userId = session.normalizedUserId

        logger.info("Unblocking sharer \(ownerId)")

        try await supabase
            .from("shift_shares")
            .update(["blocked": false])
            .eq("owner_id", value: ownerId)
            .eq("viewer_id", value: userId)
            .execute()

        logger.info("Successfully unblocked sharer")
    }

    /// Share back with someone who has shared with me
    /// Requires API for limit checks and notifications
    func shareBack(recipientId: String) async throws {
        try await performManageAction(
            action: .shareBack,
            recipientId: recipientId
        )
    }

    /// Toggle muted status for a specific sharer
    /// Viewer can update muted directly via Supabase (RLS allows this)
    func toggleSharerMuted(ownerId: String, muted: Bool) async throws {
        let session = try await supabase.auth.session
        let userId = session.normalizedUserId

        logger.info("Toggling muted status for sharer \(ownerId) to \(muted)")

        try await supabase
            .from("shift_shares")
            .update(["muted": muted])
            .eq("owner_id", value: ownerId)
            .eq("viewer_id", value: userId)
            .execute()

        logger.info("Successfully toggled muted status")
    }
}
