import SwiftUI

// MARK: - Pay Settings View

/// Main pay settings screen displaying wage history timeline and global settings
struct PaySettingsView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var viewModel: PaySettingsViewModel
  @State private var showingEditJobSheet = false
  @State private var paySetupJob: Job?
  @State private var showingArchiveConfirmation = false
  @State private var isPayReviewExpanded: Bool
  @ScaledMetric(relativeTo: .body) private var actionIconWidth: CGFloat = 22
  /// Shifts open this screen to check a date, so the date review goes above the history.
  private let showsReviewFirst: Bool

  init(
    initialJobId: String? = nil, initialDate: Date = Date(),
    initiallyExpandPayReview: Bool = false
  ) {
    _isPayReviewExpanded = State(initialValue: initiallyExpandPayReview)
    showsReviewFirst = initiallyExpandPayReview
    _viewModel = State(
      wrappedValue: PaySettingsViewModel(
        initialSelectedJobId: initialJobId, initialDate: initialDate
      ))
  }

  var body: some View {
    ZStack {
      Color.tidexBackground
        .ignoresSafeArea()

      if viewModel.isLoading, viewModel.snapshots.isEmpty {
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
      editorSheetContent
    }
    .sheet(item: $paySetupJob) { job in
      JobPaySetupSheet(
        job: job,
        initialCurrency: viewModel.userCurrency
      ) { input in
        await viewModel.completePaySetup(for: job, input: input)
      }
    }
    .sheet(isPresented: $showingEditJobSheet) {
      if let job = viewModel.selectedJob {
        EditWorkplaceSheet(
          initialName: job.name,
          initialColorHex: job.color
        ) { name, color in
          await viewModel.updateSelectedJobMetadata(name: name, color: color)
        }
      }
    }
    .sheet(
      isPresented: Binding(
        get: { viewModel.shouldRequireJobReselectionSheet },
        set: { _ in }
      )
    ) {
      RequiredJobReselectionSheet(
        jobs: viewModel.activeJobs,
        onSelect: { viewModel.resolveRequiredJobSelection($0) }
      )
      .interactiveDismissDisabled(true)
    }
    .confirmationDialog(
      String(localized: .settingsPayJobActionsArchiveConfirmTitle),
      isPresented: $showingArchiveConfirmation,
      titleVisibility: .visible
    ) {
      Button(String(localized: .settingsPayJobActionsArchive)) {
        Task {
          if await viewModel.archiveSelectedJob() {
            dismiss()
          }
        }
      }

      Button(role: .cancel) {
      } label: {
        Text(.commonCancel)
      }
    } message: {
      Text(.settingsPayJobActionsArchiveConfirmMessage)
    }
    .alert(
      viewModel.errorTitle ?? String(localized: .commonError),
      isPresented: .init(
        get: { viewModel.errorMessage != nil && !viewModel.showingEditor },
        set: { if !$0 { viewModel.clearError() } }
      )
    ) {
      Button(String(localized: .commonOk)) {
        viewModel.clearError()
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

}

extension PaySettingsView {
  @ViewBuilder
  private var editorSheetContent: some View {
    WageSnapshotEditorSheet(
      mode: viewModel.editorMode,
      snapshot: viewModel.selectedSnapshot,
      snapshots: viewModel.snapshots,
      initialDate: viewModel.reviewDate,
      userCurrency: viewModel.userCurrency,
      saveError: viewModel.errorMessage,
      initialSection: viewModel.editorSection,
      onSave: { input in
        if viewModel.editorMode == .create {
          return await viewModel.createSnapshot(input: input)
        }
        if let snapshot = viewModel.selectedSnapshot {
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
  }

  // MARK: - Loading View

  @ViewBuilder
  private var loadingView: some View {
    VStack(spacing: Spacing.md) {
      ProgressView()
        .progressViewStyle(CircularProgressViewStyle(tint: .tidexBrandPrimary))

      Text(.commonLoading)
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextSecondary)
    }
  }

  // MARK: - Main Content

  @ViewBuilder
  private var mainContent: some View {
    ScrollView {
      VStack(spacing: Spacing.lg) {
        if viewModel.shouldShowWorkplaceHeader {
          PaySettingsJobHeader(
            name: viewModel.selectedJobName,
            colorHex: viewModel.selectedJob?.color,
            isDefault: viewModel.isSelectedJobDefault,
            isConfigured: viewModel.isSelectedJobConfigured
          )
        }

        if viewModel.isSelectedJobConfigured {
          if showsReviewFirst {
            reviewCard
            wageHistory
          } else {
            wageHistory
            reviewCard
          }

          globalPaySettingsCard
        } else {
          finishPaySetupPanel
        }

        jobActionsPanel

        // Bottom padding
        Spacer()
          .frame(height: Spacing.xxl)
      }
      .padding(.horizontal, Spacing.md)
      .padding(.vertical, Spacing.lg)
    }
  }

  private var globalPaySettingsCard: some View {
    GlobalPaySettingsCard(
      jobId: viewModel.selectedJobId,
      currency: viewModel.userCurrency,
      payrollDay: viewModel.selectedJobPayrollDay,
      halfTaxMonth: viewModel.selectedJobHalfTaxMonth,
      canChangeCurrency: viewModel.canChangeCurrency,
      onUpdatePayrollDay: { viewModel.updatePayrollDay($0) },
      onUpdateHalfTaxMonth: { value in
        await viewModel.updateHalfTaxMonth(value)
      },
      onUpdateCurrency: { value in
        await viewModel.updateCurrency(value)
      },
      payPeriod: viewModel.selectedJobPayPeriod,
      onUpdatePayPeriod: { value in
        await viewModel.updatePayPeriod(value)
      }
    )
  }

  private var reviewCard: some View {
    PaySettingsReviewCard(
      isExpanded: $isPayReviewExpanded,
      workDate: $viewModel.reviewDate,
      snapshots: viewModel.snapshots,
      currency: viewModel.userCurrency,
      payrollDay: viewModel.selectedJobPayrollDay,
      halfTaxMonth: viewModel.selectedJobHalfTaxMonth,
      payPeriod: viewModel.selectedJobPayPeriod,
      onEdit: { viewModel.openEditEditor(snapshot: $0, section: $1) }
    )
  }

  private var wageHistory: some View {
    WageHistoryTimelineView(
      entries: viewModel.timelineEntries,
      currency: viewModel.userCurrency,
      onAddNew: { viewModel.openCreateEditor() },
      onEdit: { snapshot in viewModel.openEditEditor(snapshot: snapshot) }
    )
  }

  private var finishPaySetupPanel: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      Image(systemName: "exclamationmark.circle.fill")
        .font(.tidexTitle)
        .foregroundColor(.tidexWarning)
        .accessibilityHidden(true)

      Text(.settingsPaySetupFinishTitle)
        .font(.tidexTitle)
        .foregroundColor(.tidexTextPrimary)

      Text(.settingsPaySetupFinishDescription)
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextSecondary)

      Button {
        paySetupJob = viewModel.selectedJob
      } label: {
        Text(.settingsPaySetupFinishButton)
          .font(.tidexLabelStrong)
          .foregroundColor(.tidexTextOnBrand)
          .frame(maxWidth: .infinity)
          .padding(.vertical, Spacing.sm)
          .background(Color.tidexBlue)
          .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
      }
      .buttonStyle(.plain)
      .disabled(viewModel.selectedJob == nil)
    }
    .padding(Spacing.md)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.tidexSurfacePrimary)
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
  }

  @ViewBuilder
  private var jobActionsPanel: some View {
    if viewModel.selectedJob != nil {
      PaySettingsSection(
        title: .settingsPayJobActionsTitle,
        footer: viewModel.selectedJobManagementHint.map { Text($0) }
      ) {
        editJobButton

        jobActionDivider

        if !viewModel.isSelectedJobDefault {
          setDefaultButton

          jobActionDivider
        }

        archiveJobButton
      }
    }
  }

  private var editJobButton: some View {
    Button {
      showingEditJobSheet = true
    } label: {
      jobActionRow(
        icon: "pencil",
        title: String(localized: .settingsPayEditJobTitle),
        tint: .tidexBlueText
      )
    }
    .buttonStyle(.plain)
  }

  private var setDefaultButton: some View {
    Button {
      Task {
        await viewModel.setSelectedJobAsDefault()
      }
    } label: {
      jobActionRow(
        icon: "checkmark.circle",
        title: String(localized: .settingsPayJobActionsSetDefault),
        tint: .tidexBlueText,
        isEnabled: viewModel.canSetSelectedJobAsDefault
          && !viewModel.isProcessingJobAction
      )
    }
    .buttonStyle(.plain)
    .disabled(!viewModel.canSetSelectedJobAsDefault || viewModel.isProcessingJobAction)
  }

  private var archiveJobButton: some View {
    Button {
      showingArchiveConfirmation = true
    } label: {
      jobActionRow(
        icon: "archivebox",
        title: String(localized: .settingsPayJobActionsArchive),
        tint: .tidexTextPrimary,
        isEnabled: viewModel.canArchiveSelectedJob && !viewModel.isProcessingJobAction
      )
    }
    .buttonStyle(.plain)
    .disabled(!viewModel.canArchiveSelectedJob || viewModel.isProcessingJobAction)
  }

  /// Starts under the row titles, past the icon column.
  private var jobActionDivider: some View {
    Divider()
      .padding(.leading, Spacing.md + actionIconWidth + Spacing.sm)
  }

  private func jobActionRow(
    icon: String,
    title: String,
    tint: Color,
    isEnabled: Bool = true
  ) -> some View {
    HStack(spacing: Spacing.sm) {
      Image(systemName: icon)
        .font(.tidexBodyMedium)
        .foregroundColor(tint)
        .frame(width: actionIconWidth)

      Text(title)
        .font(.tidexBodyMedium)
        .foregroundColor(tint)

      Spacer()
    }
    .padding(.horizontal, Spacing.md)
    .frame(minHeight: 52)
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
    .opacity(isEnabled ? 1 : 0.45)
  }

  // MARK: - Delete Confirmation Message

  private var deleteConfirmationMessage: String {
    let count = viewModel.affectedShiftCount
    let confirmation =
      count == 0
      ? String(localized: .settingsPayDeleteConfirmation)
      : String(localized: .settingsPayDeleteConfirmationWithShifts(Int(count)))
    return confirmation + "\n\n" + String(localized: .settingsPayDeleteImpact)
  }
}

// MARK: - Preview

#Preview {
  NavigationStack {
    PaySettingsView()
  }
}
