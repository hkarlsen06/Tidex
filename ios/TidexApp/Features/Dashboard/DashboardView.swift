import Combine
import SwiftUI

private struct EventSheetSelection: Identifiable {
  let event: EventRow
  let startInEditMode: Bool

  var id: String { event.id }
}

/// Dashboard view showing the main financial overview
/// Displays payroll, total earnings, and featured shift cards
struct DashboardView: View {  // swiftlint:disable:this explicit_acl explicit_top_level_acl file_types_order line_length type_body_length
  @EnvironmentObject private var coordinator: AppCoordinator  // swiftlint:disable:this type_contents_order
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize  // swiftlint:disable:this explicit_type_interface line_length type_contents_order
  @Environment(\.layoutDirection) private var layoutDirection  // swiftlint:disable:this explicit_type_interface line_length type_contents_order

  /// Binding to the selected tab for navigation
  @Binding var selectedTab: MainTabView.Tab  // swiftlint:disable:this explicit_acl type_contents_order
  @Binding var showStatsView: Bool  // swiftlint:disable:this explicit_acl type_contents_order

  private struct MonthlyGoalEditContext: Identifiable {
    let id = UUID()  // swiftlint:disable:this explicit_type_interface
    let monthDate: Date
    let baselineGoal: Int?
    let initialGoal: Int?
    let showsAdjustmentPercentageFootnote: Bool
  }

  @StateObject private var viewModel = DashboardViewModel()  // swiftlint:disable:this explicit_type_interface line_length type_contents_order
  @StateObject private var countdownManager = CountdownManager()  // swiftlint:disable:this explicit_type_interface line_length type_contents_order
  @StateObject private var calendarSubscriptionStore = CalendarSubscriptionStore.shared  // swiftlint:disable:this explicit_type_interface line_length type_contents_order
  @StateObject private var workSetupPresentationViewModel = WorkSetupPresentationViewModel()  // swiftlint:disable:this explicit_type_interface line_length type_contents_order
  @ObservedObject private var pushManager = PushNotificationManager.shared  // swiftlint:disable:this explicit_type_interface line_length type_contents_order
  @ObservedObject private var syncStatusManager = SyncStatusManager.shared  // swiftlint:disable:this explicit_type_interface line_length type_contents_order

  /// State for showing push notification failure alert
  @State private var showPushFailureAlert = false  // swiftlint:disable:this explicit_type_interface type_contents_order
  @State private var operationErrorMessage: String?  // swiftlint:disable:this type_contents_order

  /// Selected shift for showing details sheet
  @State private var selectedShift: ShiftWithComputations?  // swiftlint:disable:this type_contents_order
  @State private var selectedEvent: EventSheetSelection?  // swiftlint:disable:this type_contents_order

  /// Active featured shift target for action sheet actions
  @State private var featuredShiftActionTarget: ShiftWithComputations?  // swiftlint:disable:this type_contents_order
  @State private var showFeaturedShiftActions = false  // swiftlint:disable:this explicit_type_interface line_length type_contents_order

  /// State for delete confirmation
  @State private var showDeleteConfirmation = false  // swiftlint:disable:this explicit_type_interface line_length type_contents_order
  @State private var shiftToDelete: ShiftWithComputations?  // swiftlint:disable:this type_contents_order
  @State private var showEventDeleteConfirmation = false  // swiftlint:disable:this explicit_type_interface line_length type_contents_order
  @State private var eventToDelete: EventRow?  // swiftlint:disable:this type_contents_order

  /// Edit mode state (when opening from swipe action)
  @State private var shiftToEditDirectly: ShiftWithComputations?  // swiftlint:disable:this type_contents_order

  /// State for recurring shift editing
  @State private var recurringShiftToEdit: RecurringShiftRow?  // swiftlint:disable:this type_contents_order
  @State private var monthlyGoalEditContext: MonthlyGoalEditContext?  // swiftlint:disable:this type_contents_order
  @State private var temporaryClockReviewSession: TemporaryClockSession?  // swiftlint:disable:this type_contents_order
  @State private var clockInJobOptions: [Job] = []  // swiftlint:disable:this type_contents_order
  @State private var showClockInJobChooser: Bool = false  // swiftlint:disable:this type_contents_order
  @State private var clockPaySetupJob: Job?  // swiftlint:disable:this type_contents_order
  @State private var pendingClockAction: PendingClockAction?  // swiftlint:disable:this type_contents_order
  @State private var temporarySessionReferenceDate: Date = .init()  // swiftlint:disable:this type_contents_order
  @State private var showMixedCurrencyBreakdownPopover: Bool = false  // swiftlint:disable:this type_contents_order
  @State private var activeDashboardRefreshTask: Task<Void, Never>?  // swiftlint:disable:this type_contents_order
  @State private var showCalendarSubscriptionSettings: Bool = false  // swiftlint:disable:this type_contents_order
  @State private var selectedPayrollDetailsVariant: PayrollCardVariant?  // swiftlint:disable:this type_contents_order

  /// Haptic feedback generator
  private let impactHaptic = UIImpactFeedbackGenerator(style: .medium)  // swiftlint:disable:this explicit_type_interface line_length type_contents_order

  private enum PendingClockAction {
    case clockIn(jobId: String?)
    case temporaryClockOut(start: Date, end: Date, jobId: String?)
  }

  private func shouldKeepShiftDetailsOpen(  // swiftlint:disable:this type_contents_order
    after editResult: ShiftEditResult,
    originalShift: ShiftWithComputations
  ) -> Bool {
    editResult.noteWasEdited
      && editResult.customSupplements == nil
      && editResult.shiftDate == originalShift.shiftDate
      && editResult.startTime == String(originalShift.startTime.prefix(5))  // swiftlint:disable:this no_magic_numbers
      && editResult.endTime == String(originalShift.endTime.prefix(5))  // swiftlint:disable:this no_magic_numbers
  }

  /// Use fixed minimum card heights for regular Dynamic Type sizes so loading
  /// placeholders and real content occupy the same vertical space.
  private var usesFixedCardHeights: Bool {
    !dynamicTypeSize.isAccessibilitySize
  }

  private let payrollSectionMinHeight: CGFloat = 89
  private let featuredSectionMinHeight: CGFloat = 118
  private let clockStateRefreshTicker = Timer.publish(every: 30, on: .main, in: .common)  // swiftlint:disable:this explicit_type_interface line_length no_magic_numbers
    .autoconnect()
  private let temporarySessionTicker = Timer.publish(every: 1, on: .main, in: .common)  // swiftlint:disable:this explicit_type_interface line_length
    .autoconnect()

  @discardableResult
  private func refreshWorkSetupPresentationState() -> Bool {  // swiftlint:disable:this type_contents_order
    let wasShowingPlaceholder: Bool = shouldShowWorkSetupRequiredPlaceholder
    workSetupPresentationViewModel.refresh(
      userId: coordinator.userId,
      initialSyncComplete: coordinator.initialSyncComplete
    )
    return wasShowingPlaceholder && !shouldShowWorkSetupRequiredPlaceholder
  }

  private var shouldShowWorkSetupRequiredPlaceholder: Bool {
    workSetupPresentationViewModel.shouldShowPlaceholder
  }

  private var operationErrorPresented: Binding<Bool> {
    Binding(
      get: { operationErrorMessage != nil },
      set: { isPresented in
        if !isPresented {
          operationErrorMessage = nil
        }
      }
    )
  }

  private func loadDashboardContent() async {  // swiftlint:disable:this type_contents_order
    guard selectedTab == .home else { return }  // swiftlint:disable:this conditional_returns_on_newline
    guard !shouldShowWorkSetupRequiredPlaceholder else { return }  // swiftlint:disable:this conditional_returns_on_newline line_length
    await calendarSubscriptionStore.refreshIfNeeded()
    await viewModel.loadDashboard()

    // If sync already completed before view appeared, reload to pick up synced data
    // This handles the race condition where sync finishes before .onChange is registered
    if coordinator.initialSyncComplete, viewModel.dashboardData == nil {
      await viewModel.reloadFromLocal()
    }
  }

  private func refreshActiveDashboardStateIfNeeded() {  // swiftlint:disable:this type_contents_order
    guard !shouldShowWorkSetupRequiredPlaceholder else { return }  // swiftlint:disable:this conditional_returns_on_newline line_length
    guard selectedTab == .home else { return }  // swiftlint:disable:this conditional_returns_on_newline
    guard viewModel.dashboardData != nil else { return }  // swiftlint:disable:this conditional_returns_on_newline

    activeDashboardRefreshTask?.cancel()
    activeDashboardRefreshTask = Task {
      await viewModel.refreshAppearanceSettingsFromLocal()
      guard !Task.isCancelled else { return }  // swiftlint:disable:this conditional_returns_on_newline
      await viewModel.refreshClockState()
      guard !Task.isCancelled else { return }  // swiftlint:disable:this conditional_returns_on_newline
      await viewModel.preloadClockSelectableJobs()
    }
  }

  private func handleInitialSyncCompleteChange(completed: Bool) {  // swiftlint:disable:this type_contents_order
    let shouldLoadAfterSetupCompleted = refreshWorkSetupPresentationState()  // swiftlint:disable:this explicit_type_interface line_length
    guard !shouldShowWorkSetupRequiredPlaceholder else { return }  // swiftlint:disable:this conditional_returns_on_newline line_length
    if shouldLoadAfterSetupCompleted {
      Task {
        await loadDashboardContent()
      }
    }

    // When initial sync completes after login, reload dashboard to show synced data
    if completed {
      viewModel.markLocalDataStale()
      guard selectedTab == .home else { return }  // swiftlint:disable:this conditional_returns_on_newline
      // Set loading state SYNCHRONOUSLY before starting async task
      // This prevents the empty state from flashing while data loads
      viewModel.prepareForReload()
      Task {
        await viewModel.reloadFromLocal()

        // Play release haptic if coming from MFA verification
        if coordinator.didJustCompleteMFA {
          Haptics.play(.release)
          coordinator.didJustCompleteMFA = false
        }
      }
    }
  }

