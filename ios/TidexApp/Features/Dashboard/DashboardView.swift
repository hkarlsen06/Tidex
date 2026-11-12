import SwiftUI

/// Dashboard view showing the main financial overview
/// Displays payroll, total earnings, and featured shift cards
struct DashboardView: View {  // swiftlint:disable:this explicit_acl explicit_top_level_acl file_types_order line_length type_body_length
  @Environment(AppCoordinator.self) var coordinator  // swiftlint:disable:this type_contents_order
  @Environment(\.dynamicTypeSize) var dynamicTypeSize  // swiftlint:disable:this explicit_type_interface line_length type_contents_order
  @Environment(\.layoutDirection) var layoutDirection  // swiftlint:disable:this explicit_type_interface line_length type_contents_order

  /// Binding to the selected tab for navigation
  @Binding var selectedTab: MainTabView.Tab  // swiftlint:disable:this explicit_acl type_contents_order
  @State private var addShiftPath: [AddShiftRoute] = []  // swiftlint:disable:this explicit_type_interface line_length type_contents_order

  @State var viewModel = DashboardViewModel()  // swiftlint:disable:this explicit_type_interface line_length type_contents_order
  private let calendarSubscriptionStore = CalendarSubscriptionStore.shared  // swiftlint:disable:this explicit_type_interface line_length type_contents_order
  @State private var workSetupPresentationViewModel = WorkSetupPresentationViewModel()  // swiftlint:disable:this explicit_type_interface line_length type_contents_order
  private let pushManager = PushNotificationManager.shared  // swiftlint:disable:this explicit_type_interface line_length type_contents_order
  private let syncStatusManager = SyncStatusManager.shared  // swiftlint:disable:this explicit_type_interface line_length type_contents_order

  /// State for showing push notification failure alert
  @State private var showPushFailureAlert = false  // swiftlint:disable:this explicit_type_interface type_contents_order
  @State var operationErrorMessage: String?  // swiftlint:disable:this type_contents_order

  /// Selected shift for showing details sheet
  @State var selectedShift: ShiftWithComputations?  // swiftlint:disable:this type_contents_order
  @State var selectedEvent: EventSheetSelection?  // swiftlint:disable:this type_contents_order

  /// Active featured shift target for action sheet actions
  @State var featuredShiftActionTarget: ShiftWithComputations?  // swiftlint:disable:this type_contents_order
  @State var showFeaturedShiftActions = false  // swiftlint:disable:this explicit_type_interface line_length type_contents_order

  /// State for delete confirmation
  @State private var showDeleteConfirmation = false  // swiftlint:disable:this explicit_type_interface line_length type_contents_order
  @State var shiftToDelete: ShiftWithComputations?  // swiftlint:disable:this type_contents_order
  @State private var showEventDeleteConfirmation = false  // swiftlint:disable:this explicit_type_interface line_length type_contents_order
  @State var eventToDelete: EventRow?  // swiftlint:disable:this type_contents_order

  /// State for recurring shift editing
  @State private var recurringShiftToEdit: RecurringShiftRow?  // swiftlint:disable:this type_contents_order
  @State var temporaryClockReviewSession: TemporaryClockSession?  // swiftlint:disable:this type_contents_order
  @State var clockInJobOptions: [Job] = []  // swiftlint:disable:this type_contents_order
  @State var showClockInJobChooser: Bool = false  // swiftlint:disable:this type_contents_order
  @State var clockPaySetupJob: Job?  // swiftlint:disable:this type_contents_order
  @State var pendingClockAction: PendingClockAction?  // swiftlint:disable:this type_contents_order
  @State var showMixedCurrencyBreakdownPopover: Bool = false  // swiftlint:disable:this type_contents_order
  @State private var activeDashboardRefreshTask: Task<Void, Never>?  // swiftlint:disable:this type_contents_order
  @State private var showCalendarSubscriptionSettings: Bool = false  // swiftlint:disable:this type_contents_order
  @State var selectedPayrollDetailsVariant: PayrollCardVariant?  // swiftlint:disable:this type_contents_order
  /// False only for a user with no shifts at all, who sees the first-shift prompt.
  @State var hasAnyShifts = true  // swiftlint:disable:this explicit_type_interface type_contents_order
  /// The pre-auth demo shift, when setup ended before the user kept or declined it.
  @State var carriedDemoShift: CarriedDemoShift?  // swiftlint:disable:this type_contents_order

  // Action to run once the currently-presented sheet finishes dismissing, so two sheets
  // never race to present at once (see `performPendingSheetAction`).
  @State private var pendingSheetAction: PendingDashboardSheetAction?  // swiftlint:disable:this type_contents_order

  enum PendingClockAction {
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
  var usesFixedCardHeights: Bool {
    !dynamicTypeSize.isAccessibilitySize
  }

  @ScaledMetric(relativeTo: .body) var payrollSectionMinHeight: CGFloat = 89  // swiftlint:disable:this explicit_type_interface line_length type_contents_order
  @ScaledMetric(relativeTo: .body) var featuredSectionMinHeight: CGFloat = 118  // swiftlint:disable:this explicit_type_interface line_length type_contents_order
  @ScaledMetric(relativeTo: .largeTitle) var errorIconSize: CGFloat = 48  // swiftlint:disable:this explicit_type_interface line_length no_magic_numbers type_contents_order

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
    carriedDemoShift = hasAnyShifts ? nil : OnboardingFirstShiftCarryoverStore.read()
  }

