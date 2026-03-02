import SwiftUI

/// Dashboard view showing the main financial overview
/// Displays payroll, total earnings, and featured shift cards
struct DashboardView: View {
  @EnvironmentObject private var coordinator: AppCoordinator
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  /// Binding to the selected tab for navigation
  @Binding var selectedTab: MainTabView.Tab

  private struct MonthlyGoalEditContext: Identifiable {
    let id = UUID()
    let monthDate: Date
    let baselineGoal: Int?
    let initialGoal: Int?
  }

  @StateObject private var viewModel = DashboardViewModel()
  @StateObject private var countdownManager = CountdownManager()
  @ObservedObject private var pushManager = PushNotificationManager.shared

  /// State for showing push notification failure alert
  @State private var showPushFailureAlert = false
  @State private var operationErrorMessage: String?

  /// Selected shift for showing details sheet
  @State private var selectedShift: ShiftWithComputations?

  /// Active featured shift target for action sheet actions
  @State private var featuredShiftActionTarget: ShiftWithComputations?
  @State private var showFeaturedShiftActions = false

  /// State for delete confirmation
  @State private var showDeleteConfirmation = false
  @State private var shiftToDelete: ShiftWithComputations?

  /// State for recurring shift editing
  @State private var recurringShiftToEdit: RecurringShiftRow?
  @State private var monthlyGoalEditContext: MonthlyGoalEditContext?
  @State private var temporaryClockReviewSession: TemporaryClockSession?
  @State private var clockInJobOptions: [Job] = []
  @State private var showClockInJobChooser = false
  @State private var selectedPayrollVariantIndex = 0
  @State private var temporarySessionReferenceDate = Date()

  /// Haptic feedback generator
  private let impactHaptic = UIImpactFeedbackGenerator(style: .medium)

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

