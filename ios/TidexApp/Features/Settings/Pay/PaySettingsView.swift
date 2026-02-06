import SwiftUI

// MARK: - Pay Settings View

/// Main pay settings screen displaying wage history timeline and global settings
struct PaySettingsView: View {
  @StateObject private var viewModel = PaySettingsViewModel()

  var body: some View {
    ZStack {
      Color.tidexBackground
        .ignoresSafeArea()

      if viewModel.isLoading && viewModel.snapshots.isEmpty {
        // Initial loading state
        loadingView
      } else {
        // Main content
        mainContent
      }
    }
    .navigationTitle(String(localized: .settingsPayTitle))
    .navigationBarTitleDisplayMode(.inline)
    .sheet(isPresented: $viewModel.showingEditor) {
      WageSnapshotEditorSheet(
        mode: viewModel.editorMode,
        snapshot: viewModel.selectedSnapshot,
        mostRecentSnapshot: viewModel.snapshots.first,
        userCurrency: viewModel.userCurrency,
        onSave: { input in
          if viewModel.editorMode == .create {
            return await viewModel.createSnapshot(input: input)
          } else if let snapshot = viewModel.selectedSnapshot {
            return await viewModel.updateSnapshot(id: snapshot.id, input: input)
          }
          return false
        },
        onDelete: { snapshot in
          viewModel.requestDelete(snapshot: snapshot)
        },
        onCancel: {
          viewModel.closeEditor()
        }
      )
    }
    .confirmationDialog(
      String(localized: .settingsPayDeleteConfirmTitle),
      isPresented: $viewModel.showingDeleteConfirmation,
      titleVisibility: .visible
    ) {
      Button(role: .destructive) {
        Task { await viewModel.confirmDelete() }
      } label: {
        Text(.commonDelete)
      }

      Button(role: .cancel) {
        viewModel.cancelDelete()
      } label: {
        Text(.commonCancel)
      }
    } message: {
      Text(deleteConfirmationMessage)
    }
    .alert(
      String(localized: .commonError),
      isPresented: .init(
        get: { viewModel.errorMessage != nil },
        set: { if !$0 { viewModel.clearMessages() } }
      )
    ) {
      Button(String(localized: .commonOk)) {
        viewModel.clearMessages()
      }
    } message: {
      if let error = viewModel.errorMessage {
        Text(error)
      }
    }
    .task {
      await viewModel.loadData()
    }
  }

  // MARK: - Loading View

  @ViewBuilder
  private var loadingView: some View {
    VStack(spacing: 16) {
      ProgressView()
        .progressViewStyle(CircularProgressViewStyle(tint: .tidexBrandPrimary))

      Text(.commonLoading)
        .font(.system(size: 14))
        .foregroundColor(.tidexTextSecondary)
    }
  }

  // MARK: - Main Content

  @ViewBuilder
  private var mainContent: some View {
    ScrollView {
      VStack(spacing: 24) {
        // Wage History Timeline
        WageHistoryTimelineView(
          entries: viewModel.timelineEntries,
          onAddNew: { viewModel.openCreateEditor() },
          onEdit: { snapshot in viewModel.openEditEditor(snapshot: snapshot) }
        )
        .padding(.horizontal, 16)

        // Tip box
        tipBox
          .padding(.horizontal, 16)

        // Divider
        Divider()
          .padding(.horizontal, 32)

        // Global Pay Settings
        GlobalPaySettingsCard(
          settings: viewModel.globalSettings,
          canChangeCurrency: viewModel.canChangeCurrency,
          onUpdateMonthlyGoal: { viewModel.updateMonthlyGoal($0) },
          onUpdatePayrollDay: { viewModel.updatePayrollDay($0) },
          onUpdateHalfTaxMonth: { value in
            await viewModel.updateHalfTaxMonth(value)
          },
          onUpdateCurrency: { value in
            await viewModel.updateCurrency(value)
          }
        )
        .padding(.horizontal, 16)

        // Bottom padding
        Spacer()
          .frame(height: 40)
      }
      .padding(.vertical, 24)
    }
    .refreshable {
      await viewModel.loadData()
    }
  }

  // MARK: - Tip Box

  private var tipText: AttributedString {
    let tipLabel = String(localized: .settingsPayTimelineTipLabel)
    let infoTip = String(localized: .settingsPayTimelineInfoTip)

    var result = AttributedString("\(tipLabel) \(infoTip)")

    // Make the tip label bold
    if let range = result.range(of: tipLabel) {
      result[range].font = .system(size: 14, weight: .semibold)
    }

    return result
  }

  @ViewBuilder
  private var tipBox: some View {
    Text(tipText)
      .font(.system(size: 14))
      .foregroundColor(.tidexBlue)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(16)
      .background(Color.tidexBlue.opacity(0.1))
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  // MARK: - Delete Confirmation Message

  private var deleteConfirmationMessage: String {
    let count = viewModel.affectedShiftCount

    if count == 0 {
      return String(localized: .settingsPayDeleteConfirmation)
    } else {
      return String(localized: .settingsPayDeleteConfirmationWithShifts(Int(count)))
    }
  }
}

// MARK: - Preview

#Preview {
  NavigationStack {
    PaySettingsView()
  }
}
