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

        if let note = report.note?.nilIfBlank {
          Section("Reporter's note") {
            Text(note).textSelection(.enabled)
          }
        }

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
    .adminErrorAlert($errorMessage)
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
