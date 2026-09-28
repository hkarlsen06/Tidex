import SwiftUI
import UIKit

// MARK: - Pay Settings View

/// Main pay settings screen displaying wage history timeline and global settings
struct PaySettingsView: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var viewModel: PaySettingsViewModel
  @State private var showingEditJobSheet = false
  @State private var paySetupJob: Job?
  @State private var showingArchiveConfirmation = false
  @State private var isPayReviewExpanded: Bool

  init(
    initialJobId: String? = nil, initialDate: Date = Date(),
    initiallyExpandPayReview: Bool = false
  ) {
    _isPayReviewExpanded = State(initialValue: initiallyExpandPayReview)
    _viewModel = StateObject(
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
    .toolbar {
      ToolbarItem(placement: .principal) {
        Text(.settingsPayTitle)
          .font(.headline)
          .foregroundColor(.tidexTextPrimary)
          .lineLimit(1)
      }
    }
    .sheet(isPresented: $viewModel.showingEditor) {
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
      requiredJobReselectionSheet
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

  @ViewBuilder
  private var requiredJobReselectionSheet: some View {
    NavigationStack {
      List {
        Section {
          Text(.settingsPayChooseJobUnavailable)
            .foregroundStyle(Color.tidexTextSecondary)
          ForEach(viewModel.activeJobs) { job in
            Button {
              viewModel.resolveRequiredJobSelection(job.id)
            } label: {
              WorkplaceNameText(
                name: job.name,
                colorHex: job.color,
                fallbackBadgeColor: .tidexBlue
              )
            }
            .buttonStyle(.plain)
          }
        } header: {
          HStack(spacing: Spacing.xxxs) {
            Image(systemName: "building.2")
              .font(.tidexCaptionRegular)
              .foregroundColor(.tidexBlue)
            Text(.settingsPayChooseJobTitle)
          }
          .textCase(nil)
        }
      }
      .navigationTitle(String(localized: .settingsMenuPayLabel))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(String(localized: .commonCancel)) { dismiss() }
        }
      }
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
          currentWorkplaceTitle
            .padding(.horizontal, Spacing.md)
        }

        if viewModel.isSelectedJobConfigured {
          PaySettingsReviewCard(
            isExpanded: $isPayReviewExpanded,
            workDate: $viewModel.reviewDate,
            snapshots: viewModel.snapshots,
            entries: viewModel.timelineEntries,
            currency: viewModel.userCurrency,
            payrollDay: viewModel.selectedJobPayrollDay,
            halfTaxMonth: viewModel.selectedJobHalfTaxMonth,
            payPeriod: viewModel.selectedJobPayPeriod,
            onEdit: { viewModel.openEditEditor(snapshot: $0, section: $1) }
          )
          .padding(.horizontal, Spacing.md)

          WageHistoryTimelineView(
            entries: viewModel.timelineEntries,
            currency: viewModel.userCurrency,
            onAddNew: { viewModel.openCreateEditor() },
            onEdit: { snapshot in viewModel.openEditEditor(snapshot: snapshot) }
          )
          .padding(.horizontal, Spacing.md)

          tipBox
            .padding(.horizontal, Spacing.md)

          Divider()
            .padding(.horizontal, Spacing.xl)

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
          .padding(.horizontal, Spacing.md)
        } else {
          finishPaySetupPanel
            .padding(.horizontal, Spacing.md)
        }

        jobActionsPanel
          .padding(.horizontal, Spacing.md)
          .padding(.top, Spacing.md)

        // Bottom padding
        Spacer()
          .frame(height: Spacing.xxl)
      }
      .padding(.vertical, Spacing.lg)
    }
    .refreshable {
      await viewModel.loadData()
    }
  }

  private var finishPaySetupPanel: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      Image(systemName: "exclamationmark.circle.fill")
        .font(.tidexTitle)
        .foregroundColor(.tidexWarning)

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
      VStack(alignment: .leading, spacing: Spacing.sm) {
        Text(.settingsPayJobActionsTitle)
          .font(.tidexLabel)
          .foregroundColor(.tidexTextSecondary)

        if viewModel.isSelectedJobDefault {
          jobStatusRow
        } else {
          Button {
            Task {
              await viewModel.setSelectedJobAsDefault()
            }
          } label: {
            jobActionRow(
              icon: "checkmark.circle",
              title: String(localized: .settingsPayJobActionsSetDefault),
              tint: .tidexBlue,
              isEnabled: viewModel.canSetSelectedJobAsDefault
                && !viewModel.isProcessingJobAction
            )
          }
          .buttonStyle(.plain)
          .disabled(!viewModel.canSetSelectedJobAsDefault || viewModel.isProcessingJobAction)
        }

        Button {
          showingArchiveConfirmation = true
        } label: {
          jobActionRow(
            icon: "archivebox",
            title: String(localized: .settingsPayJobActionsArchive),
            tint: .tidexTextSecondary,
            isEnabled: viewModel.canArchiveSelectedJob && !viewModel.isProcessingJobAction
          )
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canArchiveSelectedJob || viewModel.isProcessingJobAction)

        if let hint = viewModel.selectedJobManagementHint {
          Text(hint)
            .font(.tidexFootnote)
            .foregroundColor(.tidexTextMuted)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var jobStatusRow: some View {
    HStack(spacing: Spacing.sm) {
      Image(systemName: "checkmark.circle.fill")
        .font(.tidexBodyMedium)
        .foregroundColor(.tidexBlue)
        .frame(width: 22)

      Text(.settingsPayJobActionsStandardStatus)
        .font(.tidexBodyMedium)
        .foregroundColor(.tidexTextSecondary)

      Spacer()
    }
    .padding(.horizontal, Spacing.md)
    .padding(.vertical, Spacing.md)
    .background(Color.tidexSurfaceSecondary.opacity(0.62))
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
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
        .frame(width: 22)

      Text(title)
        .font(.tidexBodyMedium)
        .foregroundColor(tint)

      Spacer()
    }
    .padding(.horizontal, Spacing.md)
    .padding(.vertical, Spacing.md)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.tidexSurfaceSecondary)
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
    .opacity(isEnabled ? 1 : 0.45)
  }

  // MARK: - Tip Box

  @ViewBuilder
  private var currentWorkplaceTitle: some View {
    Group {
      if let selectedJobName = viewModel.selectedJobName {
        HStack(spacing: Spacing.xxs) {
          WorkplaceNameText(
            name: selectedJobName,
            colorHex: viewModel.selectedJob?.color,
            font: .tidexScreenTitle,
            fallbackBadgeColor: .tidexBlue,
            lineLimit: 2,
            maxTextAlignment: .leading,
            badgeCornerRadius: CornerRadius.md,
            badgeHorizontalPadding: Spacing.sm
          )
          .multilineTextAlignment(.leading)
          .layoutPriority(1)

          Button {
            showingEditJobSheet = true
          } label: {
            Image(systemName: "pencil")
              .font(.system(size: 28, weight: .semibold))
              .foregroundColor(.tidexBlue)
              .frame(width: 44, height: 44, alignment: .leading)
          }
          .buttonStyle(.plain)
          .accessibilityLabel(Text(.settingsPayEditJobTitle))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }

  private var tipText: AttributedString {
    let tipLabel = String(localized: .settingsPayTimelineTipLabel)
    let infoTip = String(localized: .settingsPayTimelineInfoTip)

    var result = AttributedString("\(tipLabel) \(infoTip)")

    // Make the tip label bold
    if let range = result.range(of: tipLabel) {
      result[range].font = .tidexLabelStrong
    }

    return result
  }

  @ViewBuilder
  private var tipBox: some View {
    Text(tipText)
      .font(.tidexSubheadline)
      .foregroundColor(.tidexBlue)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(Spacing.md)
      .background(Color.tidexBlue.opacity(0.1))
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous))
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

struct PaySettingsSheet: View {
  let jobId: String?
  let workDate: Date
  var initiallyExpandPayReview = false
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      PaySettingsView(
        initialJobId: jobId, initialDate: workDate,
        initiallyExpandPayReview: initiallyExpandPayReview
      )
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button(String(localized: .commonDone)) { dismiss() }
        }
      }
    }
    .presentationDetents([.large])
  }
}

