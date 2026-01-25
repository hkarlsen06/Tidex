import SwiftUI

struct AdminSettingsView: View {
    @StateObject private var viewModel = AdminSettingsViewModel()

    /// Optional initial tab to select when the view appears (for deep linking)
    var initialTab: AdminTab?

    var body: some View {
        VStack(spacing: 0) {
            // Tab picker
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(AdminTab.allCases) { tab in
                        TabButton(
                            tab: tab,
                            isSelected: viewModel.selectedTab == tab,
                            action: {
                                viewModel.selectedTab = tab
                                Task { await viewModel.loadDataForTab(tab) }
                            }
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color.tidexSurfacePrimary)

            // Messages
            if let error = viewModel.errorMessage {
                MessageBanner(message: error, type: .error) { viewModel.clearMessages() }
            }
            if let success = viewModel.successMessage {
                MessageBanner(message: success, type: .success) { viewModel.clearMessages() }
            }

            // Tab content
            TabContent(viewModel: viewModel)
        }
        .background(Color.tidexBackground)
        .navigationTitle("Admin")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Set initial tab if provided (for deep linking)
            if let initialTab = initialTab {
                viewModel.selectedTab = initialTab
            }
            await viewModel.loadInitialData()
        }
        .sheet(item: $viewModel.selectedUser) { user in
            UserActionSheet(user: user, viewModel: viewModel)
        }
        .sheet(item: $viewModel.selectedFeedback) { feedback in
            FeedbackResponseSheet(feedback: feedback, viewModel: viewModel)
        }
    }
}

// MARK: - Tab Button

private struct TabButton: View {
    let tab: AdminTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: tab.icon)
                    .font(.system(size: 12))
                Text(tab.title)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(isSelected ? .white : .tidexTextSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.tidexBlue : Color.tidexSurfaceSecondary)
            .cornerRadius(8)
        }
    }
}

// MARK: - Message Banner

private struct MessageBanner: View {
    let message: String
    let type: MessageType
    let onDismiss: () -> Void

    enum MessageType {
        case error, success
        var color: Color { self == .error ? .tidexError : .tidexSuccess }
        var icon: String { self == .error ? "exclamationmark.triangle.fill" : "checkmark.circle.fill" }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: type.icon).foregroundColor(type.color)
            Text(message).font(.system(size: 14)).foregroundColor(.tidexTextPrimary)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark").font(.system(size: 12)).foregroundColor(.tidexTextMuted)
            }
        }
        .padding(12)
        .background(type.color.opacity(0.1))
    }
}

// MARK: - Tab Content

private struct TabContent: View {
    @ObservedObject var viewModel: AdminSettingsViewModel

    var body: some View {
        switch viewModel.selectedTab {
        case .users: UsersTabView(viewModel: viewModel)
        case .subscribers: SubscribersTabView(viewModel: viewModel)
        case .feedback: FeedbackTabView(viewModel: viewModel)
        case .auditLog: AuditLogTabView(viewModel: viewModel)
        case .sql: SqlTabView(viewModel: viewModel)
        case .shares: SharesTabView(viewModel: viewModel)
        case .notifications: NotificationsTabView(viewModel: viewModel)
        }
    }
}

// MARK: - Users Tab

private struct UsersTabView: View {
    @ObservedObject var viewModel: AdminSettingsViewModel

    var body: some View {
        VStack(spacing: 0) {
            SearchBar(text: $viewModel.usersSearchQuery, placeholder: "Search users...", isSearching: viewModel.usersIsLoading) {
                viewModel.searchUsers()
            }

            if viewModel.usersIsLoading && viewModel.users.isEmpty {
                AdminLoadingView()
            } else if viewModel.users.isEmpty {
                EmptyStateView(icon: "person.3", message: "No users found")
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        Text("\(viewModel.usersTotalCount) users").font(.system(size: 12)).foregroundColor(.tidexTextMuted).frame(maxWidth: .infinity, alignment: .leading)

                        ForEach(viewModel.users) { user in
                            UserCard(user: user) { viewModel.selectedUser = user }
                        }

                        if viewModel.usersHasMore {
                            Button("Load more") { Task { await viewModel.loadMoreUsers() } }
                                .font(.system(size: 14)).foregroundColor(.tidexBlue).padding()
                        }
                    }
                    .padding(16)
                }
            }
        }
    }
}