  /// Home features only a shift that hasn't ended this month. When a first shift added from
  /// Home is not one, a link opens Schedule on its month and highlights it there.
  private func showFirstShiftWhereHomeCannot() {  // swiftlint:disable:this type_contents_order
    let dates = CelebrationManager.shared.newlyAddedDates.sorted()
    guard selectedTab == .home, let userId = coordinator.userId,
      let first = dates.first.flatMap({ Date.fromISODateString($0) }),
      let last = dates.last.flatMap({ Date.fromISODateString($0) })
    else { return }
    let newShifts = ShiftsRepository.shared.getShifts(for: userId, startDate: first, endDate: last)
      .filter { dates.contains($0.shift_date) }
    // Recurring shifts have no stored rows here, and their next occurrence shows on Home.
    guard !newShifts.isEmpty else { return }  // swiftlint:disable:this conditional_returns_on_newline
    let homeShowsOne = newShifts.contains { shift in
      DashboardFeaturedItemSelector.canFeature(
        shiftDate: shift.shift_date, startTime: shift.start_time, endTime: shift.end_time)
    }
    if !homeShowsOne {
      coordinator.pendingDeepLink = .shifts(dates: dates, shiftIds: nil, action: .highlight)
    }
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
    if completed,
      viewModel.dashboardData == nil || coordinator.initialSyncNeedsLocalReload
    {
      viewModel.markLocalDataStale()
      guard selectedTab == .home else { return }  // swiftlint:disable:this conditional_returns_on_newline
      // Set loading state SYNCHRONOUSLY before starting async task
      // This prevents the empty state from flashing while data loads
      viewModel.prepareForReload()
      Task {
        await viewModel.reloadFromLocal()
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
    NavigationStack(path: $addShiftPath) {  // swiftlint:disable:this closure_body_length
      ZStack {
        TidexAppBackground()

        // Main content - month picker is now in shared overlay.
        // ZStack, not Group: Group would apply .animation to each branch, so the swap wouldn't animate.
        ZStack {
          if shouldShowWorkSetupRequiredPlaceholder {
            WorkSetupRequiredPlaceholder { HomeFriendsShifts() }
          } else if let data = viewModel.dashboardData {
            // Keep loaded content visible when a later refresh fails
            cardContent(data: data)
          } else if let error = viewModel.error, let message = ErrorTranslations.translate(error) {
            errorView(message: message)
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
            SyncStatusIndicator(showsOfflineRetry: !coordinator.initialSyncComplete) {
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
      }
      .navigationDestination(for: AddShiftRoute.self) { _ in AddShiftScreen() }
      .addShiftRoute(on: .home, path: $addShiftPath)
      .adaptiveToolbarTransaction()
    }
  }

  private var bodyWithLifecycle: AnyView {
    AnyView(
      navigationContent
        .task(id: coordinator.userId) {
          viewModel.setActiveTabVisible(selectedTab == .home)
          refreshWorkSetupPresentationState()
          refreshHasAnyShifts()
          guard coordinator.userId != nil else { return }
          await loadDashboardContent()
        }
        .task(id: coordinator.userId) {
          guard coordinator.userId != nil else { return }
          await calendarSubscriptionStore.refreshIfNeeded()
        }
        .onChange(of: coordinator.initialSyncComplete) { _, completed in
          handleInitialSyncCompleteChange(completed: completed)
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
        .onChange(of: hasAnyShifts) { hadShifts, hasShifts in
          if !hadShifts, hasShifts {
            showFirstShiftWhereHomeCannot()
          }
        }
        .onChange(of: showFeaturedShiftActions) { _, isPresented in
          if !isPresented {
            featuredShiftActionTarget = nil
          }
        }
        .onAppear {
          handleDashboardAppear()
          handleClockOutDeepLink(coordinator.pendingDeepLink)
        }
        .onChange(of: coordinator.pendingDeepLink) { _, deepLink in
          handleClockOutDeepLink(deepLink)
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
            do {
              try await Task.sleep(for: .seconds(30))  // swiftlint:disable:this no_magic_numbers
            } catch { return }
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
            AccessibilityNotification.Announcement(
              String(localized: .dashboardAccessibilityClockedOut)
            )
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

  /// An action queued to run once the sheet that triggered it has finished dismissing.
  /// Presenting a new sheet while another is still animating out is a no-op in SwiftUI,
  /// so this replaces `DispatchQueue.main.asyncAfter` guesswork with a real `onDismiss` hook.
  private enum PendingDashboardSheetAction {
    case shiftDelete(ShiftWithComputations)
    case eventDelete(EventRow)
    case recurringEdit(RecurringShiftRow)
    case calendarSubscriptionSettings
  }

  struct EventSheetSelection: Identifiable {
    let event: EventRow
    let startInEditMode: Bool

    var id: String { event.id }
  }

}

#Preview {
  struct PreviewWrapper: View {
    @State private var selectedTab: MainTabView.Tab = .home

    var body: some View {
      DashboardView(selectedTab: $selectedTab)
        .environment(AppCoordinator.shared)
    }
  }

  return PreviewWrapper()
}  // swiftlint:disable:this file_length
