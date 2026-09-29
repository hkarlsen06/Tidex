import SwiftUI

struct AdminReportsView: View {
  /// Report to open once the list loads, from a push notification deep link.
  var initialReportID: String?

  @State private var reports: [AdminReport]?
  @State private var total = 0
  /// `nil` shows every status.
  @State private var status: AdminReportStatus?
  @State private var openedReport: AdminReport?
  @State private var didOpenInitialReport = false
  @State private var errorMessage: String?

  init(initialReportID: String? = nil) {
    self.initialReportID = initialReportID
    // The linked report may already be reviewed, so don't hide it behind the default filter.
    _status = State(initialValue: initialReportID == nil ? .open : nil)
  }

  var body: some View {
    List {
      Section {
        ForEach(reports ?? []) { report in
          Button {
            openedReport = report
          } label: {
            AdminReportRow(report: report)
          }
          .buttonStyle(.plain)
        }
      } header: {
        if reports != nil {
          Text("\(total) \(status?.title.lowercased() ?? "total")")
        }
      }
      .listRowBackground(Color.tidexSurfacePrimary)
    }
    .tidexListBackground()
    .overlay {
      if reports == nil {
        ProgressView()
      } else if reports?.isEmpty == true {
        ContentUnavailableView(
          status == .open ? "No open reports" : "No reports", systemImage: "flag.slash")
      }
    }
    .navigationTitle("Reports")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          Picker("Status", selection: $status) {
            Text("All").tag(AdminReportStatus?.none)
            ForEach(AdminReportStatus.allCases) { Text($0.title).tag(Optional($0)) }
          }
        } label: {
          Label("Filter", systemImage: "line.3.horizontal.decrease")
        }
      }
    }
    .navigationDestination(item: $openedReport) { report in
      AdminReportDetailView(report: report) { await load() }
    }
    .task(id: status) { await load() }
    .refreshable { await load() }
    .adminErrorAlert($errorMessage)
  }

  private func load() async {
    do {
      let page: AdminReportsPage = try await AdminAPI.reports(status: status)
      guard !Task.isCancelled else { return }
      reports = page.reports
      total = page.total
      if !didOpenInitialReport, let initialReportID {
        didOpenInitialReport = true
        openedReport = page.reports.first { $0.id == initialReportID }
      }
    } catch {
      guard !Task.isCancelled else { return }
      reports = reports ?? []
      errorMessage = error.localizedDescription
    }
  }
}

extension AdminReportStatus {
  var color: Color {
    switch self {
    case .open: return .tidexWarning
    case .inReview: return .tidexBlue
    case .actioned: return .tidexSuccess
    case .dismissed: return .tidexTextMuted
    }
  }
}

private struct AdminReportRow: View {
  let report: AdminReport

  var body: some View {
    HStack(alignment: .top, spacing: Spacing.sm) {
      Image(systemName: report.messageId == nil ? "person.fill.xmark" : "text.bubble.fill")
        .foregroundStyle(report.status.color)
        .frame(width: Spacing.iconSize)
        .accessibilityLabel(report.messageId == nil ? "User report" : "Message report")
      VStack(alignment: .leading, spacing: Spacing.xxs) {
        HStack(alignment: .firstTextBaseline) {
          Text(report.reasonTitle)
            .font(.tidexLabelStrong)
            .foregroundStyle(Color.tidexTextPrimary)
          Spacer()
          AdminBadge(report.status.title, color: report.status.color)
        }
        Text("\(report.reporterDisplayName) → \(report.reportedDisplayName)")
          .font(.tidexFootnote)
          .foregroundStyle(Color.tidexTextSecondary)
          .lineLimit(1)
        if let note = report.note?.nilIfBlank {
          Text(note)
            .font(.tidexFootnote)
            .foregroundStyle(Color.tidexTextMuted)
            .lineLimit(2)
        }
        AdminRelativeDate(date: report.created)
          .font(.tidexMicro)
          .foregroundStyle(Color.tidexTextMuted)
      }
    }
    .padding(.vertical, Spacing.xxs)
    .contentShape(.rect)
  }
}