// MARK: - Subscribers Tab

private struct SubscribersTabView: View {
    @ObservedObject var viewModel: AdminSettingsViewModel
    let filters = ["all", "pro", "max", "trial", "grandfathered"]

    var body: some View {
        VStack(spacing: 0) {
            Picker("Filter", selection: $viewModel.subscribersFilter) {
                ForEach(filters, id: \.self) { Text($0.capitalized).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(16)
            .onChange(of: viewModel.subscribersFilter) { _, _ in
                Task { await viewModel.fetchSubscribers() }
            }

            if viewModel.subscribersIsLoading {
                AdminLoadingView()
            } else if viewModel.subscribers.isEmpty {
                EmptyStateView(icon: "creditcard", message: "No subscribers found")
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.subscribers) { sub in
                            SubscriberCard(subscriber: sub)
                        }
                    }
                    .padding(16)
                }
            }
        }
    }
}

// MARK: - Feedback Tab

private struct FeedbackTabView: View {
    @ObservedObject var viewModel: AdminSettingsViewModel

    var body: some View {
        if viewModel.feedbackIsLoading {
            AdminLoadingView()
        } else if viewModel.feedbackItems.isEmpty {
            EmptyStateView(icon: "bubble.left.and.bubble.right", message: "No feedback yet")
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.feedbackItems) { item in
                        FeedbackCard(item: item) { viewModel.selectedFeedback = item }
                    }
                }
                .padding(16)
            }
        }
    }
}

// MARK: - Audit Log Tab

private struct AuditLogTabView: View {
    @ObservedObject var viewModel: AdminSettingsViewModel

    var body: some View {
        if viewModel.auditLogIsLoading {
            AdminLoadingView()
        } else if viewModel.auditLogEntries.isEmpty {
            EmptyStateView(icon: "list.bullet.clipboard", message: "No audit log entries")
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.auditLogEntries) { entry in
                        AuditLogCard(entry: entry)
                    }
                }
                .padding(16)
            }
        }
    }
}

// MARK: - SQL Tab

private struct SqlTabView: View {
    @ObservedObject var viewModel: AdminSettingsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Execute SQL").font(.headline).foregroundColor(.tidexTextPrimary)

                TextEditor(text: $viewModel.sqlQuery)
                    .font(.system(size: 13, design: .monospaced))
                    .frame(minHeight: 120)
                    .padding(8)
                    .background(Color.tidexSurfacePrimary)
                    .cornerRadius(8)

                Button(action: { Task { await viewModel.executeSql() } }) {
                    HStack {
                        if viewModel.sqlIsExecuting {
                            ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                        }
                        Text(viewModel.sqlIsExecuting ? "Executing..." : "Execute")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.tidexBlue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .disabled(viewModel.sqlIsExecuting)

                if let error = viewModel.sqlError {
                    Text(error).font(.system(size: 13)).foregroundColor(.tidexError)
                }

                if let result = viewModel.sqlResult {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(viewModel.sqlRowCount) rows in \(viewModel.sqlExecutionTime)ms")
                            .font(.system(size: 12)).foregroundColor(.tidexTextMuted)

                        ScrollView(.horizontal) {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(result.enumerated()), id: \.offset) { _, row in
                                    Text(row.map { "\($0.key): \($0.value.stringValue)" }.joined(separator: ", "))
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.tidexTextSecondary)
                                }
                            }
                        }
                        .padding(8)
                        .background(Color.tidexSurfacePrimary)
                        .cornerRadius(8)
                    }
                }
            }
            .padding(16)
        }
    }
}

// MARK: - Shares Tab

private struct SharesTabView: View {
    @ObservedObject var viewModel: AdminSettingsViewModel

