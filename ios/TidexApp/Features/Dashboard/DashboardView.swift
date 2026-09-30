import SwiftUI

private struct EventSheetSelection: Identifiable {
  let event: EventRow
  let startInEditMode: Bool

  var id: String { event.id }
}

/// An action queued to run once the sheet that triggered it has finished dismissing.
/// Presenting a new sheet while another is still animating out is a no-op in SwiftUI,
/// so this replaces `DispatchQueue.main.asyncAfter` guesswork with a real `onDismiss` hook.
private enum PendingDashboardSheetAction {
  case shiftDelete(ShiftWithComputations)
  case eventDelete(EventRow)
  case recurringEdit(RecurringShiftRow)
  case calendarSubscriptionSettings
}

/// Dashboard view showing the main financial overview
/// Displays payroll, total earnings, and featured shift cards
struct DashboardView: View {  // swiftlint:disable:this explicit_acl explicit_top_level_acl file_types_order line_length type_body_length
  @Environment(AppCoordinator.self) private var coordinator  // swiftlint:disable:this type_contents_order
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize  // swiftlint:disable:this explicit_type_interface line_length type_contents_order
  @Environment(\.layoutDirection) private var layoutDirection  // swiftlint:disable:this explicit_type_interface line_length type_contents_order

  /// Binding to the selected tab for navigation
  @Binding var selectedTab: MainTabView.Tab  // swiftlint:disable:this explicit_acl type_contents_order
  @Binding var showStatsView: Bool  // swiftlint:disable:this explicit_acl type_contents_order

  @State private var viewModel = DashboardViewModel()  // swiftlint:disable:this explicit_type_interface line_length type_contents_order
  private let calendarSubscriptionStore = CalendarSubscriptionStore.shared  // swiftlint:disable:this explicit_type_interface line_length type_contents_order
  @State private var workSetupPresentationViewModel = WorkSetupPresentationViewModel()  // swiftlint:disable:this explicit_type_interface line_length type_contents_order
  private let pushManager = PushNotificationManager.shared  // swiftlint:disable:this explicit_type_interface line_length type_contents_order
  private let syncStatusManager = SyncStatusManager.shared  // swiftlint:disable:this explicit_type_interface line_length type_contents_order

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

  /// State for recurring shift editing
  @State private var recurringShiftToEdit: RecurringShiftRow?  // swiftlint:disable:this type_contents_order
  @State private var temporaryClockReviewSession: TemporaryClockSession?  // swiftlint:disable:this type_contents_order
  @State private var clockInJobOptions: [Job] = []  // swiftlint:disable:this type_contents_order
  @State private var showClockInJobChooser: Bool = false  // swiftlint:disable:this type_contents_order
  @State private var clockPaySetupJob: Job?  // swiftlint:disable:this type_contents_order
  @State private var pendingClockAction: PendingClockAction?  // swiftlint:disable:this type_contents_order
  @State private var showMixedCurrencyBreakdownPopover: Bool = false  // swiftlint:disable:this type_contents_order
  @State private var activeDashboardRefreshTask: Task<Void, Never>?  // swiftlint:disable:this type_contents_order
  @State private var showCalendarSubscriptionSettings: Bool = false  // swiftlint:disable:this type_contents_order
  @State private var selectedPayrollDetailsVariant: PayrollCardVariant?  // swiftlint:disable:this type_contents_order
  /// False only for a user with no shifts at all, who sees the first-shift prompt.
  @State private var hasAnyShifts = true  // swiftlint:disable:this explicit_type_interface type_contents_order

  // Action to run once the currently-presented sheet finishes dismissing, so two sheets
  // never race to present at once (see `performPendingSheetAction`).
  @State private var pendingSheetAction: PendingDashboardSheetAction?  // swiftlint:disable:this type_contents_order

  private enum PendingClockAction {
    case clockIn(jobId: String?)
    case temporaryClockOut(start: Date, end: Date, jobId: String?)
  }

