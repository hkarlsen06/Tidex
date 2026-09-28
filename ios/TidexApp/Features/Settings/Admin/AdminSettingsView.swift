import SwiftUI

struct AdminSettingsView: View {
  @State private var viewModel = AdminSettingsViewModel()
  @Environment(\.dismiss) private var dismiss

  /// Optional initial tab to select when the view appears (for deep linking)
  var initialTab: AdminTab?
  var initialReportId: String?

  var body: some View {
    VStack(spacing: 0) {
      // Tab picker
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: Spacing.xs) {
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
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
      }
      .background(Color.tidexSurfacePrimary)

      // Messages
      if let error = viewModel.errorMessage {
        MessageBanner(message: error, type: .error) { viewModel.clearMessages() }
      }

      // Tab content
      TabContent(viewModel: viewModel)
    }
    .background(Color.tidexBackground)
    .navigationTitle("Admin")
    .navigationBarTitleDisplayMode(.inline)
    .task {
      // Set initial tab if provided (for deep linking)
      if let initialTab {
        viewModel.selectedTab = initialTab
      }
      viewModel.setInitialReportSelection(initialReportId)
      await viewModel.loadInitialData()
    }
    .sheet(item: $viewModel.selectedUser) { user in
      UserActionSheet(user: user, viewModel: viewModel)
    }
    .sheet(item: $viewModel.selectedFeedback) { feedback in
      FeedbackResponseSheet(feedback: feedback, viewModel: viewModel)
    }
    .sheet(item: $viewModel.selectedReport) { report in
      ReportReviewSheet(report: report, viewModel: viewModel)
    }
    .onChange(of: viewModel.shouldDismissAfterImpersonation) { _, shouldDismiss in
      if shouldDismiss {
        dismiss()
      }
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
      HStack(spacing: Spacing.xxxs) {
        Image(systemName: tab.icon)
          .font(.tidexCaptionRegular)
        Text(tab.title)
          .font(.tidexFootnoteMedium)
      }
      .foregroundColor(isSelected ? .white : .tidexTextSecondary)
      .padding(.horizontal, Spacing.sm)
      .padding(.vertical, Spacing.xs)
      .background(isSelected ? Color.tidexBlue : Color.tidexSurfaceSecondary)
      .cornerRadius(CornerRadius.sm)
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
    HStack(spacing: Spacing.sm) {
      Image(systemName: type.icon).foregroundColor(type.color)
      Text(message).font(.tidexSubheadline).foregroundColor(.tidexTextPrimary)
      Spacer()
      Button(action: onDismiss) {
        Image(systemName: "xmark").font(.tidexCaptionRegular).foregroundColor(.tidexTextMuted)
      }
    }
    .padding(Spacing.sm)
    .background(type.color.opacity(0.1))
  }
}

// MARK: - Tab Content

private struct TabContent: View {
  @Bindable var viewModel: AdminSettingsViewModel

  var body: some View {
    switch viewModel.selectedTab {
    case .notifications: NotificationsTabView(viewModel: viewModel)
    case .users: UsersTabView(viewModel: viewModel)
    case .feedback: FeedbackTabView(viewModel: viewModel)
    case .reports: ReportsTabView(viewModel: viewModel)
    case .subscribers: SubscribersTabView(viewModel: viewModel)
    case .shares: SharesTabView(viewModel: viewModel)
    case .auditLog: AuditLogTabView(viewModel: viewModel)
    }
  }
}

// MARK: - Users Tab

private struct UsersTabView: View {
  @Bindable var viewModel: AdminSettingsViewModel

  var body: some View {
    VStack(spacing: 0) {  // swiftlint:disable:this closure_body_length
      if viewModel.usersIsLoading, viewModel.users.isEmpty {
        ProgressView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if viewModel.users.isEmpty {
        ContentUnavailableView(
          "No users found", systemImage: "person.3"
        )
      } else {
        ScrollView {
          LazyVStack(spacing: Spacing.xs) {
            Text("\(viewModel.usersTotalCount) users").font(.tidexCaptionRegular).foregroundColor(
              .tidexTextMuted
            ).frame(maxWidth: .infinity, alignment: .leading)

            ForEach(viewModel.users) { user in
              UserCard(user: user) { viewModel.selectedUser = user }
                .onAppear {
                  // Trigger infinite scroll when last user appears
                  if user.id == viewModel.users.last?.id, viewModel.usersHasMore,
                    !viewModel.usersIsLoading
                  {
                    Task { await viewModel.loadMoreUsers() }
                  }
                }
            }

            if viewModel.usersIsLoading, !viewModel.users.isEmpty {
              ProgressView()
                .padding()
            }
          }
          .padding(Spacing.md)
        }
      }
    }
    .searchable(text: $viewModel.usersSearchQuery, prompt: "Search users...")
    .task(id: viewModel.usersSearchQuery) {
      try? await Task.sleep(for: .milliseconds(300))
      guard !Task.isCancelled else { return }
      await viewModel.searchUsers()
    }
  }
}

// MARK: - Subscribers Tab

private struct SubscribersTabView: View {
  @Bindable var viewModel: AdminSettingsViewModel

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Picker("Filter", selection: $viewModel.subscribersFilter) {
          ForEach(AdminSubscriberFilter.allCases) { filter in
            Text(filter.title).tag(filter)
          }
        }
        .pickerStyle(.menu)
        .onChange(of: viewModel.subscribersFilter) { _, filter in
          Task { await viewModel.setSubscribersFilter(filter) }
        }