    var body: some View {
        VStack(spacing: 0) {
            SearchBar(text: $viewModel.sharesSearchQuery, placeholder: "Search shares...", isSearching: viewModel.sharesIsLoading) {
                viewModel.searchShares()
            }

            if viewModel.sharesIsLoading {
                AdminLoadingView()
            } else if viewModel.shares.isEmpty {
                EmptyStateView(icon: "square.and.arrow.up", message: "No shares found")
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        Text("\(viewModel.sharesTotalCount) shares").font(.system(size: 12)).foregroundColor(.tidexTextMuted).frame(maxWidth: .infinity, alignment: .leading)

                        ForEach(viewModel.shares) { share in
                            ShareCard(share: share) {
                                Task { await viewModel.deleteShare(share.id) }
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
    }
}

// MARK: - Notifications Tab

private struct NotificationsTabView: View {
    @ObservedObject var viewModel: AdminSettingsViewModel
    let targets = ["all", "pro", "active", "specific"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Send notification section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Send Notification").font(.headline).foregroundColor(.tidexTextPrimary)

                    // Title fields
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Title").font(.subheadline).foregroundColor(.tidexTextMuted)
                        TextField("English", text: $viewModel.notificationTitle)
                            .textFieldStyle(AdminTextFieldStyle())
                        TextField("Norwegian", text: $viewModel.notificationTitleNo)
                            .textFieldStyle(AdminTextFieldStyle())
                    }

                    // Body fields
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Body").font(.subheadline).foregroundColor(.tidexTextMuted)
                        TextField("English", text: $viewModel.notificationBody, axis: .vertical)
                            .lineLimit(3...6)
                            .textFieldStyle(AdminTextFieldStyle())
                        TextField("Norwegian", text: $viewModel.notificationBodyNo, axis: .vertical)
                            .lineLimit(3...6)
                            .textFieldStyle(AdminTextFieldStyle())
                    }

                    // Deeplink fields
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Deeplink (optional)").font(.subheadline).foregroundColor(.tidexTextMuted)
                        TextField("English (e.g. tidex://shifts)", text: $viewModel.notificationDeeplink)
                            .textFieldStyle(AdminTextFieldStyle())
                        TextField("Norwegian (optional, falls back to English)", text: $viewModel.notificationDeeplinkNo)
                            .textFieldStyle(AdminTextFieldStyle())
                    }

                    Picker("Target", selection: $viewModel.notificationTarget) {
                        ForEach(targets, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: viewModel.notificationTarget) { _, _ in
                        Task { await viewModel.previewNotificationCount() }
                    }

                    // Specific user selection
                    if viewModel.notificationTarget == "specific" {
                        VStack(alignment: .leading, spacing: 8) {
                            // Selected users chips
                            if !viewModel.notificationSelectedUsers.isEmpty {
                                FlowLayout(spacing: 6) {
                                    ForEach(viewModel.notificationSelectedUsers) { user in
                                        HStack(spacing: 4) {
                                            Text(user.email ?? user.name ?? String(user.id.prefix(8)))
                                                .font(.system(size: 12))
                                                .foregroundColor(.tidexTextPrimary)
                                            Button {
                                                viewModel.deselectNotificationUser(user)
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.system(size: 12))
                                                    .foregroundColor(.tidexTextMuted)
                                            }
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.tidexSurfaceSecondary)
                                        .cornerRadius(12)
                                    }
                                }
                            }

                            // User search field
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(.tidexTextMuted)
                                TextField("Search users by email or name...", text: $viewModel.notificationUserSearch)
                                    .textFieldStyle(.plain)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .onChange(of: viewModel.notificationUserSearch) { _, _ in
                                        viewModel.searchNotificationUsers()
                                    }
                                if viewModel.isSearchingNotificationUsers {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                }
                            }
                            .padding(Spacing.xs)
                            .background(Color.tidexSurfaceSecondary)
                            .cornerRadius(8)

                            // Search results
                            if !viewModel.notificationUserSearchResults.isEmpty {
                                VStack(spacing: 0) {
                                    ForEach(viewModel.notificationUserSearchResults) { user in
                                        Button {
                                            viewModel.selectNotificationUser(user)
                                        } label: {
                                            HStack {
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(user.email ?? "No email")
                                                        .font(.system(size: 13))
                                                        .foregroundColor(.tidexTextPrimary)
                                                    if let name = user.name {
                                                        Text(name)
                                                            .font(.system(size: 11))
                                                            .foregroundColor(.tidexTextMuted)
                                                    }
                                                }
                                                Spacer()
                                                Image(systemName: "plus.circle.fill")
                                                    .foregroundColor(.tidexBlue)
                                            }
                                            .padding(.vertical, 8)
                                            .padding(.horizontal, Spacing.xs)
                                        }
                                        Divider()
                                    }
                                }
                                .background(Color.tidexSurfaceSecondary)
                                .cornerRadius(8)
                            }
                        }
                    }