  private func handleWorkSetupDataDidChange(_ notification: Notification) {  // swiftlint:disable:this line_length type_contents_order
    if notification.userInfo?["syncReason"] as? String == SyncReason.manualRefresh.rawValue,
      notification.userInfo?["userId"] as? String == coordinator.userId,
      selectedTab == .home
    {
      return
    }

    let shouldLoadAfterSetupCompleted = refreshWorkSetupPresentationState()  // swiftlint:disable:this explicit_type_interface line_length
    viewModel.markLocalDataStale()
    guard !shouldShowWorkSetupRequiredPlaceholder else { return }  // swiftlint:disable:this conditional_returns_on_newline line_length
    if shouldLoadAfterSetupCompleted {
      guard selectedTab == .home else { return }  // swiftlint:disable:this conditional_returns_on_newline
      Task {
        await loadDashboardContent()
      }
      return
    }
    guard selectedTab == .home else { return }  // swiftlint:disable:this conditional_returns_on_newline
    Task {
      await viewModel.reloadFromLocal()
    }
  }

  private func handleSuccessfulSyncSummary(_ summary: SyncCompletionSummary?) {  // swiftlint:disable:this line_length type_contents_order
    guard let summary, summary.userId == coordinator.userId else { return }  // swiftlint:disable:this conditional_returns_on_newline line_length
    guard summary.reason != .appLaunch else { return }  // swiftlint:disable:this conditional_returns_on_newline
    guard let context = summary.dashboardChangeContext else { return }  // swiftlint:disable:this conditional_returns_on_newline line_length

    guard !shouldShowWorkSetupRequiredPlaceholder else {
      viewModel.markLocalDataStale()
      return
    }

    guard !(summary.reason == .manualRefresh && selectedTab == .home) else { return }  // swiftlint:disable:this conditional_returns_on_newline line_length

    Task {
      await viewModel.handleExternalShiftsDidChange(context)
    }
  }

  private func handleDashboardDataChange(_ data: DashboardData?) {  // swiftlint:disable:this type_contents_order
    configureCountdown(with: data)
    showMixedCurrencyBreakdownPopover = false
  }

  private func handleDashboardAppear() {  // swiftlint:disable:this type_contents_order
    viewModel.setActiveTabVisible(selectedTab == .home)
    refreshWorkSetupPresentationState()
    guard selectedTab == .home else { return }  // swiftlint:disable:this conditional_returns_on_newline
    guard !shouldShowWorkSetupRequiredPlaceholder else { return }  // swiftlint:disable:this conditional_returns_on_newline line_length
    // Reconfigure timers when returning to the dashboard after a disappear cycle.
    configureCountdown(with: viewModel.dashboardData)
    refreshActiveDashboardStateIfNeeded()
  }

  private func handleSelectedTabChange(oldTab: MainTabView.Tab, newTab: MainTabView.Tab) {  // swiftlint:disable:this line_length type_contents_order
    guard oldTab != newTab else { return }  // swiftlint:disable:this conditional_returns_on_newline
    viewModel.setActiveTabVisible(newTab == .home)
    if newTab == .home {
      refreshWorkSetupPresentationState()
      configureCountdown(with: viewModel.dashboardData)
      refreshActiveDashboardStateIfNeeded()
    } else {
      activeDashboardRefreshTask?.cancel()
      activeDashboardRefreshTask = nil
    }
  }

  private func openCalendarSubscriptionSetupFromDashboard() {  // swiftlint:disable:this type_contents_order
    selectedShift = nil
    shiftToEditDirectly = nil
    selectedEvent = nil
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {  // swiftlint:disable:this no_magic_numbers
      showCalendarSubscriptionSettings = true
    }
  }