  var body: some View {
    NavigationStack {
      ZStack {
        // Background that fills entire screen including safe areas
        // Uses adaptive tidexBackground to match other tabs and prevent black bars during transitions
        Color.tidexBackground
          .ignoresSafeArea()

        // Main content - month picker is now in shared overlay
        Group {
          if let error = viewModel.error {
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

        // Sync status indicator (shows when syncing, failed, or offline)
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
      .contentShape(Rectangle())
      .highPriorityGesture(
        TapGesture(count: 2).onEnded {
          guard !viewModel.isCurrentMonth else { return }
          Haptics.play(.light)
          viewModel.goToCurrentMonth()
        }
      )
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(Color.tidexBackground, for: .navigationBar)
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
      .iPadToolbarTransaction()
    }
    .task {
      await viewModel.loadDashboard()

      // If sync already completed before view appeared, reload to pick up synced data
      // This handles the race condition where sync finishes before .onChange is registered
      if coordinator.initialSyncComplete && viewModel.dashboardData == nil {
        await viewModel.reloadFromLocal()
      }
    }
    .onChange(of: coordinator.initialSyncComplete) { _, completed in
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
    }
    .onChange(of: selectedPayrollVariantIndex) { _, _ in
      configureCountdown(with: viewModel.dashboardData)
    }
    .onChange(of: showFeaturedShiftActions) { _, isPresented in
      if !isPresented {
        featuredShiftActionTarget = nil
      }
    }
    .onAppear {
      // Reconfigure timers when returning to the dashboard after a disappear cycle.
      configureCountdown(with: viewModel.dashboardData)
      Task {
        await viewModel.refreshAppearanceSettingsFromLocal()
        await viewModel.refreshClockState()
        await viewModel.preloadClockSelectableJobs()
      }
    }
    .onDisappear {
      countdownManager.stop()
    }
    .onReceive(NotificationCenter.default.publisher(for: .shiftsDidChange)) { _ in
      // Reload dashboard when shifts change (e.g., after adding a shift)
      Task {
        await viewModel.reloadFromLocal()
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .dashboardClockButtonsVisibilityDidChange))
    { notification in
      if let isVisible = notification.userInfo?["isVisible"] as? Bool {
        viewModel.applyDashboardClockButtonsVisibility(isVisible)
      }
    }
    .onReceive(clockStateRefreshTicker) { _ in
      guard selectedTab == .home else { return }
      Task {
        await viewModel.refreshClockState()
      }
    }
    .onReceive(temporarySessionTicker) { now in
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
        initialGoal: context.initialGoal
      ) { value in
        try await viewModel.saveMonthlyGoalForDisplayedMonth(value)
      }
      .presentationDetents([.fraction(0.35), .medium])
      .presentationDragIndicator(.visible)
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
          selectedShift = nil
          Task {
            await viewModel.updateShift(editResult)
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
        tariffRules: viewModel.getTariffRules(for: shift.shiftDate)
      )
      .presentationDetents([.medium, .large])
      .presentationDragIndicator(.visible)
    }
    // Delete confirmation dialog
    .confirmationDialog(
      shiftToDelete?.isVirtual == true
        ? String(localized: .shiftsExcludeConfirmTitle)
        : String(localized: .shiftsDeleteConfirmTitle),
      isPresented: $showDeleteConfirmation,
      titleVisibility: .visible
    ) {
      Button(
        shiftToDelete?.isVirtual == true
          ? String(localized: .shiftsExcludeButton)
          : String(localized: .shiftsDeleteButton),
        role: .destructive
      ) {
        if let shift = shiftToDelete {
          Task {
            await deleteShift(shift)
          }
        }
      }
      Button(String(localized: .commonCancel), role: .cancel) {
        shiftToDelete = nil
      }
    } message: {
      Text(
        shiftToDelete?.isVirtual == true
          ? .shiftsExcludeConfirmMessage
          : .shiftsDeleteConfirmMessage)
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

    // Only show shift countdown for current month with a next shift
    let shiftDate: String?
    let startTime: String?
    let endTime: String?

    if data.isViewingCurrentMonth, let shift = data.featuredShift, !data.featuredShiftIsBestShift {
      shiftDate = shift.shiftDate
      startTime = shift.startTime
      endTime = shift.endTime
    } else {
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

    let safePayrollVariantIndex = max(
      0, min(selectedPayrollVariantIndex, payrollVariants.count - 1))
    return payrollVariants[safePayrollVariantIndex].payoutDate
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
      .monthSwipeGesture(
        onSwipeLeft: { viewModel.goToNextMonth() },
        onSwipeRight: { viewModel.goToPreviousMonth() },
        isEnabled: true
      )
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
    let payrollDayStart = calendar.startOfDay(for: data.payrollDate)
    let payrollDayEnd =
      calendar.date(byAdding: .day, value: 1, to: payrollDayStart) ?? payrollDayStart
    let isOnOrBeforePayrollDay = now < payrollDayEnd
    let canManuallySetPayrollStatus = isViewingCurrentMonth && isOnOrBeforePayrollDay

    let payrollOverrideUserId = coordinator.getCurrentUserId()
    let payrollMarkedReceived = viewModel.isPayrollReceivedOverrideForDisplayedMonth(
      userId: payrollOverrideUserId
    )
    let effectivePayrollHasPassed: Bool = {
      guard isViewingCurrentMonth else { return data.payrollHasPassed }
      if isOnOrBeforePayrollDay {
        return payrollMarkedReceived
      }
      return true
    }()

    // Determine payroll label based on whether viewing current month
    let payrollLabel: String = {
      if isViewingCurrentMonth {
        return effectivePayrollHasPassed
          ? String(localized: .dashboardPreviousPayout)
          : String(localized: .dashboardNextPayout)
      } else {
        // For non-current months, show generic "Payroll" label
        return String(localized: .dashboardPayroll)
      }
    }()

    // Calculate progress through the month until payroll (matches Next.js behavior)
    // Only show for current month when payroll hasn't passed yet
    let defaultPayrollProgress: Double? = {
      guard isViewingCurrentMonth && !effectivePayrollHasPassed else { return nil }

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

    let payrollVariants = viewModel.payrollCardVariants(
      fallback: data,
      defaultTitle: payrollLabel
    )
    let safePayrollVariantIndex = max(
      0, min(selectedPayrollVariantIndex, payrollVariants.count - 1))
    let selectedPayrollVariant = payrollVariants[safePayrollVariantIndex]
    let showsMultiWorkplacePayroll = payrollVariants.count > 1
    let selectedPayrollProgress: Double? = {
      if !showsMultiWorkplacePayroll {
        return defaultPayrollProgress
      }

      guard isViewingCurrentMonth else { return nil }

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
        monthlyGoal: data.currentMonthGoal
      )
      .contentShape(Rectangle())
      .onTapGesture {
        openMonthlyGoalEditor()
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
    .onChange(of: payrollVariants.map(\.id)) { _, _ in
      selectedPayrollVariantIndex = 0
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
      initialGoal: initialGoal
    )
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
      .padding(.vertical, Spacing.xs)
      .foregroundColor(
        isEnabled
          ? .tidexTextPrimary
          : .tidexTextMuted
      )
      .background(
        RoundedRectangle(cornerRadius: CornerRadius.card)
          .fill(
            isEnabled
              ? Color.tidexSurfacePrimary
              : Color.tidexSurfacePrimary.opacity(0.72)
          )
      )
      .tidexCardShadow(cornerRadius: CornerRadius.card)
    }
    .buttonStyle(.plain)
    .disabled(!isEnabled)
  }

  @ViewBuilder
  private func clockButtonsSkeletonSection() -> some View {
    HStack(spacing: Spacing.sm) {
      RoundedRectangle(cornerRadius: CornerRadius.card)
        .fill(Color.tidexSurfacePrimary)
        .frame(height: 34)
        .tidexCardShadow(cornerRadius: CornerRadius.card)
        .shimmer(isActive: true)

      RoundedRectangle(cornerRadius: CornerRadius.card)
        .fill(Color.tidexSurfacePrimary)
        .frame(height: 34)
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
    let safeSelectedVariantIndex = max(0, min(selectedPayrollVariantIndex, variantCount - 1))

    let card = PayrollCard(
      payrollDate: selectedVariant.payoutDate,
      label: selectedVariant.title,
      labelColorHex: selectedVariant.colorHex,
      labelIsWorkplace: showsWorkplaceVariants,
      pageIndicatorCount: variantCount,
      pageIndicatorSelectedIndex: safeSelectedVariantIndex,
      gross: selectedVariant.gross,
      net: selectedVariant.net,
      tax: selectedVariant.tax,
      taxEnabled: selectedVariant.taxEnabled,
      progress: payrollProgress
    )

    if canManuallySetPayrollStatus && !showsWorkplaceVariants {
      Menu {
        Section(String(localized: .dashboardPayrollStatusTitle)) {
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
      } label: {
        card
      }
      .menuIndicator(.hidden)
    } else if showsWorkplaceVariants {
      card
        .contentShape(Rectangle())
        .onTapGesture {
          guard variantCount > 1 else { return }
          selectedPayrollVariantIndex = (selectedPayrollVariantIndex + 1) % variantCount
          Haptics.play(.light)
        }
    } else {
      card
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
          countdownText: temporarySessionCountdownText(
            startedAt: session.startedAt,
            now: temporarySessionReferenceDate
          ),
          showJobIndicator: viewModel.shouldShowJobIndicators,
          jobName: shiftJob?.name,
          jobColorHex: shiftJob?.color,
          progress: 0,
          finalCountdownSeconds: nil,
          showTimeRangeEndSkeleton: true
        )
        .contentShape(Rectangle())
        .onTapGesture {
          impactHaptic.impactOccurred()
          Task {
            await presentTemporaryClockReview(session)
          }
        }
      } else if let featuredShift = data.featuredShift {
        // Only show progress bar for active shifts (matching Next.js behavior)
        let shiftProgress: Double? =
          countdownManager.isShiftActive ? countdownManager.shiftProgress : nil
        let displayedFeaturedShift: ShiftWithComputations =
          countdownManager.isShiftActive
          ? viewModel.liveFeaturedShiftWhileOngoing(from: featuredShift, at: Date())
          : featuredShift
        let shiftJob = viewModel.jobForShift(featuredShift)
        FeaturedShiftCard(
          shift: displayedFeaturedShift,
          isToday: data.isFeaturedShiftToday,
          isBestShift: data.featuredShiftIsBestShift,
          countdownText: countdownManager.shiftCountdownText,
          showJobIndicator: viewModel.shouldShowJobIndicators,
          jobName: shiftJob?.name,
          jobColorHex: shiftJob?.color,
          progress: shiftProgress,
          finalCountdownSeconds: countdownManager.finalShiftCountdownSeconds
        )
        .contentShape(Rectangle())
        .onTapGesture {
          impactHaptic.impactOccurred()
          if countdownManager.isShiftActive {
            featuredShiftActionTarget = featuredShift
            showFeaturedShiftActions = true
          } else {
            selectedShift = featuredShift
          }
        }
      } else {
        EmptyShiftCard(onAddShift: {
          selectedTab = .add
        })
      }
    }
  }

  private func temporarySessionCountdownText(startedAt: Date, now: Date) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = Date.localTimeZone
    let alignedStart = calendar.dateInterval(of: .minute, for: startedAt)?.start ?? startedAt
    return CountdownFormatter.formatRelativeCountdown(
      referenceDate: alignedStart,
      dayBoundaryReferenceDate: alignedStart,
      now: now
    )
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

    var body: some View {
      DashboardView(selectedTab: $selectedTab)
        .environmentObject(AppCoordinator.shared)
    }
  }

  return PreviewWrapper()
}