                    if viewModel.previewCount > 0 {
                        Text("Will send to \(viewModel.previewCount) user\(viewModel.previewCount == 1 ? "" : "s")")
                            .font(.system(size: 13)).foregroundColor(.tidexTextMuted)
                    }

                    Button(action: { Task { await viewModel.sendNotification() } }) {
                        HStack {
                            if viewModel.isSendingNotification {
                                ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                            }
                            Text(viewModel.isSendingNotification ? "Sending..." : "Send Notification")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.tidexBlue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .disabled(
                        viewModel.isSendingNotification ||
                        viewModel.notificationTitle.isEmpty ||
                        viewModel.notificationTitleNo.isEmpty ||
                        viewModel.notificationBody.isEmpty ||
                        viewModel.notificationBodyNo.isEmpty ||
                        (viewModel.notificationTarget == "specific" && viewModel.notificationSelectedUsers.isEmpty)
                    )
                }
                .padding(16)
                .background(Color.tidexSurfacePrimary)
                .cornerRadius(12)

                // History section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Recent Broadcasts").font(.headline).foregroundColor(.tidexTextPrimary)

                    if viewModel.notificationsIsLoading {
                        ProgressView()
                    } else if viewModel.broadcastHistory.isEmpty {
                        Text("No broadcasts yet").font(.system(size: 14)).foregroundColor(.tidexTextMuted)
                    } else {
                        ForEach(viewModel.broadcastHistory) { broadcast in
                            BroadcastCard(broadcast: broadcast)
                        }
                    }
                }
            }
            .padding(16)
        }
        .task { await viewModel.previewNotificationCount() }
    }
}

// MARK: - Flow Layout for User Chips

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func computeLayout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        let maxWidth = proposal.width ?? .infinity

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: currentY + lineHeight), positions)
    }
}

// MARK: - Reusable Components

private struct SearchBar: View {
    @Binding var text: String
    let placeholder: String
    let isSearching: Bool
    let onSearch: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundColor(.tidexTextMuted)
            TextField(placeholder, text: $text)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: text) { _, _ in onSearch() }
            if !text.isEmpty {
                Button { text = ""; onSearch() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.tidexTextMuted)
                }
            }
            if isSearching { ProgressView().scaleEffect(0.8) }
        }
        .padding(12)
        .background(Color.tidexSurfacePrimary)
    }
}

private struct AdminLoadingView: View {
    var body: some View {
        VStack { Spacer(); ProgressView(); Spacer() }
    }
}

private struct EmptyStateView: View {
    let icon: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: icon).font(.system(size: 40)).foregroundColor(.tidexTextMuted)
            Text(message).font(.system(size: 16)).foregroundColor(.tidexTextSecondary)
            Spacer()
        }
    }
}

private struct AdminTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(12)
            .background(Color.tidexSurfaceSecondary)
            .cornerRadius(8)
    }
}

// MARK: - Card Components

