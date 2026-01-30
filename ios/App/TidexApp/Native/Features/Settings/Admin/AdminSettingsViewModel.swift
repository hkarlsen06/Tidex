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
    case feedback
    case auditLog
    case sql
    case shares
    case impersonation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notifications: return "Notifications"
        case .users: return "Users"
        case .feedback: return "Feedback"
        case .auditLog: return "Audit Log"
        case .sql: return "SQL"
        case .shares: return "Shares"
        case .impersonation: return "Impersonate"
        }
    }

    var icon: String {
        switch self {
        case .notifications: return "bell"
        case .users: return "person.2"
        case .feedback: return "bubble.left.and.bubble.right"
        case .auditLog: return "list.bullet.clipboard"
        case .sql: return "terminal"
        case .shares: return "square.and.arrow.up"
        case .impersonation: return "person.crop.circle.badge.exclamationmark"
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
    let id: String?  // Returned when creating resources
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

// MARK: - State Structs

/// Groups related users tab state to reduce unnecessary re-renders
struct UsersTabState {
    var items: [AdminUserItem] = []
    var searchQuery: String = ""
    var isLoading: Bool = false
    var currentPage: Int = 1
    var totalCount: Int = 0
    var hasMore: Bool = false
    var selected: AdminUserItem?
}

/// Groups related feedback tab state
struct FeedbackTabState {
    var items: [AdminFeedbackItem] = []
    var isLoading: Bool = false
    var total: Int = 0
    var selected: AdminFeedbackItem?
    var responseText: String = ""
}

/// Groups related audit log tab state
struct AuditLogTabState {
    var entries: [AuditLogEntry] = []
    var isLoading: Bool = false
}

/// Groups related SQL tab state
struct SqlTabState {
    var query: String = ""
    var result: [[String: AnyCodable]]?
    var rowCount: Int = 0
    var executionTime: Int = 0
    var isExecuting: Bool = false
    var error: String?
}

/// Groups related shares tab state
struct SharesTabState {
    var items: [ShiftShareItem] = []
    var searchQuery: String = ""
    var isLoading: Bool = false
    var totalCount: Int = 0
    var isShowingCreate: Bool = false
    var showEarnings: Bool = true
    var isCreating: Bool = false
    // Owner search
    var ownerSearch: String = ""
    var ownerResults: [AdminUserItem] = []
    var selectedOwner: AdminUserItem?
    var isSearchingOwner: Bool = false
    // Viewer search
    var viewerSearch: String = ""
    var viewerResults: [AdminUserItem] = []
    var selectedViewer: AdminUserItem?
    var isSearchingViewer: Bool = false
}

/// Groups related notifications tab state
struct NotificationsTabState {
    var broadcastHistory: [BroadcastRecord] = []
    var isLoading: Bool = false
    // English fields
    var title: String = ""
    var body: String = ""
    var deeplink: String = "tidex://"
    // Norwegian fields
    var titleNo: String = ""
    var bodyNo: String = ""
    var deeplinkNo: String = ""
    var target: String = "all"
    var previewCount: Int = 0
    var isSending: Bool = false
    // Specific user targeting
    var userSearch: String = ""
    var userSearchResults: [AdminUserItem] = []
    var selectedUsers: [AdminUserItem] = []
    var isSearchingUsers: Bool = false
}

/// Groups related impersonation tab state
struct ImpersonationTabState {
    var userSearch: String = ""
    var userSearchResults: [AdminUserItem] = []
    var selectedUser: AdminUserItem?
    var isSearching: Bool = false
    var reason: String = ""
    var isStarting: Bool = false
}

// MARK: - View Model

/// AdminSettingsViewModel uses grouped state structs to reduce re-renders.
/// When a property in one state group changes, only observers of that group re-evaluate.
@MainActor
final class AdminSettingsViewModel: ObservableObject {

    // MARK: - Common State

    @Published var selectedTab: AdminTab = .users
    @Published var isSuperAdmin: Bool = false
    @Published var errorMessage: String?
    @Published var successMessage: String?
    @Published var isPerformingAction: Bool = false
    @Published var shouldDismissAfterImpersonation: Bool = false

    // MARK: - Grouped Tab States

    @Published var usersState = UsersTabState()
    @Published var feedbackState = FeedbackTabState()
    @Published var auditLogState = AuditLogTabState()
    @Published var sqlState = SqlTabState()
    @Published var sharesState = SharesTabState()
    @Published var notificationsState = NotificationsTabState()
    @Published var impersonationState = ImpersonationTabState()

    // MARK: - Legacy Computed Properties (for backwards compatibility with View)

    // Users
    var users: [AdminUserItem] {
        get { usersState.items }
        set { usersState.items = newValue }
    }
    var usersSearchQuery: String {
        get { usersState.searchQuery }
        set { usersState.searchQuery = newValue }
    }
    var usersIsLoading: Bool {
        get { usersState.isLoading }
        set { usersState.isLoading = newValue }
    }
    var usersCurrentPage: Int {
        get { usersState.currentPage }
        set { usersState.currentPage = newValue }
    }
    var usersTotalCount: Int {
        get { usersState.totalCount }
        set { usersState.totalCount = newValue }
    }
    var usersHasMore: Bool {
        get { usersState.hasMore }
        set { usersState.hasMore = newValue }
    }
    var selectedUser: AdminUserItem? {
        get { usersState.selected }
        set { usersState.selected = newValue }
    }

    // Feedback
    var feedbackItems: [AdminFeedbackItem] {
        get { feedbackState.items }
        set { feedbackState.items = newValue }
    }
    var feedbackIsLoading: Bool {
        get { feedbackState.isLoading }
        set { feedbackState.isLoading = newValue }
    }
    var feedbackTotal: Int {
        get { feedbackState.total }
        set { feedbackState.total = newValue }
    }
    var selectedFeedback: AdminFeedbackItem? {
        get { feedbackState.selected }
        set { feedbackState.selected = newValue }
    }
    var feedbackResponse: String {
        get { feedbackState.responseText }
        set { feedbackState.responseText = newValue }
    }

    // Audit Log
    var auditLogEntries: [AuditLogEntry] {
        get { auditLogState.entries }
        set { auditLogState.entries = newValue }
    }
    var auditLogIsLoading: Bool {
        get { auditLogState.isLoading }
        set { auditLogState.isLoading = newValue }
    }

    // SQL
    var sqlQuery: String {
        get { sqlState.query }
        set { sqlState.query = newValue }
    }
    var sqlResult: [[String: AnyCodable]]? {
        get { sqlState.result }
        set { sqlState.result = newValue }
    }
    var sqlRowCount: Int {
        get { sqlState.rowCount }
        set { sqlState.rowCount = newValue }
    }
    var sqlExecutionTime: Int {
        get { sqlState.executionTime }
        set { sqlState.executionTime = newValue }
    }
    var sqlIsExecuting: Bool {
        get { sqlState.isExecuting }
        set { sqlState.isExecuting = newValue }
    }
    var sqlError: String? {
        get { sqlState.error }
        set { sqlState.error = newValue }
    }

    // Shares
    var shares: [ShiftShareItem] {
        get { sharesState.items }
        set { sharesState.items = newValue }
    }
    var sharesSearchQuery: String {
        get { sharesState.searchQuery }
        set { sharesState.searchQuery = newValue }
    }
    var sharesIsLoading: Bool {
        get { sharesState.isLoading }
        set { sharesState.isLoading = newValue }
    }
    var sharesTotalCount: Int {
        get { sharesState.totalCount }
        set { sharesState.totalCount = newValue }
    }
    var isShowingCreateShare: Bool {
        get { sharesState.isShowingCreate }
        set { sharesState.isShowingCreate = newValue }
    }
    var createShareShowEarnings: Bool {
        get { sharesState.showEarnings }
        set { sharesState.showEarnings = newValue }
    }
    var isCreatingShare: Bool {
        get { sharesState.isCreating }
        set { sharesState.isCreating = newValue }
    }
    var createShareOwnerSearch: String {
        get { sharesState.ownerSearch }
        set { sharesState.ownerSearch = newValue }
    }
    var createShareOwnerResults: [AdminUserItem] {
        get { sharesState.ownerResults }
        set { sharesState.ownerResults = newValue }
    }
    var createShareSelectedOwner: AdminUserItem? {
        get { sharesState.selectedOwner }
        set { sharesState.selectedOwner = newValue }
    }
    var isSearchingOwner: Bool {
        get { sharesState.isSearchingOwner }
        set { sharesState.isSearchingOwner = newValue }
    }
    var createShareViewerSearch: String {
        get { sharesState.viewerSearch }
        set { sharesState.viewerSearch = newValue }
    }
    var createShareViewerResults: [AdminUserItem] {
        get { sharesState.viewerResults }
        set { sharesState.viewerResults = newValue }
    }
    var createShareSelectedViewer: AdminUserItem? {
        get { sharesState.selectedViewer }
        set { sharesState.selectedViewer = newValue }
    }
    var isSearchingViewer: Bool {
        get { sharesState.isSearchingViewer }
        set { sharesState.isSearchingViewer = newValue }
    }

    // Notifications
    var broadcastHistory: [BroadcastRecord] {
        get { notificationsState.broadcastHistory }
        set { notificationsState.broadcastHistory = newValue }
    }
    var notificationsIsLoading: Bool {
        get { notificationsState.isLoading }
        set { notificationsState.isLoading = newValue }
    }
    var notificationTitle: String {
        get { notificationsState.title }
        set { notificationsState.title = newValue }
    }
    var notificationBody: String {
        get { notificationsState.body }
        set { notificationsState.body = newValue }
    }
    var notificationDeeplink: String {
        get { notificationsState.deeplink }
        set { notificationsState.deeplink = newValue }
    }
    var notificationTitleNo: String {
        get { notificationsState.titleNo }
        set { notificationsState.titleNo = newValue }
    }
    var notificationBodyNo: String {
        get { notificationsState.bodyNo }
        set { notificationsState.bodyNo = newValue }
    }
    var notificationDeeplinkNo: String {
        get { notificationsState.deeplinkNo }
        set { notificationsState.deeplinkNo = newValue }
    }
    var notificationTarget: String {
        get { notificationsState.target }
        set { notificationsState.target = newValue }
    }
    var previewCount: Int {
        get { notificationsState.previewCount }
        set { notificationsState.previewCount = newValue }
    }
    var isSendingNotification: Bool {
        get { notificationsState.isSending }
        set { notificationsState.isSending = newValue }
    }
    var notificationUserSearch: String {
        get { notificationsState.userSearch }
        set { notificationsState.userSearch = newValue }
    }
    var notificationUserSearchResults: [AdminUserItem] {
        get { notificationsState.userSearchResults }
        set { notificationsState.userSearchResults = newValue }
    }
    var notificationSelectedUsers: [AdminUserItem] {
        get { notificationsState.selectedUsers }
        set { notificationsState.selectedUsers = newValue }
    }
    var isSearchingNotificationUsers: Bool {
        get { notificationsState.isSearchingUsers }
        set { notificationsState.isSearchingUsers = newValue }
    }

    // Impersonation
    var impersonationUserSearch: String {
        get { impersonationState.userSearch }
        set { impersonationState.userSearch = newValue }
    }
    var impersonationUserSearchResults: [AdminUserItem] {
        get { impersonationState.userSearchResults }
        set { impersonationState.userSearchResults = newValue }
    }
    var impersonationSelectedUser: AdminUserItem? {
        get { impersonationState.selectedUser }
        set { impersonationState.selectedUser = newValue }
    }
    var isSearchingImpersonationUsers: Bool {
        get { impersonationState.isSearching }
        set { impersonationState.isSearching = newValue }
    }
    var impersonationReason: String {
        get { impersonationState.reason }
        set { impersonationState.reason = newValue }
    }
    var isStartingImpersonation: Bool {
        get { impersonationState.isStarting }
        set { impersonationState.isStarting = newValue }
    }

    // MARK: - Private Properties

    /// Shared URLSession from factory (long-running timeout for admin operations)
    private let urlSession = URLSessionFactory.longRunning
    private var searchTask: Task<Void, Never>?
    private let perPage = 20

    deinit {
        searchTask?.cancel()
    }

    // MARK: - Common Methods

    func loadInitialData() async {
        do {
            let session = try await AuthSessionManager.shared.getSession()
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
        case .impersonation:
            break // No initial load needed - state is managed by ImpersonationManager
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

    func createShare() async {
        guard let owner = createShareSelectedOwner, let viewer = createShareSelectedViewer else {
            errorMessage = "Please select both owner and viewer"
            return
        }

        guard owner.id != viewer.id else {
            errorMessage = "Owner and viewer cannot be the same user"
            return
        }

        guard !isCreatingShare else { return }
        isCreatingShare = true
        clearMessages()

        do {
            let result: AdminActionResponse = try await makeRequest(
                url: APIConfiguration.webAppBaseURL.appendingPathComponent("/api/admin/shares"),
                method: "POST",
                body: [
                    "ownerId": owner.id,
                    "viewerId": viewer.id,
                    "showEarnings": createShareShowEarnings
                ]
            )
            if result.success {
                successMessage = "Share created"
                resetCreateShareForm()
                isShowingCreateShare = false
                await fetchShares()
            } else {
                errorMessage = result.message ?? "Failed to create share"
            }
        } catch let error as AdminError {
            // Parse error message from server response if available
            if case .serverError(_, let message) = error {
                // Try to extract the message from JSON response
                if let data = message.data(using: .utf8),
                   let json = try? JSONDecoder().decode(AdminActionResponse.self, from: data) {
                    errorMessage = json.message ?? "Failed to create share"
                } else {
                    errorMessage = error.localizedDescription
                }
            } else {
                errorMessage = error.localizedDescription
            }
        } catch {
            errorMessage = "Failed to create share: \(error.localizedDescription)"
        }

        isCreatingShare = false
    }

    func resetCreateShareForm() {
        createShareOwnerSearch = ""
        createShareOwnerResults = []
        createShareSelectedOwner = nil
        createShareViewerSearch = ""
        createShareViewerResults = []
        createShareSelectedViewer = nil
        createShareShowEarnings = true
        isSearchingOwner = false
        isSearchingViewer = false
    }

    func searchShareOwner() {
        let query = createShareOwnerSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            createShareOwnerResults = []
            return
        }

        Task {
            isSearchingOwner = true
            do {
                let url = APIConfiguration.webAppBaseURL.appendingPathComponent("/api/admin/users")
                var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
                components.queryItems = [
                    URLQueryItem(name: "search", value: query),
                    URLQueryItem(name: "perPage", value: "10")
                ]

                let result: AdminUsersResponse = try await makeRequest(url: components.url!, method: "GET")
                createShareOwnerResults = result.users
            } catch {
                createShareOwnerResults = []
            }
            isSearchingOwner = false
        }
    }

    func selectShareOwner(_ user: AdminUserItem) {
        createShareSelectedOwner = user
        createShareOwnerSearch = ""
        createShareOwnerResults = []
    }

    func clearShareOwner() {
        createShareSelectedOwner = nil
        createShareOwnerSearch = ""
        createShareOwnerResults = []
    }

    func searchShareViewer() {
        let query = createShareViewerSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            createShareViewerResults = []
            return
        }

        Task {
            isSearchingViewer = true
            do {
                let url = APIConfiguration.webAppBaseURL.appendingPathComponent("/api/admin/users")
                var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
                components.queryItems = [
                    URLQueryItem(name: "search", value: query),
                    URLQueryItem(name: "perPage", value: "10")
                ]

                let result: AdminUsersResponse = try await makeRequest(url: components.url!, method: "GET")
                createShareViewerResults = result.users
            } catch {
                createShareViewerResults = []
            }
            isSearchingViewer = false
        }
    }

    func selectShareViewer(_ user: AdminUserItem) {
        createShareSelectedViewer = user
        createShareViewerSearch = ""
        createShareViewerResults = []
    }

    func clearShareViewer() {
        createShareSelectedViewer = nil
        createShareViewerSearch = ""
        createShareViewerResults = []
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
        // Require both English and Norwegian title/body
        guard !notificationTitle.isEmpty && !notificationTitleNo.isEmpty &&
              !notificationBody.isEmpty && !notificationBodyNo.isEmpty else {
            errorMessage = "English and Norwegian title and body are required"
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
                "titleNo": notificationTitleNo,
                "body": notificationBody,
                "bodyNo": notificationBodyNo,
                "target": notificationTarget,
                "includeSelf": false
            ]
            if !notificationDeeplink.isEmpty {
                body["deeplink"] = notificationDeeplink
            }
            if !notificationDeeplinkNo.isEmpty {
                body["deeplinkNo"] = notificationDeeplinkNo
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
                // Don't clear fields on success - user may want to send similar notification
                await fetchBroadcastHistory()
            } else {
                errorMessage = result.message ?? "Failed to send notification"
            }
        } catch {
            errorMessage = "Failed to send notification"
        }

        isSendingNotification = false
    }

    // MARK: - Impersonation Tab Methods

    func searchImpersonationUsers() {
        let query = impersonationUserSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            impersonationUserSearchResults = []
            return
        }

        Task {
            isSearchingImpersonationUsers = true
            do {
                let url = APIConfiguration.webAppBaseURL.appendingPathComponent("/api/admin/users")
                var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
                components.queryItems = [
                    URLQueryItem(name: "search", value: query),
                    URLQueryItem(name: "perPage", value: "10")
                ]

                let result: AdminUsersResponse = try await makeRequest(url: components.url!, method: "GET")
                impersonationUserSearchResults = result.users
            } catch {
                impersonationUserSearchResults = []
            }
            isSearchingImpersonationUsers = false
        }
    }

    func selectImpersonationUser(_ user: AdminUserItem) {
        impersonationSelectedUser = user
        impersonationUserSearch = ""
        impersonationUserSearchResults = []
    }

    func clearImpersonationUser() {
        impersonationSelectedUser = nil
        impersonationUserSearch = ""
        impersonationUserSearchResults = []
    }

    func startImpersonation() async {
        guard let targetUser = impersonationSelectedUser else {
            errorMessage = "Please select a user to impersonate"
            return
        }

        let reason = impersonationReason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard reason.count >= 5 else {
            errorMessage = "Reason must be at least 5 characters"
            return
        }

        isStartingImpersonation = true
        clearMessages()

        do {
            _ = try await ImpersonationManager.shared.startImpersonation(
                targetUserId: targetUser.id,
                reason: reason
            )
            successMessage = "Now impersonating \(targetUser.displayName)"
            // Clear form
            clearImpersonationUser()
            impersonationReason = ""
            // Signal that the admin view should dismiss
            shouldDismissAfterImpersonation = true
        } catch {
            errorMessage = error.localizedDescription
        }

        isStartingImpersonation = false
    }

    // MARK: - Network Helper

    private func makeRequest<T: Decodable>(url: URL, method: String, body: [String: Any]? = nil) async throws -> T {
        let session = try await AuthSessionManager.shared.getSession()

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

