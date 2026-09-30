// Admin screens are English only and skipped by the localization audit (see ios/Scripts/audit-strings.swift).
import SwiftUI

/// Admin sections. Deep links open the admin screen on `.feedback` or `.reports`.
enum AdminTab: String, CaseIterable, Identifiable, Hashable {
  case feedback
  case reports
  case stats
  case users
  case shares
  case broadcast
  case auditLog

  var id: String { rawValue }

  var title: String {
    switch self {
    case .feedback: return "Feedback"
    case .reports: return "Reports"
    case .stats: return "Stats"
    case .users: return "Users"
    case .shares: return "Shares"
    case .broadcast: return "Broadcast"
    case .auditLog: return "Audit log"
    }
  }

  var icon: String {
    switch self {
    case .feedback: return "bubble.left.and.text.bubble.right"
    case .reports: return "flag"
    case .stats: return "chart.bar.xaxis"
    case .users: return "person.2"
    case .shares: return "person.2.wave.2"
    case .broadcast: return "megaphone"
    case .auditLog: return "list.bullet.rectangle"
    }
  }

  var tint: Color {
    switch self {
    case .feedback: return .tidexBlueText
    case .reports: return .tidexError
    case .stats: return .tidexBlueText
    case .users: return .tidexPurple
    case .shares: return .tidexSuccess
    case .broadcast: return .tidexWarning
    case .auditLog: return .tidexTextSecondary
    }
  }
}

/// Admin home. Shows what needs attention and links to each admin tool.
struct AdminSettingsView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var initialTab: AdminTab?
  var initialReportId: String?

  @State private var deepLinkedTab: AdminTab?
  @State private var deepLinkedReportID: String?
  @State private var didApplyDeepLink = false
  @State private var summary = Summary()
  @State private var activeUsers: AdminActiveUsersChart?
  @Environment(\.dismiss) private var dismiss

  private struct Summary {
    var users: Int?
    var unansweredFeedback: Int?
    var openReports: Int?
  }

  var body: some View {
    List {
      activeUsersSection

      Section {
        HStack(spacing: Spacing.xs) {
          statTile("Unanswered", value: summary.unansweredFeedback, tab: .feedback)
          statTile("Open reports", value: summary.openReports, tab: .reports)
          statTile("Users", value: summary.users, tab: .users)
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
      }

      Group {
        Section("Inbox") {
          link(.feedback, count: summary.unansweredFeedback)
          link(.reports, count: summary.openReports)
        }

        Section("Insights") {
          link(.stats)
        }

        Section("People") {
          link(.users)
          link(.shares)
        }

        Section("Tools") {
          link(.broadcast)
          link(.auditLog)
        }
      }
      .listRowBackground(Color.tidexSurfacePrimary)
    }
    .tidexListBackground()
    .navigationTitle("Admin")
    .navigationBarTitleDisplayMode(.inline)
    .navigationDestination(item: $deepLinkedTab) { tab in
      AdminDestination(tab: tab, initialReportID: deepLinkedReportID)
    }
    .onChange(of: deepLinkedTab) { _, tab in
      // The deep-linked report opens once. Later taps show the plain list.
      if tab == nil { deepLinkedReportID = nil }
    }
    .refreshable { await loadSummary() }
    .task {
      if !didApplyDeepLink {
        didApplyDeepLink = true
        deepLinkedReportID = initialReportId
        deepLinkedTab = initialTab
      }
      await loadSummary()
    }
    .onChange(of: ImpersonationManager.shared.isImpersonating) { _, isImpersonating in
      // The app now runs as the target user, so leave the admin screens.
      if isImpersonating { dismiss() }
    }
  }

  private var activeUsersSection: some View {
    Section("Users who opened the app") {
      AdminActiveUsersCharts(chart: activeUsers)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }
  }

  private func link(_ tab: AdminTab, count: Int? = nil) -> some View {
    NavigationLink {
      AdminDestination(tab: tab, initialReportID: nil)
    } label: {
      LabeledContent {
        if let count, count > 0 {
          Text(count, format: .number)
            .font(.tidexCaption)
            .foregroundStyle(tab == .reports ? Color.tidexTextOnDanger : Color.tidexTextOnBrand)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, Spacing.micro)
            // The feedback tint is the light text blue, so its badge fills with the brand blue.
            .background(tab == .feedback ? Color.tidexBlue : tab.tint, in: Capsule())
        }
      } label: {
        Label {
          Text(tab.title).foregroundStyle(Color.tidexTextPrimary)
        } icon: {
          Image(systemName: tab.icon).foregroundStyle(tab.tint)
        }
      }
    }
  }

  private func statTile(_ title: String, value: Int?, tab: AdminTab) -> some View {
    Button {
      deepLinkedTab = tab
    } label: {
      AdminStatTile(title: title, value: value, icon: tab.icon, tint: tab.tint)
    }
    .buttonStyle(.plain)
  }

  private func loadSummary() async {
    async let users: AdminUsersPage? = try? AdminAPI.users(page: 1, perPage: 1, search: nil)
    async let feedback: [AdminFeedback]? = try? AdminAPI.feedback()
    async let reports: AdminReportsPage? = try? AdminAPI.reports(status: .open, limit: 1)
    async let chart: AdminActiveUsersChart? = try? AdminAPI.activeUsersChart()
    let (usersPage, feedbackItems, reportsPage, chartData) = await (users, feedback, reports, chart)
    withAnimation(reduceMotion ? nil : .default) {
      activeUsers = chartData
      summary = Summary(
        users: usersPage?.totalCount,
        unansweredFeedback: feedbackItems?.count(where: { !$0.isAnswered }),
        openReports: reportsPage?.total
      )
    }
  }
}