  private func payrollDetailsSheet(for variant: PayrollCardVariant) -> some View {  // swiftlint:disable:this line_length type_contents_order
    PayrollDetailsSheet(
      variant: variant,
      onCreateAdjustment: { draft in
        try await viewModel.createPayrollAdjustment(draft)
      },
      onUpdateAdjustment: { id, draft in
        try await viewModel.updatePayrollAdjustment(id, draft)
      },
      onDeleteAdjustment: { id in
        try await viewModel.deletePayrollAdjustment(id: id)
      }
    )
    .userCurrency(variant.currency)
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.visible)
  }

  private var navigationContent: some View {
    NavigationStack {  // swiftlint:disable:this closure_body_length
      ZStack {
        // Background that fills entire screen including safe areas.
        // Matches the brighter-at-the-top app chrome used in the marketing mockup.
        TidexAppBackground()

        // Main content - month picker is now in shared overlay
        Group {
          if shouldShowWorkSetupRequiredPlaceholder {
            WorkSetupRequiredPlaceholder()
          } else if let error = viewModel.error {
            errorView(error: error)
          } else if let data = viewModel.dashboardData {
            cardContent(data: data)
          } else {
            // Show skeleton cards with shimmer while loading or waiting for sync
            // This provides a consistent visual preview of the layout
            loadingSkeletonView
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        if !shouldShowWorkSetupRequiredPlaceholder {
          VStack {
            SyncStatusIndicator {
              Task {
                await viewModel.refresh()
              }
            }
            .padding(.top, Spacing.xs)
            Spacer()
          }
        }
      }
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(.hidden, for: .navigationBar)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          statsToolbarButton
        }
        ToolbarItem(placement: .topBarTrailing) {
          UserMenuButton(
            displayName: coordinator.userDisplayName,
            avatarUrl: coordinator.userAvatarUrl
          )
        }
      }
      .navigationDestination(isPresented: $showStatsView) {
        StatsView()
      }
      .iPadToolbarTransaction()
    }
  }

  private var statsToolbarButton: some View {
    Button {
      Haptics.play(.light)
      showStatsView = true
    } label: {
      Image(systemName: "chart.bar.xaxis")
        .accessibilityHidden(true)
    }
    .accessibilityLabel(Text(.tabsStats))
  }

  private var bodyWithLifecycle: AnyView {
    AnyView(
      navigationContent
        .task {
          viewModel.setActiveTabVisible(selectedTab == .home)
          refreshWorkSetupPresentationState()
          await loadDashboardContent()
        }
        .onChange(of: coordinator.initialSyncComplete) { _, completed in
          handleInitialSyncCompleteChange(completed: completed)
        }
        .onChange(of: coordinator.userId) { _, _ in
          refreshWorkSetupPresentationState()
          viewModel.markLocalDataStale()
          guard selectedTab == .home else { return }  // swiftlint:disable:this conditional_returns_on_newline
          guard !shouldShowWorkSetupRequiredPlaceholder else { return }  // swiftlint:disable:this conditional_returns_on_newline line_length
          Task {
            await viewModel.reloadFromLocal()
          }
        }
        .onReceive(NotificationCenter.default.publisher(for: .workSetupDataDidChange)) {
          notification in
          handleWorkSetupDataDidChange(notification)
        }
        .onChange(of: syncStatusManager.lastSuccessfulSyncSummary) { _, summary in
          handleSuccessfulSyncSummary(summary)
        }
        .onChange(of: viewModel.dashboardData) { _, newData in
          handleDashboardDataChange(newData)
        }
        .onChange(of: showFeaturedShiftActions) { _, isPresented in
          if !isPresented {
            featuredShiftActionTarget = nil
          }
        }
        .onAppear {
          handleDashboardAppear()
        }
        .onDisappear {
          activeDashboardRefreshTask?.cancel()
          activeDashboardRefreshTask = nil
          countdownManager.stop()
        }
        .onChange(of: selectedTab) { oldTab, newTab in
          handleSelectedTabChange(oldTab: oldTab, newTab: newTab)
        }
        .onReceive(NotificationCenter.default.publisher(for: .shiftsDidChange)) { notification in
          guard !shouldShowWorkSetupRequiredPlaceholder else { return }  // swiftlint:disable:this conditional_returns_on_newline line_length
          guard (notification.object as AnyObject?) !== viewModel else { return }  // swiftlint:disable:this conditional_returns_on_newline line_length
          Task {
            await viewModel.handleExternalShiftsDidChange(notification.shiftChangeContext)
          }
        }
        .onReceive(
          NotificationCenter.default.publisher(for: .dashboardClockButtonsVisibilityDidChange)
        ) { notification in
          guard !shouldShowWorkSetupRequiredPlaceholder else { return }  // swiftlint:disable:this conditional_returns_on_newline line_length
          if let isVisible = notification.userInfo?["isVisible"] as? Bool {
            viewModel.applyDashboardClockButtonsVisibility(isVisible)
          }
        }
        .onReceive(clockStateRefreshTicker) { _ in
          guard selectedTab == .home else { return }  // swiftlint:disable:this conditional_returns_on_newline
          guard !shouldShowWorkSetupRequiredPlaceholder else { return }  // swiftlint:disable:this conditional_returns_on_newline line_length
          Task {
            await viewModel.refreshClockState()
          }
        }
        .onReceive(temporarySessionTicker) { now in
          guard selectedTab == .home else { return }  // swiftlint:disable:this conditional_returns_on_newline
          guard case .temporary = viewModel.activeClockState else { return }  // swiftlint:disable:this conditional_returns_on_newline line_length
          guard !shouldShowWorkSetupRequiredPlaceholder else { return }  // swiftlint:disable:this conditional_returns_on_newline line_length
          temporarySessionReferenceDate = now
        }
        .onChange(of: viewModel.activeClockState) { _, state in
          if case .temporary = state {
            temporarySessionReferenceDate = Date()
          }
        }
        .onChange(of: pushManager.shouldShowAlert) { _, shouldShow in
          // Show alert when push registration fails
          if shouldShow {
            showPushFailureAlert = true
          }
        }
    )
  }

  var body: some View {  // swiftlint:disable:this explicit_acl
    bodyWithLifecycle
      .alert(
        String(localized: .pushFailureTitle),
        isPresented: $showPushFailureAlert
      ) {
        Button(String(localized: .pushFailureSettingsButton)) {
          pushManager.openSettings()
          pushManager.dismissAlert()
        }
        Button(String(localized: .pushFailureLaterButton), role: .cancel) {
          pushManager.dismissAlert()
        }
      } message: {
        Text(.pushFailureMessage)
      }
      .alert(
        String(localized: .commonError),
        isPresented: operationErrorPresented
      ) {
        Button(String(localized: .commonOk), role: .cancel) {
          operationErrorMessage = nil
        }
      } message: {
        if let operationErrorMessage {
          Text(operationErrorMessage)
        }
      }
      .confirmationDialog(
        "",
        isPresented: $showFeaturedShiftActions,
        titleVisibility: .hidden,
        presenting: featuredShiftActionTarget
      ) { shift in
        Button(String(localized: .shiftsDetails)) {
          guard !viewModel.isUpdatingShift else { return }  // swiftlint:disable:this conditional_returns_on_newline
          featuredShiftActionTarget = nil
          selectedShift = shift
        }
        Button(String(localized: .dashboardFeaturedShiftActionsEndNow)) {
          guard !viewModel.isUpdatingShift else { return }  // swiftlint:disable:this conditional_returns_on_newline
          featuredShiftActionTarget = nil
          Task {
            await viewModel.endShiftNow(shift)
          }
        }
        Button(String(localized: .commonCancel), role: .cancel) {
          featuredShiftActionTarget = nil
        }
      }
      .sheet(item: $monthlyGoalEditContext) { context in
        MonthlyGoalEditSheet(
          monthDate: context.monthDate,
          baselineGoal: context.baselineGoal,
          initialGoal: context.initialGoal,
          showsAdjustmentPercentageFootnote: context.showsAdjustmentPercentageFootnote
        ) { value in
          try await viewModel.saveMonthlyGoalForDisplayedMonth(value)
        }
        .presentationDetents([.fraction(0.35), .medium])  // swiftlint:disable:this no_magic_numbers
        .presentationDragIndicator(.visible)
      }
      .sheet(item: $selectedPayrollDetailsVariant) { variant in
        payrollDetailsSheet(for: variant)
      }
      .sheet(item: $temporaryClockReviewSession) { session in
        let clockJobs = viewModel.clockSelectableJobsSnapshot()  // swiftlint:disable:this explicit_type_interface
        ClockOutReviewSheet(
          session: session,
          initialAvailableJobs: clockJobs,
          loadJobs: {
            await viewModel.clockSelectableJobs()
          },
          initialSelectedJobId: viewModel.preferredClockJobId(for: session),
          jobRequiringPaySetup: { jobId in
            await viewModel.clockJobRequiringPaySetup(jobId: jobId)
          },
          onPaySetupRequired: { start, end, jobId, job in
            pendingClockAction = .temporaryClockOut(start: start, end: end, jobId: jobId ?? job.id)
            clockPaySetupJob = job
          },
          onSave: { start, end, jobId in
            try await viewModel.commitTemporaryClockOut(start: start, end: end, jobId: jobId)
          },
          onDiscard: {
            await viewModel.discardTemporaryClockSession()
          }
        )
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
      }
      .sheet(isPresented: $showClockInJobChooser) {
        DashboardClockJobChooserSheet(
          initialJobs: clockInJobOptions,
          loadJobs: {
            await viewModel.clockSelectableJobs()
          },
          onSelect: { jobId in
            showClockInJobChooser = false
            Task {
              await handleClockIn(jobId: jobId)
            }
          },
          onCancel: {
            showClockInJobChooser = false
          }
        )
      }
      .sheet(item: $clockPaySetupJob) { job in
        JobPaySetupSheet(
          job: job,
          initialCurrency: job.currency
        ) { input in
          await completeClockPaySetup(for: job, input: input)
        }
      }
      // Shift details sheet with full edit/delete capabilities
      .sheet(item: $selectedShift) { shift in  // swiftlint:disable:this closure_body_length
        let shiftJob = viewModel.shouldShowJobIndicators ? viewModel.jobForShift(shift) : nil  // swiftlint:disable:this explicit_type_interface line_length
        ShiftDetailsSheet(
          shift: shift,
          jobName: shiftJob?.name,
          jobColorHex: shiftJob?.color,
          onDelete: {
            selectedShift = nil
            // Small delay before showing delete confirmation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {  // swiftlint:disable:this no_magic_numbers
              shiftToDelete = shift
              showDeleteConfirmation = true
            }
          },
          onUpdate: { editResult in
            let shouldKeepSheetOpen = shouldKeepShiftDetailsOpen(  // swiftlint:disable:this explicit_type_interface
              after: editResult, originalShift: shift)  // swiftlint:disable:this multiline_arguments_brackets
            try await viewModel.updateShift(editResult)
            if shouldKeepSheetOpen {
              if let refreshedShift = viewModel.getDisplayedShift(id: editResult.shiftId) {
                selectedShift = refreshedShift
              }
            } else {
              selectedShift = nil
            }
          },
          onUpdatePause: { pauseResult in
            selectedShift = nil
            Task {
              await viewModel.updateShiftPause(pauseResult)
            }
          },
          onEditRecurring: { recurringId in
            selectedShift = nil
            // Small delay to allow sheet to dismiss
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {  // swiftlint:disable:this no_magic_numbers
              if let recurring = viewModel.getRecurringShift(id: recurringId) {
                recurringShiftToEdit = recurring
              }
            }
          },
          onStopRecurringAfterDate: { recurringId, occurrenceDate in
            try await viewModel.stopRecurringShiftAfterDate(
              recurringId: recurringId,
              occurrenceDate: occurrenceDate
            )
            selectedShift = nil
          },
          showsCalendarSubscriptionCTA: !calendarSubscriptionStore.isActive,
          onShowInCalendarRequested: {
            openCalendarSubscriptionSetupFromDashboard()
          },
          tariffRules: viewModel.getTariffRules(for: shift.shiftDate)
        )
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
      }
      .sheet(item: $shiftToEditDirectly) { shift in  // swiftlint:disable:this closure_body_length
        let shiftJob = viewModel.shouldShowJobIndicators ? viewModel.jobForShift(shift) : nil  // swiftlint:disable:this explicit_type_interface line_length
        ShiftDetailsSheet(
          shift: shift,
          jobName: shiftJob?.name,
          jobColorHex: shiftJob?.color,
          onDelete: {
            shiftToEditDirectly = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {  // swiftlint:disable:this no_magic_numbers
              shiftToDelete = shift
              showDeleteConfirmation = true
            }
          },
          onUpdate: { editResult in
            let shouldKeepSheetOpen = shouldKeepShiftDetailsOpen(  // swiftlint:disable:this explicit_type_interface
              after: editResult, originalShift: shift)  // swiftlint:disable:this multiline_arguments_brackets
            try await viewModel.updateShift(editResult)
            if shouldKeepSheetOpen {
              if let refreshedShift = viewModel.getDisplayedShift(id: editResult.shiftId) {
                shiftToEditDirectly = refreshedShift
              }
            } else {
              shiftToEditDirectly = nil
            }
          },
          onUpdatePause: { pauseResult in
            shiftToEditDirectly = nil
            Task {
              await viewModel.updateShiftPause(pauseResult)
            }
          },
          onEditRecurring: { recurringId in
            shiftToEditDirectly = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {  // swiftlint:disable:this no_magic_numbers
              if let recurring = viewModel.getRecurringShift(id: recurringId) {
                recurringShiftToEdit = recurring
              }
            }
          },
          onStopRecurringAfterDate: { recurringId, occurrenceDate in
            try await viewModel.stopRecurringShiftAfterDate(
              recurringId: recurringId,
              occurrenceDate: occurrenceDate
            )
            shiftToEditDirectly = nil
          },
          showsCalendarSubscriptionCTA: !calendarSubscriptionStore.isActive,
          onShowInCalendarRequested: {
            openCalendarSubscriptionSetupFromDashboard()
          },
          startInEditMode: true,
          tariffRules: viewModel.getTariffRules(for: shift.shiftDate)
        )
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
      }
      .sheet(item: $selectedEvent) { selection in
        EventDetailsSheet(
          event: selection.event,
          onDelete: {
            selectedEvent = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {  // swiftlint:disable:this no_magic_numbers
              eventToDelete = selection.event
              showEventDeleteConfirmation = true
            }
          },
          onUpdate: { editResult in
            try await viewModel.updateEvent(editResult)
            selectedEvent = nil
          },
          onInlineReminderUpdate: { editResult in
            try await viewModel.updateEvent(editResult)
          },
          showsCalendarSubscriptionCTA: !calendarSubscriptionStore.isActive,
          onShowInCalendarRequested: {
            openCalendarSubscriptionSetupFromDashboard()
          },
          startInEditMode: selection.startInEditMode
        )
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
      }
      .sheet(isPresented: $showCalendarSubscriptionSettings) {
        SettingsView(
          initialDestination: .calendarSync(
            calendarSetupIntent: .setup(mode: .shiftsAndEvents, autoOpen: false)))  // swiftlint:disable:this line_length multiline_arguments_brackets
      }
      // Delete confirmation alert
      .alert(
        shiftToDelete?.isVirtual == true
          ? String(localized: .shiftsExcludeConfirmTitle)
          : String(localized: .shiftsDeleteConfirmTitle),
        isPresented: $showDeleteConfirmation,
        presenting: shiftToDelete
      ) { shift in
        Button(String(localized: .commonCancel), role: .cancel) {
          shiftToDelete = nil
        }
        Button(
          shift.isVirtual
            ? String(localized: .shiftsExcludeButton)
            : String(localized: .shiftsDeleteButton),
          role: .destructive
        ) {
          Task {
            await deleteShift(shift)
          }
        }
      } message: { shift in
        Text(
          shift.isVirtual
            ? String(localized: .shiftsExcludeConfirmMessage)
            : String(localized: .shiftsDeleteConfirmMessage))  // swiftlint:disable:this multiline_arguments_brackets
      }
      .alert(
        String(localized: .eventsDeleteConfirmTitle),
        isPresented: $showEventDeleteConfirmation,
        presenting: eventToDelete
      ) { event in
        Button(String(localized: .commonCancel), role: .cancel) {
          eventToDelete = nil
        }
        Button(String(localized: .eventsDeleteButton), role: .destructive) {
          Task {
            await deleteEvent(event)
          }
        }
      } message: { _ in
        Text(.eventsDeleteConfirmMessage)
      }
      // Recurring shift editor sheet
      .sheet(item: $recurringShiftToEdit) { recurring in
        RecurringShiftEditorSheet(
          recurringShift: recurring,
          onSave: { editResult in
            recurringShiftToEdit = nil
            Task {
              await updateRecurringShift(editResult)
            }
          },
          onDelete: {
            let recurringId = recurring.id  // swiftlint:disable:this explicit_type_interface
            recurringShiftToEdit = nil
            Task {
              await deleteRecurringShift(recurringId)
            }
          }
        )
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
      }
  }

  // MARK: - Shift Operations

  /// Delete a shift (or exclude a virtual shift)
  private func deleteShift(_ shift: ShiftWithComputations) async {  // swiftlint:disable:this type_contents_order
    impactHaptic.impactOccurred()

    do {
      if shift.isVirtual {
        // Virtual shift: add date to exclusions of parent recurring shift
        guard let recurringId = shift.shift.recurring_id else {
          return
        }
        try await RecurringShiftsRepository.shared.addExclusion(
          id: recurringId,
          date: shift.shiftDate
        )
      } else {
        // Regular shift: mark for deletion
        try await ShiftsRepository.shared.deleteShift(id: shift.id)
      }

      // Post notification for other views
      NotificationCenter.default.postShiftsDidChange(
        context: .affecting(isoDate: shift.shiftDate)
      )

    } catch {
      operationErrorMessage = ErrorTranslations.translate(error)
    }

    shiftToDelete = nil
  }

  private func deleteEvent(_ event: EventRow) async {  // swiftlint:disable:this type_contents_order
    impactHaptic.impactOccurred()

    do {
      try await viewModel.deleteEvent(event)
      eventToDelete = nil
    } catch {
      operationErrorMessage = ErrorTranslations.translate(error)
      eventToDelete = nil
    }
  }

  /// Update a recurring shift pattern
  private func updateRecurringShift(_ editResult: RecurringShiftEditResult) async {  // swiftlint:disable:this line_length type_contents_order
    do {
      _ = try await RecurringShiftsRepository.shared.updateRecurringShift(
        id: editResult.recurringId,
        startTime: editResult.startTime,
        endTime: editResult.endTime,
        repeatIntervalWeeks: editResult.repeatIntervalWeeks,
        selectedDays: editResult.selectedDays,
        endCondition: editResult.endCondition,
        exclusions: editResult.exclusions
      )

      // Post notification for other views
      NotificationCenter.default.postShiftsDidChange(context: .fullReload)

    } catch {
      operationErrorMessage = ErrorTranslations.translate(error)
    }
  }

  /// Delete a recurring shift pattern
  private func deleteRecurringShift(_ recurringId: String) async {  // swiftlint:disable:this type_contents_order
    do {
      try await RecurringShiftsRepository.shared.deleteRecurringShift(id: recurringId)

      // Post notification for other views
      NotificationCenter.default.postShiftsDidChange(context: .fullReload)

    } catch {
      operationErrorMessage = ErrorTranslations.translate(error)
    }
  }

  // MARK: - Countdown Configuration

  private func configureCountdown(with data: DashboardData?) {  // swiftlint:disable:this type_contents_order
    guard let data else {
      countdownManager.stop()
      return
    }

    let shiftDate: String?
    let startTime: String?
    let endTime: String?

    switch data.featuredItem {
    case .shift(let shift)
    where data.isViewingCurrentMonth && !data.featuredShiftIsBestShift:
      shiftDate = shift.shiftDate
      startTime = shift.startTime
      endTime = shift.endTime

    case .event(let event, _)
    where data.isViewingCurrentMonth && !data.featuredShiftIsBestShift && !event.is_all_day:
      shiftDate = event.start_date
      startTime = event.start_time
      endTime = event.end_time

    default:
      shiftDate = nil
      startTime = nil
      endTime = nil
    }

    // Configure countdown with current data
    // Payroll countdown shown for all months (not just current)
    countdownManager.configure(
      shiftDate: shiftDate,
      startTime: startTime,
      endTime: endTime,
      payrollDate: selectedPayrollDate(for: data)
    )
  }

  private func selectedPayrollDate(for data: DashboardData) -> Date {  // swiftlint:disable:this type_contents_order
    let payrollVariants = viewModel.payrollCardVariants(  // swiftlint:disable:this explicit_type_interface
      fallback: data,
      defaultTitle: String(localized: .dashboardPayroll)
    )

    guard !payrollVariants.isEmpty else {
      return data.payrollDate
    }

    return payrollVariants[0].payoutDate
  }

  private func featuredEventCountdownStatus(_ event: EventRow, now: Date = Date())  // swiftlint:disable:this line_length type_contents_order
    -> ShiftPreviewStatus
  {
    guard
      !event.is_all_day,
      let startTime = event.start_time,
      let endTime = event.end_time,
      let startDate = Date.fromDateAndTime(event.start_date, time: startTime),
      let endDate = Date.fromDateAndTime(event.end_date, time: endTime)
    else {
      return .upcoming
    }

    if now >= startDate, now < endDate {
      return .active
    }

    return now >= endDate ? .past : .upcoming
  }

  @ViewBuilder
  private func featuredEventFooter(_ event: EventRow) -> some View {  // swiftlint:disable:this type_contents_order
    if event.is_all_day {
      HStack(spacing: Spacing.xxxs) {
        Image(systemName: "calendar")
          .font(.tidexCaptionRegular)
          .foregroundColor(.tidexBlue)
        Text(.addShiftEventAllDay)
          .font(.tidexLabel)
          .foregroundColor(.tidexTextSecondary)
      }
      .frame(height: 20)  // swiftlint:disable:this no_magic_numbers
    } else if let countdownText = countdownManager.shiftCountdownText {
      ShiftCountdownBadge(
        text: countdownText,
        status: featuredEventCountdownStatus(event),
        finalCountdownSeconds: countdownManager.finalShiftCountdownSeconds
      )
      .frame(height: 20)  // swiftlint:disable:this no_magic_numbers
    } else {
      RoundedRectangle(cornerRadius: CornerRadius.xxs)
        .fill(Color.tidexTextMuted.opacity(0.3))  // swiftlint:disable:this no_magic_numbers
        .frame(width: 80, height: 14)  // swiftlint:disable:this no_magic_numbers
        .frame(height: 20)  // swiftlint:disable:this no_magic_numbers
    }
  }

  // MARK: - Card Content

  /// Card content with pull-to-refresh and swipe gestures
  /// Month picker is handled separately in the main body so it's always visible
  @ViewBuilder
  private func cardContent(data: DashboardData) -> some View {  // swiftlint:disable:this type_contents_order
    PullToRefreshContainer(onRefresh: {
      await viewModel.refresh()
    }) {
      // Cards centered in available space (between toolbar and month picker)
      GeometryReader { geometry in
        VStack(spacing: 0) {
          Spacer()

          // Animated card content - centered vertically
          animatedCardContent(data: data)
            .frame(maxWidth: AdaptiveMaxWidth.tabContent)
            .padding(.horizontal, Spacing.md)

          Spacer()
        }
        // Offset for month picker overlay so content centers in available space
        .padding(.bottom, MonthPickerLayout.totalBottomInset)
        .frame(width: geometry.size.width, height: geometry.size.height)
        .contentShape(Rectangle())
      }
      .contentShape(Rectangle())
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    // Pass user's currency to all child views
    .userCurrency(data.currency)
  }

  // MARK: - Animated Card Content

  @ViewBuilder
  private func animatedCardContent(data: DashboardData) -> some View {  // swiftlint:disable:this cyclomatic_complexity function_body_length line_length type_contents_order
    let now = Date()  // swiftlint:disable:this explicit_type_interface
    let calendar = Calendar.current  // swiftlint:disable:this explicit_type_interface
    let isViewingCurrentMonth = data.isViewingCurrentMonth  // swiftlint:disable:this explicit_type_interface
    let preliminaryPayrollVariants = viewModel.payrollCardVariants(  // swiftlint:disable:this explicit_type_interface
      fallback: data,
      defaultTitle: String(localized: .dashboardPayroll)
    )
    let selectedPayoutDate: Date = preliminaryPayrollVariants.first?.payoutDate ?? data.payrollDate
    let payrollDayStart: Date = calendar.startOfDay(for: selectedPayoutDate)
    let payrollDayEnd =  // swiftlint:disable:this explicit_type_interface
      calendar.date(byAdding: .day, value: 1, to: payrollDayStart) ?? payrollDayStart
    let isOnOrBeforePayrollDay = now < payrollDayEnd  // swiftlint:disable:this explicit_type_interface
    let selectedPayoutYM = selectedPayoutDate.yearMonth()  // swiftlint:disable:this explicit_type_interface
    let current = Date.currentYearMonth()  // swiftlint:disable:this explicit_type_interface
    let selectedPayoutIsInCurrentMonth =  // swiftlint:disable:this explicit_type_interface
      selectedPayoutYM.year == current.year && selectedPayoutYM.month == current.month
    let currentMonthStart = calendar.date(  // swiftlint:disable:this explicit_type_interface
      from: calendar.dateComponents([.year, .month], from: now))  // swiftlint:disable:this multiline_arguments_brackets
    let payrollProgressStartDate: (Date) -> Date? = { payoutDate in
      return viewModel.currentPayrollProgressStartDate(for: payoutDate, now: now)
        ?? currentMonthStart
    }
    let canManuallySetPayrollStatus =  // swiftlint:disable:this explicit_type_interface
      isViewingCurrentMonth && selectedPayoutIsInCurrentMonth && isOnOrBeforePayrollDay
    let isCurrentAdvancedNextPayout =  // swiftlint:disable:this explicit_type_interface
      !isViewingCurrentMonth
      && viewModel.isCurrentMonthAdvancedNextPayoutDate(selectedPayoutDate, now: now)
    let shouldShowLivePayrollProgress = isViewingCurrentMonth || isCurrentAdvancedNextPayout  // swiftlint:disable:this explicit_type_interface line_length

    let payrollOverrideUserId = coordinator.getCurrentUserId()  // swiftlint:disable:this explicit_type_interface
    let payrollMarkedReceived = viewModel.isPayrollReceivedOverrideForDisplayedMonth(  // swiftlint:disable:this explicit_type_interface line_length
      userId: payrollOverrideUserId
    )
    let effectivePayrollHasPassed: Bool = {
      guard isViewingCurrentMonth else { return data.payrollHasPassed }  // swiftlint:disable:this conditional_returns_on_newline line_length
      if calendar.isDate(selectedPayoutDate, inSameDayAs: now) {
        return payrollMarkedReceived
      }
      return !isOnOrBeforePayrollDay
    }()

    // Determine payroll label based on whether viewing current month
    let payrollLabel: String = {
      if isViewingCurrentMonth {
        return effectivePayrollHasPassed
          ? String(localized: .dashboardPreviousPayout)
          : String(localized: .dashboardNextPayout)
      }

      if selectedPayoutYM.year < current.year
        || (selectedPayoutYM.year == current.year && selectedPayoutYM.month < current.month)
      {
        return String(localized: .dashboardEarlierPayout)
      }

      if isCurrentAdvancedNextPayout {
        return String(localized: .dashboardNextPayout)
      }

      if selectedPayoutYM.year > current.year
        || (selectedPayoutYM.year == current.year && selectedPayoutYM.month > current.month)
      {
        return String(localized: .dashboardFuturePayout)
      }

      if effectivePayrollHasPassed {
        return String(localized: .dashboardPreviousPayout)
      }

      // Fallback for non-current month views that resolve to the real current payout month.
      // This should be uncommon, but keeps the label neutral instead of implying today-relative
      // "next payout" semantics while browsing months.
      return String(localized: .dashboardPayroll)
    }()

    // Calculate progress from the previous payroll date to the selected payout.
    let defaultPayrollProgress: Double? = {
      guard shouldShowLivePayrollProgress, !effectivePayrollHasPassed else { return nil }  // swiftlint:disable:this conditional_returns_on_newline line_length

      guard let progressStartDate = payrollProgressStartDate(payrollDayStart) else {
        return nil
      }

      let totalDuration = payrollDayStart.timeIntervalSince(progressStartDate)  // swiftlint:disable:this explicit_type_interface line_length
      let elapsed = now.timeIntervalSince(progressStartDate)  // swiftlint:disable:this explicit_type_interface

      guard totalDuration > 0 else {
        // Edge case: payroll is on the 1st
        return 100
      }

      let progress = (elapsed / totalDuration) * 100  // swiftlint:disable:this explicit_type_interface
      // Clamp to 1-100 (minimum 1% so users recognize it's a progress bar)
      return max(1, min(100, progress))
    }()

    let payrollVariants = viewModel.payrollCardVariants(fallback: data, defaultTitle: payrollLabel)  // swiftlint:disable:this explicit_type_interface line_length
    let previousPayrollVariant: PayrollCardVariant? = viewModel.previousPayrollCardVariants(
      fallback: data,
      defaultTitle: String(localized: .dashboardPreviousPayout)
    ).first
    let isPayrollCardLoading = viewModel.payrollCardSnapshot == nil  // swiftlint:disable:this explicit_type_interface
    if let selectedPayrollVariant = payrollVariants.first {
      let showsMultiWorkplacePayroll = !selectedPayrollVariant.badges.isEmpty  // swiftlint:disable:this explicit_type_interface line_length
      let selectedPayrollProgress: Double? = {
        if !showsMultiWorkplacePayroll {
          return defaultPayrollProgress
        }

        guard shouldShowLivePayrollProgress else {
          return nil
        }

        let selectedPayrollDayStart: Date =
          calendar.startOfDay(for: selectedPayrollVariant.payoutDate)
        let selectedPayrollDayEnd =  // swiftlint:disable:this explicit_type_interface
          calendar.date(byAdding: .day, value: 1, to: selectedPayrollDayStart)
          ?? selectedPayrollDayStart
        guard now < selectedPayrollDayEnd else { return nil }  // swiftlint:disable:this conditional_returns_on_newline

        guard let progressStartDate = payrollProgressStartDate(selectedPayrollDayStart) else {
          return nil
        }

        let totalDuration = selectedPayrollDayStart.timeIntervalSince(progressStartDate)  // swiftlint:disable:this explicit_type_interface line_length
        let elapsed = now.timeIntervalSince(progressStartDate)  // swiftlint:disable:this explicit_type_interface
        guard totalDuration > 0 else { return 100 }  // swiftlint:disable:this conditional_returns_on_newline

        let progress = (elapsed / totalDuration) * 100  // swiftlint:disable:this explicit_type_interface
        return max(1, min(100, progress))
      }()

      // Cards stay in place - only numbers animate on month change (like Next.js)
      VStack(spacing: Spacing.sm) {  // swiftlint:disable:this closure_body_length
        // Payroll countdown slot - fixed height to prevent layout shift.
        if let previousPayrollVariant, !isPayrollCardLoading {
          previousPayrollDetailsChip(for: previousPayrollVariant)
        } else {
          Text(countdownManager.payrollCountdownText ?? " ")
            .font(.tidexLabel)
            .foregroundColor(.tidexTextSecondary)
            .opacity(countdownManager.payrollCountdownText != nil ? 1 : 0)
            .frame(height: 20)  // swiftlint:disable:this no_magic_numbers
        }

        // Payroll Card (Previous Month relative to displayed month)
        payrollCardSection(
          selectedVariant: selectedPayrollVariant,
          variantCount: payrollVariants.count,
          canManuallySetPayrollStatus: canManuallySetPayrollStatus,
          payrollMarkedReceived: payrollMarkedReceived,
          payrollOverrideUserId: payrollOverrideUserId,
          payrollProgress: isPayrollCardLoading ? nil : selectedPayrollProgress,
          isLoading: isPayrollCardLoading,
          showsLoadingShimmer: false
        )
        .frame(
          minHeight: usesFixedCardHeights ? payrollSectionMinHeight : 0,
          alignment: .top
        )

        // Total Card (Displayed Month) - THE ANCHOR
        // Numbers animate smoothly when values change
        TotalCard(
          gross: data.currentMonthGross,
          net: data.currentMonthNet,
          completedGross: data.currentMonthCompletedGross,
          completedNet: data.currentMonthCompletedNet,
          shiftCount: data.currentMonthShiftCount,
          plannedCount: data.currentMonthPlannedCount,
          percentageChange: data.percentageChangeVsPrevious,
          taxEnabled: data.currentMonthTaxEnabled,
          monthlyGoal: data.currentMonthGoal,
          percentageIncludesPayrollAdjustments: data.previousMonthHasPayrollAdjustments
        )
        .contentShape(Rectangle())
        .gesture(monthSwipeGesture())
        .onTapGesture {
          if data.currentMonthCurrencyAggregate.hasMixedCurrency {
            impactHaptic.impactOccurred()
            showMixedCurrencyBreakdownPopover.toggle()
          } else {
            openMonthlyGoalEditor()
          }
        }
        .popover(isPresented: $showMixedCurrencyBreakdownPopover) {
          MixedCurrencyBreakdownPopover(entries: data.currentMonthCurrencyAggregate.secondary)
            .presentationCompactAdaptation(.popover)
        }

        if viewModel.shouldShowDashboardClockButtons {
          clockButtonsSection()
        }

        // Featured Shift Card - exact height on regular Dynamic Type to avoid
        // skeleton/content vertical recentering during the loading transition.
        if usesFixedCardHeights {
          featuredShiftSection(data: data)
            .frame(height: featuredSectionMinHeight, alignment: .top)
        } else {
          featuredShiftSection(data: data)
        }
      }
    } else {
      EmptyView()
    }
  }

  private func openMonthlyGoalEditor() {  // swiftlint:disable:this type_contents_order
    impactHaptic.impactOccurred()
    let baseline = viewModel.baselineMonthlyGoal  // swiftlint:disable:this explicit_type_interface
    let override = viewModel.displayedMonthOverrideGoal  // swiftlint:disable:this explicit_type_interface
    let effectiveGoal = viewModel.dashboardData?.currentMonthGoal.flatMap {  // swiftlint:disable:this explicit_type_interface line_length
      $0 > 0 ? Int($0.rounded()) : nil  // swiftlint:disable:this anonymous_argument_in_multiline_closure
    }

    let initialGoal =  // swiftlint:disable:this explicit_type_interface
      override
      ?? effectiveGoal.flatMap { effective in
        if let baseline, effective == baseline {
          return nil
        }
        return effective
      }
    let monthDate =  // swiftlint:disable:this explicit_type_interface
      Calendar.current.date(
        from: DateComponents(year: viewModel.displayYear, month: viewModel.displayMonth, day: 1)
      ) ?? Date()

    monthlyGoalEditContext = MonthlyGoalEditContext(
      monthDate: monthDate,
      baselineGoal: baseline,
      initialGoal: initialGoal,
      showsAdjustmentPercentageFootnote: viewModel.dashboardData?.previousMonthHasPayrollAdjustments
        ?? false
    )
  }

  private func monthSwipeGesture() -> some Gesture {  // swiftlint:disable:this type_contents_order
    DragGesture(minimumDistance: 30)  // swiftlint:disable:this no_magic_numbers
      .onEnded { value in
        let horizontal = value.translation.width  // swiftlint:disable:this explicit_type_interface
        let vertical = abs(value.translation.height)  // swiftlint:disable:this explicit_type_interface

        guard abs(horizontal) > vertical else { return }  // swiftlint:disable:this conditional_returns_on_newline

        impactHaptic.impactOccurred()

        let isRTL = layoutDirection == .rightToLeft  // swiftlint:disable:this explicit_type_interface
        if horizontal < 0 {
          if isRTL {
            viewModel.goToPreviousMonth()
          } else {
            viewModel.goToNextMonth()
          }
        } else {
          if isRTL {
            viewModel.goToNextMonth()
          } else {
            viewModel.goToPreviousMonth()
          }
        }
      }
  }

  @ViewBuilder
  private func clockButtonsSection() -> some View {  // swiftlint:disable:this type_contents_order
    HStack(spacing: Spacing.sm) {  // swiftlint:disable:this closure_body_length
      clockButton(
        title: .dashboardClockIn,
        systemImage: "play.fill",
        isEnabled: viewModel.isClockInEnabled
      ) {
        guard viewModel.isClockInEnabled else { return }  // swiftlint:disable:this conditional_returns_on_newline
        impactHaptic.impactOccurred()
        Task {
          let cachedJobs = viewModel.clockSelectableJobsSnapshot()  // swiftlint:disable:this explicit_type_interface
          if cachedJobs.count > 1 {
            clockInJobOptions = cachedJobs
            showClockInJobChooser = true
            return
          }
          if cachedJobs.count == 1 {
            await handleClockIn(jobId: cachedJobs.first?.id)
            return
          }
          clockInJobOptions = []
          showClockInJobChooser = true
        }
      }

      clockButton(
        title: .dashboardClockOut,
        systemImage: "stop.fill",
        isEnabled: viewModel.isClockOutEnabled
      ) {
        guard viewModel.isClockOutEnabled else { return }  // swiftlint:disable:this conditional_returns_on_newline
        impactHaptic.impactOccurred()
        Task {
          let route = await viewModel.routeClockOut()  // swiftlint:disable:this explicit_type_interface
          if case .temporaryReview(let session) = route {
            await presentTemporaryClockReview(session)
          }
        }
      }
    }
    .padding(.horizontal, Spacing.mlg)
  }

  private func clockButton(  // swiftlint:disable:this type_contents_order
    title: LocalizedStringResource,
    systemImage: String,
    isEnabled: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Label {
        Text(title)
          .font(.tidexLabel)
      } icon: {
        Image(systemName: systemImage)
          .font(.tidexCaption)
      }
      .frame(maxWidth: .infinity)
      .frame(minHeight: 44)  // swiftlint:disable:this no_magic_numbers
      .padding(.vertical, Spacing.xxs)
      .foregroundColor(
        isEnabled
          ? .tidexTextPrimary
          : .tidexTextMuted
      )
      .background(
        RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous)
          .fill(Color.tidexSurfacePrimary)
      )
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous))
      .contentShape(RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous))
      .tidexCardShadow()
    }
    .buttonStyle(DashboardClockButtonStyle())
    .disabled(!isEnabled)
  }

  @ViewBuilder
  private func clockButtonsSkeletonSection() -> some View {  // swiftlint:disable:this type_contents_order
    HStack(spacing: Spacing.sm) {
      RoundedRectangle(cornerRadius: CornerRadius.card)
        .fill(Color.tidexSurfacePrimary)
        .frame(height: 44)  // swiftlint:disable:this no_magic_numbers
        .tidexCardShadow()
        .shimmer(isActive: true)

      RoundedRectangle(cornerRadius: CornerRadius.card)
        .fill(Color.tidexSurfacePrimary)
        .frame(height: 44)  // swiftlint:disable:this no_magic_numbers
        .tidexCardShadow()
        .shimmer(isActive: true)
    }
    .padding(.horizontal, Spacing.mlg)
  }

  @ViewBuilder
  private func payrollCardSection(  // swiftlint:disable:this function_body_length function_parameter_count line_length type_contents_order
    selectedVariant: PayrollCardVariant,
    variantCount: Int,
    canManuallySetPayrollStatus: Bool,
    payrollMarkedReceived: Bool,
    payrollOverrideUserId: String?,
    payrollProgress: Double?,
    isLoading: Bool = false,
    showsLoadingShimmer: Bool = true
  ) -> some View {
    let showsWorkplaceVariants = variantCount > 1  // swiftlint:disable:this explicit_type_interface
    let showsGroupedWorkplaces = !selectedVariant.badges.isEmpty  // swiftlint:disable:this explicit_type_interface

    let card = PayrollCard(  // swiftlint:disable:this explicit_type_interface
      payrollDate: selectedVariant.payoutDate,
      label: selectedVariant.title,
      labelColorHex: selectedVariant.colorHex,
      labelIsWorkplace: showsWorkplaceVariants || showsGroupedWorkplaces,
      workplaceBadges: selectedVariant.badges,
      gross: selectedVariant.gross,
      net: selectedVariant.net,
      tax: selectedVariant.tax,
      taxEnabled: selectedVariant.taxEnabled,
      hasPayrollAdjustments: selectedVariant.hasPayrollAdjustments,
      progress: payrollProgress,
      isLoading: isLoading,
      showsLoadingShimmer: showsLoadingShimmer
    )

    card
      .userCurrency(selectedVariant.currency)
      .contentShape(Rectangle())
      .onTapGesture {
        guard !isLoading else { return }  // swiftlint:disable:this conditional_returns_on_newline
        impactHaptic.impactOccurred()
        selectedPayrollDetailsVariant = selectedVariant
      }
      .contextMenu {
        if canManuallySetPayrollStatus, !isLoading {
          Button {
            impactHaptic.impactOccurred()
            viewModel.markPayrollReceivedForDisplayedMonth(userId: payrollOverrideUserId)
          } label: {
            Label(
              String(localized: .dashboardPayrollStatusReceived),
              systemImage: payrollMarkedReceived ? "checkmark.circle.fill" : "circle"
            )
          }

          Button {
            impactHaptic.impactOccurred()
            viewModel.clearPayrollReceivedOverrideForDisplayedMonth(
              userId: payrollOverrideUserId)  // swiftlint:disable:this multiline_arguments_brackets
          } label: {
            Label(
              String(localized: .dashboardPayrollStatusNotReceived),
              systemImage: payrollMarkedReceived ? "circle" : "checkmark.circle.fill"
            )
          }
        }
      }
  }

  private func previousPayrollDetailsChip(for variant: PayrollCardVariant) -> some View {  // swiftlint:disable:this line_length type_contents_order
    Button {
      impactHaptic.impactOccurred()
      selectedPayrollDetailsVariant = variant
    } label: {
      HStack(spacing: Spacing.xxs) {
        Image(systemName: "clock.arrow.circlepath")
          .font(.tidexCaptionRegular.weight(.semibold))
          .foregroundColor(.tidexBlue)

        Text(.dashboardSeePreviousPayout)
          .font(.tidexLabelStrong)
          .foregroundColor(.tidexBlue)
          .lineLimit(1)
      }
      .padding(.horizontal, Spacing.sm)
      .frame(height: 20)  // swiftlint:disable:this no_magic_numbers
      .background(Color.tidexBlue.opacity(0.1))  // swiftlint:disable:this no_magic_numbers
      .clipShape(Capsule())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text(.dashboardSeePreviousPayout))
  }

  // MARK: - Featured Shift Section

  /// Featured shift card with fixed height to prevent layout jumps
  @ViewBuilder
  private func featuredShiftSection(data: DashboardData) -> some View {  // swiftlint:disable:this function_body_length line_length type_contents_order
    // Use a fixed height container so the layout doesn't shift
    // when switching between FeaturedShiftCard and EmptyShiftCard
    Group {  // swiftlint:disable:this closure_body_length
      if case .temporary(let session) = viewModel.activeClockState {
        let temporaryShift = viewModel.temporaryFeaturedShift(  // swiftlint:disable:this explicit_type_interface
          from: session,
          at: temporarySessionReferenceDate
        )
        let shiftJob = viewModel.jobForTemporarySession(session)  // swiftlint:disable:this explicit_type_interface
        FeaturedShiftCard(
          shift: temporaryShift,
          isToday: true,
          isBestShift: false,
          countdownText: String(localized: .commonInProgress),
          showJobIndicator: viewModel.shouldShowJobIndicators,
          jobName: shiftJob?.name,
          jobColorHex: shiftJob?.color,
          progress: 0,
          finalCountdownSeconds: nil,
          showTimeRangeEndSkeleton: false
        )
        .userCurrency(shiftJob?.currency ?? data.currency)
        .contentShape(Rectangle())
        .onTapGesture {
          impactHaptic.impactOccurred()
          Task {
            await presentTemporaryClockReview(session)
          }
        }
      } else if let featuredItem = data.featuredItem {
        switch featuredItem {
        case .shift(let featuredShift):
          // Only show progress bar for active shifts (matching Next.js behavior)
          let shiftProgress: Double? =
            countdownManager.isShiftActive ? countdownManager.shiftProgress : nil
          let displayedFeaturedShift: ShiftWithComputations =
            countdownManager.isShiftActive
            ? viewModel.liveFeaturedShiftWhileOngoing(from: featuredShift, at: Date())
            : featuredShift
          let shiftJob = viewModel.jobForShift(featuredShift)  // swiftlint:disable:this explicit_type_interface
          SwipeableShiftCard(
            onEdit: {
              shiftToEditDirectly = featuredShift
            },
            onDelete: {
              impactHaptic.impactOccurred()
              shiftToDelete = featuredShift
              showDeleteConfirmation = true
            },
            actionHeight: usesFixedCardHeights ? ShiftCardMetrics.regularCardMinHeight : nil
          ) {
            FeaturedShiftCard(
              shift: displayedFeaturedShift,
              isToday: data.isFeaturedItemToday,
              isBestShift: data.featuredShiftIsBestShift,
              countdownText: countdownManager.shiftCountdownText,
              showJobIndicator: viewModel.shouldShowJobIndicators,
              jobName: shiftJob?.name,
              jobColorHex: shiftJob?.color,
              progress: shiftProgress,
              finalCountdownSeconds: countdownManager.finalShiftCountdownSeconds
            )
            .userCurrency(shiftJob?.currency ?? data.currency)
            .contentShape(Rectangle())
            .onTapGesture {
              impactHaptic.impactOccurred()
              if countdownManager.isShiftActive {
                if viewModel.shouldShowDashboardClockButtons {
                  selectedShift = featuredShift
                } else {
                  featuredShiftActionTarget = featuredShift
                  showFeaturedShiftActions = true
                }
              } else {
                selectedShift = featuredShift
              }
            }
          }

        case .event(let event, let coveredDateISO):  // swiftlint:disable:this pattern_matching_keywords
          SwipeableShiftCard(
            onEdit: {
              selectedEvent = EventSheetSelection(event: event, startInEditMode: true)
            },
            onDelete: {
              impactHaptic.impactOccurred()
              eventToDelete = event
              showEventDeleteConfirmation = true
            },
            actionHeight: usesFixedCardHeights ? ShiftCardMetrics.regularCardMinHeight : nil
          ) {
            VStack(spacing: Spacing.sm) {
              EventRowCard(
                event: event,
                coveredDateISO: coveredDateISO,
                onTap: {
                  impactHaptic.impactOccurred()
                  selectedEvent = EventSheetSelection(event: event, startInEditMode: false)
                },
                showTodayHighlight: false
              )

              featuredEventFooter(event)
            }
          }
        }
      } else {
        EmptyShiftCard(onAddShift: {
          selectedTab = .add
        })
      }
    }
  }

  private func presentTemporaryClockReview(_ session: TemporaryClockSession) async {  // swiftlint:disable:this line_length type_contents_order
    if viewModel.clockSelectableJobsSnapshot().isEmpty {
      _ = await viewModel.clockSelectableJobs()
    }
    temporaryClockReviewSession = session
  }

  private func handleClockIn(jobId: String?) async {  // swiftlint:disable:this type_contents_order
    if let job = await viewModel.clockJobRequiringPaySetup(jobId: jobId) {
      pendingClockAction = .clockIn(jobId: job.id)
      clockPaySetupJob = job
      return
    }

    await viewModel.clockIn(jobId: jobId)
  }

  private func completeClockPaySetup(for job: Job, input: JobPaySetupInput) async -> Bool {  // swiftlint:disable:this line_length type_contents_order
    let didSave = await viewModel.completeClockPaySetup(for: job, input: input)  // swiftlint:disable:this explicit_type_interface line_length
    guard didSave else { return false }  // swiftlint:disable:this conditional_returns_on_newline

    let pendingAction = pendingClockAction  // swiftlint:disable:this explicit_type_interface
    pendingClockAction = nil

    switch pendingAction {
    case .clockIn(let jobId):
      Task {
        await viewModel.clockIn(jobId: jobId)
      }

    case .temporaryClockOut(let start, let end, let jobId):  // swiftlint:disable:this pattern_matching_keywords
      Task {
        do {
          try await viewModel.commitTemporaryClockOut(start: start, end: end, jobId: jobId)
          temporaryClockReviewSession = nil
        } catch {
          // The review sheet remains dismissed; the repository guard prevents an invalid shift.
        }
      }

    case .none:
      break
    }

    return true
  }

  // MARK: - Loading Skeleton View

  /// Skeleton cards with shimmer animation shown while loading
  /// Provides a visual preview of the dashboard layout during data fetch
  private var loadingSkeletonView: some View {
    PullToRefreshContainer(onRefresh: {
      await viewModel.refresh()
    }) {  // swiftlint:disable:this closure_body_length
      GeometryReader { geometry in  // swiftlint:disable:this closure_body_length
        VStack(spacing: 0) {  // swiftlint:disable:this closure_body_length
          Spacer()

          // Skeleton cards matching the real dashboard layout
          VStack(spacing: Spacing.sm) {  // swiftlint:disable:this closure_body_length
            // Placeholder for payroll countdown text
            Color.clear
              .frame(height: 20)  // swiftlint:disable:this no_magic_numbers

            // Payroll Card skeleton
            PayrollCard(
              payrollDate: Date(),
              label: String(localized: .dashboardNextPayout),
              gross: 0,
              net: nil,
              tax: nil,
              taxEnabled: false,
              isLoading: true
            )
            .frame(
              minHeight: usesFixedCardHeights ? payrollSectionMinHeight : 0,
              alignment: .top
            )

            // Total Card skeleton
            TotalCard(
              gross: 0,
              net: nil,
              completedGross: 0,
              completedNet: nil,
              shiftCount: 0,
              plannedCount: 0,
              percentageChange: nil,
              taxEnabled: false,
              monthlyGoal: nil,
              isLoading: true
            )

            if viewModel.shouldShowDashboardClockButtons {
              clockButtonsSkeletonSection()
            }

            // Featured Shift Card skeleton
            if usesFixedCardHeights {
              EmptyShiftCard(isLoading: true)
                .frame(height: featuredSectionMinHeight, alignment: .top)
            } else {
              EmptyShiftCard(isLoading: true)
            }
          }
          .frame(maxWidth: AdaptiveMaxWidth.tabContent)
          .padding(.horizontal, Spacing.md)

          Spacer()
        }
        // Offset for month picker overlay so content centers in available space
        .padding(.bottom, MonthPickerLayout.totalBottomInset)
        .frame(width: geometry.size.width, height: geometry.size.height)
        .contentShape(Rectangle())
      }
      .contentShape(Rectangle())
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  // MARK: - Error View

  @ViewBuilder
  private func errorView(error: Error) -> some View {
    VStack(spacing: Spacing.md) {
      Image(systemName: "exclamationmark.triangle")
        .font(.system(size: 48))  // swiftlint:disable:this no_magic_numbers
        .foregroundColor(.tidexWarning)

      Text(.dashboardLoadError)
        .font(.tidexBodyMedium)
        .foregroundColor(.tidexTextPrimary)

      Text(error.localizedDescription)
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextSecondary)
        .multilineTextAlignment(.center)

      Button {
        Task { await viewModel.loadDashboard() }
      } label: {
        Text(.commonRetry)
          .font(.tidexLabel)
          .foregroundColor(.tidexBlue)
          .padding(.horizontal, Spacing.mlg)
          .padding(.vertical, Spacing.sm)
          .background(Color.tidexBlue.opacity(0.1))  // swiftlint:disable:this no_magic_numbers
          .cornerRadius(CornerRadius.sm)
      }
    }
    .frame(maxWidth: AdaptiveMaxWidth.tabContent)
    .padding(.horizontal, Spacing.xxl)
  }

}