private struct UserCard: View {
    let user: AdminUserItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(user.displayName).font(.system(size: 15, weight: .medium)).foregroundColor(.tidexTextPrimary).lineLimit(1)
                    Spacer()
                    HStack(spacing: 4) {
                        if user.isSuperAdmin { Badge(text: "Super", color: .tidexWarning) }
                        else if user.isAdmin { Badge(text: "Admin", color: .tidexWarning) }
                        if user.isBanned { Badge(text: "Banned", color: .tidexError) }
                        if user.isGrandfathered { Badge(text: "GF", color: .tidexSuccess) }
                        Badge(text: user.planDisplayName, color: planColor(user.plan))
                    }
                }
                if let email = user.email, email != user.displayName {
                    Text(email).font(.system(size: 13)).foregroundColor(.tidexTextSecondary).lineLimit(1)
                }
            }
            .padding(12)
            .background(Color.tidexSurfacePrimary)
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    private func planColor(_ plan: String) -> Color {
        switch plan {
        case "max": return .tidexPurple
        case "pro": return .tidexBlue
        case "trial": return .tidexWarning
        default: return .tidexTextMuted
        }
    }
}

private struct SubscriberCard: View {
    let subscriber: SubscriberItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(subscriber.displayName).font(.system(size: 15, weight: .medium)).foregroundColor(.tidexTextPrimary)
                Spacer()
                Badge(text: subscriber.planDisplayName, color: .tidexBlue)
                if subscriber.isGrandfathered { Badge(text: "GF", color: .tidexSuccess) }
            }
            if let status = subscriber.status {
                Text("Status: \(status)").font(.system(size: 12)).foregroundColor(.tidexTextMuted)
            }
            if let provider = subscriber.provider {
                Text("Provider: \(provider)").font(.system(size: 12)).foregroundColor(.tidexTextMuted)
            }
        }
        .padding(12)
        .background(Color.tidexSurfacePrimary)
        .cornerRadius(10)
    }
}

private struct FeedbackCard: View {
    let item: AdminFeedbackItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(item.userName ?? item.userEmail).font(.system(size: 14, weight: .medium)).foregroundColor(.tidexTextPrimary)
                    Spacer()
                    if item.response != nil {
                        Badge(text: "Responded", color: .tidexSuccess)
                    }
                }
                Text(item.message).font(.system(size: 14)).foregroundColor(.tidexTextSecondary).lineLimit(3)
            }
            .padding(12)
            .background(Color.tidexSurfacePrimary)
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }
}

private struct AuditLogCard: View {
    let entry: AuditLogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.action).font(.system(size: 13, weight: .medium)).foregroundColor(.tidexTextPrimary)
                Spacer()
                Text(entry.createdAt.prefix(10)).font(.system(size: 11)).foregroundColor(.tidexTextMuted)
            }
            Text("by \(entry.adminEmail ?? "System")").font(.system(size: 12)).foregroundColor(.tidexTextSecondary)
            if let target = entry.targetEmail {
                Text("Target: \(target)").font(.system(size: 12)).foregroundColor(.tidexTextMuted)
            }
        }
        .padding(Spacing.xs)
        .background(Color.tidexSurfacePrimary)
        .cornerRadius(8)
    }
}

private struct ShareCard: View {
    let share: ShiftShareItem
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Owner: \(share.ownerName ?? share.ownerEmail ?? String(share.ownerId.prefix(8)))")
                        .font(.system(size: 13)).foregroundColor(.tidexTextPrimary)
                    Text("Viewer: \(share.viewerName ?? share.viewerEmail ?? String(share.viewerId.prefix(8)))")
                        .font(.system(size: 13)).foregroundColor(.tidexTextSecondary)
                }
                Spacer()
                HStack(spacing: 4) {
                    if share.blocked { Badge(text: "Blocked", color: .tidexError) }
                    if share.muted { Badge(text: "Muted", color: .tidexWarning) }
                }
            }
            HStack {
                Text(share.showEarnings ? "Shows earnings" : "Hidden earnings").font(.system(size: 11)).foregroundColor(.tidexTextMuted)
                Spacer()
                Button("Delete") { onDelete() }
                    .font(.system(size: 12)).foregroundColor(.tidexError)
            }
        }
        .padding(Spacing.xs)
        .background(Color.tidexSurfacePrimary)
        .cornerRadius(8)
    }
}