/// The screen for one admin tool.
private struct AdminDestination: View {
  let tab: AdminTab
  let initialReportID: String?

  var body: some View {
    switch tab {
    case .feedback: AdminFeedbackView()
    case .reports: AdminReportsView(initialReportID: initialReportID)
    case .stats: AdminStatsView()
    case .users: AdminUsersView()
    case .shares: AdminSharesView()
    case .broadcast: AdminBroadcastView()
    case .auditLog: AdminAuditLogView()
    }
  }
}

// MARK: - Shared components

/// A number with an icon and caption, shown in a row of three on the admin home and user screens.
struct AdminStatTile: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let title: String
  let value: Int?
  let icon: String
  let tint: Color

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.xxs) {
      Image(systemName: icon)
        .font(.tidexFootnoteStrong)
        .foregroundStyle(tint)
        .accessibilityHidden(true)
      Group {
        if let value {
          Text(value, format: .number).contentTransition(reduceMotion ? .identity : .numericText())
        } else {
          Text(verbatim: "–")
        }
      }
      .font(.tidexTitle)
      .foregroundStyle(Color.tidexTextPrimary)
      Text(title)
        .font(.tidexCaptionRegular)
        .foregroundStyle(Color.tidexTextSecondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(Spacing.sm)
    .background(Color.tidexSurfacePrimary, in: .rect(cornerRadius: CornerRadius.md))
    .accessibilityElement(children: .combine)
  }
}

/// Small colored capsule for statuses and roles.
struct AdminBadge: View {
  let text: String
  let color: Color

  init(_ text: String, color: Color) {
    self.text = text
    self.color = color
  }

  var body: some View {
    Text(text)
      .font(.tidexMicro.weight(.semibold))
      .foregroundStyle(color)
      .padding(.horizontal, Spacing.xxxs)
      .padding(.vertical, Spacing.micro)
      .background(color.opacity(0.15), in: Capsule())
  }
}

/// A search field row plus result rows, for picking a user inside a List or Form section.
struct AdminUserSearchRows: View {
  var excluding: Set<String> = []
  let onSelect: (AdminUser) -> Void

  @State private var query = ""
  @State private var results: [AdminUser] = []
  @State private var isSearching = false

  private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

  var body: some View {
    HStack {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(Color.tidexTextMuted)
        .accessibilityHidden(true)
      TextField("Name, email, phone or ID", text: $query)
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
      if isSearching {
        ProgressView().controlSize(.small)
      }
    }
    .task(id: trimmedQuery) { await search() }

    ForEach(results.filter { !excluding.contains($0.id) }) { user in
      Button {
        onSelect(user)
        query = ""
      } label: {
        HStack {
          AdminUserLabel(user: user)
          Spacer()
          Image(systemName: "plus.circle.fill")
            .foregroundStyle(Color.tidexBlueText)
            .accessibilityHidden(true)
        }
      }
      .buttonStyle(.plain)
    }
  }

  private func search() async {
    let query: String = trimmedQuery
    guard query.count >= 2 else {
      results = []
      return
    }
    try? await Task.sleep(for: .milliseconds(300))
    guard !Task.isCancelled else { return }
    isSearching = true
    defer { isSearching = false }
    let page: AdminUsersPage? = try? await AdminAPI.users(page: 1, perPage: 10, search: query)
    guard !Task.isCancelled else { return }
    results = page?.users ?? []
  }
}

/// Name with email or phone underneath.
struct AdminUserLabel: View {
  let user: AdminUser

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.micro) {
      Text(user.displayName)
        .font(.tidexBodyMedium)
        .foregroundStyle(Color.tidexTextPrimary)
        .lineLimit(1)
      if let contact = user.contact {
        Text(contact)
          .font(.tidexFootnote)
          .foregroundStyle(Color.tidexTextSecondary)
          .lineLimit(1)
      }
    }
  }
}

extension View {
  /// Shows `message` in an alert and clears it on dismiss.
  func adminErrorAlert(_ message: Binding<String?>) -> some View {
    alert(
      "Something went wrong",
      isPresented: Binding(
        get: { message.wrappedValue != nil }, set: { if !$0 { message.wrappedValue = nil } })
    ) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(message.wrappedValue ?? "")
    }
  }
}

/// Relative time such as "3 hours ago", or a dash when the date is missing.
struct AdminRelativeDate: View {
  let date: Date?

  var body: some View {
    if let date {
      Text(date, format: .relative(presentation: .named))
    } else {
      Text(verbatim: "–")
    }
  }
}

#Preview {
  NavigationStack {
    AdminSettingsView()
  }
}