private struct DashboardClockButtonStyle: ButtonStyle {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion  // swiftlint:disable:this explicit_type_interface

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(reduceMotion ? 1.0 : (configuration.isPressed ? 0.98 : 1.0))  // swiftlint:disable:this line_length no_magic_numbers
      .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)  // swiftlint:disable:this line_length no_magic_numbers
  }
}

private struct ClockOutReviewSheet: View {
  let loadJobs: () async -> [Job]
  let jobRequiringPaySetup: (String?) async -> Job?
  let onPaySetupRequired: (Date, Date, String?, Job) -> Void
  let onSave: (Date, Date, String?) async throws -> Void
  let onDiscard: () async -> Void

  @Environment(\.dismiss) private var dismiss  // swiftlint:disable:this explicit_type_interface
  @State private var availableJobs: [Job]
  @State private var startTime: Date?
  @State private var endTime: Date?
  @State private var selectedJobId: String?
  @State private var focusedTimeField: TimeInputField?
  @State private var showJobChooser = false  // swiftlint:disable:this explicit_type_interface
  @State private var isSaving = false  // swiftlint:disable:this explicit_type_interface
  @State private var isDiscarding = false  // swiftlint:disable:this explicit_type_interface
  @State private var errorMessage: String?

  init(  // swiftlint:disable:this type_contents_order
    session: TemporaryClockSession,
    initialAvailableJobs: [Job],
    loadJobs: @escaping () async -> [Job],
    initialSelectedJobId: String?,
    jobRequiringPaySetup: @escaping (String?) async -> Job?,
    onPaySetupRequired: @escaping (Date, Date, String?, Job) -> Void,
    onSave: @escaping (Date, Date, String?) async throws -> Void,
    onDiscard: @escaping () async -> Void
  ) {
    self.loadJobs = loadJobs
    self.jobRequiringPaySetup = jobRequiringPaySetup
    self.onPaySetupRequired = onPaySetupRequired
    self.onSave = onSave
    self.onDiscard = onDiscard

    let initialStart = session.startedAt  // swiftlint:disable:this explicit_type_interface
    let initialEnd = max(Date(), initialStart.addingTimeInterval(60))  // swiftlint:disable:this explicit_type_interface line_length no_magic_numbers
    let fallbackJobId =  // swiftlint:disable:this explicit_type_interface
      initialSelectedJobId
      ?? initialAvailableJobs.first(where: \.is_default)?.id
      ?? initialAvailableJobs.first?.id
    _availableJobs = State(initialValue: initialAvailableJobs)
    _startTime = State(initialValue: initialStart)
    _endTime = State(initialValue: initialEnd)
    _selectedJobId = State(initialValue: fallbackJobId)
  }