private struct BroadcastCard: View {
    let broadcast: BroadcastRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(broadcast.title).font(.system(size: 14, weight: .medium)).foregroundColor(.tidexTextPrimary)
                Spacer()
                Badge(text: broadcast.status, color: statusColor(broadcast.status))
            }
            Text(broadcast.body).font(.system(size: 13)).foregroundColor(.tidexTextSecondary).lineLimit(2)
            HStack {
                Text("Target: \(broadcast.target)").font(.system(size: 11)).foregroundColor(.tidexTextMuted)
                Text("Sent: \(broadcast.sentCount)/\(broadcast.targetCount)").font(.system(size: 11)).foregroundColor(.tidexTextMuted)
            }
        }
        .padding(Spacing.xs)
        .background(Color.tidexSurfacePrimary)
        .cornerRadius(8)
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "completed": return .tidexSuccess
        case "pending", "queued": return .tidexWarning
        case "failed", "partial_failure": return .tidexError
        default: return .tidexTextMuted
        }
    }
}

private struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .cornerRadius(4)
    }
}

// MARK: - Sheets

private struct UserActionSheet: View {
    let user: AdminUserItem
    @ObservedObject var viewModel: AdminSettingsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(user.displayName).font(.headline)
                    if let email = user.email { Text(email).font(.subheadline).foregroundColor(.secondary) }
                }

                Section("Actions") {
                    if !user.isSuperAdmin {
                        Button(user.isBanned ? "Unban User" : "Ban User") {
                            Task { await viewModel.toggleBan(user: user); dismiss() }
                        }
                        .foregroundColor(user.isBanned ? .tidexSuccess : .tidexError)
                    }

                    if viewModel.isSuperAdmin && !user.isSuperAdmin {
                        Button(user.isAdmin ? "Revoke Admin" : "Grant Admin") {
                            Task { await viewModel.toggleAdmin(user: user); dismiss() }
                        }
                    }

                    Button(user.isGrandfathered ? "Revoke Grandfathered" : "Grant Grandfathered") {
                        Task { await viewModel.toggleGrandfathered(user: user); dismiss() }
                    }

                    if user.plan == "trial" {
                        Button("Revoke Trial") {
                            Task { await viewModel.toggleTrial(user: user, create: false); dismiss() }
                        }
                        .foregroundColor(.tidexError)
                    } else if user.plan == "free" {
                        Button("Grant 7-day Trial") {
                            Task { await viewModel.toggleTrial(user: user, create: true); dismiss() }
                        }
                    }
                }
            }
            .navigationTitle("User Actions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct FeedbackResponseSheet: View {
    let feedback: AdminFeedbackItem
    @ObservedObject var viewModel: AdminSettingsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("From: \(feedback.userName ?? feedback.userEmail)").font(.subheadline).foregroundColor(.secondary)
                    Text(feedback.message).font(.body)
                }
                .padding()
                .background(Color.tidexSurfacePrimary)
                .cornerRadius(12)

                if let existingResponse = feedback.response {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Previous Response").font(.subheadline).foregroundColor(.secondary)
                        Text(existingResponse).font(.body)
                    }
                    .padding()
                    .background(Color.tidexSuccess.opacity(0.1))
                    .cornerRadius(12)
                }

                TextField("Your response...", text: $viewModel.feedbackResponse, axis: .vertical)
                    .lineLimit(4...8)
                    .textFieldStyle(AdminTextFieldStyle())

                Button(action: {
                    Task {
                        await viewModel.respondToFeedback(feedback.id, response: viewModel.feedbackResponse)
                        dismiss()
                    }
                }) {
                    Text(viewModel.isPerformingAction ? "Sending..." : "Send Response")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.tidexBlue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .disabled(viewModel.feedbackResponse.isEmpty || viewModel.isPerformingAction)

                Spacer()
            }
            .padding()
            .navigationTitle("Respond to Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { viewModel.feedbackResponse = ""; dismiss() }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        AdminSettingsView()
    }
}