        Spacer()

        Button {
          Task { await viewModel.fetchSubscribers() }
        } label: {
          Image(systemName: "arrow.clockwise")
            .font(.tidexBodyMedium)
            .foregroundColor(.tidexBlue)
        }
        .disabled(viewModel.subscribersIsLoading)
      }
      .padding(.horizontal, Spacing.md)
      .padding(.vertical, Spacing.sm)

      if viewModel.subscribersIsLoading {
        ProgressView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if viewModel.subscribers.isEmpty {
        ContentUnavailableView(
          "No subscribers found", systemImage: "person.crop.circle.badge.checkmark"
        )
      } else {
        ScrollView {
          LazyVStack(spacing: Spacing.xs) {
            Text("\(viewModel.subscribers.count) subscribers")
              .font(.tidexCaptionRegular)
              .foregroundColor(.tidexTextMuted)
              .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(viewModel.subscribers) { subscriber in
              SubscriberCard(subscriber: subscriber, viewModel: viewModel)
            }
          }
          .padding(Spacing.md)
        }
      }
    }
  }
}

// MARK: - Feedback Tab

private struct FeedbackTabView: View {
  @Bindable var viewModel: AdminSettingsViewModel

  var body: some View {
    if viewModel.feedbackIsLoading {
      ProgressView()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if viewModel.feedbackItems.isEmpty {
      ContentUnavailableView(
        "No feedback yet", systemImage: "bubble.left.and.bubble.right"
      )
    } else {
      ScrollView {
        LazyVStack(spacing: Spacing.sm) {
          ForEach(viewModel.feedbackItems) { item in
            FeedbackCard(item: item) { viewModel.selectedFeedback = item }
          }
        }
        .padding(Spacing.md)
      }
    }
  }
}

private enum ReportsFilterOption: String, CaseIterable, Identifiable {
  case all
  case open
  case inReview
  case actioned
  case dismissed

  var id: String { rawValue }

  var title: String {
    switch self {
    case .all: return "All"
    case .open: return "Open"
    case .inReview: return "In Review"
    case .actioned: return "Actioned"
    case .dismissed: return "Dismissed"
    }
  }

  var status: AdminReportStatus? {
    switch self {
    case .all: return nil
    case .open: return .open
    case .inReview: return .inReview
    case .actioned: return .actioned
    case .dismissed: return .dismissed
    }
  }

  init(status: AdminReportStatus?) {
    switch status {
    case .none: self = .all
    case .open: self = .open
    case .inReview: self = .inReview
    case .actioned: self = .actioned
    case .dismissed: self = .dismissed
    }
  }
}

private struct ReportsTabView: View {
  @Bindable var viewModel: AdminSettingsViewModel

  private var selectedFilter: Binding<ReportsFilterOption> {
    Binding(
      get: { ReportsFilterOption(status: viewModel.reportsStatusFilter) },
      set: { option in
        Task { await viewModel.updateReportsFilter(option.status) }
      }
    )
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Picker("Status", selection: selectedFilter) {
          ForEach(ReportsFilterOption.allCases) { option in
            Text(option.title).tag(option)
          }
        }
        .pickerStyle(.menu)

        Spacer()

        Button {
          Task { await viewModel.fetchReports() }
        } label: {
          Image(systemName: "arrow.clockwise")
            .font(.tidexBodyMedium)
            .foregroundColor(.tidexBlue)
        }
        .disabled(viewModel.reportsIsLoading)
      }
      .padding(.horizontal, Spacing.md)
      .padding(.vertical, Spacing.sm)

      if viewModel.reportsIsLoading {
        ProgressView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if viewModel.reportsItems.isEmpty {
        ContentUnavailableView("No reports found", systemImage: "flag")
      } else {
        ScrollView {
          LazyVStack(spacing: Spacing.sm) {
            Text("\(viewModel.reportsTotal) reports")
              .font(.tidexCaptionRegular)
              .foregroundColor(.tidexTextMuted)
              .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(viewModel.reportsItems) { item in
              ReportCard(item: item) { viewModel.selectedReport = item }
            }
          }
          .padding(Spacing.md)
        }
      }
    }
  }
}

// MARK: - Audit Log Tab

private struct AuditLogTabView: View {
  @Bindable var viewModel: AdminSettingsViewModel

  var body: some View {
    if viewModel.auditLogIsLoading {
      ProgressView()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if viewModel.auditLogEntries.isEmpty {
      ContentUnavailableView(
        "No audit log entries", systemImage: "list.bullet.clipboard"
      )
    } else {
      ScrollView {
        LazyVStack(spacing: Spacing.xs) {
          ForEach(viewModel.auditLogEntries) { entry in
            AuditLogCard(entry: entry)
          }
        }
        .padding(Spacing.md)
      }
    }
  }
}

// MARK: - Shares Tab

private struct SharesTabView: View {
  @Bindable var viewModel: AdminSettingsViewModel