private struct AdminReportDetailView: View {
  let report: AdminReport
  let onSaved: () async -> Void

  @State private var status: AdminReportStatus
  @State private var notes: String
  @State private var isSaving = false
  @State private var errorMessage: String?
  @State private var messages: [FriendMessage]?
  @State private var reportedAvatarUrl: String?
  @State private var reporter: AdminUser?
  @State private var reported: AdminUser?
  @State private var viewerIsSuperadmin = false
  @State private var isWorking = false
  @State private var confirmBan = false
  @State private var confirmDelete = false
  @Environment(\.dismiss) private var dismiss

  init(report: AdminReport, onSaved: @escaping () async -> Void) {
    self.report = report
    self.onSaved = onSaved
    _status = State(initialValue: report.status)
    _notes = State(initialValue: report.reviewerNotes ?? "")
  }

  private var hasChanges: Bool {
    status != report.status
      || notes.trimmingCharacters(in: .whitespacesAndNewlines) != (report.reviewerNotes ?? "")
  }

  var body: some View {
    List {
      Group {
        summarySection

        conversationSection

        if let note = report.note?.nilIfBlank {
          Section("Reporter's note") {
            Text(note).textSelection(.enabled)
          }
        }

        actionsSection

        Section("Review") {
          Picker("Status", selection: $status) {
            ForEach(AdminReportStatus.allCases) { Text($0.title).tag($0) }
          }
          TextField("Reviewer notes", text: $notes, axis: .vertical)
            .lineLimit(3...10)
        }

        Section("IDs") {
          idRow("Reporter", report.reporterUserId)
          idRow("Reported", report.reportedUserId)
          idRow("Thread", report.threadId)
          if let messageId = report.messageId {
            idRow("Message", messageId)
          }
        }
      }
      .listRowBackground(Color.tidexSurfacePrimary)
    }
    .tidexListBackground()
    .navigationTitle("Report")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        if isSaving {
          ProgressView()
        } else {
          Button("Save", action: save).disabled(!hasChanges)
        }
      }
    }
    .disabled(isWorking)
    .task { await load() }
    .adminErrorAlert($errorMessage)
    .confirmationDialog(
      "Delete this message?", isPresented: $confirmDelete, titleVisibility: .visible
    ) {
      Button("Delete message", role: .destructive, action: deleteMessage)
    } message: {
      Text("It disappears for both users. It stays visible here, dimmed.")
    }
    .confirmationDialog(
      reported?.isBanned == true
        ? "Unban \(report.reportedDisplayName)?" : "Ban \(report.reportedDisplayName)?",
      isPresented: $confirmBan,
      titleVisibility: .visible
    ) {
      Button(
        reported?.isBanned == true ? "Unban" : "Ban",
        role: reported?.isBanned == true ? nil : .destructive,
        action: toggleBan)
    } message: {
      Text(
        reported?.isBanned == true
          ? "They can sign in again." : "They are signed out and can't sign in.")
    }
  }

  private var conversationSection: some View {
    Section("Conversation") {
      if let messages {
        if messages.isEmpty {
          Text("No messages").foregroundStyle(Color.tidexTextMuted)
        } else {
          AdminReportConversation(
            messages: messages, report: report, reportedAvatarUrl: reportedAvatarUrl)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
      } else {
        ProgressView().frame(maxWidth: .infinity)
      }
    }
  }

  private var reportedMessageIsDeleted: Bool {
    messages?.first { $0.id == report.messageId }?.deletedAt != nil
  }

  private var actionsSection: some View {
    Section("Actions") {
      if report.messageId != nil, messages != nil, !reportedMessageIsDeleted {
        Button("Delete message", systemImage: "trash") { confirmDelete = true }
          .foregroundStyle(Color.tidexError)
      }
      if let reported {
        NavigationLink {
          AdminBroadcastView(recipient: reported)
        } label: {
          Label("Send notification", systemImage: "bell.badge")
        }
        // The server refuses to ban admins.
        if !reported.isSuperAdmin, !reported.isAdmin || reported.isBanned {
          Button(
            reported.isBanned ? "Unban \(reported.displayName)" : "Ban \(reported.displayName)",
            systemImage: "nosign"
          ) {
            confirmBan = true
          }
          .foregroundStyle(reported.isBanned ? Color.tidexBlue : Color.tidexError)
        }
        userLink("Reported user", reported) { self.reported = $0 }
      }
      if let reporter {
        userLink("Reporter", reporter) { self.reporter = $0 }
      }
    }
  }

  private func userLink(
    _ title: String, _ user: AdminUser, onChange: @escaping (AdminUser) -> Void
  ) -> some View {
    NavigationLink {
      AdminUserDetailView(user: user, viewerIsSuperadmin: viewerIsSuperadmin, onChange: onChange)
    } label: {
      LabeledContent(title, value: user.displayName)
    }
  }

  private func load() async {
    async let loadedMessages = AdminAPI.reportMessages(id: report.id)
    async let loadedReporter = Self.user(id: report.reporterUserId)
    async let loadedReported = Self.user(id: report.reportedUserId)
    viewerIsSuperadmin = await AdminAPI.currentUserIsSuperadmin()
    do {
      let page = try await loadedMessages
      messages = page.friendMessages
      reportedAvatarUrl = page.reportedAvatarUrl
      reporter = try await loadedReporter
      reported = try await loadedReported
    } catch {
      guard !Task.isCancelled else { return }
      messages = messages ?? []
      errorMessage = error.localizedDescription
    }
  }

  private static func user(id: String) async throws -> AdminUser? {
    try await AdminAPI.users(page: 1, perPage: 1, search: id).users.first { $0.id == id }
  }

  private func deleteMessage() {
    guard let messageId = report.messageId else { return }
    run {
      try await AdminAPI.deleteMessage(id: messageId)
      status = .actioned
      messages = try await AdminAPI.reportMessages(id: report.id).friendMessages
    }
  }

  private func toggleBan() {
    guard let user = reported else { return }
    run {
      try await AdminAPI.setBanned(!user.isBanned, for: user)
      reported?.isBanned.toggle()
      if !user.isBanned {
        status = .actioned
      }
    }
  }

  /// Runs a moderation action. Actions that act on the report set the status to Actioned;
  /// Save stores it with the notes.
  private func run(_ work: @escaping () async throws -> Void) {
    Task {
      isWorking = true
      defer { isWorking = false }
      do {
        try await work()
        Haptics.play(.success)
      } catch {
        Haptics.play(.error)
        errorMessage = AdminError(error).message
      }
    }
  }

  private var summarySection: some View {
    Section {
      LabeledContent("Reason", value: report.reasonTitle)
      LabeledContent("Reporter", value: report.reporterDisplayName)
      LabeledContent("Reported", value: report.reportedDisplayName)
      LabeledContent("Type", value: report.messageId == nil ? "User" : "Message")
      if let created = report.created {
        LabeledContent("Created") { Text(created, format: .dateTime.day().month().hour().minute()) }
      }
      if let reviewed = report.reviewed {
        LabeledContent("Reviewed") {
          Text(reviewed, format: .dateTime.day().month().hour().minute())
        }
      }
    }
  }

  private func idRow(_ title: String, _ value: String) -> some View {
    LabeledContent(title) {
      Text(value)
        .font(.tidexMonoCaptionRegular)
        .lineLimit(1)
        .truncationMode(.middle)
        .textSelection(.enabled)
    }
  }

  private func save() {
    Task {
      isSaving = true
      defer { isSaving = false }
      do {
        try await AdminAPI.updateReport(id: report.id, status: status, reviewerNotes: notes)
        Haptics.play(.success)
        await onSaved()
        dismiss()
      } catch {
        Haptics.play(.error)
        errorMessage = error.localizedDescription
      }
    }
  }
}
