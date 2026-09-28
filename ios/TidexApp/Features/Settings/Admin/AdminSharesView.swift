import SwiftUI

struct AdminSharesView: View {
  @State private var query: String
  @State private var shares: [AdminShare]?
  @State private var total = 0
  @State private var pendingDelete: AdminShare?
  @State private var isCreating = false
  @State private var errorMessage: String?

  init(initialSearch: String = "") {
    _query = State(initialValue: initialSearch)
  }

  var body: some View {
    List {
      Section {
        ForEach(shares ?? []) { share in
          AdminShareRow(share: share)
            .swipeActions {
              Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = share }
            }
        }
      } header: {
        if let shares, !shares.isEmpty {
          Text(total > shares.count ? "\(shares.count) of \(total) shares" : "\(total) shares")
        }
      }
      .listRowBackground(Color.tidexSurfacePrimary)
    }
    .tidexListBackground()
    .overlay {
      if shares == nil {
        ProgressView()
      } else if shares?.isEmpty == true {
        if query.isEmpty {
          ContentUnavailableView("No shares", systemImage: "person.2.slash")
        } else {
          ContentUnavailableView.search(text: query)
        }
      }
    }
    .navigationTitle("Shares")
    .navigationBarTitleDisplayMode(.inline)
    .searchable(text: $query, prompt: "Name, email, phone or ID")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button("New share", systemImage: "plus") { isCreating = true }
      }
    }
    .sheet(isPresented: $isCreating) {
      AdminCreateShareSheet { await load() }
    }
    .confirmationDialog(
      "Delete this share?",
      isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
      titleVisibility: .visible,
      presenting: pendingDelete
    ) { share in
      Button("Delete", role: .destructive) { delete(share) }
    } message: { share in
      Text("\(share.viewerDisplayName) will no longer see \(share.ownerDisplayName)'s shifts.")
    }
    .task(id: query) {
      if shares != nil {
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
      }
      await load()
    }
    .refreshable { await load() }
    .adminErrorAlert($errorMessage)
  }

  private func load() async {
    do {
      let page: AdminSharesPage = try await AdminAPI.shares(search: query.nilIfBlank)
      guard !Task.isCancelled else { return }
      shares = page.shares ?? []
      total = page.totalCount ?? 0
    } catch {
      guard !Task.isCancelled else { return }
      shares = shares ?? []
      errorMessage = error.localizedDescription
    }
  }

  private func delete(_ share: AdminShare) {
    Task {
      do {
        try await AdminAPI.deleteShare(id: share.id)
        Haptics.play(.success)
        withAnimation { shares?.removeAll { $0.id == share.id } }
        total -= 1
      } catch {
        Haptics.play(.error)
        errorMessage = error.localizedDescription
      }
    }
  }
}

private struct AdminShareRow: View {
  let share: AdminShare

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.xxs) {
      HStack(spacing: Spacing.xxs) {
        Text(share.ownerDisplayName)
          .foregroundStyle(Color.tidexTextPrimary)
        Image(systemName: "arrow.right")
          .font(.tidexCaptionStrong)
          .foregroundStyle(Color.tidexTextMuted)
          .accessibilityLabel("shares with")
        Text(share.viewerDisplayName)
          .foregroundStyle(Color.tidexTextPrimary)
      }
      .font(.tidexLabel)
      .lineLimit(1)

      HStack(spacing: Spacing.xxs) {
        if share.showEarnings {
          AdminBadge("Earnings", color: .tidexSuccess)
        }
        if share.blocked {
          AdminBadge("Hidden", color: .tidexError)
        }
        if share.muted {
          AdminBadge("Muted", color: .tidexWarning)
        }
        Spacer()
        AdminRelativeDate(date: share.created)
          .font(.tidexMicro)
          .foregroundStyle(Color.tidexTextMuted)
      }
    }
    .padding(.vertical, Spacing.micro)
  }
}

private struct AdminCreateShareSheet: View {
  let onCreated: () async -> Void

  @State private var owner: AdminUser?
  @State private var viewer: AdminUser?
  @State private var showEarnings = true
  @State private var isSaving = false
  @State private var errorMessage: String?
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        Group {
          pickerSection(
            "Owner", footer: "The person whose shifts are shared.", selection: $owner, other: viewer
          )
          pickerSection(
            "Viewer", footer: "The person who sees the owner's shifts.", selection: $viewer,
            other: owner)
          Section {
            Toggle("Show earnings", isOn: $showEarnings)
          }
        }
        .listRowBackground(Color.tidexSurfacePrimary)
      }
      .tidexListBackground()
      .navigationTitle("New share")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", role: .cancel) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          if isSaving {
            ProgressView()
          } else {
            Button("Create", action: create).disabled(owner == nil || viewer == nil)
          }
        }
      }
      .adminErrorAlert($errorMessage)
    }
  }

  private func pickerSection(
    _ title: String, footer: String, selection: Binding<AdminUser?>, other: AdminUser?
  ) -> some View {
    Section {
      if let user = selection.wrappedValue {
        HStack {
          AdminUserLabel(user: user)
          Spacer()
          Button("Change", systemImage: "xmark.circle.fill") { selection.wrappedValue = nil }
            .labelStyle(.iconOnly)
            .foregroundStyle(Color.tidexTextMuted)
            .buttonStyle(.plain)
        }
      } else {
        AdminUserSearchRows(excluding: Set([other?.id].compactMap { $0 })) {
          selection.wrappedValue = $0
        }
      }
    } header: {
      Text(title)
    } footer: {
      Text(footer)
    }
  }

  private func create() {
    guard let owner, let viewer else { return }
    Task {
      isSaving = true
      defer { isSaving = false }
      do {
        try await AdminAPI.createShare(
          ownerID: owner.id, viewerID: viewer.id, showEarnings: showEarnings)
        Haptics.play(.success)
        await onCreated()
        dismiss()
      } catch {
        Haptics.play(.error)
        errorMessage = error.localizedDescription
      }
    }
  }
}
