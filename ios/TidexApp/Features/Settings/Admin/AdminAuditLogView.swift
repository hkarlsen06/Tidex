import SwiftUI

struct AdminAuditLogView: View {
  /// Shows only entries about this user when set.
  var targetUserID: String?

  @State private var entries: [AdminAuditEntry]?
  @State private var query = ""
  @State private var errorMessage: String?

  private struct Day: Identifiable {
    let day: Date
    let entries: [AdminAuditEntry]

    var id: Date { day }
  }

  private var days: [Day] {
    let matches: [AdminAuditEntry] = (entries ?? []).filter { entry in
      query.isEmpty
        || [entry.action.adminHumanized, entry.adminEmail, entry.targetEmail]
          .contains { $0?.localizedStandardContains(query) == true }
    }
    let grouped: [Date: [AdminAuditEntry]] = Dictionary(grouping: matches) { entry in
      Calendar.current.startOfDay(for: entry.created ?? .distantPast)
    }
    return grouped.keys.sorted(by: >).map { Day(day: $0, entries: grouped[$0] ?? []) }
  }

  var body: some View {
    List {
      ForEach(days) { day in
        Section {
          ForEach(day.entries) { AdminAuditRow(entry: $0) }
        } header: {
          Text(day.day, format: .dateTime.weekday(.wide).day().month().year())
        }
        .listRowBackground(Color.tidexSurfacePrimary)
      }
    }
    .tidexListBackground()
    .overlay {
      if entries == nil {
        ProgressView()
      } else if days.isEmpty {
        if query.isEmpty {
          ContentUnavailableView("No audit entries", systemImage: "list.bullet.rectangle")
        } else {
          ContentUnavailableView.search(text: query)
        }
      }
    }
    .navigationTitle(targetUserID == nil ? "Audit log" : "Audit history")
    .navigationBarTitleDisplayMode(.inline)
    .searchable(
      text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Action or email"
    )
    .task { await load() }
    .refreshable { await load() }
    .adminErrorAlert($errorMessage)
  }

  private func load() async {
    do {
      entries = try await AdminAPI.auditLog(targetUserID: targetUserID)
    } catch {
      entries = entries ?? []
      errorMessage = error.localizedDescription
    }
  }
}

private struct AdminAuditRow: View {
  let entry: AdminAuditEntry

  private var icon: String {
    let action: String = entry.action
    if action.contains("ban") { return "nosign" }
    if action.contains("admin") { return "shield.lefthalf.filled" }
    if action.contains("impersonat") { return "person.crop.circle.badge.questionmark" }
    if action.contains("share") { return "person.2" }
    if action.contains("broadcast") { return "megaphone" }
    return "circle.fill"
  }

  var body: some View {
    DisclosureGroup {
      ForEach(entry.metadataRows, id: \.key) { row in
        LabeledContent(row.key) {
          Text(row.value)
            .font(.tidexMonoCaptionRegular)
            .multilineTextAlignment(.trailing)
            .textSelection(.enabled)
        }
        .font(.tidexFootnote)
      }
      if entry.metadataRows.isEmpty {
        Text("No details").font(.tidexFootnote).foregroundStyle(Color.tidexTextMuted)
      }
    } label: {
      HStack(alignment: .top, spacing: Spacing.sm) {
        Image(systemName: icon)
          .foregroundStyle(Color.tidexTextSecondary)
          .frame(width: Spacing.iconSize)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: Spacing.micro) {
          Text(entry.action.adminHumanized)
            .font(.tidexLabelStrong)
            .foregroundStyle(Color.tidexTextPrimary)
          if let target = entry.targetEmail?.nilIfBlank {
            Text(target)
              .font(.tidexFootnote)
              .foregroundStyle(Color.tidexTextSecondary)
          }
          HStack(spacing: Spacing.xxs) {
            Text(entry.adminEmail ?? "System")
            if let created = entry.created {
              Text(created, format: .dateTime.hour().minute())
            }
          }
          .font(.tidexMicro)
          .foregroundStyle(Color.tidexTextMuted)
        }
      }
    }
  }
}
