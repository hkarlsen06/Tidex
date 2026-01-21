import Foundation
import Supabase
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "AdminSettingsViewModel")

/// Superadmin user ID - only this user can grant/revoke admin privileges
private let SUPERADMIN_USER_ID = "032d8c2a-9af6-4777-99f0-24e2c4058bf3"

// MARK: - Admin Tab

enum AdminTab: String, CaseIterable, Identifiable {
    case notifications
    case users
    case subscribers
    case feedback
    case auditLog
    case sql
    case shares

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notifications: return "Notifications"
        case .users: return "Users"
        case .subscribers: return "Subscribers"
        case .feedback: return "Feedback"
        case .auditLog: return "Audit Log"
        case .sql: return "SQL"
        case .shares: return "Shares"
        }
    }

    var icon: String {
        switch self {
        case .notifications: return "bell"
        case .users: return "person.2"
        case .subscribers: return "creditcard"
        case .feedback: return "bubble.left.and.bubble.right"
        case .auditLog: return "list.bullet.clipboard"
        case .sql: return "terminal"
        case .shares: return "square.and.arrow.up"
        }
    }
}

// MARK: - Models

/// A user item from the admin API
struct AdminUserItem: Codable, Identifiable {
    let id: String
    let email: String?
    let phone: String?
    let name: String?
    let lastSignInAt: String?
    let createdAt: String
    let isBanned: Bool
    let bannedUntil: String?
    let isAdmin: Bool
    let isSuperAdmin: Bool
    let isGrandfathered: Bool
    let plan: String
}

struct AdminUsersResponse: Codable {
    let users: [AdminUserItem]
    let totalCount: Int
    let page: Int
    let perPage: Int
    let resultsArePartial: Bool
}

/// Subscriber data
struct SubscriberItem: Codable, Identifiable {
    var id: String { userId }
    let userId: String
    let email: String?
    let phone: String?
    let name: String?
    let provider: String?
    let productId: String?
    let priceId: String?
    let status: String?
    let currentPeriodEnd: String?
    let isGrandfathered: Bool
    let plan: String
}

struct SubscribersResponse: Codable {
    let success: Bool
    let subscribers: [SubscriberItem]?
    let message: String?
}

/// Feedback item for admin view
struct AdminFeedbackItem: Codable, Identifiable {
    let id: String
    let userId: String
    let message: String
    let userEmail: String
    let userName: String?
    let userProfilePicture: String?
    let createdAt: String
    let response: String?
    let respondedAt: String?
    let respondedBy: String?
}

struct AdminFeedbackResponse: Codable {
    let feedback: [AdminFeedbackItem]
    let total: Int
}

/// Audit log entry
struct AuditLogEntry: Codable, Identifiable {
    let id: String
    let adminId: String?
    let adminEmail: String?
    let action: String
    let targetUserId: String?
    let targetEmail: String?
    let metadata: [String: AnyCodable]?
    let createdAt: String
}

struct AuditLogResponse: Codable {
    let success: Bool
    let entries: [AuditLogEntry]?
    let message: String?
}

/// SQL result
struct SqlResponse: Codable {
    let success: Bool
    let data: [[String: AnyCodable]]?
    let rowCount: Int?
    let executionTimeMs: Int?
    let message: String?
}

/// Shift share item
struct ShiftShareItem: Codable, Identifiable {
    let id: String
    let ownerId: String
    let ownerEmail: String?
    let ownerName: String?
    let ownerPhone: String?
    let viewerId: String
    let viewerEmail: String?
    let viewerName: String?
    let viewerPhone: String?
    let createdAt: String
    let showEarnings: Bool
    let blocked: Bool
    let muted: Bool
}

struct SharesResponse: Codable {
    let success: Bool
    let shares: [ShiftShareItem]?
    let totalCount: Int?
    let page: Int?
    let pageSize: Int?
    let message: String?
}

/// Broadcast record
struct BroadcastRecord: Codable, Identifiable {
    let id: String
    let title: String
    let body: String
    let target: String
    let targetCount: Int
    let status: String
    let createdAt: String
    let sentCount: Int
    let failedCount: Int
    let skippedCount: Int
    let pendingCount: Int
}

struct BroadcastHistoryResponse: Codable {
    let broadcasts: [BroadcastRecord]
}

struct PreviewCountResponse: Codable {
    let count: Int
}

/// Generic action response
struct AdminActionResponse: Codable {
    let success: Bool
    let message: String?
    let error: String?
}