  var body: some View {
    VStack(spacing: 0) {
      // Create button row
      HStack {
        Spacer()
        Button {
          viewModel.resetCreateShareForm()
          viewModel.isShowingCreateShare = true
        } label: {
          Image(systemName: "plus.circle.fill")
            .font(.tidexLargeTitle)
            .foregroundColor(.tidexBlue)
        }
        .padding(.trailing, Spacing.sm)
      }

      if viewModel.sharesIsLoading {
        ProgressView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if viewModel.shares.isEmpty {
        ContentUnavailableView(
          "No shares found", systemImage: "square.and.arrow.up"
        )
      } else {
        ScrollView {
          LazyVStack(spacing: Spacing.xs) {
            Text("\(viewModel.sharesTotalCount) shares").font(.tidexCaptionRegular).foregroundColor(
              .tidexTextMuted
            ).frame(maxWidth: .infinity, alignment: .leading)

            ForEach(viewModel.shares) { share in
              ShareCard(share: share) {
                Task { await viewModel.deleteShare(share.id) }
              }
            }
          }
          .padding(Spacing.md)
        }
      }
    }
    .sheet(isPresented: $viewModel.isShowingCreateShare) {
      CreateShareSheet(viewModel: viewModel)
    }
    .searchable(text: $viewModel.sharesSearchQuery, prompt: "Search shares...")
    .task(id: viewModel.sharesSearchQuery) {
      try? await Task.sleep(for: .milliseconds(300))
      guard !Task.isCancelled else { return }
      await viewModel.fetchShares()
    }
  }
}

// MARK: - Notifications Tab

private struct NotificationsTabView: View {
  @Bindable var viewModel: AdminSettingsViewModel
  let targets = ["all", "pro", "active", "specific"]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Spacing.mlg) {
        // Send notification section
        VStack(alignment: .leading, spacing: Spacing.sm) {
          Text("Send Notification").font(.headline).foregroundColor(.tidexTextPrimary)

          // Title fields
          VStack(alignment: .leading, spacing: Spacing.xxxs) {
            Text("Title").font(.subheadline).foregroundColor(.tidexTextMuted)
            TextField("English", text: $viewModel.notificationTitle)
              .textFieldStyle(AdminTextFieldStyle())
            TextField("Norwegian", text: $viewModel.notificationTitleNo)
              .textFieldStyle(AdminTextFieldStyle())
          }

          // Body fields
          VStack(alignment: .leading, spacing: Spacing.xxxs) {
            Text("Body").font(.subheadline).foregroundColor(.tidexTextMuted)
            TextField("English", text: $viewModel.notificationBody, axis: .vertical)
              .lineLimit(3...6)
              .textFieldStyle(AdminTextFieldStyle())
            TextField("Norwegian", text: $viewModel.notificationBodyNo, axis: .vertical)
              .lineLimit(3...6)
              .textFieldStyle(AdminTextFieldStyle())
          }

          // Deeplink fields
          VStack(alignment: .leading, spacing: Spacing.xxxs) {
            Text("Deeplink (optional)").font(.subheadline).foregroundColor(.tidexTextMuted)
            TextField("English (e.g. tidex://shifts)", text: $viewModel.notificationDeeplink)
              .textFieldStyle(AdminTextFieldStyle())
            TextField(
              "Norwegian (optional)", text: $viewModel.notificationDeeplinkNo
            )
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
            VStack(alignment: .leading, spacing: Spacing.xs) {
              // Selected users chips
              if !viewModel.notificationSelectedUsers.isEmpty {
                FlowLayout(spacing: Spacing.xxxs) {
                  ForEach(viewModel.notificationSelectedUsers) { user in
                    HStack(spacing: Spacing.xxs) {
                      Text(user.email ?? user.name ?? String(user.id.prefix(8)))
                        .font(.tidexCaptionRegular)
                        .foregroundColor(.tidexTextPrimary)
                      Button {
                        viewModel.deselectNotificationUser(user)
                      } label: {
                        Image(systemName: "xmark.circle.fill")
                          .font(.tidexCaptionRegular)
                          .foregroundColor(.tidexTextMuted)
                      }
                    }
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, Spacing.xxs)
                    .background(Color.tidexSurfaceSecondary)
                    .cornerRadius(CornerRadius.lg)
                  }
                }
              }

              // User search field
              HStack {
                Image(systemName: "magnifyingglass")
                  .foregroundColor(.tidexTextMuted)
                TextField(
                  "Search users by email or name...", text: $viewModel.notificationUserSearch
                )
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
              .cornerRadius(CornerRadius.sm)

              // Search results
              if !viewModel.notificationUserSearchResults.isEmpty {
                VStack(spacing: 0) {
                  ForEach(viewModel.notificationUserSearchResults) { user in
                    Button {
                      viewModel.selectNotificationUser(user)
                    } label: {
                      HStack {
                        VStack(alignment: .leading, spacing: Spacing.micro) {
                          Text(user.email ?? "No email")
                            .font(.tidexFootnote)
                            .foregroundColor(.tidexTextPrimary)
                          if let name = user.name {
                            Text(name)
                              .font(.tidexMicro)
                              .foregroundColor(.tidexTextMuted)
                          }
                        }
                        Spacer()
                        Image(systemName: "plus.circle.fill")
                          .foregroundColor(.tidexBlue)
                      }
                      .padding(.vertical, Spacing.xs)
                      .padding(.horizontal, Spacing.xs)
                    }
                    Divider()
                  }
                }
                .background(Color.tidexSurfaceSecondary)
                .cornerRadius(CornerRadius.sm)
              }
            }
          }

          if viewModel.previewCount > 0 {
            Text(
              "Will send to \(viewModel.previewCount) user\(viewModel.previewCount == 1 ? "" : "s")"
            )
            .font(.tidexFootnote).foregroundColor(.tidexTextMuted)
          }

          Button(action: { Task { await viewModel.sendNotification() } }) {
            HStack {
              if viewModel.isSendingNotification {
                ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .tidexTextOnBrand))
              }
              Text(viewModel.isSendingNotification ? "Sending..." : "Send Notification")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
            .background(Color.tidexBlue)
            .foregroundColor(.tidexTextOnBrand)
            .cornerRadius(CornerRadius.sm)
          }
          .disabled(
            viewModel.isSendingNotification || viewModel.notificationTitle.isEmpty
              || viewModel.notificationTitleNo.isEmpty || viewModel.notificationBody.isEmpty
              || viewModel.notificationBodyNo.isEmpty
              || (viewModel.notificationTarget == "specific"
                && viewModel.notificationSelectedUsers.isEmpty)
          )
        }
        .padding(Spacing.md)
        .background(Color.tidexSurfacePrimary)
        .cornerRadius(CornerRadius.lg)

