import SwiftUI

/// Stats tab view - displays statistics and analytics
/// Shows monthly earnings, hours, shifts, and goal progress
struct StatsView: View {
  @EnvironmentObject private var coordinator: AppCoordinator

  /// Binding to the selected tab for navigation
  @Binding var selectedTab: MainTabView.Tab

  private struct MonthlyGoalEditContext: Identifiable {
    let id = UUID()
    let monthDate: Date
    let baselineGoal: Int?
    let initialGoal: Int?
  }

  @StateObject private var viewModel = StatsViewModel()
  @State private var monthlyGoalEditContext: MonthlyGoalEditContext?

  // Haptic feedback
  private let selectionHaptic = UISelectionFeedbackGenerator()

  /// Shared refresh action used by pull-to-refresh and sync retry UI.
  private func refreshStatsContent() async {
    AppearanceTracker.shared.reset()
    await viewModel.refresh()
  }

  var body: some View {
    NavigationStack {
      ZStack {
        // Background
        Color.tidexBackground
          .ignoresSafeArea()

        // Main content - month picker is now in shared overlay
        Group {
          if let error = viewModel.error {
            errorView(error: error)
          } else if let stats = viewModel.stats {
            statsContent(stats: stats)
          } else if viewModel.isLoading {
            loadingView
          } else {
            // Initial state - show loading
            loadingView
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Pass user's currency to all child views
        .userCurrency(viewModel.currency)

        // Sync status indicator (shows when syncing, failed, or offline)
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
    }
    .task {
      await viewModel.loadStats()
    }
    .onAppear {
      selectionHaptic.prepare()
    }
  }

  // MARK: - Stats Content

  @ViewBuilder
  private func statsContent(stats: StatsData) -> some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(spacing: Spacing.md) {
          Color.clear.frame(height: 0).id("stats-top")
          sectionHeader(.statsSectionOverview)

          // Monthly Earnings Card (large)
          MonthlyEarningsCard(
            grossEarnings: stats.currentMonth.totalEarnings,
            netEarnings: stats.currentMonth.totalEarningsNet,
            taxEnabled: stats.tax.enabled,
            percentageChange: stats.percentageChange,
            onTap: { openMonthlyGoalEditor() }
          )

          // Hours and Shifts cards (side by side)
          HStack(spacing: Spacing.sm) {
            HoursStatCard(hours: stats.currentMonth.totalHours)
            ShiftsStatCard(count: stats.currentMonth.shiftCount)
          }

          // Monthly Goal Card
          if stats.monthlyGoal.enabled {
            MonthlyGoalCard(
              goal: stats.monthlyGoal,
              onTap: { openMonthlyGoalEditor() }
            )
          } else {
            MonthlyGoalEmptyCard(onTap: { openMonthlyGoalEditor() })
          }

          sectionHeader(.statsSectionCharts)

          // Weekly Chart (This Week or Best Week)
          weeklyChartSection(stats: stats)

          // Monthly Progress Chart
          if !stats.thisMonthCumulative.isEmpty {
            MonthlyProgressChart(data: stats.thisMonthCumulative)
          } else {
            MonthlyProgressChartEmpty()
          }

          // Yearly Income Chart
          yearlyIncomeChartSection(stats: stats)

          // Employment Percentage Chart
          if let employment = stats.employment,
            employment.monthlyData.contains(where: { $0.averagePercentage > 0 })
          {
            EmploymentPercentageChart(data: employment)
          } else {
            EmploymentPercentageChartEmpty()
          }

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
          isEnabled: true
        )
      }
      .refreshable {
        await refreshStatsContent()
      }
      .onReceive(NotificationCenter.default.publisher(for: .tabReselected)) { notification in
        guard let tab = notification.userInfo?["tab"] as? MainTabView.Tab,
          tab == .stats
        else { return }
        withAnimation { proxy.scrollTo("stats-top", anchor: .top) }
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

  private func openMonthlyGoalEditor() {
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

  // MARK: - Loading View

  @ViewBuilder
  private var loadingView: some View {
    ScrollView {
      VStack(spacing: Spacing.md) {
        // Skeleton for Monthly Earnings Card
        skeletonCard(height: 200)

        // Skeleton for Hours and Shifts cards
        HStack(spacing: Spacing.sm) {
          skeletonCard(height: 100)
          skeletonCard(height: 100)
        }

        // Skeleton for Monthly Goal Card
        skeletonCard(height: 140)

        // Skeleton for Weekly Chart
        skeletonCard(height: 260)

        // Skeleton for Monthly Progress Chart
        skeletonCard(height: 280)

        // Skeleton for Yearly Income Chart
        skeletonCard(height: 280)

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
        isEnabled: true
      )
    }
    .refreshable {
      await refreshStatsContent()
    }
  }

  @ViewBuilder
  private func skeletonCard(height: CGFloat) -> some View {
    RoundedRectangle(cornerRadius: CornerRadius.xxl)
      .fill(Color.tidexSurfacePrimary)
      .frame(height: height)
      .overlay(
        RoundedRectangle(cornerRadius: CornerRadius.xxl)
          .stroke(Color.tidexBorderSubtle, lineWidth: 1)
      )
      .shimmer(isActive: true)
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
  StatsView(selectedTab: .constant(.stats))
    .environmentObject(AppCoordinator.shared)
}
