import SwiftUI

/// Dashboard view showing the main financial overview
/// Displays payroll, total earnings, and featured shift cards
struct DashboardView: View {
  @EnvironmentObject private var coordinator: AppCoordinator
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  /// Binding to the selected tab for navigation
  @Binding var selectedTab: MainTabView.Tab

  @StateObject private var viewModel = DashboardViewModel()
  @StateObject private var countdownManager = CountdownManager()
  @ObservedObject private var pushManager = PushNotificationManager.shared

  /// State for showing push notification failure alert
  @State private var showPushFailureAlert = false

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

  /// Haptic feedback generator
  private let impactHaptic = UIImpactFeedbackGenerator(style: .medium)

  /// Use fixed minimum card heights for regular Dynamic Type sizes so loading
  /// placeholders and real content occupy the same vertical space.
  private var usesFixedCardHeights: Bool {
    !dynamicTypeSize.isAccessibilitySize
  }

  private let payrollSectionMinHeight: CGFloat = 89
  private let featuredSectionMinHeight: CGFloat = 118

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
    .onChange(of: showFeaturedShiftActions) { _, isPresented in
      if !isPresented {
        featuredShiftActionTarget = nil
      }
    }
    .onAppear {
      // Reconfigure timers when returning to the dashboard after a disappear cycle.
      configureCountdown(with: viewModel.dashboardData)
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
    // Shift details sheet with full edit/delete capabilities
    .sheet(item: $selectedShift) { shift in
      ShiftDetailsSheet(
        shift: shift,
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

      // Reload to reflect changes
      await viewModel.reloadFromLocal()

      // Post notification for other views
      NotificationCenter.default.post(name: .shiftsDidChange, object: nil)

    } catch {
      // Error handling - could show an alert here
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

      // Reload to reflect changes
      await viewModel.reloadFromLocal()

      // Post notification for other views
      NotificationCenter.default.post(name: .shiftsDidChange, object: nil)

    } catch {
      // Error handling - could show an alert here
    }
  }

  /// Delete a recurring shift pattern
  private func deleteRecurringShift(_ recurringId: String) async {
    do {
      try await RecurringShiftsRepository.shared.deleteRecurringShift(id: recurringId)

      // Reload to reflect changes
      await viewModel.reloadFromLocal()

      // Post notification for other views
      NotificationCenter.default.post(name: .shiftsDidChange, object: nil)

    } catch {
      // Error handling - could show an alert here
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

    if viewModel.isCurrentMonth, let shift = data.featuredShift, !data.featuredShiftIsBestShift {
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
      payrollDate: data.payrollDate
    )
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
    let payrollDayStart = calendar.startOfDay(for: data.payrollDate)
    let payrollDayEnd =
      calendar.date(byAdding: .day, value: 1, to: payrollDayStart) ?? payrollDayStart
    let isOnOrBeforePayrollDay = now < payrollDayEnd
    let canManuallySetPayrollStatus = viewModel.isCurrentMonth && isOnOrBeforePayrollDay

    let payrollOverrideUserId = coordinator.getCurrentUserId()
    let payrollMarkedReceived = viewModel.isPayrollReceivedOverrideForDisplayedMonth(
      userId: payrollOverrideUserId
    )
    let effectivePayrollHasPassed: Bool = {
      guard viewModel.isCurrentMonth else { return data.payrollHasPassed }
      if isOnOrBeforePayrollDay {
        return payrollMarkedReceived
      }
      return true
    }()

    // Determine payroll label based on whether viewing current month
    let payrollLabel: String = {
      if viewModel.isCurrentMonth {
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
    let payrollProgress: Double? = {
      guard viewModel.isCurrentMonth && !effectivePayrollHasPassed else { return nil }

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

    // Cards stay in place - only numbers animate on month change (like Next.js)
    VStack(spacing: Spacing.sm) {
      // Payroll countdown text - fixed height to prevent layout shift
      Text(countdownManager.payrollCountdownText ?? " ")
        .font(.tidexLabel)
        .foregroundColor(.tidexTextSecondary)
        .opacity(countdownManager.payrollCountdownText != nil ? 1 : 0)
        .frame(height: 20)

      // Payroll Card (Previous Month relative to displayed month)
      Group {
        if canManuallySetPayrollStatus {
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
            PayrollCard(
              payrollDate: data.payrollDate,
              label: payrollLabel,
              gross: data.previousMonthGross,
              net: data.previousMonthNet,
              tax: data.previousMonthTax,
              taxEnabled: data.previousMonthTaxEnabled,
              progress: payrollProgress
            )
          }
          .menuIndicator(.hidden)
        } else {
          PayrollCard(
            payrollDate: data.payrollDate,
            label: payrollLabel,
            gross: data.previousMonthGross,
            net: data.previousMonthNet,
            tax: data.previousMonthTax,
            taxEnabled: data.previousMonthTaxEnabled,
            progress: payrollProgress
          )
        }
      }
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
        taxEnabled: data.currentMonthTaxEnabled
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

  // MARK: - Featured Shift Section

  /// Featured shift card with fixed height to prevent layout jumps
  @ViewBuilder
  private func featuredShiftSection(data: DashboardData) -> some View {
    // Use a fixed height container so the layout doesn't shift
    // when switching between FeaturedShiftCard and EmptyShiftCard
    Group {
      if let featuredShift = data.featuredShift {
        // Only show progress bar for active shifts (matching Next.js behavior)
        let shiftProgress: Double? =
          countdownManager.isShiftActive ? countdownManager.shiftProgress : nil
        FeaturedShiftCard(
          shift: featuredShift,
          isToday: data.isFeaturedShiftToday,
          isBestShift: data.featuredShiftIsBestShift,
          countdownText: countdownManager.shiftCountdownText,
          progress: shiftProgress
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
              isLoading: true
            )

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
