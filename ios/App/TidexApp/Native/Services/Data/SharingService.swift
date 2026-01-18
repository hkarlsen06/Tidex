import Foundation
import Supabase
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

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.urlSession = URLSession(configuration: config)
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
    func fetchShiftPreviews(sharerIds: [String]) async throws -> [SharerShiftPreview] {
        guard !sharerIds.isEmpty else { return [] }

        do {
            // Get the current session token
            let session = try await supabase.auth.session
            let accessToken = session.accessToken

            // Build URL
            var components = URLComponents(
                url: APIConfiguration.webAppBaseURL.appendingPathComponent("/api/sharing/previews"),
                resolvingAgainstBaseURL: false
            )!
            components.queryItems = [
                URLQueryItem(name: "sharerIds", value: sharerIds.joined(separator: ","))
            ]

            guard let url = components.url else {
                throw SharingServiceError.networkError(underlying: URLError(.badURL))
            }

            // Build request with auth header
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            logger.info("Fetching shift previews from \(url.absoluteString)")

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
                let previews = apiResponse.previews.map { preview in
                    SharerShiftPreview(
                        sharerId: preview.sharerId,
                        shift: preview.shift,
                        status: preview.status.flatMap { ShiftPreviewStatus(rawValue: $0) },
                        showEarnings: preview.showEarnings
                    )
                }
                logger.info("Loaded \(previews.count) shift previews")
                return previews
            } catch {
                logger.error("Failed to decode shift previews: \(error)")
                throw SharingServiceError.decodingError(underlying: error)
            }

        } catch let error as SharingServiceError {
            throw error
        } catch {
            throw SharingServiceError.networkError(underlying: error)
        }
    }
}