        // History section
        VStack(alignment: .leading, spacing: Spacing.sm) {
          Text("Recent Broadcasts").font(.headline).foregroundColor(.tidexTextPrimary)

          if viewModel.notificationsIsLoading {
            ProgressView()
          } else if viewModel.broadcastHistory.isEmpty {
            Text("No broadcasts yet").font(.tidexSubheadline).foregroundColor(.tidexTextMuted)
          } else {
            ForEach(viewModel.broadcastHistory) { broadcast in
              BroadcastCard(broadcast: broadcast)
            }
          }
        }
      }
      .padding(Spacing.md)
    }
    .task { await viewModel.previewNotificationCount() }
  }
}

// MARK: - Flow Layout for User Chips

private struct FlowLayout: Layout {
  var spacing: CGFloat = 8

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
    let result = computeLayout(proposal: proposal, subviews: subviews)
    return result.size
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()
  ) {
    let result = computeLayout(proposal: proposal, subviews: subviews)
    for (index, position) in result.positions.enumerated() {
      subviews[index].place(
        at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
        proposal: .unspecified)
    }
  }

  private func computeLayout(proposal: ProposedViewSize, subviews: Subviews) -> (
    size: CGSize, positions: [CGPoint]
  ) {
    var positions: [CGPoint] = []
    var currentX: CGFloat = 0
    var currentY: CGFloat = 0
    var lineHeight: CGFloat = 0
    let maxWidth = proposal.width ?? .infinity

    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if currentX + size.width > maxWidth, currentX > 0 {
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

private struct AdminTextFieldStyle: TextFieldStyle {
  func _body(configuration: TextField<Self._Label>) -> some View {
    configuration
      .padding(Spacing.sm)
      .background(Color.tidexSurfaceSecondary)
      .cornerRadius(CornerRadius.sm)
  }
}

// MARK: - Card Components

private struct UserCard: View {
  let user: AdminUserItem
  let onTap: () -> Void

  var body: some View {
    Button(action: onTap) {
      VStack(alignment: .leading, spacing: Spacing.xxxs) {
        HStack {
          Text(user.displayName).font(.tidexLabel).foregroundColor(
            .tidexTextPrimary
          ).lineLimit(1)
          Spacer()
          HStack(spacing: Spacing.xxs) {
            if user.isSuperAdmin {
              Badge(text: "Super", color: .tidexWarning)
            } else if user.isAdmin {
              Badge(text: "Admin", color: .tidexWarning)
            }
            if user.isBanned { Badge(text: "Banned", color: .tidexError) }
            if user.isGrandfathered { Badge(text: "GF", color: .tidexSuccess) }
            Badge(text: user.planDisplayName, color: planColor(user.plan))
          }
        }
        if let email = user.email, email != user.displayName {
          Text(email).font(.tidexFootnote).foregroundColor(.tidexTextSecondary).lineLimit(1)
        }
      }
      .padding(Spacing.sm)
      .background(Color.tidexSurfacePrimary)
      .cornerRadius(CornerRadius.md)
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
  let subscriber: AdminSubscriberItem
  @Bindable var viewModel: AdminSettingsViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      HStack {
        Text(subscriber.displayName)
          .font(.tidexLabel)
          .foregroundColor(.tidexTextPrimary)
          .lineLimit(1)

        Spacer()

        HStack(spacing: Spacing.xxs) {
          Badge(text: subscriber.planDisplayName, color: planColor(subscriber.plan))
          if subscriber.isGrandfathered {
            Badge(text: "Lifetime", color: .tidexSuccess)
          }
        }
      }

      Text(subscriber.contactDisplay)
        .font(.tidexFootnote)
        .foregroundColor(.tidexTextSecondary)
        .lineLimit(1)

      HStack {
        Text("Expires: \(formattedDate(subscriber.currentPeriodEnd))")
          .font(.tidexCaptionRegular)
          .foregroundColor(.tidexTextMuted)
        Spacer()
      }

      HStack(spacing: Spacing.sm) {
        if subscriber.isGrandfathered {
          Button("Revoke Lifetime") {
            Task { await viewModel.toggleSubscriberGrandfathered(subscriber) }
          }
          .foregroundColor(.tidexError)
          .disabled(viewModel.isPerformingAction)
        } else {
          Button("Grant Lifetime") {
            Task { await viewModel.toggleSubscriberGrandfathered(subscriber) }
          }
          .disabled(viewModel.isPerformingAction)
        }

        if subscriber.plan == "trial" {
          Button("End Trial") {
            Task { await viewModel.toggleSubscriberTrial(subscriber, create: false) }
          }
          .foregroundColor(.tidexError)
          .disabled(viewModel.isPerformingAction)
        } else if subscriber.plan == "free" {
          Button("Grant Trial") {
            Task { await viewModel.toggleSubscriberTrial(subscriber, create: true) }
          }
          .disabled(viewModel.isPerformingAction)
        }
      }
      .font(.tidexCaptionRegular)
    }
    .padding(Spacing.sm)
    .background(Color.tidexSurfacePrimary)
    .cornerRadius(CornerRadius.md)
  }

  private func planColor(_ plan: String) -> Color {
    switch plan {
    case "max": return .tidexPurple
    case "pro": return .tidexBlue
    case "trial": return .tidexWarning
    default: return .tidexTextMuted
    }
  }

  private func formattedDate(_ dateString: String?) -> String {
    guard let dateString else { return "-" }
    guard let date = ISO8601Timestamp.date(from: dateString) else { return dateString }

    return date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(.appLocale))
  }
}

private struct FeedbackCard: View {
  let item: AdminFeedbackItem
  let onTap: () -> Void

  var body: some View {
    Button(action: onTap) {
      VStack(alignment: .leading, spacing: Spacing.xs) {
        HStack {
          Text(item.userName ?? item.userEmail).font(.tidexLabel)
            .foregroundColor(.tidexTextPrimary)
          Spacer()
          if item.response != nil {
            Badge(text: "Responded", color: .tidexSuccess)
          }
        }
        Text(item.message).font(.tidexSubheadline).foregroundColor(.tidexTextSecondary).lineLimit(3)
      }
      .padding(Spacing.sm)
      .background(Color.tidexSurfacePrimary)
      .cornerRadius(CornerRadius.md)
    }
    .buttonStyle(.plain)
  }
}

private struct ReportCard: View {
  let item: AdminReportItem
  let onTap: () -> Void

  var body: some View {
    Button(action: onTap) {
      VStack(alignment: .leading, spacing: Spacing.xs) {
        HStack(alignment: .top) {
          VStack(alignment: .leading, spacing: Spacing.xxxs) {
            Text(item.reasonTitle)
              .font(.tidexLabel)
              .foregroundColor(.tidexTextPrimary)
            Text("\(item.reporterDisplayName) reported \(item.reportedDisplayName)")
              .font(.tidexCaptionRegular)
              .foregroundColor(.tidexTextSecondary)
          }
          Spacer()
          Badge(text: item.status.title, color: statusColor)
        }

        if let note = item.note, !note.isEmpty {
          Text(note)
            .font(.tidexSubheadline)
            .foregroundColor(.tidexTextSecondary)
            .lineLimit(2)
        }

        HStack {
          Text("Created \(formattedDate(item.createdAt))")
            .font(.tidexMicro)
            .foregroundColor(.tidexTextMuted)
          Spacer()
          if item.messageId != nil {
            Text("Message report")
              .font(.tidexMicro)
              .foregroundColor(.tidexTextMuted)
          } else {
            Text("User report")
              .font(.tidexMicro)
              .foregroundColor(.tidexTextMuted)
          }
        }
      }
      .padding(Spacing.sm)
      .background(Color.tidexSurfacePrimary)
      .cornerRadius(CornerRadius.md)
    }
    .buttonStyle(.plain)
  }

  private var statusColor: Color {
    switch item.status {
    case .open: return .tidexWarning
    case .inReview: return .tidexBlue
    case .actioned: return .tidexSuccess
    case .dismissed: return .tidexTextMuted
    }
  }

  private func formattedDate(_ dateString: String) -> String {
    guard let date = ISO8601Timestamp.date(from: dateString) else { return dateString }

    return date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(.appLocale))
  }
}