/// AnyCodable for handling dynamic JSON
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else if container.decodeNil() {
            value = NSNull()
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let bool as Bool:
            try container.encode(bool)
        case let string as String:
            try container.encode(string)
        case is NSNull:
            try container.encodeNil()
        default:
            try container.encodeNil()
        }
    }

    var stringValue: String {
        switch value {
        case let s as String: return s
        case let i as Int: return String(i)
        case let d as Double: return String(d)
        case let b as Bool: return b ? "true" : "false"
        default: return "null"
        }
    }
}

// MARK: - View Model

@MainActor
final class AdminSettingsViewModel: ObservableObject {

    // MARK: - Common State

    @Published var selectedTab: AdminTab = .users
    @Published var isSuperAdmin: Bool = false
    @Published var errorMessage: String?
    @Published var successMessage: String?
    @Published var isPerformingAction: Bool = false

    // MARK: - Users Tab State

    @Published var users: [AdminUserItem] = []
    @Published var usersSearchQuery: String = ""
    @Published var usersIsLoading: Bool = false
    @Published var usersCurrentPage: Int = 1
    @Published var usersTotalCount: Int = 0
    @Published var usersHasMore: Bool = false
    @Published var selectedUser: AdminUserItem?

    // MARK: - Subscribers Tab State

    @Published var subscribers: [SubscriberItem] = []
    @Published var subscribersFilter: String = "all"
    @Published var subscribersIsLoading: Bool = false

    // MARK: - Feedback Tab State

    @Published var feedbackItems: [AdminFeedbackItem] = []
    @Published var feedbackIsLoading: Bool = false
    @Published var feedbackTotal: Int = 0
    @Published var selectedFeedback: AdminFeedbackItem?
    @Published var feedbackResponse: String = ""

    // MARK: - Audit Log Tab State

    @Published var auditLogEntries: [AuditLogEntry] = []
    @Published var auditLogIsLoading: Bool = false

    // MARK: - SQL Tab State

    @Published var sqlQuery: String = ""
    @Published var sqlResult: [[String: AnyCodable]]?
    @Published var sqlRowCount: Int = 0
    @Published var sqlExecutionTime: Int = 0
    @Published var sqlIsExecuting: Bool = false
    @Published var sqlError: String?

    // MARK: - Shares Tab State

    @Published var shares: [ShiftShareItem] = []
    @Published var sharesSearchQuery: String = ""
    @Published var sharesIsLoading: Bool = false
    @Published var sharesTotalCount: Int = 0

    // MARK: - Notifications Tab State

    @Published var broadcastHistory: [BroadcastRecord] = []
    @Published var notificationsIsLoading: Bool = false
    @Published var notificationTitle: String = ""
    @Published var notificationBody: String = ""
    @Published var notificationTarget: String = "all"
    @Published var notificationDeeplink: String = ""
    @Published var previewCount: Int = 0
    @Published var isSendingNotification: Bool = false

    // Specific user targeting
    @Published var notificationUserSearch: String = ""
    @Published var notificationUserSearchResults: [AdminUserItem] = []
    @Published var notificationSelectedUsers: [AdminUserItem] = []
    @Published var isSearchingNotificationUsers: Bool = false

    // MARK: - Private Properties

    private let urlSession: URLSession
    private var searchTask: Task<Void, Never>?
    private let perPage = 20

