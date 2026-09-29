import SwiftUI

/// Sheets presented from the add screen for previews, job choice, pay setup and job creation.
struct AddShiftSheetsModifier: ViewModifier {
  @Bindable var viewModel: AddShiftViewModel
  @Binding var showAddJobSheet: Bool
  @Binding var showPaySettings: Bool
  @Binding var openJobsAndPaySettingsAfterPickerDismiss: Bool
  @Binding var paySettingsDetent: PresentationDetent
  let compactDetent: PresentationDetent

  func body(content: Content) -> some View {
    content
      .sheet(isPresented: $viewModel.showPreviewSheet) {
        RecurringPreviewSheet(viewModel: viewModel)
      }
      .sheet(
        isPresented: $viewModel.showSubmitJobChooser,
        onDismiss: {
          guard openJobsAndPaySettingsAfterPickerDismiss else { return }
          openJobsAndPaySettingsAfterPickerDismiss = false
          paySettingsDetent = compactDetent
          showPaySettings = true
        }
      ) {
        jobChooserSheet
      }
      .sheet(isPresented: $showPaySettings) {
        paySettingsSheet
      }
      .sheet(isPresented: $showAddJobSheet) {
        addJobSheet
      }
      .sheet(item: $viewModel.paySetupRequest) { request in
        JobPaySetupSheet(
          job: request.job,
          initialCurrency: request.job.currency,
          dismissTitle: String(localized: .settingsPaySetupLaterButton)
        ) { input in
          await viewModel.completePaySetup(for: request.job, input: input)
        }
      }
  }

  private var jobChooserSheet: some View {
    JobChooserSheet(
      jobs: viewModel.submissionJobs,
      configuredJobIds: viewModel.configuredJobIds,
      onAddJob: {
        viewModel.dismissJobSelection()
        showAddJobSheet = true
      },
      onOpenSettings: {
        openJobsAndPaySettingsAfterPickerDismiss = true
        viewModel.dismissJobSelection()
      },
      onSelect: { jobId in
        viewModel.selectJobForShiftCreation(jobId)
        viewModel.dismissJobSelection()
      },
      onCancel: {
        viewModel.dismissJobSelection()
      }
    )
  }

  private var paySettingsSheet: some View {
    SettingsView(
      initialDestination: .pay(jobId: nil),
      sheetPresentationDetent: $paySettingsDetent,
      directPayManagerCompactDetent: compactDetent
    )
    .presentationDetents(
      [compactDetent, .large], selection: $paySettingsDetent
    )
    .presentationDragIndicator(.visible)
  }

  private var addJobSheet: some View {
    AddJobSheet(
      initialCurrency: viewModel.jobCreationInitialCurrency,
      initialPayrollDay: viewModel.jobCreationInitialPayrollDay,
      setupDismissTitle: String(localized: .settingsPaySetupLaterButton),
      onSaveBasics: { input in
        await viewModel.createBasicJobForSetup(input: input)
      }
    ) { input in
      await viewModel.createConfiguredJob(input: input)
    }
  }
}