private struct AuditLogCard: View {
  let entry: AuditLogEntry

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.xxs) {
      HStack {
        Text(entry.action).font(.tidexFootnoteMedium).foregroundColor(
          .tidexTextPrimary)
        Spacer()
        Text(entry.createdAt.prefix(10)).font(.tidexMicro).foregroundColor(.tidexTextMuted)
      }
      Text("by \(entry.adminEmail ?? "System")").font(.tidexCaptionRegular).foregroundColor(
        .tidexTextSecondary)
      if let target = entry.targetEmail {
        Text("Target: \(target)").font(.tidexCaptionRegular).foregroundColor(.tidexTextMuted)
      }
    }
    .padding(Spacing.xs)
    .background(Color.tidexSurfacePrimary)
    .cornerRadius(CornerRadius.sm)
  }
}

private struct ShareCard: View {
  let share: ShiftShareItem
  let onDelete: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.xxxs) {
      HStack {
        VStack(alignment: .leading) {
          Text("Owner: \(share.ownerName ?? share.ownerEmail ?? String(share.ownerId.prefix(8)))")
            .font(.tidexFootnote).foregroundColor(.tidexTextPrimary)
          Text(
            "Viewer: \(share.viewerName ?? share.viewerEmail ?? String(share.viewerId.prefix(8)))"
          )
          .font(.tidexFootnote).foregroundColor(.tidexTextSecondary)
        }
        Spacer()
        HStack(spacing: Spacing.xxs) {
          if share.blocked { Badge(text: "Blocked", color: .tidexError) }
          if share.muted { Badge(text: "Muted", color: .tidexWarning) }
        }
      }
      HStack {
        Text(share.showEarnings ? "Shows earnings" : "Hidden earnings").font(.tidexMicro)
          .foregroundColor(.tidexTextMuted)
        Spacer()
        Button("Delete") { onDelete() }
          .font(.tidexCaptionRegular).foregroundColor(.tidexError)
      }
    }
    .padding(Spacing.xs)
    .background(Color.tidexSurfacePrimary)
    .cornerRadius(CornerRadius.sm)
  }
}

