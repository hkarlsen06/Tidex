import SwiftUI

/// Stats tab view - displays statistics and analytics
/// Shows monthly earnings, hours, shifts, and goal progress
struct StatsView: View {
  @EnvironmentObject private var coordinator: AppCoordinator

  private struct MonthlyGoalEditContext: Identifiable {
    let id = UUID()
    let monthDate: Date
    let baselineGoal: Int?
    let initialGoal: Int?
  }

  @StateObject private var viewModel = StatsViewModel()
  @State private var monthlyGoalEditContext: MonthlyGoalEditContext?
  @State private var isJobFilterDialogPresented = false
  @State private var showMixedCurrencyBreakdownPopover = false
  @State private var showExportSettings = false

  // Haptic feedback
  private let selectionHaptic = UISelectionFeedbackGenerator()
  private let workSetupStatusService = WorkSetupStatusService.shared

  /// Shared refresh action used by pull-to-refresh and sync retry UI.
  private func refreshStatsContent() async {
    AppearanceTracker.shared.reset()
    await viewModel.refresh()
  }

  private var displayedStats: StatsData {
    viewModel.stats
      ?? StatsData.empty(year: viewModel.displayYear, month: viewModel.displayMonth)
  }

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

  var body: some View {
    ZStack {
      // Background
      TidexAppBackground()

      // Main content - month picker is now in shared overlay
      Group {
        if shouldShowWorkSetupRequiredPlaceholder {
          WorkSetupRequiredPlaceholder()
        } else if let error = viewModel.error, viewModel.stats == nil {
          errorView(error: error)
        } else {
          statsContent(stats: displayedStats)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      // Pass user's currency to all child views
      .userCurrency(viewModel.currency)

      if !shouldShowWorkSetupRequiredPlaceholder {
        VStack {
          SyncStatusIndicator {
            Task {
              await refreshStatsContent()
            }
          }
          .padding(.top, Spacing.xs)
          Spacer()
        }
      }
    }
    .navigationBarTitleDisplayMode(.inline)
    .iPadToolbarBackground()
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
    .sheet(isPresented: $showExportSettings) {
      SettingsView(initialDestination: .data)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
    .task {
      guard !shouldShowWorkSetupRequiredPlaceholder else { return }
      await viewModel.loadStats()
    }
    .onAppear {
      selectionHaptic.prepare()
    }
    .onChange(of: viewModel.stats?.focusMonth) { _, _ in
      showMixedCurrencyBreakdownPopover = false
    }
  }

  // MARK: - Stats Content

  @ViewBuilder
  private func statsContent(stats: StatsData) -> some View {
    ScrollViewReader { _ in
      ScrollView {
        VStack(spacing: Spacing.md) {
          Color.clear.frame(height: 0).id("stats-top")

          if viewModel.shouldShowJobFilter {
            statsJobFilterRow
          }

          sectionHeader(.statsSectionOverview)

          // Monthly Earnings Card (large)
          let currentMonthAggregate = stats.currentMonthCurrencyAggregate
          let usesMixedCurrency = currentMonthAggregate?.hasMixedCurrency == true
          let breakdownEntries = currentMonthAggregate?.secondary ?? []
          let monthlyCardCurrency = currentMonthAggregate?.primary.currency ?? viewModel.currency

          MonthlyEarningsCard(
            grossEarnings: stats.currentMonth.totalEarnings,
            netEarnings: stats.currentMonth.totalEarningsNet,
            taxEnabled: stats.tax.enabled,
            percentageChange: stats.percentageChange,
            onTap: {
              if usesMixedCurrency && !breakdownEntries.isEmpty {
                selectionHaptic.selectionChanged()
                showMixedCurrencyBreakdownPopover.toggle()
              } else {
                openMonthlyGoalEditor()
              }
            }
          )
          .userCurrency(monthlyCardCurrency)
          .popover(isPresented: $showMixedCurrencyBreakdownPopover) {
            MixedCurrencyBreakdownPopover(entries: breakdownEntries)
              .presentationCompactAdaptation(.popover)
          }

          // Hours and Shifts cards (side by side)
          HStack(spacing: Spacing.sm) {
            HoursStatCard(hours: stats.currentMonth.totalHours)
            ShiftsStatCard(count: stats.currentMonth.shiftCount)
          }

          // Monthly Goal Card
          Group {
            if stats.monthlyGoal.enabled {
              MonthlyGoalCard(
                goal: stats.monthlyGoal,
                onTap: { openMonthlyGoalEditor() }
              )
            } else {
              MonthlyGoalEmptyCard(onTap: { openMonthlyGoalEditor() })
            }
          }
          .frame(minHeight: 140, alignment: .top)

          sectionHeader(.statsSectionCharts)

          // Weekly Chart (This Week or Best Week)
          weeklyChartSection(stats: stats)
            .frame(minHeight: 260, alignment: .top)

          // Monthly Progress Chart
          Group {
            if !stats.thisMonthCumulative.isEmpty {
              MonthlyProgressChart(data: stats.thisMonthCumulative)
            } else {
              MonthlyProgressChartEmpty()
            }
          }
          .frame(minHeight: 280, alignment: .top)

          // Yearly Income Chart
          yearlyIncomeChartSection(stats: stats)
            .frame(minHeight: 280, alignment: .top)

          // Employment Percentage Chart
          Group {
            if let employment = stats.employment,
              employment.monthlyData.contains(where: { $0.averagePercentage > 0 })
            {
              EmploymentPercentageChart(data: employment)
            } else {
              EmploymentPercentageChartEmpty()
            }
          }
          .frame(minHeight: 280, alignment: .top)

          PrimaryButton(title: String(localized: .dataExportPdfButton)) {
            showExportSettings = true
          }
          .clipShape(RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous))

          // Bottom spacing for floating month picker
          Spacer()
            .frame(height: MonthPickerLayout.totalBottomInset + Spacing.lg)
        }
        .frame(maxWidth: AdaptiveMaxWidth.tabContent)
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.md)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .monthSwipeGesture(
          onSwipeLeft: { viewModel.goToNextMonth() },
          onSwipeRight: { viewModel.goToPreviousMonth() },
          edgeExclusion: 24,
          isEnabled: true
        )
      }
      .refreshable {
        await refreshStatsContent()
      }
    }  // ScrollViewReader
  }

  private func sectionHeader(_ title: LocalizedStringResource) -> some View {
    Text(title)
      .font(.tidexLabelStrong)
      .foregroundColor(.tidexTextSecondary)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.top, Spacing.xs)
  }