private struct EditWorkplaceSheet: View {
  @Environment(\.dismiss) private var dismiss

  let onSave: (String, String?) async -> Bool

  @State private var name: String
  @State private var selectedColor: Color
  @State private var isSaving = false
  @State private var saveError: String?

  init(
    initialName: String,
    initialColorHex: String?,
    onSave: @escaping (String, String?) async -> Bool
  ) {
    self.onSave = onSave
    _name = State(initialValue: initialName)
    _selectedColor = State(
      initialValue: Self.colorFromHex(initialColorHex)
        ?? Color(red: 59 / 255, green: 130 / 255, blue: 246 / 255)
    )
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField(String(localized: .settingsPayAddJobName), text: $name)
            .textInputAutocapitalization(.words)

          VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(.settingsPayAddJobColorLabel)
              .font(.tidexFootnote)
              .foregroundColor(.tidexTextSecondary)

            WorkplaceColorCarousel(selectedHex: Self.normalizedHex(from: selectedColor)) { hex in
              selectedColor = Self.colorFromHex(hex) ?? .tidexBlue
            }
          }
        }

        if let saveError {
          Section {
            Text(saveError)
              .font(.tidexFootnote)
              .foregroundColor(.tidexError)
          }
        }
      }
      .navigationTitle(String(localized: .settingsPayEditJobTitle))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(String(localized: .commonCancel)) {
            dismiss()
          }
          .disabled(isSaving)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(String(localized: .commonSave)) {
            Task {
              await save()
            }
          }
          .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
    }
  }

  private func save() async {
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else {
      saveError = String(localized: .settingsPayAddJobErrorName)
      return
    }

    isSaving = true
    let didSave = await onSave(trimmedName, Self.normalizedHex(from: selectedColor))
    isSaving = false

    if didSave {
      dismiss()
    } else {
      saveError = String(localized: .settingsPayErrorSaveFailed)
    }
  }

  private static func normalizedHex(from color: Color) -> String? {
    let uiColor = UIColor(color)
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0

    guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
      return nil
    }

    return String(
      format: "#%02X%02X%02X",
      Int(red * 255),
      Int(green * 255),
      Int(blue * 255)
    )
  }

  private static func colorFromHex(_ hex: String?) -> Color? {
    guard var hex else { return nil }
    hex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if hex.hasPrefix("#") {
      hex.removeFirst()
    }
    guard hex.count == 6, let int = Int(hex, radix: 16) else {
      return nil
    }
    let red = Double((int >> 16) & 0xFF) / 255.0
    let green = Double((int >> 8) & 0xFF) / 255.0
    let blue = Double(int & 0xFF) / 255.0
    return Color(red: red, green: green, blue: blue)
  }
}

// MARK: - Preview

#Preview {
  NavigationStack {
    PaySettingsView()
  }
}
