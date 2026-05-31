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
  @StateObject private var workSetupPresentationViewModel = WorkSetupPresentationViewModel()
  @State private var monthlyGoalEditContext: MonthlyGoalEditContext?
  @State private var isJobFilterDialogPresented = false
  @State private var showMixedCurrencyBreakdownPopover = false
  @State private var showExportSettings = false

  // Haptic feedback
  private let selectionHaptic = UISelectionFeedbackGenerator()

  /// Shared refresh action used by pull-to-refresh and sync retry UI.
  private func refreshStatsContent() async {
    AppearanceTracker.shared.reset()
    await viewModel.refresh()
  }

  private var displayedStats: StatsData {
    viewModel.stats
      ?? StatsData.empty(year: viewModel.displayYear, month: viewModel.displayMonth)
  }

  @discardableResult
  private func refreshWorkSetupPresentationState() -> Bool {
    let wasShowingPlaceholder = shouldShowWorkSetupRequiredPlaceholder
    workSetupPresentationViewModel.refresh(
      userId: coordinator.userId,
      initialSyncComplete: coordinator.initialSyncComplete
    )
    return wasShowingPlaceholder && !shouldShowWorkSetupRequiredPlaceholder
  }

  private var shouldShowWorkSetupRequiredPlaceholder: Bool {
    workSetupPresentationViewModel.shouldShowPlaceholder
  }

  private func loadStatsContent() async {
    guard !shouldShowWorkSetupRequiredPlaceholder else { return }
    await viewModel.loadStats()
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
      refreshWorkSetupPresentationState()
      await loadStatsContent()
    }
    .onAppear {
      refreshWorkSetupPresentationState()
      selectionHaptic.prepare()
    }
    .onChange(of: coordinator.initialSyncComplete) { _, _ in
      let shouldLoadAfterSetupCompleted = refreshWorkSetupPresentationState()
      guard shouldLoadAfterSetupCompleted else { return }
      Task {
        await loadStatsContent()
      }
    }
    .onChange(of: coordinator.userId) { _, _ in
      refreshWorkSetupPresentationState()
    }
    .onReceive(NotificationCenter.default.publisher(for: .workSetupDataDidChange)) { _ in
      let shouldLoadAfterSetupCompleted = refreshWorkSetupPresentationState()
      guard shouldLoadAfterSetupCompleted else { return }
      Task {
        await loadStatsContent()
      }
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
        VStack(spacing: Spacing.lg) {
          Color.clear.frame(height: 0).id("stats-top")

          if viewModel.shouldShowJobFilter {
            statsJobFilterRow
          }

          let currentMonthAggregate = stats.currentMonthCurrencyAggregate
          let usesMixedCurrency = currentMonthAggregate?.hasMixedCurrency == true
          let breakdownEntries = currentMonthAggregate?.secondary ?? []
          let monthlyCardCurrency = currentMonthAggregate?.primary.currency ?? viewModel.currency

          StatsOverviewLedger(
            stats: stats,
            showsCurrencyBreakdown: usesMixedCurrency && !breakdownEntries.isEmpty,
            onEarningsTap: {
              if usesMixedCurrency && !breakdownEntries.isEmpty {
                selectionHaptic.selectionChanged()
                showMixedCurrencyBreakdownPopover.toggle()
              }
            },
            onGoalTap: {
              openMonthlyGoalEditor()
            }
          )
          .userCurrency(monthlyCardCurrency)
          .popover(isPresented: $showMixedCurrencyBreakdownPopover) {
            MixedCurrencyBreakdownPopover(entries: breakdownEntries)
              .presentationCompactAdaptation(.popover)
          }

          sectionHeader(.statsSectionCharts)

          VStack(spacing: Spacing.md) {
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
          }

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
    .statsPanelSurface(
      padding: Spacing.sm,
      cornerRadius: CornerRadius.xxl,
      shadowLevel: .subtle
    )
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

private struct StatsOverviewLedger: View {
  let stats: StatsData
  let showsCurrencyBreakdown: Bool
  let onEarningsTap: () -> Void
  let onGoalTap: () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.userCurrency) private var currency

  private var mainDisplayValue: Double {
    stats.tax.enabled ? stats.currentMonth.totalEarningsNet : stats.currentMonth.totalEarnings
  }

  private var showBeforeTaxRow: Bool {
    stats.tax.enabled && stats.currentMonth.totalEarnings != stats.currentMonth.totalEarningsNet
  }

  private var hasChange: Bool {
    stats.percentageChange != nil && stats.percentageChange != 0
  }

  private var isPositiveChange: Bool {
    (stats.percentageChange ?? 0) >= 0
  }

  private var changeText: String {
    let change = stats.percentageChange ?? 0
    let prefix: String

    if change > 0 {
      prefix = "+"
    } else if change < 0 {
      prefix = "-"
    } else {
      prefix = ""
    }

    return
      "\(prefix)\(Int(abs(change)))% \(String(localized: .statsFromPreviousMonth))"
  }

  private var clampedGoalPercentage: Double {
    min(max(stats.monthlyGoal.percentage, 0), 100)
  }

  private var goalReached: Bool {
    stats.monthlyGoal.progress >= stats.monthlyGoal.target && stats.monthlyGoal.enabled
  }

  private var goalStatusText: String {
    guard stats.monthlyGoal.enabled else {
      return String(localized: .statsMonthlyGoalNotEnabled)
    }

    let overAmount = max(stats.monthlyGoal.progress - stats.monthlyGoal.target, 0)
    if overAmount > 0 {
      return String(localized: .statsMonthlyGoalOverTarget(formatCurrency(overAmount)))
    }

    if goalReached {
      return String(localized: .statsMonthlyGoalGoalReached)
    }

    return String(
      localized: .statsMonthlyGoalRemaining(formatCurrency(stats.monthlyGoal.remaining)))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.mlg) {
      earningsHeader

      Divider()
        .overlay(Color.tidexBorderSubtle.opacity(0.55))

      metricStrip

      Divider()
        .overlay(Color.tidexBorderSubtle.opacity(0.55))

      goalPanel
    }
    .statsPanelSurface(
      padding: Spacing.lg,
      cornerRadius: CornerRadius.card,
      shadowLevel: .card
    )
  }

  @ViewBuilder
  private var earningsHeader: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      HStack(alignment: .top, spacing: Spacing.sm) {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
          Text(.statsMonthlyEarnings)
            .font(.tidexLabelStrong)
            .foregroundColor(.tidexTextSecondary)

          CurrencyCountUpText(
            amount: mainDisplayValue,
            animateOnAppear: false,
            animateChanges: false
          )
          .font(.tidexAmountDisplay)
          .foregroundColor(.tidexTextPrimary)
          .minimumScaleFactor(0.45)
          .lineLimit(1)

          if stats.tax.enabled {
            Text(String(localized: .statsAfterTax).lowercased())
              .font(.tidexSubheadline)
              .foregroundColor(.tidexTextSecondary)
          }
        }

        Spacer(minLength: Spacing.sm)

        if showsCurrencyBreakdown {
          Button(action: onEarningsTap) {
            Image(systemName: "ellipsis.circle")
              .font(.tidexTitle2)
              .foregroundColor(.tidexTextMuted)
              .frame(width: 44, height: 44)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel(Text(.statsMonthlyEarnings))
        }
      }

      VStack(alignment: .leading, spacing: Spacing.xs) {
        if showBeforeTaxRow {
          StatsLedgerValueRow(
            label: .statsBeforeTax,
            value: formatCurrency(stats.currentMonth.totalEarnings)
          )
        }

        if hasChange {
          HStack(spacing: Spacing.xs) {
            Image(
              systemName: isPositiveChange
                ? "chart.line.uptrend.xyaxis" : "chart.line.downtrend.xyaxis"
            )
            .font(.tidexCaptionStrong)

            Text(changeText)
              .font(.tidexFootnoteMedium)
          }
          .foregroundColor(isPositiveChange ? .tidexSuccess : .tidexError)
          .padding(.horizontal, Spacing.xs)
          .padding(.vertical, Spacing.xxxs)
          .background(
            Capsule(style: .continuous)
              .fill((isPositiveChange ? Color.tidexSuccess : Color.tidexError).opacity(0.12))
          )
        }
      }
    }
  }

  private var metricStrip: some View {
    HStack(spacing: 0) {
      StatsLedgerMetric(
        label: .statsHours,
        value: formatHours(stats.currentMonth.totalHours),
        systemImage: "clock"
      )

      Rectangle()
        .fill(Color.tidexBorderSubtle.opacity(0.55))
        .frame(width: 1, height: 44)

      StatsLedgerMetric(
        label: .statsShifts,
        value: "\(stats.currentMonth.shiftCount)",
        systemImage: "calendar"
      )
      .padding(.leading, Spacing.md)
    }
  }

  private var goalPanel: some View {
    Button(action: onGoalTap) {
      VStack(alignment: .leading, spacing: Spacing.sm) {
        HStack(alignment: .center, spacing: Spacing.xs) {
          Label {
            Text(.statsMonthlyGoalTitle)
              .font(.tidexLabelStrong)
          } icon: {
            Image(systemName: "target")
              .font(.tidexLabelStrong)
          }
          .foregroundColor(.tidexTextPrimary)

          Spacer(minLength: Spacing.sm)

          Image(systemName: "gearshape")
            .font(.tidexFootnoteMedium)
            .foregroundColor(.tidexTextMuted)
        }

        if stats.monthlyGoal.enabled {
          HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
            Text("\(Int(clampedGoalPercentage.rounded()))%")
              .font(.tidexMonoTitle)
              .foregroundColor(goalReached ? .tidexSuccess : .tidexTextPrimary)

            Text(
              String(
                localized: .statsMonthlyGoalProgressTargetSuffix(
                  formatCurrency(stats.monthlyGoal.target)
                ))
            )
            .font(.tidexSubheadline)
            .foregroundColor(.tidexTextSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
          }

          goalProgressBar
        }

        Text(goalStatusText)
          .font(.tidexSubheadline)
          .foregroundColor(goalReached ? .tidexSuccess : .tidexTextSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private var goalProgressBar: some View {
    GeometryReader { geometry in
      ZStack(alignment: .leading) {
        Capsule(style: .continuous)
          .fill(Color.tidexBackgroundSecondary)
          .frame(height: 10)

        Capsule(style: .continuous)
          .fill(goalReached ? Color.tidexSuccess : Color.tidexBlue)
          .frame(
            width: max(0, geometry.size.width * (clampedGoalPercentage / 100)),
            height: 10
          )
          .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: clampedGoalPercentage)
      }
    }
    .frame(height: 10)
  }

  private func formatCurrency(_ amount: Double) -> String {
    CurrencyConfig.format(amount, currency: currency)
  }

  private func formatHours(_ hours: Double) -> String {
    hours.formatted(.number.precision(.fractionLength(0...1)).locale(Locale.appLocale))
  }
}

private struct StatsLedgerMetric: View {
  let label: LocalizedStringResource
  let value: String
  let systemImage: String

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.xxs) {
      HStack(spacing: Spacing.xxs) {
        Image(systemName: systemImage)
          .font(.tidexCaptionStrong)
          .foregroundColor(.tidexTextMuted)

        Text(label)
          .font(.tidexCaptionStrong)
          .foregroundColor(.tidexTextSecondary)
      }

      Text(value)
        .font(.tidexTitle)
        .foregroundColor(.tidexTextPrimary)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, Spacing.xxs)
  }
}

private struct StatsLedgerValueRow: View {
  let label: LocalizedStringResource
  let value: String

  var body: some View {
    HStack(spacing: Spacing.sm) {
      Text(label)
        .font(.tidexFootnoteMedium)
        .foregroundColor(.tidexTextSecondary)

      Spacer(minLength: Spacing.sm)

      Text(value)
        .font(.tidexMonoLabel)
        .foregroundColor(.tidexTextPrimary)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
    .padding(.vertical, Spacing.xxxs)
  }
}

#Preview {
  StatsView()
    .environmentObject(AppCoordinator.shared)
}