  @ViewBuilder
  private var statsJobFilterRow: some View {
    let selectedJob = viewModel.activeJobs.first(where: { $0.id == viewModel.selectedJobId })

    HStack {
      HStack(spacing: Spacing.xxxs) {
        Image(systemName: "line.3.horizontal.decrease.circle")
          .font(.tidexFootnote)
          .foregroundColor(.tidexTextMuted)
        Text(.jobsFilterTitle)
          .font(.tidexLabel)
          .foregroundColor(.tidexTextSecondary)
      }

      Spacer()

      Button {
        selectionHaptic.selectionChanged()
        isJobFilterDialogPresented = true
      } label: {
        statsJobFilterMenuLabel(selectedJob: selectedJob)
      }
      .buttonStyle(.plain)
      .confirmationDialog(
        String(localized: .jobsFilterTitle),
        isPresented: $isJobFilterDialogPresented,
        titleVisibility: .visible
      ) {
        Button {
          selectionHaptic.selectionChanged()
          viewModel.selectJobFilter(nil)
        } label: {
          if viewModel.selectedJobId == nil {
            Label(String(localized: .jobsFilterAll), systemImage: "checkmark")
          } else {
            Text(.jobsFilterAll)
          }
        }

        ForEach(viewModel.activeJobs) { job in
          Button {
            selectionHaptic.selectionChanged()
            viewModel.selectJobFilter(job.id)
          } label: {
            if viewModel.selectedJobId == job.id {
              Label(job.name, systemImage: "checkmark")
            } else {
              Text(job.name)
            }
          }
        }

        Button(String(localized: .commonCancel), role: .cancel) {}
      }
    }
    // Keep filter control styling stable while stats cards animate numeric transitions.
    .transaction { transaction in
      transaction.disablesAnimations = true
      transaction.animation = nil
    }
  }

  @ViewBuilder
  private func statsJobFilterMenuLabel(selectedJob: Job?) -> some View {
    let shape = RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)

