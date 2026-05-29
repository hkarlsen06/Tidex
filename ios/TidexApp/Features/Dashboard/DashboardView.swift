import SwiftUI

private struct EventSheetSelection: Identifiable {
  let event: EventRow
  let startInEditMode: Bool

  var id: String { event.id }
}

/// Dashboard view showing the main financial overview
/// Displays payroll, total earnings, and featured shift cards
struct DashboardView: View {
  @EnvironmentObject private var coordinator: AppCoordinator
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.layoutDirection) private var layoutDirection

  /// Binding to the selected tab for navigation
  @Binding var selectedTab: MainTabView.Tab
  @Binding var showStatsView: Bool

  private struct MonthlyGoalEditContext: Identifiable {
    let id = UUID()
    let monthDate: Date
    let baselineGoal: Int?
    let initialGoal: Int?
    let showsAdjustmentPercentageFootnote: Bool
  }

  @StateObject private var viewModel = DashboardViewModel()
  @StateObject private var countdownManager = CountdownManager()
  @StateObject private var calendarSubscriptionStore = CalendarSubscriptionStore.shared
  @ObservedObject private var pushManager = PushNotificationManager.shared

  /// State for showing push notification failure alert
  @State private var showPushFailureAlert = false
  @State private var operationErrorMessage: String?

  /// Selected shift for showing details sheet
  @State private var selectedShift: ShiftWithComputations?
  @State private var selectedEvent: EventSheetSelection?

  /// Active featured shift target for action sheet actions
  @State private var featuredShiftActionTarget: ShiftWithComputations?
  @State private var showFeaturedShiftActions = false

  /// State for delete confirmation
  @State private var showDeleteConfirmation = false
  @State private var shiftToDelete: ShiftWithComputations?
  @State private var showEventDeleteConfirmation = false
  @State private var eventToDelete: EventRow?

  /// Edit mode state (when opening from swipe action)
  @State private var shiftToEditDirectly: ShiftWithComputations?

  /// State for recurring shift editing
  @State private var recurringShiftToEdit: RecurringShiftRow?
  @State private var monthlyGoalEditContext: MonthlyGoalEditContext?
  @State private var temporaryClockReviewSession: TemporaryClockSession?
  @State private var clockInJobOptions: [Job] = []
  @State private var showClockInJobChooser = false
  @State private var temporarySessionReferenceDate = Date()
  @State private var showMixedCurrencyBreakdownPopover = false
  @State private var activeDashboardRefreshTask: Task<Void, Never>?
  @State private var showCalendarSubscriptionSettings = false
  @State private var selectedPayrollDetailsVariant: PayrollCardVariant?

  /// Haptic feedback generator
  private let impactHaptic = UIImpactFeedbackGenerator(style: .medium)
  private let workSetupStatusService = WorkSetupStatusService.shared

  private func shouldKeepShiftDetailsOpen(
    after editResult: ShiftEditResult,
    originalShift: ShiftWithComputations
  ) -> Bool {
    editResult.noteWasEdited
      && editResult.customSupplements == nil
      && editResult.shiftDate == originalShift.shiftDate
      && editResult.startTime == String(originalShift.startTime.prefix(5))
      && editResult.endTime == String(originalShift.endTime.prefix(5))
  }

  /// Use fixed minimum card heights for regular Dynamic Type sizes so loading
  /// placeholders and real content occupy the same vertical space.
  private var usesFixedCardHeights: Bool {
    !dynamicTypeSize.isAccessibilitySize
  }

  private let payrollSectionMinHeight: CGFloat = 89
  private let featuredSectionMinHeight: CGFloat = 118
  private let clockStateRefreshTicker = Timer.publish(every: 30, on: .main, in: .common)
    .autoconnect()
  private let temporarySessionTicker = Timer.publish(every: 1, on: .main, in: .common)
    .autoconnect()

  private var workSetupPresentationState: WorkSetupPresentationState? {
    guard let userId = coordinator.getCurrentUserId() else { return nil }
    return workSetupStatusService.presentationState(
      for: userId,
      initialSyncComplete: coordinator.initialSyncComplete
    )
  }

  private var shouldShowWorkSetupRequiredPlaceholder: Bool {
    workSetupPresentationState?.shouldShowPlaceholder == true
  }

  private func refreshActiveDashboardStateIfNeeded() {
    guard !shouldShowWorkSetupRequiredPlaceholder else { return }
    guard selectedTab == .home else { return }
    guard viewModel.dashboardData != nil else { return }

    activeDashboardRefreshTask?.cancel()
    activeDashboardRefreshTask = Task {
      await viewModel.refreshAppearanceSettingsFromLocal()
      guard !Task.isCancelled else { return }
      await viewModel.refreshClockState()
      guard !Task.isCancelled else { return }
      await viewModel.preloadClockSelectableJobs()
    }
  }

  private func openCalendarSubscriptionSetupFromDashboard() {
    selectedShift = nil
    shiftToEditDirectly = nil
    selectedEvent = nil
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
      showCalendarSubscriptionSettings = true
    }
  }

  private func payrollDetailsSheet(for variant: PayrollCardVariant) -> some View {
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

  var body: some View {
    NavigationStack {
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
          TodayDateLabel()
        }
        .sharedBackgroundVisibility(.hidden)
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
    .task {
      guard !shouldShowWorkSetupRequiredPlaceholder else { return }
      await calendarSubscriptionStore.refreshIfNeeded()
      await viewModel.loadDashboard()

      // If sync already completed before view appeared, reload to pick up synced data
      // This handles the race condition where sync finishes before .onChange is registered
      if coordinator.initialSyncComplete && viewModel.dashboardData == nil {
        await viewModel.reloadFromLocal()
      }
    }
    .onChange(of: coordinator.initialSyncComplete) { _, completed in
      guard !shouldShowWorkSetupRequiredPlaceholder else { return }
      // When initial sync completes after login, reload dashboard to show synced data
      if completed {
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
    .onChange(of: viewModel.dashboardData) { _, newData in
      configureCountdown(with: newData)
      showMixedCurrencyBreakdownPopover = false
    }
    .onChange(of: showFeaturedShiftActions) { _, isPresented in
      if !isPresented {
        featuredShiftActionTarget = nil
      }
    }
    .onAppear {
      guard !shouldShowWorkSetupRequiredPlaceholder else { return }
      // Reconfigure timers when returning to the dashboard after a disappear cycle.
      configureCountdown(with: viewModel.dashboardData)
      refreshActiveDashboardStateIfNeeded()
    }
    .onDisappear {
      activeDashboardRefreshTask?.cancel()
      activeDashboardRefreshTask = nil
      countdownManager.stop()
    }
    .onChange(of: selectedTab) { oldTab, newTab in
      guard oldTab != newTab else { return }
      if newTab == .home {
        configureCountdown(with: viewModel.dashboardData)
        refreshActiveDashboardStateIfNeeded()
      } else {
        activeDashboardRefreshTask?.cancel()
        activeDashboardRefreshTask = nil
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .shiftsDidChange)) { notification in
      guard !shouldShowWorkSetupRequiredPlaceholder else { return }
      guard (notification.object as AnyObject?) !== viewModel else { return }
      // Reload dashboard when shifts change (e.g., after adding a shift)
      Task {
        await viewModel.reloadFromLocal()
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .dashboardClockButtonsVisibilityDidChange))
    { notification in
      guard !shouldShowWorkSetupRequiredPlaceholder else { return }
      if let isVisible = notification.userInfo?["isVisible"] as? Bool {
        viewModel.applyDashboardClockButtonsVisibility(isVisible)
      }
    }
    .onReceive(clockStateRefreshTicker) { _ in
      guard !shouldShowWorkSetupRequiredPlaceholder else { return }
      guard selectedTab == .home else { return }
      Task {
        await viewModel.refreshClockState()
      }
    }
    .onReceive(temporarySessionTicker) { now in
      guard !shouldShowWorkSetupRequiredPlaceholder else { return }
      guard selectedTab == .home else { return }
      guard case .temporary = viewModel.activeClockState else { return }
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
      isPresented: .init(
        get: { operationErrorMessage != nil },
        set: { if !$0 { operationErrorMessage = nil } }
      )
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
        guard !viewModel.isUpdatingShift else { return }
        featuredShiftActionTarget = nil
        selectedShift = shift
      }
      Button(String(localized: .dashboardFeaturedShiftActionsEndNow)) {
        guard !viewModel.isUpdatingShift else { return }
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
      .presentationDetents([.fraction(0.35), .medium])
      .presentationDragIndicator(.visible)
    }
    .sheet(item: $selectedPayrollDetailsVariant) { variant in
      payrollDetailsSheet(for: variant)
    }
    .sheet(item: $temporaryClockReviewSession) { session in
      let clockJobs = viewModel.clockSelectableJobsSnapshot()
      ClockOutReviewSheet(
        session: session,
        initialAvailableJobs: clockJobs,
        loadJobs: {
          await viewModel.clockSelectableJobs()
        },
        initialSelectedJobId: viewModel.preferredClockJobId(for: session),
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
            await viewModel.clockIn(jobId: jobId)
          }
        },
        onCancel: {
          showClockInJobChooser = false
        }
      )
    }
    // Shift details sheet with full edit/delete capabilities
    .sheet(item: $selectedShift) { shift in
      let shiftJob = viewModel.shouldShowJobIndicators ? viewModel.jobForShift(shift) : nil
      ShiftDetailsSheet(
        shift: shift,
        jobName: shiftJob?.name,
        jobColorHex: shiftJob?.color,
        onDelete: {
          selectedShift = nil
          // Small delay before showing delete confirmation
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            shiftToDelete = shift
            showDeleteConfirmation = true
          }
        },
        onUpdate: { editResult in
          let shouldKeepSheetOpen = shouldKeepShiftDetailsOpen(
            after: editResult, originalShift: shift)
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
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if let recurring = viewModel.getRecurringShift(id: recurringId) {
              recurringShiftToEdit = recurring
            }
          }
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
    .sheet(item: $shiftToEditDirectly) { shift in
      let shiftJob = viewModel.shouldShowJobIndicators ? viewModel.jobForShift(shift) : nil
      ShiftDetailsSheet(
        shift: shift,
        jobName: shiftJob?.name,
        jobColorHex: shiftJob?.color,
        onDelete: {
          shiftToEditDirectly = nil
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            shiftToDelete = shift
            showDeleteConfirmation = true
          }
        },
        onUpdate: { editResult in
          let shouldKeepSheetOpen = shouldKeepShiftDetailsOpen(
            after: editResult, originalShift: shift)
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
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if let recurring = viewModel.getRecurringShift(id: recurringId) {
              recurringShiftToEdit = recurring
            }
          }
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
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
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
          calendarSetupIntent: .setup(mode: .shiftsAndEvents, autoOpen: false)))
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
          : String(localized: .shiftsDeleteConfirmMessage))
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
          let recurringId = recurring.id
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
  private func deleteShift(_ shift: ShiftWithComputations) async {
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
      NotificationCenter.default.post(name: .shiftsDidChange, object: nil)

    } catch {
      operationErrorMessage = ErrorTranslations.translate(error)
    }

    shiftToDelete = nil
  }

  private func deleteEvent(_ event: EventRow) async {
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
  private func updateRecurringShift(_ editResult: RecurringShiftEditResult) async {
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
      NotificationCenter.default.post(name: .shiftsDidChange, object: nil)

    } catch {
      operationErrorMessage = ErrorTranslations.translate(error)
    }
  }

  /// Delete a recurring shift pattern
  private func deleteRecurringShift(_ recurringId: String) async {
    do {
      try await RecurringShiftsRepository.shared.deleteRecurringShift(id: recurringId)

      // Post notification for other views
      NotificationCenter.default.post(name: .shiftsDidChange, object: nil)

    } catch {
      operationErrorMessage = ErrorTranslations.translate(error)
    }
  }

  // MARK: - Countdown Configuration

  private func configureCountdown(with data: DashboardData?) {
    guard let data = data else {
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

  private func selectedPayrollDate(for data: DashboardData) -> Date {
    let payrollVariants = viewModel.payrollCardVariants(
      fallback: data,
      defaultTitle: String(localized: .dashboardPayroll)
    )

    guard !payrollVariants.isEmpty else {
      return data.payrollDate
    }

    return payrollVariants[0].payoutDate
  }

  private func featuredEventCountdownStatus(_ event: EventRow, now: Date = Date())
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

    if now >= startDate && now < endDate {
      return .active
    }

    return now >= endDate ? .past : .upcoming
  }

  @ViewBuilder
  private func featuredEventFooter(_ event: EventRow) -> some View {
    if event.is_all_day {
      HStack(spacing: Spacing.xxxs) {
        Image(systemName: "calendar")
          .font(.tidexCaptionRegular)
          .foregroundColor(.tidexBlue)
        Text(.addShiftEventAllDay)
          .font(.tidexLabel)
          .foregroundColor(.tidexTextSecondary)
      }
      .frame(height: 20)
    } else if let countdownText = countdownManager.shiftCountdownText {
      ShiftCountdownBadge(
        text: countdownText,
        status: featuredEventCountdownStatus(event),
        finalCountdownSeconds: countdownManager.finalShiftCountdownSeconds
      )
      .frame(height: 20)
    } else {
      RoundedRectangle(cornerRadius: CornerRadius.xxs)
        .fill(Color.tidexTextMuted.opacity(0.3))
        .frame(width: 80, height: 14)
        .frame(height: 20)
    }
  }

  // MARK: - Card Content

  /// Card content with pull-to-refresh and swipe gestures
  /// Month picker is handled separately in the main body so it's always visible
  @ViewBuilder
  private func cardContent(data: DashboardData) -> some View {
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
  private func animatedCardContent(data: DashboardData) -> some View {
    let now = Date()
    let calendar = Calendar.current
    let isViewingCurrentMonth = data.isViewingCurrentMonth
    let preliminaryPayrollVariants = viewModel.payrollCardVariants(
      fallback: data,
      defaultTitle: String(localized: .dashboardPayroll)
    )
    let selectedPayoutDate = preliminaryPayrollVariants.first?.payoutDate ?? data.payrollDate
    let payrollDayStart = calendar.startOfDay(for: selectedPayoutDate)
    let payrollDayEnd =
      calendar.date(byAdding: .day, value: 1, to: payrollDayStart) ?? payrollDayStart
    let isOnOrBeforePayrollDay = now < payrollDayEnd
    let selectedPayoutYM = selectedPayoutDate.yearMonth()
    let current = Date.currentYearMonth()
    let selectedPayoutIsInCurrentMonth =
      selectedPayoutYM.year == current.year && selectedPayoutYM.month == current.month
    let canManuallySetPayrollStatus =
      isViewingCurrentMonth && selectedPayoutIsInCurrentMonth && isOnOrBeforePayrollDay
    let isCurrentAdvancedNextPayout =
      !isViewingCurrentMonth
      && viewModel.isCurrentMonthAdvancedNextPayoutDate(selectedPayoutDate, now: now)
    let shouldShowLivePayrollProgress = isViewingCurrentMonth || isCurrentAdvancedNextPayout

    let payrollOverrideUserId = coordinator.getCurrentUserId()
    let payrollMarkedReceived = viewModel.isPayrollReceivedOverrideForDisplayedMonth(
      userId: payrollOverrideUserId
    )
    let effectivePayrollHasPassed: Bool = {
      guard isViewingCurrentMonth else { return data.payrollHasPassed }
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
        return String(localized: "dashboard.earlierPayout")
      }

      if isCurrentAdvancedNextPayout {
        return String(localized: .dashboardNextPayout)
      }

      if selectedPayoutYM.year > current.year
        || (selectedPayoutYM.year == current.year && selectedPayoutYM.month > current.month)
      {
        return String(localized: "dashboard.futurePayout")
      }

      if effectivePayrollHasPassed {
        return String(localized: .dashboardPreviousPayout)
      }

      // Fallback for non-current month views that resolve to the real current payout month.
      // This should be uncommon, but keeps the label neutral instead of implying today-relative
      // "next payout" semantics while browsing months.
      return String(localized: .dashboardPayroll)
    }()

    // Calculate progress through the month until payroll (matches Next.js behavior)
    // Only show for current month when payroll hasn't passed yet
    let defaultPayrollProgress: Double? = {
      guard shouldShowLivePayrollProgress && !effectivePayrollHasPassed else { return nil }

      // Get start of the current month
      guard
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now))
      else {
        return nil
      }

      let totalDuration = payrollDayStart.timeIntervalSince(monthStart)
      let elapsed = now.timeIntervalSince(monthStart)

      guard totalDuration > 0 else {
        // Edge case: payroll is on the 1st
        return 100
      }

      let progress = (elapsed / totalDuration) * 100
      // Clamp to 1-100 (minimum 1% so users recognize it's a progress bar)
      return max(1, min(100, progress))
    }()

    let payrollVariants = viewModel.payrollCardVariants(fallback: data, defaultTitle: payrollLabel)
    if let selectedPayrollVariant = payrollVariants.first {
      let showsMultiWorkplacePayroll = !selectedPayrollVariant.badges.isEmpty
      let selectedPayrollProgress: Double? = {
        if !showsMultiWorkplacePayroll {
          return defaultPayrollProgress
        }

        guard shouldShowLivePayrollProgress else { return nil }

        let selectedPayrollDayStart = calendar.startOfDay(for: selectedPayrollVariant.payoutDate)
        let selectedPayrollDayEnd =
          calendar.date(byAdding: .day, value: 1, to: selectedPayrollDayStart)
          ?? selectedPayrollDayStart
        guard now < selectedPayrollDayEnd else { return nil }

        guard
          let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now))
        else {
          return nil
        }

        let totalDuration = selectedPayrollDayStart.timeIntervalSince(monthStart)
        let elapsed = now.timeIntervalSince(monthStart)
        guard totalDuration > 0 else { return 100 }

        let progress = (elapsed / totalDuration) * 100
        return max(1, min(100, progress))
      }()

      // Cards stay in place - only numbers animate on month change (like Next.js)
      VStack(spacing: Spacing.sm) {
        // Payroll countdown text - fixed height to prevent layout shift
        Text(countdownManager.payrollCountdownText ?? " ")
          .font(.tidexLabel)
          .foregroundColor(.tidexTextSecondary)
          .opacity(countdownManager.payrollCountdownText != nil ? 1 : 0)
          .frame(height: 20)

        // Payroll Card (Previous Month relative to displayed month)
        payrollCardSection(
          selectedVariant: selectedPayrollVariant,
          variantCount: payrollVariants.count,
          canManuallySetPayrollStatus: canManuallySetPayrollStatus,
          payrollMarkedReceived: payrollMarkedReceived,
          payrollOverrideUserId: payrollOverrideUserId,
          payrollProgress: selectedPayrollProgress
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

  private func openMonthlyGoalEditor() {
    impactHaptic.impactOccurred()
    let baseline = viewModel.baselineMonthlyGoal
    let override = viewModel.displayedMonthOverrideGoal
    let effectiveGoal = viewModel.dashboardData?.currentMonthGoal.flatMap {
      $0 > 0 ? Int($0.rounded()) : nil
    }

    let initialGoal =
      override
      ?? effectiveGoal.flatMap { effective in
        if let baseline, effective == baseline {
          return nil
        }
        return effective
      }
    let monthDate =
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

  private func monthSwipeGesture() -> some Gesture {
    DragGesture(minimumDistance: 30)
      .onEnded { value in
        let horizontal = value.translation.width
        let vertical = abs(value.translation.height)

        guard abs(horizontal) > vertical else { return }

        impactHaptic.impactOccurred()

        let isRTL = layoutDirection == .rightToLeft
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
  private func clockButtonsSection() -> some View {
    HStack(spacing: Spacing.sm) {
      clockButton(
        title: .dashboardClockIn,
        systemImage: "play.fill",
        isEnabled: viewModel.isClockInEnabled
      ) {
        guard viewModel.isClockInEnabled else { return }
        impactHaptic.impactOccurred()
        Task {
          let cachedJobs = viewModel.clockSelectableJobsSnapshot()
          if cachedJobs.count > 1 {
            clockInJobOptions = cachedJobs
            showClockInJobChooser = true
            return
          }
          if cachedJobs.count == 1 {
            await viewModel.clockIn(jobId: cachedJobs.first?.id)
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
        guard viewModel.isClockOutEnabled else { return }
        impactHaptic.impactOccurred()
        Task {
          let route = await viewModel.routeClockOut()
          if case .temporaryReview(let session) = route {
            await presentTemporaryClockReview(session)
          }
        }
      }
    }
    .padding(.horizontal, Spacing.mlg)
  }

  private func clockButton(
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
      .frame(minHeight: 44)
      .padding(.vertical, Spacing.xxs)
      .foregroundColor(
        isEnabled
          ? .tidexTextPrimary
          : .tidexTextMuted
      )
      .tidexGlass(
        shape: .rect(cornerRadius: CornerRadius.card),
        tint: isEnabled
          ? Color.tidexBlue.opacity(0.04)
          : Color.tidexSurfaceSecondary.opacity(0.04),
        clear: true,
        interactive: isEnabled,
        fallbackOpacity: isEnabled ? 0.5 : 0.42
      )
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous))
      .contentShape(RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous))
      .tidexCardShadow(cornerRadius: CornerRadius.card)
    }
    .buttonStyle(DashboardClockButtonStyle())
    .disabled(!isEnabled)
  }

  @ViewBuilder
  private func clockButtonsSkeletonSection() -> some View {
    HStack(spacing: Spacing.sm) {
      RoundedRectangle(cornerRadius: CornerRadius.card)
        .frame(height: 44)
        .tidexGlass(
          shape: .rect(cornerRadius: CornerRadius.card),
          tint: Color.tidexBlue.opacity(0.03),
          clear: true,
          fallbackOpacity: 0.5
        )
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous))
        .tidexCardShadow(cornerRadius: CornerRadius.card)
        .shimmer(isActive: true)

      RoundedRectangle(cornerRadius: CornerRadius.card)
        .frame(height: 44)
        .tidexGlass(
          shape: .rect(cornerRadius: CornerRadius.card),
          tint: Color.tidexBlue.opacity(0.03),
          clear: true,
          fallbackOpacity: 0.5
        )
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous))
        .tidexCardShadow(cornerRadius: CornerRadius.card)
        .shimmer(isActive: true)
    }
    .padding(.horizontal, Spacing.mlg)
  }

  @ViewBuilder
  private func payrollCardSection(
    selectedVariant: PayrollCardVariant,
    variantCount: Int,
    canManuallySetPayrollStatus: Bool,
    payrollMarkedReceived: Bool,
    payrollOverrideUserId: String?,
    payrollProgress: Double?
  ) -> some View {
    let showsWorkplaceVariants = variantCount > 1
    let showsGroupedWorkplaces = !selectedVariant.badges.isEmpty

    let card = PayrollCard(
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
      progress: payrollProgress
    )

    let interactiveCard =
      card
      .userCurrency(selectedVariant.currency)
      .contentShape(Rectangle())
      .onTapGesture {
        impactHaptic.impactOccurred()
        selectedPayrollDetailsVariant = selectedVariant
      }

    if canManuallySetPayrollStatus {
      interactiveCard
        .contextMenu {
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
              userId: payrollOverrideUserId)
          } label: {
            Label(
              String(localized: .dashboardPayrollStatusNotReceived),
              systemImage: payrollMarkedReceived ? "circle" : "checkmark.circle.fill"
            )
          }
        }
    } else {
      interactiveCard
    }
  }

  // MARK: - Featured Shift Section

  /// Featured shift card with fixed height to prevent layout jumps
  @ViewBuilder
  private func featuredShiftSection(data: DashboardData) -> some View {
    // Use a fixed height container so the layout doesn't shift
    // when switching between FeaturedShiftCard and EmptyShiftCard
    Group {
      if case .temporary(let session) = viewModel.activeClockState {
        let temporaryShift = viewModel.temporaryFeaturedShift(
          from: session,
          at: temporarySessionReferenceDate
        )
        let shiftJob = viewModel.jobForTemporarySession(session)
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
          let shiftJob = viewModel.jobForShift(featuredShift)
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
        case .event(let event, let coveredDateISO):
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

  private func presentTemporaryClockReview(_ session: TemporaryClockSession) async {
    if viewModel.clockSelectableJobsSnapshot().isEmpty {
      _ = await viewModel.clockSelectableJobs()
    }
    temporaryClockReviewSession = session
  }

  // MARK: - Loading Skeleton View

  /// Skeleton cards with shimmer animation shown while loading
  /// Provides a visual preview of the dashboard layout during data fetch
  private var loadingSkeletonView: some View {
    PullToRefreshContainer(onRefresh: {
      await viewModel.refresh()
    }) {
      GeometryReader { geometry in
        VStack(spacing: 0) {
          Spacer()

          // Skeleton cards matching the real dashboard layout
          VStack(spacing: Spacing.sm) {
            // Placeholder for payroll countdown text
            Color.clear
              .frame(height: 20)

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
        .font(.system(size: 48))
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
          .background(Color.tidexBlue.opacity(0.1))
          .cornerRadius(CornerRadius.sm)
      }
    }
    .frame(maxWidth: AdaptiveMaxWidth.tabContent)
    .padding(.horizontal, Spacing.xxl)
  }

}

private struct DashboardClockButtonStyle: ButtonStyle {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(reduceMotion ? 1.0 : (configuration.isPressed ? 0.98 : 1.0))
      .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
  }
}

private struct ClockOutReviewSheet: View {
  let loadJobs: () async -> [Job]
  let onSave: (Date, Date, String?) async throws -> Void
  let onDiscard: () async -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var availableJobs: [Job]
  @State private var startTime: Date?
  @State private var endTime: Date?
  @State private var selectedJobId: String?
  @State private var focusedTimeField: TimeInputField?
  @State private var showJobChooser = false
  @State private var isSaving = false
  @State private var isDiscarding = false
  @State private var errorMessage: String?

  init(
    session: TemporaryClockSession,
    initialAvailableJobs: [Job],
    loadJobs: @escaping () async -> [Job],
    initialSelectedJobId: String?,
    onSave: @escaping (Date, Date, String?) async throws -> Void,
    onDiscard: @escaping () async -> Void
  ) {
    self.loadJobs = loadJobs
    self.onSave = onSave
    self.onDiscard = onDiscard

    let initialStart = session.startedAt
    let initialEnd = max(Date(), initialStart.addingTimeInterval(60))
    let fallbackJobId =
      initialSelectedJobId
      ?? initialAvailableJobs.first(where: { $0.is_default })?.id
      ?? initialAvailableJobs.first?.id
    _availableJobs = State(initialValue: initialAvailableJobs)
    _startTime = State(initialValue: initialStart)
    _endTime = State(initialValue: initialEnd)
    _selectedJobId = State(initialValue: fallbackJobId)
  }

  private var selectedJob: Job? {
    guard let selectedJobId else { return availableJobs.first }
    return availableJobs.first(where: { $0.id == selectedJobId }) ?? availableJobs.first
  }

  private var resolvedEndTime: Date? {
    guard let startTime, let endTime else { return nil }
    guard endTime <= startTime else { return endTime }
    return Calendar.current.date(byAdding: .day, value: 1, to: endTime) ?? endTime
  }

  private var isValidRange: Bool {
    guard let startTime, let resolvedEndTime else { return false }
    return resolvedEndTime > startTime
  }

  private var showsCrossMidnightHint: Bool {
    guard let startTime, let resolvedEndTime else { return false }
    return !Calendar.current.isDate(startTime, inSameDayAs: resolvedEndTime)
  }

  private var isWorking: Bool {
    isSaving || isDiscarding
  }

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: Spacing.md) {
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
              Text(String(localized: "settings.pay.choose_workplace.title"))
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
                  badgeVerticalPadding: 2
                )
                .lineLimit(1)
                .truncationMode(.tail)
              }

              Image(systemName: "chevron.down")
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
            Image(systemName: "moon.fill")
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
    guard !isSaving else { return }
    guard isValidRange else { return }
    guard let startTime, let resolvedEndTime else { return }

    isSaving = true
    errorMessage = nil

    do {
      try await onSave(startTime, resolvedEndTime, selectedJobId)
      dismiss()
    } catch {
      errorMessage = ErrorTranslations.translate(error)
    }

    isSaving = false
  }

  private func discard() async {
    guard !isWorking else { return }

    isDiscarding = true
    await onDiscard()
    isDiscarding = false
    dismiss()
  }

  private func ensureJobsLoaded() async {
    guard availableJobs.isEmpty else { return }
    let loadedJobs = await loadJobs()
    guard !loadedJobs.isEmpty else { return }
    availableJobs = loadedJobs
    if selectedJobId == nil {
      selectedJobId = loadedJobs.first(where: { $0.is_default })?.id ?? loadedJobs.first?.id
    }
  }
}

private struct DashboardClockJobChooserSheet: View {
  let loadJobs: (() async -> [Job])?
  let onSelect: (String) -> Void
  let onCancel: () -> Void

  @State private var jobs: [Job]
  @State private var isLoading: Bool

  init(
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
    let visibleRows = max(1, min(jobs.count, 4))
    return CGFloat(visibleRows) * 70 + 120
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        Group {
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

                    Image(systemName: "chevron.right")
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
      .navigationTitle(String(localized: "settings.pay.choose_workplace.title"))
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
    guard jobs.isEmpty, let loadJobs else { return }
    let loadedJobs = await loadJobs()
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
    @State private var showStatsView = false

    var body: some View {
      DashboardView(selectedTab: $selectedTab, showStatsView: $showStatsView)
        .environmentObject(AppCoordinator.shared)
    }
  }

  return PreviewWrapper()
}