  @ViewBuilder
  // swiftlint:disable:next type_contents_order
  private func shiftDetailsSheet(for shift: ShiftWithComputations) -> some View {
    // swiftlint:disable:next explicit_type_interface
    let shiftJob = viewModel.shouldShowJobIndicators ? viewModel.jobForShift(shift) : nil
    ShiftDetailsSheet(
      shift: shift,
      jobName: shiftJob?.name,
      jobColorHex: shiftJob?.color,
      onDelete: {
        pendingSheetAction = .shiftDelete(shift)
        selectedShift = nil
      },
      onUpdate: { editResult in
        try await applyShiftEdit(editResult, originalShift: shift)
      },
      onUpdatePause: { pauseResult in
        selectedShift = nil
        Task {
          await viewModel.updateShiftPause(pauseResult)
        }
      },
      onEditRecurring: { recurringId in
        if let recurring = viewModel.getRecurringShift(id: recurringId) {
          pendingSheetAction = .recurringEdit(recurring)
        }
        selectedShift = nil
      },
      onStopRecurringAfterDate: { recurringId, occurrenceDate in
        try await viewModel.stopRecurringShiftAfterDate(
          recurringId: recurringId,
          occurrenceDate: occurrenceDate
        )
        selectedShift = nil
      },
      showsCalendarSubscriptionCTA: calendarSubscriptionStore.canOfferSetup,
      onShowInCalendarRequested: {
        openCalendarSubscriptionSetupFromDashboard()
      },
      tariffRules: viewModel.getTariffRules(for: shift.shiftDate)
    )
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.visible)
  }

  private func applyShiftEdit(
    _ editResult: ShiftEditResult,
    originalShift: ShiftWithComputations
  ) async throws {  // swiftlint:disable:this type_contents_order
    let shouldKeepSheetOpen = shouldKeepShiftDetailsOpen(  // swiftlint:disable:this explicit_type_interface
      after: editResult, originalShift: originalShift)  // swiftlint:disable:this multiline_arguments_brackets
    try await viewModel.updateShift(editResult)
    if shouldKeepSheetOpen {
      if let refreshedShift = viewModel.getDisplayedShift(id: editResult.shiftId) {
        selectedShift = refreshedShift
      }
    } else {
      selectedShift = nil
    }
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

  @ScaledMetric(relativeTo: .body) private var payrollSectionMinHeight: CGFloat = 89  // swiftlint:disable:this explicit_type_interface line_length type_contents_order
  @ScaledMetric(relativeTo: .body) private var featuredSectionMinHeight: CGFloat = 118  // swiftlint:disable:this explicit_type_interface line_length type_contents_order
  @ScaledMetric(relativeTo: .largeTitle) private var errorIconSize: CGFloat = 48  // swiftlint:disable:this explicit_type_interface line_length no_magic_numbers type_contents_order

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

  private func refreshHasAnyShifts() {  // swiftlint:disable:this type_contents_order
    hasAnyShifts = ShiftsRepository.shared.hasAnyShifts(
      for: coordinator.userId,
      initialSyncComplete: coordinator.initialSyncComplete
    )
  }

  private func handleInitialSyncCompleteChange(completed: Bool) {  // swiftlint:disable:this type_contents_order
    refreshHasAnyShifts()
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
    refreshHasAnyShifts()
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

  private func handleDashboardDataChange(_ data: DashboardData?) {  // swiftlint:disable:this line_length type_contents_order unused_parameter
    showMixedCurrencyBreakdownPopover = false
    refreshHasAnyShifts()
  }

  private func handleDashboardAppear() {  // swiftlint:disable:this type_contents_order
    viewModel.setActiveTabVisible(selectedTab == .home)
    refreshWorkSetupPresentationState()
    guard selectedTab == .home else { return }  // swiftlint:disable:this conditional_returns_on_newline
    guard !shouldShowWorkSetupRequiredPlaceholder else { return }  // swiftlint:disable:this conditional_returns_on_newline line_length
    refreshActiveDashboardStateIfNeeded()
  }

  private func handleSelectedTabChange(oldTab: MainTabView.Tab, newTab: MainTabView.Tab) {  // swiftlint:disable:this line_length type_contents_order
    guard oldTab != newTab else { return }  // swiftlint:disable:this conditional_returns_on_newline
    viewModel.setActiveTabVisible(newTab == .home)
    if newTab == .home {
      refreshWorkSetupPresentationState()
      refreshActiveDashboardStateIfNeeded()
    } else {
      activeDashboardRefreshTask?.cancel()
      activeDashboardRefreshTask = nil
    }
  }

  private func openCalendarSubscriptionSetupFromDashboard() {  // swiftlint:disable:this type_contents_order
    pendingSheetAction = .calendarSubscriptionSettings
    selectedShift = nil
    selectedEvent = nil
  }

  /// Runs the sheet queued by `pendingSheetAction`, called from the dismissed sheet's
  /// `onDismiss`. Attach this to every `.sheet` that can set `pendingSheetAction`.
  private func performPendingSheetAction() {  // swiftlint:disable:this type_contents_order
    guard let action = pendingSheetAction else { return }
    pendingSheetAction = nil
    switch action {
    case .shiftDelete(let shift):
      shiftToDelete = shift
      showDeleteConfirmation = true
    case .eventDelete(let event):
      eventToDelete = event
      showEventDeleteConfirmation = true
    case .recurringEdit(let recurring):
      recurringShiftToEdit = recurring
    case .calendarSubscriptionSettings:
      showCalendarSubscriptionSettings = true
    }
  }

  /// Variant ids are per job, so the same id can belong to both the next and the previous payout.
  private func isSamePayout(_ lhs: PayrollCardVariant, _ rhs: PayrollCardVariant) -> Bool {  // swiftlint:disable:this line_length type_contents_order
    lhs.id == rhs.id
      && lhs.jobBreakdowns.first?.earningsPeriodStart
        == rhs.jobBreakdowns.first?.earningsPeriodStart
  }

  /// The previous payout for the displayed month, or nil when the sheet already shows it.
  private func previousPayrollVariant(unlessShowing variant: PayrollCardVariant)  // swiftlint:disable:this line_length type_contents_order
    -> PayrollCardVariant?
  {
    guard let data = viewModel.dashboardData,
      let previous = viewModel.previousPayrollCardVariants(
        fallback: data,
        defaultTitle: String(localized: .dashboardPreviousPayout)
      ).first,
      !isSamePayout(previous, variant)
    else { return nil }
    return previous
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
      },
      onShowPreviousPayout: previousPayrollVariant(unlessShowing: variant).map { previous in
        { selectedPayrollDetailsVariant = previous }
      }
    )
    .userCurrency(variant.currency)
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.visible)
  }

  private var navigationContent: some View {
    NavigationStack {  // swiftlint:disable:this closure_body_length
      ZStack {
        TidexAppBackground()

        // Main content - month picker is now in shared overlay.
        // ZStack, not Group: Group would apply .animation to each branch, so the swap wouldn't animate.
        ZStack {
          if shouldShowWorkSetupRequiredPlaceholder {
            WorkSetupRequiredPlaceholder()
          } else if let data = viewModel.dashboardData {
            // Keep loaded content visible when a later refresh fails
            cardContent(data: data)
          } else if let error = viewModel.error {
            errorView(error: error)
          } else {
            // Show skeleton cards with shimmer while loading or waiting for sync
            // This provides a consistent visual preview of the layout
            loadingSkeletonView
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Crossfade skeleton to content instead of swapping abruptly on launch
        .animation(.easeOut(duration: 0.3), value: viewModel.dashboardData == nil)  // swiftlint:disable:this no_magic_numbers line_length

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
          Image("TidexLogo")
            .resizable()
            .scaledToFit()
            .frame(height: Spacing.xl)
            .accessibilityLabel(Text(.tabsHome))
            .accessibilityAddTraits(.isHeader)
        }
        .sharedBackgroundVisibility(.hidden)
        ToolbarItem(placement: .topBarTrailing) {
          statsToolbarButton
        }
      }
      .navigationDestination(isPresented: $showStatsView) {
        StatsView()
          .id(coordinator.userId)
      }
      .addShiftDestination(in: .home)
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
    .accessibilityIdentifier("home.stats")
  }

  private var bodyWithLifecycle: AnyView {
    AnyView(
      navigationContent
        .task {
          viewModel.setActiveTabVisible(selectedTab == .home)
          refreshWorkSetupPresentationState()
          refreshHasAnyShifts()
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
        }
        .onChange(of: selectedTab) { oldTab, newTab in
          handleSelectedTabChange(oldTab: oldTab, newTab: newTab)
        }
        .onReceive(NotificationCenter.default.publisher(for: .shiftsDidChange)) { notification in
          // A shift added or deleted in another month doesn't reload Home, so check here.
          refreshHasAnyShifts()
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
        .task {
          while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(30))  // swiftlint:disable:this no_magic_numbers
            guard selectedTab == .home else { continue }
            guard !shouldShowWorkSetupRequiredPlaceholder else { continue }
            await viewModel.refreshClockState()
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
      .sheet(item: $selectedPayrollDetailsVariant) { variant in
        payrollDetailsSheet(for: variant)
      }
      .onChange(of: viewModel.payrollCardSnapshot) { _, snapshot in
        guard let selected = selectedPayrollDetailsVariant, let snapshot else { return }
        if let updated = (snapshot.variants + snapshot.previousPayoutVariants).first(where: {
          isSamePayout($0, selected)
        }) {
          selectedPayrollDetailsVariant = updated
        }
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
            AccessibilityNotification.Announcement(String(localized: .dashboardAccessibilityClockedOut))
              .post()
          },
          onDiscard: {
            await viewModel.discardTemporaryClockSession()
          }
        )
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
      }
      .sheet(isPresented: $showClockInJobChooser) {
        JobChooserSheet(
          jobs: clockInJobOptions,
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
      .sheet(
        item: $selectedShift, onDismiss: performPendingSheetAction
      ) { shift in
        shiftDetailsSheet(for: shift)
      }
      .sheet(item: $selectedEvent, onDismiss: performPendingSheetAction) { selection in
        EventDetailsSheet(
          event: selection.event,
          onDelete: {
            pendingSheetAction = .eventDelete(selection.event)
            selectedEvent = nil
          },
          onUpdate: { editResult in
            try await viewModel.updateEvent(editResult)
            selectedEvent = nil
          },
          onInlineReminderUpdate: { editResult in
            try await viewModel.updateEvent(editResult)
          },
          showsCalendarSubscriptionCTA: calendarSubscriptionStore.canOfferSetup,
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
    Haptics.play(.medium)

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
    Haptics.play(.medium)

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

  private struct CountdownState {
    let text: String
    let isActive: Bool
    let progress: Double
    let finalSeconds: Int?
  }

  private struct CountdownTarget {
    let shiftDate: String
    let startTime: String
    let endTime: String
  }

  /// Shift/event date and times to feed the countdown, if the featured item currently tracks one.
  private func countdownTarget(for data: DashboardData) -> CountdownTarget? {
    // swiftlint:disable:previous type_contents_order
    switch data.featuredItem {
    case .shift(let shift)
    where data.isViewingCurrentMonth && !data.featuredShiftIsBestShift:
      return CountdownTarget(
        shiftDate: shift.shiftDate, startTime: shift.startTime, endTime: shift.endTime)

    case .event(let event, _)
    where data.isViewingCurrentMonth && !data.featuredShiftIsBestShift && !event.is_all_day:
      guard let startTime = event.start_time, let endTime = event.end_time else { return nil }  // swiftlint:disable:this conditional_returns_on_newline line_length
      return CountdownTarget(
        shiftDate: event.start_date, startTime: startTime, endTime: endTime)

    default:
      return nil
    }
  }

  /// Countdown text/progress for the featured item at `now`, recomputed on every timeline tick.
  private func countdownState(for data: DashboardData, now: Date) -> CountdownState? {  // swiftlint:disable:this line_length type_contents_order
    guard let target = countdownTarget(for: data) else { return nil }  // swiftlint:disable:this conditional_returns_on_newline line_length

    let (text, isActive, progress) = CountdownFormatter.formatShiftCountdown(
      shiftDate: target.shiftDate,
      startTime: target.startTime,
      endTime: target.endTime,
      now: now
    )
    let finalSeconds = CountdownFormatter.finalCountdownSecondsForShift(
      shiftDate: target.shiftDate,
      startTime: target.startTime,
      endTime: target.endTime,
      now: now
    )
    return CountdownState(
      text: text, isActive: isActive, progress: progress, finalSeconds: finalSeconds)
  }

  private func featuredEventCountdownStatus(_ event: EventRow, now: Date)  // swiftlint:disable:this type_contents_order
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
  private func featuredEventFooter(_ event: EventRow, now: Date, state: CountdownState?)
    -> some View
  {  // swiftlint:disable:this type_contents_order
    if event.is_all_day {
      HStack(spacing: Spacing.xxxs) {
        Image(systemName: "calendar")
          .font(.tidexCaptionRegular)
          .foregroundColor(.tidexTextSecondary)
          .accessibilityHidden(true)
        Text(.addShiftEventAllDay)
          .font(.tidexLabel)
          .foregroundColor(.tidexTextSecondary)
      }
      .frame(minHeight: 20)  // swiftlint:disable:this no_magic_numbers
    } else if let countdownText = state?.text {
      ShiftCountdownBadge(
        text: countdownText,
        status: featuredEventCountdownStatus(event, now: now),
        finalCountdownSeconds: state?.finalSeconds
      )
      .frame(minHeight: 20)  // swiftlint:disable:this no_magic_numbers
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
      centeredDashboardCards {
        // Animated card content - centered vertically
        animatedCardContent(data: data)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    // Pass user's currency to all child views
    .userCurrency(data.currency)
  }

  /// Centers the cards between the toolbar and the month picker. At accessibility text sizes the
  /// cards are taller than the screen, so they scroll from the top instead of being squeezed
  /// into a viewport-height frame.
  @ViewBuilder
  private func centeredDashboardCards<Content: View>(  // swiftlint:disable:this type_contents_order
    @ViewBuilder content: @escaping () -> Content
  ) -> some View {
    if dynamicTypeSize.isAccessibilitySize {
      content()
        .frame(maxWidth: AdaptiveMaxWidth.tabContent)
        .padding(.horizontal, Spacing.xxl)
        .padding(.top, Spacing.lg)
        // Offset for month picker overlay so the last card stays reachable
        .padding(.bottom, MonthPickerLayout.totalBottomInset)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    } else {
      GeometryReader { geometry in
        VStack(spacing: 0) {
          Spacer()

          content()
            .frame(maxWidth: AdaptiveMaxWidth.tabContent)
            .padding(.horizontal, Spacing.xxl)

          Spacer()
        }
        // Offset for month picker overlay so content centers in available space
        .padding(.bottom, MonthPickerLayout.totalBottomInset)
        .frame(width: geometry.size.width, height: geometry.size.height)
        .contentShape(Rectangle())
      }
      .contentShape(Rectangle())
    }
  }

  // MARK: - Animated Card Content

  @ViewBuilder
  private func animatedCardContent(data: DashboardData) -> some View {  // swiftlint:disable:this cyclomatic_complexity function_body_length line_length type_contents_order
    let now = Date()  // swiftlint:disable:this explicit_type_interface
    let calendar = Calendar.gregorianCurrent  // swiftlint:disable:this explicit_type_interface
    let isViewingCurrentMonth = data.isViewingCurrentMonth  // swiftlint:disable:this explicit_type_interface
    let preliminaryPayrollVariants = viewModel.payrollCardVariants(  // swiftlint:disable:this explicit_type_interface
      fallback: data,
      defaultTitle: String(localized: .dashboardPayroll)
    )
    let nextPayoutLabel = String(localized: .dashboardNextPayout)  // swiftlint:disable:this explicit_type_interface
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
          : nextPayoutLabel
      }

      if selectedPayoutYM.year < current.year
        || (selectedPayoutYM.year == current.year && selectedPayoutYM.month < current.month)
      {
        return String(localized: .dashboardEarlierPayout)
      }

      if isCurrentAdvancedNextPayout {
        return nextPayoutLabel
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
      VStack(spacing: Spacing.lg) {  // swiftlint:disable:this closure_body_length
        // Total Card (Displayed Month) - THE ANCHOR
        // Numbers animate smoothly when values change
        let toggleMixedCurrencyBreakdown = {  // swiftlint:disable:this explicit_type_interface
          if data.currentMonthCurrencyAggregate.hasMixedCurrency {
            Haptics.play(.medium)
            showMixedCurrencyBreakdownPopover.toggle()
          }
        }
        TotalCard(
          gross: data.currentMonthGross,
          net: data.currentMonthNet,
          completedGross: data.currentMonthCompletedGross,
          completedNet: data.currentMonthCompletedNet,
          shiftCount: data.currentMonthShiftCount,
          plannedCount: data.currentMonthPlannedCount,
          percentageChange: data.percentageChangeVsPrevious,
          taxEnabled: data.currentMonthTaxEnabled,
          monthName: data.currentMonthName,
          showsCurrencyBreakdownCue: data.currentMonthCurrencyAggregate.hasMixedCurrency,
          isElevated: false
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: toggleMixedCurrencyBreakdown)
        .accessibilityElement(children: .combine)
        .accessibilityAction(.default, toggleMixedCurrencyBreakdown)
        .accessibilityAddTraits(
          data.currentMonthCurrencyAggregate.hasMixedCurrency ? .isButton : []
        )
        .accessibilityHint(
          data.currentMonthCurrencyAggregate.hasMixedCurrency
            ? Text(.dashboardTotalMixedCurrencyHint) : Text(verbatim: "")
        )
        .popover(isPresented: $showMixedCurrencyBreakdownPopover) {
          MixedCurrencyBreakdownPopover(entries: data.currentMonthCurrencyAggregate.secondary)
            .presentationCompactAdaptation(.popover)
        }

        if viewModel.shouldShowDashboardClockButtons {
          clockButtonsSection()
        }

        // The previous payout is reached from the payout details sheet, so the payout
        // and the featured shift are the only rows here.
        VStack(spacing: Spacing.sm) {
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
            height: usesFixedCardHeights ? payrollSectionMinHeight : nil,
            alignment: .top
          )

          // Featured Shift Card - exact height on regular Dynamic Type to avoid
          // skeleton/content vertical recentering during the loading transition.
          if usesFixedCardHeights {
            featuredShiftSection(data: data)
              .frame(height: featuredSectionMinHeight, alignment: .top)
          } else {
            featuredShiftSection(data: data)
          }
        }
      }
      .contentShape(Rectangle())
      .gesture(monthSwipeGesture())
    } else {
      EmptyView()
    }
  }

  private func monthSwipeGesture() -> some Gesture {  // swiftlint:disable:this type_contents_order
    DragGesture(minimumDistance: 30)  // swiftlint:disable:this no_magic_numbers
      .onEnded { value in
        let horizontal = value.translation.width  // swiftlint:disable:this explicit_type_interface
        let vertical = abs(value.translation.height)  // swiftlint:disable:this explicit_type_interface

        guard abs(horizontal) > vertical else { return }  // swiftlint:disable:this conditional_returns_on_newline

        Haptics.play(.medium)

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
  private func clockButtonsSection() -> some View {  // swiftlint:disable:this function_body_length type_contents_order
    let layout =  // swiftlint:disable:this explicit_type_interface
      dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(spacing: Spacing.sm))
      : AnyLayout(HStackLayout(spacing: Spacing.sm))
    layout {  // swiftlint:disable:this closure_body_length
      clockButton(
        title: .dashboardClockIn,
        systemImage: "play.fill",
        isEnabled: viewModel.isClockInEnabled
      ) {
        guard viewModel.isClockInEnabled else { return }  // swiftlint:disable:this conditional_returns_on_newline
        Haptics.play(.medium)
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
        Haptics.play(.medium)
        Task {
          let route = await viewModel.routeClockOut()  // swiftlint:disable:this explicit_type_interface
          if case .temporaryReview(let session) = route {
            await presentTemporaryClockReview(session)
          } else if case .persistedEnded = route {
            AccessibilityNotification.Announcement(String(localized: .dashboardAccessibilityClockedOut))
              .post()
          }
        }
      }
    }
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
    }
    .buttonStyle(DashboardClockButtonStyle())
    .disabled(!isEnabled)
  }

  @ViewBuilder
  private func clockButtonsSkeletonSection() -> some View {  // swiftlint:disable:this type_contents_order
    HStack(spacing: Spacing.sm) {
      clockButton(
        title: .dashboardClockIn,
        systemImage: "play.fill",
        isEnabled: false,
        action: {}
      )

      clockButton(
        title: .dashboardClockOut,
        systemImage: "stop.fill",
        isEnabled: false,
        action: {}
      )
    }
    .redacted(reason: .placeholder)
    .shimmer(isActive: true)
    .accessibilityHidden(true)
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
    // The received override only changes anything on payday, so the visible toggle is payday-only.
    let showsReceivedToggle =  // swiftlint:disable:this explicit_type_interface
      canManuallySetPayrollStatus && !isLoading
      && Calendar.gregorianCurrent.isDateInToday(selectedVariant.payoutDate)
    let toggleReceived = {  // swiftlint:disable:this explicit_type_interface
      Haptics.play(payrollMarkedReceived ? .medium : .success)
      if payrollMarkedReceived {
        viewModel.clearPayrollReceivedOverrideForDisplayedMonth(userId: payrollOverrideUserId)
      } else {
        viewModel.markPayrollReceivedForDisplayedMonth(userId: payrollOverrideUserId)
      }
    }

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
      showsLoadingShimmer: showsLoadingShimmer,
      isElevated: false,
      isMarkedReceived: payrollMarkedReceived,
      onToggleReceived: showsReceivedToggle ? toggleReceived : nil
    )

    let openPayrollDetails = {  // swiftlint:disable:this explicit_type_interface
      guard !isLoading else { return }  // swiftlint:disable:this conditional_returns_on_newline
      Haptics.play(.medium)
      selectedPayrollDetailsVariant = selectedVariant
    }

    // Re-runs when another celebration closes or the payout turns positive, so payday waits
    // its turn instead of being skipped.
    let celebrationManager = ShiftCompletionCelebrationManager.shared  // swiftlint:disable:this explicit_type_interface
    let paydayAmount: Double =
      selectedVariant.taxEnabled ? (selectedVariant.net ?? selectedVariant.gross) : selectedVariant.gross
    let paydayCelebrationID: String? =
      showsReceivedToggle && paydayAmount > 0 && celebrationManager.celebrationData == nil
      ? selectedVariant.payoutDate.toISODateString()
      : nil

    card
      .task(id: paydayCelebrationID) {
        guard paydayCelebrationID != nil, let payrollOverrideUserId else { return }  // swiftlint:disable:this conditional_returns_on_newline line_length
        celebrationManager.celebratePaydayIfNeeded(
          userId: payrollOverrideUserId,
          payoutDate: selectedVariant.payoutDate,
          amount: paydayAmount,
          currency: selectedVariant.currency
        )
      }
      .userCurrency(selectedVariant.currency)
      .accessibilityIdentifier("home.payroll-card")
      .contentShape(Rectangle())
      .onTapGesture(perform: openPayrollDetails)
      .accessibilityElement(children: .combine)
      .accessibilityAddTraits(.isButton)
      .accessibilityAction(.default, openPayrollDetails)
      .accessibilityHint(Text(.dashboardPayrollDetailsTitle))
      // The skeleton has no text, so an empty button would be announced.
      .accessibilityHidden(isLoading)
      .accessibilityActions {
        if showsReceivedToggle {
          Button(
            payrollMarkedReceived
              ? String(localized: .dashboardPayrollStatusNotReceived)
              : String(localized: .dashboardPayrollMarkReceived),
            action: toggleReceived
          )
        }
      }
      .contextMenu {
        if canManuallySetPayrollStatus, !isLoading {
          Button {
            Haptics.play(.medium)
            viewModel.markPayrollReceivedForDisplayedMonth(userId: payrollOverrideUserId)
          } label: {
            Label(
              String(localized: .dashboardPayrollStatusReceived),
              systemImage: payrollMarkedReceived ? "checkmark.circle.fill" : "circle"
            )
          }

          Button {
            Haptics.play(.medium)
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

  // MARK: - Featured Shift Section

  /// Featured shift card with fixed height to prevent layout jumps
  @ViewBuilder
  private func featuredShiftSection(data: DashboardData) -> some View {  // swiftlint:disable:this type_contents_order
    TimelineView(.periodic(from: .now, by: 1)) { context in
      featuredShiftContent(data: data, now: context.date)
    }
  }

  @ViewBuilder
  private func featuredShiftContent(data: DashboardData, now: Date) -> some View {  // swiftlint:disable:this function_body_length line_length type_contents_order
    // Use a fixed height container so the layout doesn't shift
    // when switching between FeaturedShiftCard and EmptyShiftCard
    Group {  // swiftlint:disable:this closure_body_length
      if case .temporary(let session) = viewModel.activeClockState {
        let temporaryShift = viewModel.temporaryFeaturedShift(  // swiftlint:disable:this explicit_type_interface
          from: session,
          at: now
        )
        let shiftJob = viewModel.jobForTemporarySession(session)  // swiftlint:disable:this explicit_type_interface
        let openTemporaryReview = {  // swiftlint:disable:this explicit_type_interface
          Haptics.play(.medium)
          Task {
            await presentTemporaryClockReview(session)
          }
        }
        FeaturedShiftCard(
          shift: temporaryShift,
          isToday: true,
          isBestShift: false,
          countdownText: String(localized: .commonInProgress),
          progress: 0,
          finalCountdownSeconds: nil,
          showTimeRangeEndSkeleton: false,
          surfaceStyle: .flat
        )
        .userCurrency(shiftJob?.currency ?? data.currency)
        .contentShape(Rectangle())
        .onTapGesture(perform: openTemporaryReview)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits([.isButton, .updatesFrequently])
        .accessibilityAction(.default, openTemporaryReview)
      } else if let featuredItem = data.featuredItem {
        switch featuredItem {
        case .shift(let featuredShift):
          // Only show progress bar for active shifts (matching Next.js behavior)
          let state = countdownState(for: data, now: now)  // swiftlint:disable:this explicit_type_interface
          let isActive = state?.isActive ?? false
          let shiftProgress: Double? = isActive ? state?.progress : nil
          let displayedFeaturedShift: ShiftWithComputations =
            isActive
            ? viewModel.liveFeaturedShiftWhileOngoing(from: featuredShift, at: now)
            : featuredShift
          let shiftJob = viewModel.jobForShift(featuredShift)  // swiftlint:disable:this explicit_type_interface
          let openFeaturedShift = {  // swiftlint:disable:this explicit_type_interface
            Haptics.play(.medium)
            if isActive {
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
          FeaturedShiftCard(
            shift: displayedFeaturedShift,
            isToday: data.isFeaturedItemToday,
            isBestShift: data.featuredShiftIsBestShift,
            countdownText: state?.text,
            progress: shiftProgress,
            finalCountdownSeconds: state?.finalSeconds,
            surfaceStyle: .flat
          )
          .userCurrency(shiftJob?.currency ?? data.currency)
          .contentShape(Rectangle())
          .onTapGesture(perform: openFeaturedShift)
          .accessibilityElement(children: .combine)
          .accessibilityAddTraits([.isButton, .updatesFrequently])
          .accessibilityAction(.default, openFeaturedShift)

        case .event(let event, let coveredDateISO):  // swiftlint:disable:this pattern_matching_keywords
          VStack(spacing: Spacing.sm) {
            EventRowCard(
              event: event,
              coveredDateISO: coveredDateISO,
              onTap: {
                Haptics.play(.medium)
                selectedEvent = EventSheetSelection(event: event, startInEditMode: false)
              },
              showTodayHighlight: false,
              isElevated: false
            )

            featuredEventFooter(event, now: now, state: countdownState(for: data, now: now))
          }
        }
      } else if !hasAnyShifts {
        FirstShiftPrompt {
          coordinator.pendingDeepLink = .addShift(mode: nil, date: nil)
        }
      } else {
        EmptyShiftCard(
          onAddShift: {
            coordinator.pendingDeepLink = .addShift(mode: nil, date: nil)
          },
          isElevated: false
        )
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
    if case .temporary = viewModel.activeClockState {
      AccessibilityNotification.Announcement(String(localized: .dashboardAccessibilityClockedIn))
        .post()
    }
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
      centeredDashboardCards {  // swiftlint:disable:this closure_body_length
        // Skeleton cards matching the real dashboard layout
        VStack(spacing: Spacing.lg) {  // swiftlint:disable:this closure_body_length
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
            isElevated: false,
            isLoading: true
          )

          if viewModel.shouldShowDashboardClockButtons {
            clockButtonsSkeletonSection()
          }

          VStack(spacing: Spacing.sm) {
            // Payroll Card skeleton
            PayrollCard(
              payrollDate: Date(),
              label: String(localized: .dashboardNextPayout),
              gross: 0,
              net: nil,
              tax: nil,
              taxEnabled: false,
              isLoading: true,
              isElevated: false
            )
            .frame(
              height: usesFixedCardHeights ? payrollSectionMinHeight : nil,
              alignment: .top
            )

            // Featured Shift Card skeleton
            if usesFixedCardHeights {
              EmptyShiftCard(isLoading: true, isElevated: false)
                .frame(height: featuredSectionMinHeight, alignment: .top)
            } else {
              EmptyShiftCard(isLoading: true, isElevated: false)
            }
          }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(.commonLoading))
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  // MARK: - Error View

  @ViewBuilder
  private func errorView(error: Error) -> some View {
    VStack(spacing: Spacing.md) {
      Image(systemName: "exclamationmark.triangle")
        .font(.system(size: errorIconSize))
        .foregroundColor(.tidexWarning)
        .accessibilityHidden(true)

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
          .foregroundColor(.tidexBlueText)
          .padding(.horizontal, Spacing.mlg)
          .padding(.vertical, Spacing.sm)
          .background(Color.tidexBlue.opacity(0.1))  // swiftlint:disable:this no_magic_numbers
          .cornerRadius(CornerRadius.sm)
      }
    }
    .frame(maxWidth: AdaptiveMaxWidth.tabContent)
    .padding(.horizontal, Spacing.xxl)
    .announcesToVoiceOver(String(localized: .dashboardLoadError))
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
  @Environment(\.accessibilityReduceMotion) private var reduceMotion  // swiftlint:disable:this explicit_type_interface
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize  // swiftlint:disable:this explicit_type_interface
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
    return Calendar.gregorianCurrent.date(byAdding: .day, value: 1, to: endTime) ?? endTime
  }

  private var isValidRange: Bool {
    guard let startTime, let resolvedEndTime else { return false }  // swiftlint:disable:this conditional_returns_on_newline line_length
    return resolvedEndTime > startTime
  }

  private var showsCrossMidnightHint: Bool {
    guard let startTime, let resolvedEndTime else { return false }  // swiftlint:disable:this conditional_returns_on_newline line_length
    return !Calendar.gregorianCurrent.isDate(startTime, inSameDayAs: resolvedEndTime)
  }

  private var isWorking: Bool {
    isSaving || isDiscarding
  }

  private var durationText: String {
    guard isValidRange, let startTime, let resolvedEndTime else { return "--" }  // swiftlint:disable:this conditional_returns_on_newline line_length
    // swiftlint:disable:next explicit_type_interface no_magic_numbers
    let wholeMinutes = Duration.seconds(Int(resolvedEndTime.timeIntervalSince(startTime) / 60) * 60)
    return wholeMinutes.formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
  }

  var body: some View {
    NavigationStack {  // swiftlint:disable:this closure_body_length
      ScrollView {  // swiftlint:disable:this closure_body_length
        VStack(alignment: .leading, spacing: Spacing.md) {  // swiftlint:disable:this closure_body_length
          VStack(spacing: Spacing.xxs) {
            Text(durationText)
              .font(.tidexAmountLarge)
              .monospacedDigit()
              .foregroundColor(isValidRange ? .tidexTextPrimary : .tidexTextMuted)
              .contentTransition(reduceMotion ? .identity : .numericText())
              .animation(reduceMotion ? nil : .snappy, value: durationText)
            if let startTime {
              Text(startTime, format: .dateTime.weekday(.wide).day().month(.wide))
                .font(.tidexSubheadline)
                .foregroundColor(.tidexTextSecondary)
            }
          }
          .frame(maxWidth: .infinity)
          .accessibilityElement(children: .combine)

          VStack(spacing: Spacing.md) {  // swiftlint:disable:this closure_body_length
            TimeRangePicker(
              startTime: $startTime,
              endTime: $endTime,
              focusedFieldBinding: $focusedTimeField,
              showsRecentTimeChips: false
            )

            if availableJobs.count > 1 {
              Divider()

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
                      lineLimit: dynamicTypeSize.isAccessibilitySize ? nil : 1,
                      badgeHorizontalPadding: Spacing.xs,
                      badgeVerticalPadding: 2  // swiftlint:disable:this no_magic_numbers
                    )
                    .truncationMode(.tail)
                  }

                  Image(systemName: "chevron.up.chevron.down")
                    .font(.tidexMicro)
                    .foregroundColor(.tidexTextMuted)
                    .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
            }
          }
          .padding(Spacing.md)
          .background(
            RoundedRectangle(cornerRadius: CornerRadius.xxl)
              .fill(Color.tidexSurfacePrimary)
          )

          if showsCrossMidnightHint {
            HStack(spacing: Spacing.xs) {
              Image(systemName: "moon.fill")
                .font(.tidexCaption)
                .foregroundColor(.tidexTextSecondary)
                .accessibilityHidden(true)
              Text(.shiftsCrossMidnightInfo)
                .font(.tidexFootnote)
                .foregroundColor(.tidexTextSecondary)
            }
          }

          if let errorMessage {
            Text(errorMessage)
              .font(.tidexFootnote)
              .foregroundColor(.tidexError)
              .announcesToVoiceOver(errorMessage)
          }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.md)
      }
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
          Label(String(localized: .dashboardClockOutDiscardShift), systemImage: "trash")
            .font(.tidexLabel)
            .foregroundColor(.tidexError)
            .frame(maxWidth: .infinity, minHeight: 44)  // swiftlint:disable:this no_magic_numbers
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Spacing.md)
        .disabled(isWorking)
      }
      .task {
        await ensureJobsLoaded()
      }
      .sheet(isPresented: $showJobChooser) {
        JobChooserSheet(
          jobs: availableJobs,
          selectedJobId: selectedJobId,
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

#Preview {
  struct PreviewWrapper: View {
    @State private var selectedTab: MainTabView.Tab = .home
    @State private var showStatsView = false  // swiftlint:disable:this explicit_type_interface

    var body: some View {
      DashboardView(selectedTab: $selectedTab, showStatsView: $showStatsView)
        .environment(AppCoordinator.shared)
    }
  }

  return PreviewWrapper()
}  // swiftlint:disable:this file_length