private struct BroadcastCard: View {
  let broadcast: BroadcastRecord

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.xxxs) {
      HStack {
        Text(broadcast.title).font(.tidexLabel).foregroundColor(
          .tidexTextPrimary)
        Spacer()
        Badge(text: broadcast.status, color: statusColor(broadcast.status))
      }
      Text(broadcast.body).font(.tidexFootnote).foregroundColor(.tidexTextSecondary).lineLimit(2)
      HStack {
        Text("Target: \(broadcast.target)").font(.tidexMicro).foregroundColor(.tidexTextMuted)
        Text("Sent: \(broadcast.sentCount)/\(broadcast.targetCount)").font(.tidexMicro)
          .foregroundColor(.tidexTextMuted)
      }
    }
    .padding(Spacing.xs)
    .background(Color.tidexSurfacePrimary)
    .cornerRadius(CornerRadius.sm)
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
      .font(.tidexMicro)
      .foregroundColor(color)
      .padding(.horizontal, Spacing.xxxs)
      .padding(.vertical, Spacing.micro)
      .background(color.opacity(0.15))
      .cornerRadius(CornerRadius.xxs)
  }
}

// MARK: - Sheets

private struct UserActionSheet: View {
  let user: AdminUserItem
  @Bindable var viewModel: AdminSettingsViewModel
  @Environment(\.dismiss) private var dismiss
  @State private var impersonationReason = ""
  @State private var impersonationError: String?
  @State private var isStartingImpersonation = false

  private var formattedLastSignIn: String? {
    guard let lastSignIn = user.lastSignInAt else { return nil }
    guard let date = ISO8601Timestamp.date(from: lastSignIn) else { return lastSignIn }
    return formatDate(date)
  }

  private func formatDate(_ date: Date) -> String {
    date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(.appLocale))
  }

  var body: some View {
    NavigationStack {
      List {
        Group {
          Section {
            Text(user.displayName).font(.headline)
            if let email = user.email { Text(email).font(.subheadline).foregroundColor(.secondary) }
            if let lastSignIn = formattedLastSignIn {
              HStack {
                Text("Last login")
                  .foregroundColor(.secondary)
                Spacer()
                Text(lastSignIn)
                  .foregroundColor(.tidexTextMuted)
              }
              .font(.subheadline)
            } else {
              HStack {
                Text("Last login")
                  .foregroundColor(.secondary)
                Spacer()
                Text("Never")
                  .foregroundColor(.tidexTextMuted)
              }
              .font(.subheadline)
            }
          }

          Section("Actions") {
            if !user.isSuperAdmin {
              Button(user.isBanned ? "Unban User" : "Ban User") {
                Task {
                  await viewModel.toggleBan(user: user)
                  dismiss()
                }
              }
              .foregroundColor(user.isBanned ? .tidexSuccess : .tidexError)
            }

            if viewModel.isSuperAdmin, !user.isSuperAdmin {
              Button(user.isAdmin ? "Revoke Admin" : "Grant Admin") {
                Task {
                  await viewModel.toggleAdmin(user: user)
                  dismiss()
                }
              }
            }

            Button(user.isGrandfathered ? "Revoke Grandfathered" : "Grant Grandfathered") {
              Task {
                await viewModel.toggleGrandfathered(user: user)
                dismiss()
              }
            }

            if user.plan == "trial" {
              Button("Revoke Trial") {
                Task {
                  await viewModel.toggleTrial(user: user, create: false)
                  dismiss()
                }
              }
              .foregroundColor(.tidexError)
            } else if user.plan == "free" {
              Button("Grant 7-day Trial") {
                Task {
                  await viewModel.toggleTrial(user: user, create: true)
                  dismiss()
                }
              }
            }
          }

          if !user.isAdmin || (viewModel.isSuperAdmin && !user.isSuperAdmin) {
            Section("Impersonation") {
              TextField("Reason (minimum 5 characters)", text: $impersonationReason)
                .textInputAutocapitalization(.sentences)

              if let impersonationError {
                Text(impersonationError)
                  .font(.tidexCaptionRegular)
                  .foregroundColor(.tidexError)
              }

              Button(isStartingImpersonation ? "Starting..." : "Impersonate User") {
                Task { await startImpersonation() }
              }
              .disabled(
                isStartingImpersonation
                  || impersonationReason.trimmingCharacters(in: .whitespacesAndNewlines).count < 5)
            }
          }
        }
        .listRowBackground(Color.tidexSurfacePrimary)
      }
      .tidexListBackground()
      .navigationTitle("User Actions")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
        }
      }
    }
    .presentationDetents([.medium, .large])
  }

  private func startImpersonation() async {
    let reason = impersonationReason.trimmingCharacters(in: .whitespacesAndNewlines)
    guard reason.count >= 5 else {
      impersonationError = "Reason must be at least 5 characters"
      return
    }

    isStartingImpersonation = true
    impersonationError = nil

    do {
      _ = try await ImpersonationManager.shared.startImpersonation(
        targetUserId: user.id,
        reason: reason
      )
      Haptics.play(.success)
      viewModel.shouldDismissAfterImpersonation = true
      dismiss()
    } catch {
      impersonationError = "Failed to start impersonation"
    }

    isStartingImpersonation = false
  }
}

