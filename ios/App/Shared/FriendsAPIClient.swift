import Foundation

// MARK: - Shift Status (local definition to avoid cross-target dependencies)

/// Status of a shift preview
/// Note: This mirrors FriendShiftStatus from the main Shared folder
/// but is defined locally to avoid cross-target compilation issues
enum FriendShiftStatus: String, Codable, Sendable {
    case active
    case upcoming
    case past
}

// MARK: - API Response Types

/// Response from /api/sharing/sharers endpoint
struct SharersResponse: Codable, Sendable {
    let sharers: [SharerData]

    struct SharerData: Codable, Sendable {
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
/// Matches the format returned by the iOS app's SharingService
struct PreviewsResponse: Codable, Sendable {
    let previews: [PreviewData]

    struct PreviewData: Codable, Sendable {
        let sharerId: String
        let shift: ShiftData?
        let status: String?
        let showEarnings: Bool
    }

    /// Shift data matching the API's ShiftWithComputations format
    /// Only decodes the fields we need for the Watch/Widget
    struct ShiftData: Codable, Sendable {
        let id: String
        let shift_date: String
        let start_time: String
        let end_time: String
        let computed: ComputedData

        /// Computed payroll data - only extract what we need
        struct ComputedData: Codable, Sendable {
            let gross: Double
        }

        /// Convenience accessor for gross
        var gross: Double { computed.gross }
    }
}

// MARK: - Combined Friends Data

/// Combined data for a friend with their shift preview
/// Used by widget and watch for display
struct FriendWithShift: Sendable {
    let id: String
    let displayName: String
    let initials: String
    let profilePictureUrl: String?
    let oauthAvatarUrl: String?
    let showEarnings: Bool
    let blocked: Bool

    // Shift data (if available)
    let shiftId: String?
    let shiftDate: String?
    let startTime: String?
    let endTime: String?
    let gross: Double?
    let status: FriendShiftStatus?

    /// Whether this friend has a shift to display
    var hasShift: Bool {
        shiftId != nil
    }

    /// Effective avatar URL (profile picture takes precedence)
    var effectiveAvatarURL: URL? {
        if let urlString = profilePictureUrl ?? oauthAvatarUrl,
           !urlString.isEmpty {
            return URL(string: urlString)
        }
        return nil
    }
}

// MARK: - Errors

enum FriendsAPIError: Error, LocalizedError, Sendable {
    case noAccessToken
    case networkError(underlying: String)
    case httpError(statusCode: Int)
    case decodingError(underlying: String)
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .noAccessToken:
            return "No access token available"
        case .networkError(let message):
            return "Network error: \(message)"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .decodingError(let message):
            return "Decoding error: \(message)"
        case .unauthorized:
            return "Unauthorized - token may be expired"
        }
    }
}

// MARK: - Friends API Client

/// Lightweight API client for fetching friends data directly
/// Used by widget and watch to bypass the main app's data flow
enum FriendsAPIClient {
    /// Base URL for the API
    private static let baseURL = URL(string: "https://app.tidex.no")!

    /// Shared URLSession with reasonable timeouts
    private static let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    // MARK: - Public API