    // MARK: - Initialization

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        self.urlSession = URLSession(configuration: config)
    }

    // MARK: - Common Methods

    func loadInitialData() async {
        do {
            let session = try await supabase.auth.session
            isSuperAdmin = session.normalizedUserId == SUPERADMIN_USER_ID
        } catch {
            logger.error("Failed to check superadmin status: \(error.localizedDescription)")
        }

        await loadDataForTab(selectedTab)
    }

    func loadDataForTab(_ tab: AdminTab) async {
        switch tab {
        case .users:
            await fetchUsers(page: 1, search: nil)
        case .subscribers:
            await fetchSubscribers()
        case .feedback:
            await fetchFeedback()
        case .auditLog:
            await fetchAuditLog()
        case .sql:
            break // No initial load needed
        case .shares:
            await fetchShares()
        case .notifications:
            await fetchBroadcastHistory()
        }
    }

    func clearMessages() {
        errorMessage = nil
        successMessage = nil
        sqlError = nil
    }

    // MARK: - Users Tab Methods

    func searchUsers() {
        searchTask?.cancel()
        let query = usersSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await fetchUsers(page: 1, search: query.isEmpty ? nil : query)
        }
    }

    func loadMoreUsers() async {
        guard usersHasMore && !usersIsLoading else { return }
        let query = usersSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        await fetchUsers(page: usersCurrentPage + 1, search: query.isEmpty ? nil : query, append: true)
    }

    private func fetchUsers(page: Int, search: String?, append: Bool = false) async {
        if !append { usersIsLoading = true }

        do {
            var components = URLComponents(url: APIConfiguration.webAppBaseURL.appendingPathComponent("/api/admin/users"), resolvingAgainstBaseURL: false)!
            var queryItems = [URLQueryItem(name: "page", value: String(page)), URLQueryItem(name: "perPage", value: String(perPage))]
            if let search = search { queryItems.append(URLQueryItem(name: "search", value: search)) }
            components.queryItems = queryItems

            let result: AdminUsersResponse = try await makeRequest(url: components.url!, method: "GET")

            if append {
                users.append(contentsOf: result.users)
            } else {
                users = result.users
            }
            usersCurrentPage = result.page
            usersTotalCount = result.totalCount
            usersHasMore = result.users.count == perPage
        } catch {
            logger.error("Failed to fetch users: \(error.localizedDescription)")
            if !append { errorMessage = "Failed to load users" }
        }

        usersIsLoading = false
    }

    func toggleBan(user: AdminUserItem) async {
        await performUserAction(endpoint: "/api/admin/users/ban", body: ["targetUserId": user.id, "targetEmail": user.email ?? "", "ban": !user.isBanned])
    }

    func toggleAdmin(user: AdminUserItem) async {
        guard isSuperAdmin else { return }
        await performUserAction(endpoint: "/api/admin/users/admin", body: ["targetUserId": user.id, "targetEmail": user.email ?? "", "grant": !user.isAdmin])
    }

    func toggleGrandfathered(user: AdminUserItem) async {
        await performUserAction(endpoint: "/api/admin/users/grandfathered", body: ["targetUserId": user.id, "targetEmail": user.email ?? "", "grant": !user.isGrandfathered])
    }

    func toggleTrial(user: AdminUserItem, create: Bool, days: Int = 7) async {
        await performUserAction(endpoint: "/api/admin/users/trial", body: ["targetUserId": user.id, "targetEmail": user.email ?? "", "action": create ? "create" : "revoke", "durationDays": days])
    }

    private func performUserAction(endpoint: String, body: [String: Any]) async {
        guard !isPerformingAction else { return }
        isPerformingAction = true
        clearMessages()

        do {
            let response: AdminActionResponse = try await makeRequest(url: APIConfiguration.webAppBaseURL.appendingPathComponent(endpoint), method: "POST", body: body)
            if response.success {
                successMessage = response.message ?? "Action completed"
                await fetchUsers(page: usersCurrentPage, search: usersSearchQuery.isEmpty ? nil : usersSearchQuery)
            } else {
                errorMessage = response.error ?? response.message ?? "Action failed"
            }
        } catch {
            errorMessage = "Failed to perform action"
        }

        isPerformingAction = false
    }

    // MARK: - Subscribers Tab Methods

    func fetchSubscribers() async {
        subscribersIsLoading = true

        do {
            var components = URLComponents(url: APIConfiguration.webAppBaseURL.appendingPathComponent("/api/admin/subscribers"), resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "filter", value: subscribersFilter)]

            let result: SubscribersResponse = try await makeRequest(url: components.url!, method: "GET")
            subscribers = result.subscribers ?? []
        } catch {
            logger.error("Failed to fetch subscribers: \(error.localizedDescription)")
            errorMessage = "Failed to load subscribers"
        }

        subscribersIsLoading = false
    }

    // MARK: - Feedback Tab Methods

    func fetchFeedback() async {
        feedbackIsLoading = true

        do {
            let url = APIConfiguration.webAppBaseURL.appendingPathComponent("/api/admin/feedback")
            let result: AdminFeedbackResponse = try await makeRequest(url: url, method: "GET")
            feedbackItems = result.feedback
            feedbackTotal = result.total
        } catch {
            logger.error("Failed to fetch feedback: \(error.localizedDescription)")
            errorMessage = "Failed to load feedback"
        }

        feedbackIsLoading = false
    }

    func respondToFeedback(_ feedbackId: String, response: String) async {
        guard !isPerformingAction else { return }
        isPerformingAction = true
        clearMessages()

        do {
            let result: AdminActionResponse = try await makeRequest(
                url: APIConfiguration.webAppBaseURL.appendingPathComponent("/api/admin/feedback/respond"),
                method: "POST",
                body: ["feedbackId": feedbackId, "response": response]
            )
            if result.success {
                successMessage = "Response sent"
                selectedFeedback = nil
                feedbackResponse = ""
                await fetchFeedback()
            } else {
                errorMessage = result.message ?? "Failed to send response"
            }
        } catch {
            errorMessage = "Failed to send response"
        }

        isPerformingAction = false
    }

    // MARK: - Audit Log Tab Methods

    func fetchAuditLog() async {
        auditLogIsLoading = true

        do {
            let url = APIConfiguration.webAppBaseURL.appendingPathComponent("/api/admin/audit-log")
            let result: AuditLogResponse = try await makeRequest(url: url, method: "GET")
            auditLogEntries = result.entries ?? []
        } catch {
            logger.error("Failed to fetch audit log: \(error.localizedDescription)")
            errorMessage = "Failed to load audit log"
        }

        auditLogIsLoading = false
    }

    // MARK: - SQL Tab Methods

    func executeSql() async {
        guard !sqlQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            sqlError = "Query cannot be empty"
            return
        }

        sqlIsExecuting = true
        sqlError = nil
        sqlResult = nil

        do {
            let result: SqlResponse = try await makeRequest(
                url: APIConfiguration.webAppBaseURL.appendingPathComponent("/api/admin/sql"),
                method: "POST",
                body: ["query": sqlQuery]
            )

            if result.success {
                sqlResult = result.data
                sqlRowCount = result.rowCount ?? 0
                sqlExecutionTime = result.executionTimeMs ?? 0
            } else {
                sqlError = result.message ?? "Query failed"
            }
        } catch {
            sqlError = "Failed to execute query"
        }

        sqlIsExecuting = false
    }

    // MARK: - Shares Tab Methods

    func fetchShares() async {
        sharesIsLoading = true

        do {
            var components = URLComponents(url: APIConfiguration.webAppBaseURL.appendingPathComponent("/api/admin/shares"), resolvingAgainstBaseURL: false)!
            var queryItems: [URLQueryItem] = []
            if !sharesSearchQuery.isEmpty {
                queryItems.append(URLQueryItem(name: "search", value: sharesSearchQuery))
            }
            components.queryItems = queryItems.isEmpty ? nil : queryItems

            let result: SharesResponse = try await makeRequest(url: components.url!, method: "GET")
            shares = result.shares ?? []
            sharesTotalCount = result.totalCount ?? 0
        } catch {
            logger.error("Failed to fetch shares: \(error.localizedDescription)")
            errorMessage = "Failed to load shares"
        }

        sharesIsLoading = false
    }

    func searchShares() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await fetchShares()
        }
    }

    func deleteShare(_ shareId: String) async {
        guard !isPerformingAction else { return }
        isPerformingAction = true
        clearMessages()

        do {
            let result: AdminActionResponse = try await makeRequest(
                url: APIConfiguration.webAppBaseURL.appendingPathComponent("/api/admin/shares/\(shareId)"),
                method: "DELETE"
            )
            if result.success {
                successMessage = "Share deleted"
                await fetchShares()
            } else {
                errorMessage = result.message ?? "Failed to delete share"
            }
        } catch {
            errorMessage = "Failed to delete share"
        }

        isPerformingAction = false
    }

    // MARK: - Notifications Tab Methods

    func fetchBroadcastHistory() async {
        notificationsIsLoading = true

        do {
            let url = APIConfiguration.webAppBaseURL.appendingPathComponent("/api/admin/notifications/history")
            let result: BroadcastHistoryResponse = try await makeRequest(url: url, method: "GET")
            broadcastHistory = result.broadcasts
        } catch {
            logger.error("Failed to fetch broadcast history: \(error.localizedDescription)")
            errorMessage = "Failed to load notification history"
        }

        notificationsIsLoading = false
    }

    func previewNotificationCount() async {
        // For specific target, count is the selected users count
        if notificationTarget == "specific" {
            previewCount = notificationSelectedUsers.count
            return
        }

        do {
            let result: PreviewCountResponse = try await makeRequest(
                url: APIConfiguration.webAppBaseURL.appendingPathComponent("/api/admin/notifications/preview"),
                method: "POST",
                body: ["target": notificationTarget, "includeSelf": false]
            )
            previewCount = result.count
        } catch {
            previewCount = 0
        }
    }

    func searchNotificationUsers() {
        let query = notificationUserSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            notificationUserSearchResults = []
            return
        }

        Task {
            isSearchingNotificationUsers = true
            do {
                let url = APIConfiguration.webAppBaseURL.appendingPathComponent("/api/admin/users")
                var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
                components.queryItems = [
                    URLQueryItem(name: "search", value: query),
                    URLQueryItem(name: "limit", value: "10")
                ]

                let result: AdminUsersResponse = try await makeRequest(url: components.url!, method: "GET")
                // Filter out already selected users
                let selectedIds = Set(notificationSelectedUsers.map { $0.id })
                notificationUserSearchResults = result.users.filter { !selectedIds.contains($0.id) }
            } catch {
                notificationUserSearchResults = []
            }
            isSearchingNotificationUsers = false
        }
    }

    func selectNotificationUser(_ user: AdminUserItem) {
        guard !notificationSelectedUsers.contains(where: { $0.id == user.id }) else { return }
        notificationSelectedUsers.append(user)
        notificationUserSearchResults.removeAll { $0.id == user.id }
        notificationUserSearch = ""
        previewCount = notificationSelectedUsers.count
    }

    func deselectNotificationUser(_ user: AdminUserItem) {
        notificationSelectedUsers.removeAll { $0.id == user.id }
        previewCount = notificationSelectedUsers.count
    }

    func sendNotification() async {
        guard !notificationTitle.isEmpty && !notificationBody.isEmpty else {
            errorMessage = "Title and body are required"
            return
        }

        // For specific target, require at least one selected user
        if notificationTarget == "specific" && notificationSelectedUsers.isEmpty {
            errorMessage = "Please select at least one user"
            return
        }

        isSendingNotification = true
        clearMessages()

        do {
            var body: [String: Any] = [
                "title": notificationTitle,
                "body": notificationBody,
                "target": notificationTarget,
                "includeSelf": false
            ]
            if !notificationDeeplink.isEmpty {
                body["deeplink"] = notificationDeeplink
            }
            if notificationTarget == "specific" {
                body["specificUserIds"] = notificationSelectedUsers.map { $0.id }
            }

            let result: AdminActionResponse = try await makeRequest(
                url: APIConfiguration.webAppBaseURL.appendingPathComponent("/api/admin/notifications/send"),
                method: "POST",
                body: body
            )

            if result.success {
                successMessage = result.message ?? "Notification sent"
                notificationTitle = ""
                notificationBody = ""
                notificationDeeplink = ""
                notificationSelectedUsers = []
                notificationUserSearch = ""
                notificationUserSearchResults = []
                previewCount = 0
                await fetchBroadcastHistory()
            } else {
                errorMessage = result.message ?? "Failed to send notification"
            }
        } catch {
            errorMessage = "Failed to send notification"
        }

        isSendingNotification = false
    }

    // MARK: - Network Helper

    private func makeRequest<T: Decodable>(url: URL, method: String, body: [String: Any]? = nil) async throws -> T {
        let session = try await supabase.auth.session

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let body = body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AdminError.networkError
        }

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 { throw AdminError.unauthorized }
            if httpResponse.statusCode == 403 { throw AdminError.forbidden }
            throw AdminError.serverError(code: httpResponse.statusCode, message: String(data: data, encoding: .utf8) ?? "Unknown error")
        }

        return try JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - Errors

enum AdminError: LocalizedError {
    case invalidURL, networkError, unauthorized, forbidden
    case serverError(code: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .networkError: return "Network error"
        case .unauthorized: return "Not authenticated"
        case .forbidden: return "Access denied"
        case .serverError(let code, let message): return "Error (\(code)): \(message)"
        }
    }
}

// MARK: - Extensions

extension AdminUserItem {
    var displayName: String {
        name ?? email ?? phone ?? String(id.prefix(8)) + "..."
    }

    var planDisplayName: String {
        switch plan {
        case "max": return "Max"
        case "pro": return "Pro"
        case "trial": return "Trial"
        default: return "Free"
        }
    }
}

extension SubscriberItem {
    var displayName: String {
        name ?? email ?? phone ?? String(userId.prefix(8)) + "..."
    }

    var planDisplayName: String {
        switch plan {
        case "max": return "Max"
        case "pro": return "Pro"
        case "trial": return "Trial"
        default: return "Free"
        }
    }
}
