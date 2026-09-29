import SwiftUI

/// Lists offline edits that ended in a sync conflict and lets the user pick a version.
struct SyncConflictsView: View {
  @State private var viewModel = SyncConflictsViewModel()
  @State private var pendingDiscard: SyncConflictRow?

  var body: some View {
    List {
      Group {
        if let error = viewModel.errorMessage {
          Section {
            ErrorBanner(message: error, onDismiss: { viewModel.errorMessage = nil })
          }
        }

        ForEach(viewModel.rows) { row in
          conflictSection(row)
        }

        if !viewModel.rows.isEmpty {
          Text(.syncConflictsIntro)
            .font(.tidexFootnote)
            .foregroundColor(.tidexTextSecondary)
            .listRowBackground(Color.clear)
        }
      }
      .listRowBackground(Color.tidexSurfacePrimary)
    }
    .tidexListBackground()
    .overlay {
      if !viewModel.isLoading, viewModel.rows.isEmpty {
        ContentUnavailableView {
          Label(String(localized: .syncConflictsEmpty), systemImage: "checkmark.circle")
        }
      }
    }
    .navigationTitle(String(localized: .syncConflictsTitle))
    .navigationBarTitleDisplayMode(.inline)
    .task {
      await viewModel.load()
    }
    .confirmationDialog(
      Text(.syncConflictsDiscardWarning),
      isPresented: Binding(
        get: { pendingDiscard != nil },
        set: { if !$0 { pendingDiscard = nil } }
      ),
      titleVisibility: .visible,
      presenting: pendingDiscard
    ) { row in
      Button(discardLabel(for: row), role: .destructive) {
        resolve(row, .keepServer)
      }
    }
  }

  private func conflictSection(_ row: SyncConflictRow) -> some View {
    Section {
      VStack(alignment: .leading, spacing: Spacing.xxs) {
        Text(verbatim: row.title)
          .font(.tidexBodyMedium)
          .foregroundColor(.tidexTextPrimary)

        if let detail = row.detail {
          Text(verbatim: detail)
            .font(.tidexFootnote)
            .foregroundColor(.tidexTextSecondary)
        }

        if !row.hasServerVersion {
          Text(.syncConflictsRejected)
            .font(.tidexFootnote)
            .foregroundColor(.tidexTextSecondary)
        }
      }
      .padding(.vertical, Spacing.xxxs)

      Button(keepLabel(for: row)) {
        resolve(row, .keepLocal)
      }

      Button(discardLabel(for: row), role: row.hasServerVersion ? nil : .destructive) {
        pendingDiscard = row
      }
    }
    .disabled(viewModel.resolvingId != nil)
    .tint(.tidexBlue)
  }

  private func keepLabel(for row: SyncConflictRow) -> LocalizedStringResource {
    row.hasServerVersion ? .syncConflictsKeepMine : .commonRetry
  }

  private func discardLabel(for row: SyncConflictRow) -> LocalizedStringResource {
    row.hasServerVersion ? .syncConflictsUseOther : .syncConflictsDiscard
  }

  private func resolve(_ row: SyncConflictRow, _ resolution: ConflictResolution) {
    Task {
      await viewModel.resolve(row, resolution)
    }
  }
}