    /// Fetch all friends with their shift previews in a single call
    /// This is the main entry point for widget and watch
    /// - Returns: Array of friends with their shift data
    static func fetchFriendsWithShifts() async throws -> [FriendWithShift] {
        // Get the access token from shared keychain
        guard let accessToken = SharedKeychainStorage.getValidAccessToken() else {
            throw FriendsAPIError.noAccessToken
        }

        // Fetch sharers first
        let sharers = try await fetchSharers(accessToken: accessToken)

        // Filter out blocked sharers
        let activeSharers = sharers.filter { !$0.blocked }

        guard !activeSharers.isEmpty else {
            return []
        }

        // Fetch shift previews for all active sharers
        let sharerIds = activeSharers.map { $0.id }
        let previews = try await fetchPreviews(sharerIds: sharerIds, accessToken: accessToken)

        // Build a lookup map for previews
        var previewMap: [String: PreviewsResponse.PreviewData] = [:]
        for preview in previews {
            previewMap[preview.sharerId] = preview
        }

        // Combine sharers with their previews
        let results = activeSharers.map { sharer in
            let preview = previewMap[sharer.id]
            let status = preview?.status.flatMap { FriendShiftStatus(rawValue: $0) }

            return FriendWithShift(
                id: sharer.id,
                displayName: sharer.firstName ?? sharer.email?.components(separatedBy: "@").first ?? "Unknown",
                initials: makeInitials(from: sharer.firstName ?? sharer.email?.components(separatedBy: "@").first ?? "?"),
                profilePictureUrl: sharer.profilePictureUrl,
                oauthAvatarUrl: sharer.oauthAvatarUrl,
                showEarnings: preview?.showEarnings ?? sharer.showEarnings,
                blocked: sharer.blocked,
                shiftId: preview?.shift?.id,
                shiftDate: preview?.shift?.shift_date,
                startTime: preview?.shift?.start_time,
                endTime: preview?.shift?.end_time,
                gross: preview?.shift?.gross,
                status: status
            )
        }

        // Sort by shift proximity: active first, then upcoming (soonest), then past (most recent), then no shifts
        return results.sorted { a, b in
            let priorityOrder: [FriendShiftStatus?] = [.active, .upcoming, .past, nil]
            let aPriority = priorityOrder.firstIndex(where: { $0 == a.status }) ?? 4
            let bPriority = priorityOrder.firstIndex(where: { $0 == b.status }) ?? 4

            if aPriority != bPriority {
                return aPriority < bPriority
            }

            // Same status - sort by date
            guard let aDate = a.shiftDate, let bDate = b.shiftDate else {
                return a.shiftDate != nil // Put shifts before no-shifts
            }

            if a.status == .upcoming {
                return aDate < bDate // Upcoming: soonest first
            } else if a.status == .past {
                return aDate > bDate // Past: most recent first
            }

            return false
        }
    }

    // MARK: - Private API Methods

    private static func fetchSharers(accessToken: String) async throws -> [SharersResponse.SharerData] {
        let url = baseURL.appendingPathComponent("api/sharing/sharers")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw FriendsAPIError.networkError(underlying: "Invalid response type")
            }

            switch httpResponse.statusCode {
            case 200:
                break
            case 401:
                throw FriendsAPIError.unauthorized
            default:
                throw FriendsAPIError.httpError(statusCode: httpResponse.statusCode)
            }

            let decoder = JSONDecoder()
            let result = try decoder.decode(SharersResponse.self, from: data)
            return result.sharers

        } catch let error as FriendsAPIError {
            throw error
        } catch let decodingError as DecodingError {
            throw FriendsAPIError.decodingError(underlying: decodingError.localizedDescription)
        } catch {
            throw FriendsAPIError.networkError(underlying: error.localizedDescription)
        }
    }

    private static func fetchPreviews(sharerIds: [String], accessToken: String) async throws -> [PreviewsResponse.PreviewData] {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/sharing/previews"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "sharerIds", value: sharerIds.joined(separator: ","))
        ]

        guard let url = components.url else {
            throw FriendsAPIError.networkError(underlying: "Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw FriendsAPIError.networkError(underlying: "Invalid response type")
            }

            switch httpResponse.statusCode {
            case 200:
                break
            case 401:
                throw FriendsAPIError.unauthorized
            default:
                throw FriendsAPIError.httpError(statusCode: httpResponse.statusCode)
            }

            let decoder = JSONDecoder()
            let result = try decoder.decode(PreviewsResponse.self, from: data)
            return result.previews

        } catch let error as FriendsAPIError {
            throw error
        } catch let decodingError as DecodingError {
            throw FriendsAPIError.decodingError(underlying: decodingError.localizedDescription)
        } catch {
            throw FriendsAPIError.networkError(underlying: error.localizedDescription)
        }
    }

    // MARK: - Helpers

    private static func makeInitials(from name: String) -> String {
        let words = name.split(separator: " ")
        if words.count >= 2 {
            let first = words[0].prefix(1).uppercased()
            let second = words[1].prefix(1).uppercased()
            return first + second
        }
        return String(name.prefix(2).uppercased())
    }
}