  private var selectedJob: Job? {
    guard let selectedJobId else {
      return availableJobs.first
    }
    return availableJobs.first(where: { $0.id == selectedJobId }) ?? availableJobs.first
  }

  private var resolvedEndTime: Date? {
    guard let startTime, let endTime else { return nil }  // swiftlint:disable:this conditional_returns_on_newline
    guard endTime <= startTime else { return endTime }  // swiftlint:disable:this conditional_returns_on_newline
    return Calendar.current.date(byAdding: .day, value: 1, to: endTime) ?? endTime
  }

  private var isValidRange: Bool {
    guard let startTime, let resolvedEndTime else { return false }  // swiftlint:disable:this conditional_returns_on_newline line_length
    return resolvedEndTime > startTime
  }

  private var showsCrossMidnightHint: Bool {
    guard let startTime, let resolvedEndTime else { return false }  // swiftlint:disable:this conditional_returns_on_newline line_length
    return !Calendar.current.isDate(startTime, inSameDayAs: resolvedEndTime)
  }

  private var isWorking: Bool {
    isSaving || isDiscarding
  }

  var body: some View {
    NavigationStack {  // swiftlint:disable:this closure_body_length
      VStack(alignment: .leading, spacing: Spacing.md) {  // swiftlint:disable:this closure_body_length
        HStack {
          Text(.shiftsDate)
            .font(.tidexSubheadline)
            .foregroundColor(.tidexTextSecondary)
          Spacer()
          if let startTime {
            Text(startTime, format: .dateTime.day().month().year())
              .font(.tidexBodyMedium)
              .foregroundColor(.tidexTextPrimary)
          } else {
            Text("--")
              .font(.tidexBodyMedium)
              .foregroundColor(.tidexTextMuted)
          }
        }
        .padding(.horizontal, Spacing.md)

        if availableJobs.count > 1 {
          Button {
            showJobChooser = true
          } label: {
            HStack(spacing: Spacing.sm) {
              Text(.settingsPayChooseJobTitle)
                .font(.tidexSubheadline)
                .foregroundColor(.tidexTextSecondary)

              Spacer(minLength: Spacing.sm)

              if let selectedJob {
                WorkplaceNameText(
                  name: selectedJob.name,
                  colorHex: selectedJob.color,
                  font: .tidexMonoCaption,
                  fallbackBadgeColor: .tidexBlue,
                  badgeHorizontalPadding: Spacing.xs,
                  badgeVerticalPadding: 2  // swiftlint:disable:this no_magic_numbers
                )
                .lineLimit(1)
                .truncationMode(.tail)
              }

              Image(systemName: "chevron.down")  // swiftlint:disable:this accessibility_label_for_image
                .font(.tidexMicro)
                .foregroundColor(.tidexTextMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.md)
            .background(
              RoundedRectangle(cornerRadius: CornerRadius.xxl)
                .fill(Color.tidexSurfacePrimary)
            )
          }
          .buttonStyle(.plain)
        }

        VStack(spacing: Spacing.md) {
          TimeRangePicker(
            startTime: $startTime,
            endTime: $endTime,
            focusedFieldBinding: $focusedTimeField
          )
        }
        .padding(Spacing.md)
        .background(
          RoundedRectangle(cornerRadius: CornerRadius.xxl)
            .fill(Color.tidexSurfacePrimary)
        )

        if showsCrossMidnightHint {
          HStack(spacing: Spacing.xs) {
            Image(systemName: "moon.fill")  // swiftlint:disable:this accessibility_label_for_image
              .font(.tidexCaption)
              .foregroundColor(.tidexBlue)
            Text(.shiftsCrossMidnightInfo)
              .font(.tidexFootnote)
              .foregroundColor(.tidexTextSecondary)
          }
          .padding(.horizontal, Spacing.md)
        }

        if let errorMessage {
          Text(errorMessage)
            .font(.tidexFootnote)
            .foregroundColor(.tidexError)
            .padding(.horizontal, Spacing.md)
        }

        Spacer()
      }
      .padding(.top, Spacing.md)
      .background(Color.tidexBackground.ignoresSafeArea())
      .navigationTitle(.dashboardClockOutReviewTitle)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(String(localized: .commonCancel)) {
            dismiss()
          }
          .disabled(isWorking)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(String(localized: .commonSave)) {
            Task {
              await save()
            }
          }
          .disabled(isWorking || !isValidRange)
        }
      }
      .safeAreaInset(edge: .bottom) {
        Button(role: .destructive) {
          Task {
            await discard()
          }
        } label: {
          Text(.dashboardClockOutDiscardShift)
            .font(.tidexLabelStrong)
            .foregroundColor(.tidexError)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
            .background(
              RoundedRectangle(cornerRadius: CornerRadius.card)
                .fill(Color.tidexSurfacePrimary)
            )
            .tidexCardShadow(cornerRadius: CornerRadius.card)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.xs)
        .background(Color.tidexBackground)
        .disabled(isWorking)
      }
      .task {
        await ensureJobsLoaded()
      }
      .sheet(isPresented: $showJobChooser) {
        DashboardClockJobChooserSheet(
          initialJobs: availableJobs,
          onSelect: { jobId in
            selectedJobId = jobId
            showJobChooser = false
          },
          onCancel: {
            showJobChooser = false
          }
        )
      }
    }
  }

  private func save() async {
    guard !isSaving else { return }  // swiftlint:disable:this conditional_returns_on_newline
    guard isValidRange else { return }  // swiftlint:disable:this conditional_returns_on_newline
    guard let startTime, let resolvedEndTime else { return }  // swiftlint:disable:this conditional_returns_on_newline

    isSaving = true
    errorMessage = nil

    do {
      if let job = await jobRequiringPaySetup(selectedJobId) {
        onPaySetupRequired(startTime, resolvedEndTime, selectedJobId, job)
        isSaving = false
        dismiss()
        return
      }

      try await onSave(startTime, resolvedEndTime, selectedJobId)
      dismiss()
    } catch {
      errorMessage = ErrorTranslations.translate(error)
    }

    isSaving = false
  }

  private func discard() async {
    guard !isWorking else { return }  // swiftlint:disable:this conditional_returns_on_newline

    isDiscarding = true
    await onDiscard()
    isDiscarding = false
    dismiss()
  }

  private func ensureJobsLoaded() async {
    guard availableJobs.isEmpty else { return }  // swiftlint:disable:this conditional_returns_on_newline
    let loadedJobs = await loadJobs()  // swiftlint:disable:this explicit_type_interface
    guard !loadedJobs.isEmpty else { return }  // swiftlint:disable:this conditional_returns_on_newline
    availableJobs = loadedJobs
    if selectedJobId == nil {
      selectedJobId = loadedJobs.first(where: \.is_default)?.id ?? loadedJobs.first?.id
    }
  }
}