private struct FeedbackResponseSheet: View {
  let feedback: AdminFeedbackItem
  @Bindable var viewModel: AdminSettingsViewModel
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: Spacing.md) {
        VStack(alignment: .leading, spacing: Spacing.xs) {
          Text("From: \(feedback.userName ?? feedback.userEmail)").font(.subheadline)
            .foregroundColor(.secondary)
          Text(feedback.message).font(.body)
        }
        .padding()
        .background(Color.tidexSurfacePrimary)
        .cornerRadius(CornerRadius.lg)

        if let existingResponse = feedback.response {
          VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Previous Response").font(.subheadline).foregroundColor(.secondary)
            Text(existingResponse).font(.body)
          }
          .padding()
          .background(Color.tidexSuccess.opacity(0.1))
          .cornerRadius(CornerRadius.lg)
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
            .padding(.vertical, Spacing.sm)
            .background(Color.tidexBlue)
            .foregroundColor(.tidexTextOnBrand)
            .cornerRadius(CornerRadius.sm)
        }
        .disabled(viewModel.feedbackResponse.isEmpty || viewModel.isPerformingAction)

        Spacer()
      }
      .padding()
      .navigationTitle("Respond to Feedback")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Cancel") {
            viewModel.feedbackResponse = ""
            dismiss()
          }
        }
      }
    }
  }
}

private struct ReportReviewSheet: View {
  let report: AdminReportItem
  @Bindable var viewModel: AdminSettingsViewModel
  @Environment(\.dismiss) private var dismiss
  @State private var selectedStatus: AdminReportStatus

  init(report: AdminReportItem, viewModel: AdminSettingsViewModel) {
    self.report = report
    self.viewModel = viewModel
    _selectedStatus = State(initialValue: report.status)
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: Spacing.md) {
          infoSection

          if let note = report.note, !note.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.xs) {
              Text("User Note")
                .font(.tidexSubheadline)
                .foregroundColor(.tidexTextMuted)
              Text(note)
                .font(.tidexBody)
                .foregroundColor(.tidexTextPrimary)
            }
            .padding()
            .background(Color.tidexSurfacePrimary)
            .cornerRadius(CornerRadius.lg)
          }

          VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Status")
              .font(.tidexSubheadline)
              .foregroundColor(.tidexTextMuted)

            Picker("Status", selection: $selectedStatus) {
              ForEach(AdminReportStatus.allCases) { status in
                Text(status.title).tag(status)
              }
            }
            .pickerStyle(.segmented)

            TextField("Reviewer notes", text: $viewModel.reportsReviewerNotes, axis: .vertical)
              .lineLimit(4...8)
              .textFieldStyle(AdminTextFieldStyle())
          }
          .padding()
          .background(Color.tidexSurfacePrimary)
          .cornerRadius(CornerRadius.lg)

          Button(action: save) {
            Text(viewModel.isPerformingAction ? "Saving..." : "Save Review")
              .frame(maxWidth: .infinity)
              .padding(.vertical, Spacing.sm)
              .background(Color.tidexBlue)
              .foregroundColor(.tidexTextOnBrand)
              .cornerRadius(CornerRadius.sm)
          }
          .disabled(viewModel.isPerformingAction)
        }
        .padding()
      }
      .navigationTitle("Report Review")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") {
            viewModel.reportsReviewerNotes = ""
            dismiss()
          }
        }
      }
      .onAppear {
        viewModel.reportsReviewerNotes = report.reviewerNotes ?? ""
      }
    }
  }

  private var infoSection: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      LabeledContent("Reason", value: report.reasonTitle)
      LabeledContent("Reporter", value: report.reporterDisplayName)
      LabeledContent("Reported", value: report.reportedDisplayName)
      LabeledContent("Thread", value: report.threadId)
      if let messageId = report.messageId {
        LabeledContent("Message", value: messageId)
      }
      LabeledContent("Created", value: formattedDate(report.createdAt) ?? report.createdAt)
      LabeledContent("Reviewed", value: formattedDate(report.reviewedAt) ?? "Not reviewed")
    }
    .font(.tidexFootnote)
    .foregroundColor(.tidexTextPrimary)
    .padding()
    .background(Color.tidexSurfacePrimary)
    .cornerRadius(CornerRadius.lg)
  }

  private func save() {
    Task {
      await viewModel.updateReportStatus(
        report.id,
        status: selectedStatus,
        reviewerNotes: viewModel.reportsReviewerNotes
      )
      dismiss()
    }
  }

  private func formattedDate(_ dateString: String?) -> String? {
    guard let dateString, !dateString.isEmpty else { return nil }
    guard let date = ISO8601Timestamp.date(from: dateString) else { return dateString }

    return date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(.appLocale))
  }
}

