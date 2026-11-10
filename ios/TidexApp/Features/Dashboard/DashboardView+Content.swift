import SwiftUI

extension DashboardView {

  // MARK: - Card Content

  /// Card content with pull-to-refresh and swipe gestures
  /// Month picker is handled separately in the main body so it's always visible
  @ViewBuilder
  func cardContent(data: DashboardData) -> some View {  // swiftlint:disable:this type_contents_order
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

        if let payAssumptions {
          PayAssumptionsCard(
            assumptions: payAssumptions,
            onReview: {
              finishPayAssumptionsReview()
              coordinator.pendingDeepLink = .settings(destination: .pay(jobId: payAssumptions.jobId))
            },
            onDismiss: finishPayAssumptionsReview
          )
          .transition(.opacity)
        }
      }
      .contentShape(Rectangle())
      .gesture(monthSwipeGesture())
    } else {
      EmptyView()
    }
  }

  private func finishPayAssumptionsReview() {  // swiftlint:disable:this type_contents_order
    if let userId = coordinator.userId {
      OnboardingCompletionStore.setPayAssumptionsReviewPending(false, userId: userId)
    }
    withAnimation(.easeOut(duration: 0.2)) {  // swiftlint:disable:this no_magic_numbers
      payAssumptions = nil
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
  private func clockButtonsSection() -> some View {  // swiftlint:disable:this type_contents_order
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
          await clockOut()
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
      .foregroundStyle(
        isEnabled
          ? Color.tidexTextPrimary
          : Color.tidexTextMuted
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
      selectedVariant.taxEnabled
      ? (selectedVariant.net ?? selectedVariant.gross) : selectedVariant.gross
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
        FirstShiftPrompt(carriedShift: carriedDemoShift) {
          if carriedDemoShift != nil, OnboardingFirstShiftCarryoverStore.moveToAddShiftDraft() {
            OnboardingFunnelRecorder.shared.record("demo_shift_prefilled")
          }
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

  private func clockOut() async {  // swiftlint:disable:this type_contents_order
    let route = await viewModel.routeClockOut()  // swiftlint:disable:this explicit_type_interface
    if case .temporaryReview(let session) = route {
      await presentTemporaryClockReview(session)
    } else if case .persistedEnded = route {
      AccessibilityNotification.Announcement(String(localized: .dashboardAccessibilityClockedOut))
        .post()
    }
  }

  // swiftlint:disable:next type_contents_order
  /// Siri's Clock Out action opens Home with this link.
  func handleClockOutDeepLink(_ deepLink: AppCoordinator.DeepLink?) {
    guard deepLink == .clockOut else { return }  // swiftlint:disable:this conditional_returns_on_newline
    coordinator.clearPendingDeepLink()
    Task {
      await clockOut()
    }
  }

  private func presentTemporaryClockReview(_ session: TemporaryClockSession) async {  // swiftlint:disable:this line_length type_contents_order
    if viewModel.clockSelectableJobsSnapshot().isEmpty {
      _ = await viewModel.clockSelectableJobs()
    }
    temporaryClockReviewSession = session
  }

  func handleClockIn(jobId: String?) async {  // swiftlint:disable:this type_contents_order
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

  func completeClockPaySetup(for job: Job, input: JobPaySetupInput) async -> Bool {  // swiftlint:disable:this line_length type_contents_order
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
  var loadingSkeletonView: some View {
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
  func errorView(message: String) -> some View {
    VStack(spacing: Spacing.md) {
      Image(systemName: "exclamationmark.triangle")
        .font(.system(size: errorIconSize))
        .foregroundStyle(Color.tidexWarning)
        .accessibilityHidden(true)

      Text(.dashboardLoadError)
        .font(.tidexBodyMedium)
        .foregroundStyle(Color.tidexTextPrimary)

      Text(message)
        .font(.tidexSubheadline)
        .foregroundStyle(Color.tidexTextSecondary)
        .multilineTextAlignment(.center)

      Button {
        Task { await viewModel.loadDashboard() }
      } label: {
        Text(.commonRetry)
          .font(.tidexLabel)
          .foregroundStyle(Color.tidexBlueText)
          .padding(.horizontal, Spacing.mlg)
          .padding(.vertical, Spacing.sm)
          .background(Color.tidexBlue.opacity(0.1))  // swiftlint:disable:this no_magic_numbers
          .clipShape(.rect(cornerRadius: CornerRadius.sm))
      }
    }
    .frame(maxWidth: AdaptiveMaxWidth.tabContent)
    .padding(.horizontal, Spacing.xxl)
    .announcesToVoiceOver(String(localized: .dashboardLoadError))
  }
}

extension DashboardView {

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
          .foregroundStyle(Color.tidexTextSecondary)
          .accessibilityHidden(true)
        Text(.addShiftEventAllDay)
          .font(.tidexLabel)
          .foregroundStyle(Color.tidexTextSecondary)
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
}

private struct DashboardClockButtonStyle: ButtonStyle {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion  // swiftlint:disable:this explicit_type_interface

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(reduceMotion ? 1.0 : (configuration.isPressed ? 0.98 : 1.0))  // swiftlint:disable:this line_length no_magic_numbers
      .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)  // swiftlint:disable:this line_length no_magic_numbers
  }
}