    HStack(spacing: Spacing.xs) {
      if let selectedJob {
        WorkplaceNameText(
          name: selectedJob.name,
          colorHex: selectedJob.color,
          font: .tidexBody,
          fallbackBadgeColor: .tidexBlue
        )
      } else {
        Text(viewModel.selectedJobName ?? String(localized: .jobsFilterAll))
          .font(.tidexBody)
          .foregroundColor(.tidexTextPrimary)
      }
      Image(systemName: "chevron.down")
        .font(.tidexCaptionRegular)
        .foregroundColor(.tidexTextMuted)
    }
    .padding(.horizontal, Spacing.sm)
    .padding(.vertical, Spacing.xs)
    .background(shape.fill(Color.tidexSurfaceSecondary))
    .overlay(shape.stroke(Color.tidexBorderSubtle, lineWidth: 1))
    .contentShape(shape)
  }

  private func openMonthlyGoalEditor() {
    guard viewModel.stats != nil else { return }
    selectionHaptic.selectionChanged()
    let baseline = viewModel.baselineMonthlyGoal
    let override = viewModel.displayedMonthOverrideGoal
    let effectiveGoal =
      viewModel.stats?.monthlyGoal.enabled == true
      ? Int((viewModel.stats?.monthlyGoal.target ?? 0).rounded())
      : nil

    let initialGoal =
      override
      ?? effectiveGoal.flatMap { effective in
        guard effective > 0 else { return nil }
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

  // MARK: - Weekly Chart Section

  @ViewBuilder
  private func weeklyChartSection(stats: StatsData) -> some View {
    if let thisWeek = stats.thisWeek, !thisWeek.isEmpty {
      // Current month: show "This Week"
      let hasData = thisWeek.contains { $0.earnings > 0 }
      if hasData {
        WeeklyBarChart(
          data: thisWeek,
          title: String(localized: .statsChartsWeeklyChartThisWeek),
          highlightToday: true
        )
      } else {
        WeeklyBarChartEmpty(
          title: String(localized: .statsChartsWeeklyChartThisWeek)
        )
      }
    } else if let bestWeek = stats.bestWeek {
      // Past month: show "Best Week"
      let hasData = bestWeek.weekData.contains { $0.earnings > 0 }
      if hasData {
        let title = String(localized: .statsChartsWeeklyChartBestWeek(bestWeek.weekNumber))
        WeeklyBarChart(
          data: bestWeek.weekData,
          title: title,
          highlightToday: false
        )
      } else {
        // Past month with no shifts in best week (shouldn't happen, but handle gracefully)
        WeeklyBarChartEmpty(
          title: String(localized: .statsChartsWeeklyChartThisWeek)
        )
      }
    } else {
      // No weekly data available (past month with no shifts)
      WeeklyBarChartEmpty(
        title: String(localized: .statsChartsWeeklyChartThisWeek)
      )
    }
  }

  // MARK: - Yearly Income Chart Section

  @ViewBuilder
  private func yearlyIncomeChartSection(stats: StatsData) -> some View {
    if let yearlyIncome = stats.yearlyIncome {
      let hasData = yearlyIncome.contains { $0.earnings > 0 }
      if hasData {
        YearlyIncomeChart(
          data: yearlyIncome,
          focusYear: stats.focusMonth.year
        )
      } else {
        YearlyIncomeChartEmpty(focusYear: stats.focusMonth.year)
      }
    } else {
      YearlyIncomeChartEmpty(focusYear: stats.focusMonth.year)
    }
  }

  // MARK: - Error View

  @ViewBuilder
  private func errorView(error: Error) -> some View {
    VStack(spacing: Spacing.md) {
      Image(systemName: "exclamationmark.triangle")
        .font(.system(size: 48))
        .foregroundColor(.tidexTextMuted)

      Text(.statsErrorsCouldNotUpdate)
        .font(.tidexBodyMedium)
        .foregroundColor(.tidexTextSecondary)
        .multilineTextAlignment(.center)

      Button {
        Task {
          await refreshStatsContent()
        }
      } label: {
        Text(.commonRetry)
          .font(.tidexButton)
          .foregroundColor(.tidexTextOnBrand)
          .padding(.horizontal, Spacing.lg)
          .padding(.vertical, Spacing.sm)
          .background(Color.tidexBlue)
          .cornerRadius(CornerRadius.sm)
      }
    }
    .frame(maxWidth: AdaptiveMaxWidth.tabContent)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding()
  }
}

#Preview {
  StatsView()
    .environmentObject(AppCoordinator.shared)
}