private struct CreateShareSheet: View {
  @Bindable var viewModel: AdminSettingsViewModel
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: Spacing.md) {
          Text(
            "Create a new share between two users. The owner's shifts will be visible to the viewer."
          )
          .font(.subheadline)
          .foregroundColor(.tidexTextSecondary)

          // Owner selection
          VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Owner (shares their shifts)").font(.subheadline).foregroundColor(.tidexTextMuted)

            if let owner = viewModel.createShareSelectedOwner {
              // Selected owner chip
              HStack {
                VStack(alignment: .leading, spacing: Spacing.micro) {
                  Text(owner.displayName)
                    .font(.tidexLabel)
                    .foregroundColor(.tidexTextPrimary)
                  if let email = owner.email {
                    Text(email)
                      .font(.tidexCaptionRegular)
                      .foregroundColor(.tidexTextMuted)
                  }
                }
                Spacer()
                Button {
                  viewModel.clearShareOwner()
                } label: {
                  Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.tidexTextMuted)
                }
              }
              .padding(Spacing.sm)
              .background(Color.tidexSurfaceSecondary)
              .cornerRadius(CornerRadius.sm)
            } else {
              // Search field
              HStack {
                Image(systemName: "magnifyingglass")
                  .foregroundColor(.tidexTextMuted)
                TextField(
                  "Search by name, email, or phone...", text: $viewModel.createShareOwnerSearch
                )
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: viewModel.createShareOwnerSearch) { _, _ in
                  viewModel.searchShareOwner()
                }
                if viewModel.isSearchingOwner {
                  ProgressView().scaleEffect(0.8)
                }
              }
              .padding(Spacing.sm)
              .background(Color.tidexSurfaceSecondary)
              .cornerRadius(CornerRadius.sm)

              // Search results
              if !viewModel.createShareOwnerResults.isEmpty {
                VStack(spacing: 0) {
                  ForEach(viewModel.createShareOwnerResults) { user in
                    Button {
                      viewModel.selectShareOwner(user)
                    } label: {
                      UserSearchResultRow(user: user)
                    }
                    if user.id != viewModel.createShareOwnerResults.last?.id {
                      Divider()
                    }
                  }
                }
                .background(Color.tidexSurfaceSecondary)
                .cornerRadius(CornerRadius.sm)
              }
            }
          }

          // Viewer selection
          VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Viewer (can see owner's shifts)").font(.subheadline).foregroundColor(
              .tidexTextMuted)

            if let viewer = viewModel.createShareSelectedViewer {
              // Selected viewer chip
              HStack {
                VStack(alignment: .leading, spacing: Spacing.micro) {
                  Text(viewer.displayName)
                    .font(.tidexLabel)
                    .foregroundColor(.tidexTextPrimary)
                  if let email = viewer.email {
                    Text(email)
                      .font(.tidexCaptionRegular)
                      .foregroundColor(.tidexTextMuted)
                  }
                }
                Spacer()
                Button {
                  viewModel.clearShareViewer()
                } label: {
                  Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.tidexTextMuted)
                }
              }
              .padding(Spacing.sm)
              .background(Color.tidexSurfaceSecondary)
              .cornerRadius(CornerRadius.sm)
            } else {
              // Search field
              HStack {
                Image(systemName: "magnifyingglass")
                  .foregroundColor(.tidexTextMuted)
                TextField(
                  "Search by name, email, or phone...", text: $viewModel.createShareViewerSearch
                )
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: viewModel.createShareViewerSearch) { _, _ in
                  viewModel.searchShareViewer()
                }
                if viewModel.isSearchingViewer {
                  ProgressView().scaleEffect(0.8)
                }
              }
              .padding(Spacing.sm)
              .background(Color.tidexSurfaceSecondary)
              .cornerRadius(CornerRadius.sm)

              // Search results
              if !viewModel.createShareViewerResults.isEmpty {
                VStack(spacing: 0) {
                  ForEach(viewModel.createShareViewerResults) { user in
                    Button {
                      viewModel.selectShareViewer(user)
                    } label: {
                      UserSearchResultRow(user: user)
                    }
                    if user.id != viewModel.createShareViewerResults.last?.id {
                      Divider()
                    }
                  }
                }
                .background(Color.tidexSurfaceSecondary)
                .cornerRadius(CornerRadius.sm)
              }
            }
          }

          Toggle("Show Earnings", isOn: $viewModel.createShareShowEarnings)
            .tint(.tidexBlue)

          Button(action: {
            Task { await viewModel.createShare() }
          }) {
            HStack {
              if viewModel.isCreatingShare {
                ProgressView()
                  .progressViewStyle(CircularProgressViewStyle(tint: .tidexTextOnBrand))
              }
              Text(viewModel.isCreatingShare ? "Creating..." : "Create Share")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
            .background(
              (viewModel.createShareSelectedOwner != nil
                && viewModel.createShareSelectedViewer != nil && !viewModel.isCreatingShare)
                ? Color.tidexBlue
                : Color.tidexBlue.opacity(0.5)
            )
            .foregroundColor(.tidexTextOnBrand)
            .cornerRadius(CornerRadius.sm)
          }
          .disabled(
            viewModel.isCreatingShare || viewModel.createShareSelectedOwner == nil
              || viewModel.createShareSelectedViewer == nil
          )
        }
        .padding()
      }
      .navigationTitle("Create Share")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Cancel") { dismiss() }
        }
      }
    }
    .presentationDetents([.large])
  }
}

private struct UserSearchResultRow: View {
  let user: AdminUserItem

  var body: some View {
    HStack {
      VStack(alignment: .leading, spacing: Spacing.micro) {
        Text(user.displayName)
          .font(.tidexLabel)
          .foregroundColor(.tidexTextPrimary)
        if let email = user.email, email != user.displayName {
          Text(email)
            .font(.tidexCaptionRegular)
            .foregroundColor(.tidexTextMuted)
        }
        if let phone = user.phone {
          Text(phone)
            .font(.tidexCaptionRegular)
            .foregroundColor(.tidexTextMuted)
        }
      }
      Spacer()
      Image(systemName: "plus.circle.fill")
        .foregroundColor(.tidexBlue)
    }
    .padding(.vertical, Spacing.xsm)
    .padding(.horizontal, Spacing.sm)
    .contentShape(Rectangle())
  }
}

#Preview {
  NavigationStack {
    AdminSettingsView()
  }
}  // swiftlint:disable:this file_length