private struct DashboardClockJobChooserSheet: View {
  let loadJobs: (() async -> [Job])?
  let onSelect: (String) -> Void
  let onCancel: () -> Void

  @State private var jobs: [Job]
  @State private var isLoading: Bool

  init(  // swiftlint:disable:this type_contents_order
    initialJobs: [Job],
    loadJobs: (() async -> [Job])? = nil,
    onSelect: @escaping (String) -> Void,
    onCancel: @escaping () -> Void
  ) {
    self.loadJobs = loadJobs
    self.onSelect = onSelect
    self.onCancel = onCancel
    _jobs = State(initialValue: initialJobs)
    _isLoading = State(initialValue: initialJobs.isEmpty && loadJobs != nil)
  }

  private var detentHeight: CGFloat {
    let visibleRows = max(1, min(jobs.count, 4))  // swiftlint:disable:this explicit_type_interface no_magic_numbers
    return CGFloat(visibleRows) * 70 + 120  // swiftlint:disable:this no_magic_numbers
  }

  var body: some View {
    NavigationStack {  // swiftlint:disable:this closure_body_length
      ScrollView {  // swiftlint:disable:this closure_body_length
        Group {  // swiftlint:disable:this closure_body_length
          if isLoading {
            VStack(spacing: Spacing.sm) {
              ProgressView()
              Text(.commonLoading)
                .font(.tidexFootnote)
                .foregroundColor(.tidexTextSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.lg)
          } else {
            VStack(spacing: Spacing.sm) {
              ForEach(jobs, id: \.id) { job in
                Button {
                  onSelect(job.id)
                } label: {
                  HStack(spacing: Spacing.sm) {
                    WorkplaceNameText(
                      name: job.name,
                      colorHex: job.color,
                      font: .tidexBodyMedium,
                      fallbackBadgeColor: .tidexBlue
                    )

                    Spacer()

                    Image(systemName: "chevron.right")  // swiftlint:disable:this accessibility_label_for_image
                      .font(.tidexCaptionRegular)
                      .foregroundColor(.tidexTextMuted)
                  }
                  .padding(.horizontal, Spacing.md)
                  .padding(.vertical, Spacing.md)
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .background(Color.tidexSurfaceSecondary)
                  .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
                  .contentShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
              }
            }
          }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.sm)
        .padding(.bottom, Spacing.md)
      }
      .scrollIndicators(.hidden)
      .background(Color.tidexBackground)
      .navigationTitle(String(localized: .settingsPayChooseJobTitle))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(String(localized: .commonCancel)) {
            onCancel()
          }
        }
      }
    }
    .task {
      await ensureJobsLoaded()
    }
    .presentationDetents([.height(detentHeight)])
    .presentationDragIndicator(.visible)
  }

  private func ensureJobsLoaded() async {
    guard jobs.isEmpty, let loadJobs else { return }  // swiftlint:disable:this conditional_returns_on_newline
    let loadedJobs = await loadJobs()  // swiftlint:disable:this explicit_type_interface
    jobs = loadedJobs
    isLoading = false

    if loadedJobs.count == 1, let onlyJobId = loadedJobs.first?.id {
      onSelect(onlyJobId)
    }
  }
}

#Preview {
  struct PreviewWrapper: View {
    @State private var selectedTab: MainTabView.Tab = .home
    @State private var showStatsView = false  // swiftlint:disable:this explicit_type_interface

    var body: some View {
      DashboardView(selectedTab: $selectedTab, showStatsView: $showStatsView)
        .environmentObject(AppCoordinator.shared)
    }
  }

  return PreviewWrapper()
}  // swiftlint:disable:this file_length
