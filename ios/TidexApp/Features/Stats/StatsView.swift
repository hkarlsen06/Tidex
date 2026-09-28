import SwiftUI

/// Stats tab view - displays statistics and analytics
/// Shows monthly earnings, hours, shifts, and trends
struct StatsView: View {
  // swiftlint:disable:previous explicit_acl explicit_top_level_acl file_types_order type_body_length
  @EnvironmentObject private var coordinator: AppCoordinator  // swiftlint:disable:this type_contents_order

  @StateObject private var viewModel = StatsViewModel()  // swiftlint:disable:this explicit_type_interface
  @StateObject private var workSetupPresentationViewModel = WorkSetupPresentationViewModel()  // swiftlint:disable:this explicit_type_interface line_length
  @State private var isJobFilterDialogPresented = false  // swiftlint:disable:this explicit_type_interface
  @State private var showMixedCurrencyBreakdownPopover = false  // swiftlint:disable:this explicit_type_interface
  @State private var showExportSettings = false  // swiftlint:disable:this explicit_type_interface

  // Haptic feedback
  private let selectionHaptic = UISelectionFeedbackGenerator()  // swiftlint:disable:this explicit_type_interface

  /// Shared refresh action used by pull-to-refresh and sync retry UI.
  private func refreshStatsContent() async {  // swiftlint:disable:this type_contents_order
    AppearanceTracker.shared.reset()
    await viewModel.refresh()
  }

  private var displayedStats: StatsData {
    viewModel.stats
      ?? StatsData.empty(year: viewModel.displayYear, month: viewModel.displayMonth)
  }

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

  private func loadStatsContent() async {  // swiftlint:disable:this type_contents_order
    guard !shouldShowWorkSetupRequiredPlaceholder else { return }  // swiftlint:disable:this conditional_returns_on_newline line_length
    await viewModel.loadStats()
  }

  var body: some View {  // swiftlint:disable:this explicit_acl
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
    .iPadToolbarTransaction()
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
      let shouldLoadAfterSetupCompleted = refreshWorkSetupPresentationState()  // swiftlint:disable:this explicit_type_interface line_length
      guard shouldLoadAfterSetupCompleted else { return }  // swiftlint:disable:this conditional_returns_on_newline
      Task {
        await loadStatsContent()
      }
    }
    .onChange(of: coordinator.userId) { _, _ in
      refreshWorkSetupPresentationState()
    }
    .onReceive(NotificationCenter.default.publisher(for: .workSetupDataDidChange)) { _ in
      let shouldLoadAfterSetupCompleted = refreshWorkSetupPresentationState()  // swiftlint:disable:this explicit_type_interface line_length
      guard shouldLoadAfterSetupCompleted else { return }  // swiftlint:disable:this conditional_returns_on_newline
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
  private func statsContent(stats: StatsData) -> some View {  // swiftlint:disable:this function_body_length line_length type_contents_order
    ScrollViewReader { _ in  // swiftlint:disable:this closure_body_length
      ScrollView {  // swiftlint:disable:this closure_body_length
        VStack(spacing: Spacing.lg) {  // swiftlint:disable:this closure_body_length
          Color.clear.frame(height: 0).id("stats-top")

          if viewModel.shouldShowJobFilter {
            statsJobFilterRow
          }

          let currentMonthAggregate = stats.currentMonthCurrencyAggregate  // swiftlint:disable:this explicit_type_interface line_length
          let usesMixedCurrency = currentMonthAggregate?.hasMixedCurrency == true  // swiftlint:disable:this explicit_type_interface line_length
          let breakdownEntries = currentMonthAggregate?.secondary ?? []  // swiftlint:disable:this explicit_type_interface line_length
          let monthlyCardCurrency = currentMonthAggregate?.primary.currency ?? viewModel.currency  // swiftlint:disable:this explicit_type_interface line_length

          StatsOverviewLedger(
            stats: stats,
            showsCurrencyBreakdown: usesMixedCurrency && !breakdownEntries.isEmpty,
            onEarningsTap: {
              if usesMixedCurrency, !breakdownEntries.isEmpty {
                selectionHaptic.selectionChanged()
                showMixedCurrencyBreakdownPopover.toggle()
              }
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
              .frame(minHeight: 260, alignment: .top)  // swiftlint:disable:this no_magic_numbers

            // Monthly Progress Chart
            Group {
              if !stats.thisMonthCumulative.isEmpty {
                MonthlyProgressChart(data: stats.thisMonthCumulative)
              } else {
                MonthlyProgressChartEmpty()
              }
            }
            .frame(minHeight: 280, alignment: .top)  // swiftlint:disable:this no_magic_numbers

            // Yearly Income Chart
            yearlyIncomeChartSection(stats: stats)
              .frame(minHeight: 280, alignment: .top)  // swiftlint:disable:this no_magic_numbers

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
            .frame(minHeight: 280, alignment: .top)  // swiftlint:disable:this no_magic_numbers
          }
          .userCurrency(monthlyCardCurrency)

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
          edgeExclusion: 24,  // swiftlint:disable:this no_magic_numbers
          isEnabled: true
        )
      }
      .refreshable {
        await refreshStatsContent()
      }
    }  // ScrollViewReader
  }

  private func sectionHeader(_ title: LocalizedStringResource) -> some View {  // swiftlint:disable:this line_length type_contents_order
    Text(title)
      .font(.tidexLabelStrong)
      .foregroundColor(.tidexTextSecondary)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.top, Spacing.xs)
  }

  @ViewBuilder
  private var statsJobFilterRow: some View {
    let selectedJob = viewModel.activeJobs.first(where: { $0.id == viewModel.selectedJobId })  // swiftlint:disable:this explicit_type_interface line_length

    HStack {  // swiftlint:disable:this closure_body_length
      HStack(spacing: Spacing.xxxs) {
        Image(systemName: "line.3.horizontal.decrease.circle")
          .font(.tidexFootnote)
          .foregroundColor(.tidexTextMuted)
          .accessibilityHidden(true)
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

        Button(String(localized: .commonCancel), role: .cancel) {}  // swiftlint:disable:this no_empty_block
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
    let shape = RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)  // swiftlint:disable:this explicit_type_interface line_length

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
        .accessibilityHidden(true)
    }
    .padding(.horizontal, Spacing.sm)
    .padding(.vertical, Spacing.xs)
    .background(shape.fill(Color.tidexSurfaceSecondary))
    .overlay(shape.stroke(Color.tidexBorderSubtle, lineWidth: 1))
    .contentShape(shape)
  }

  // MARK: - Weekly Chart Section

  @ViewBuilder
  private func weeklyChartSection(stats: StatsData) -> some View {
    if let thisWeek = stats.thisWeek, !thisWeek.isEmpty {
      // Current month: show "This Week"
      let hasData = thisWeek.contains { $0.earnings > 0 }  // swiftlint:disable:this explicit_type_interface
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
      let hasData = bestWeek.weekData.contains { $0.earnings > 0 }  // swiftlint:disable:this explicit_type_interface
      if hasData {
        let title = String(localized: .statsChartsWeeklyChartBestWeek(bestWeek.weekNumber))  // swiftlint:disable:this explicit_type_interface line_length
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
      let hasData = yearlyIncome.contains { $0.earnings > 0 }  // swiftlint:disable:this explicit_type_interface
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
  private func errorView(error _: Error) -> some View {
    VStack(spacing: Spacing.md) {
      Image(systemName: "exclamationmark.triangle")
        .font(.system(size: 48))  // swiftlint:disable:this no_magic_numbers
        .foregroundColor(.tidexTextMuted)
        .accessibilityHidden(true)

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

  @Environment(\.userCurrency) private var currency  // swiftlint:disable:this explicit_type_interface

  private var mainDisplayValue: Double {
    stats.tax.enabled ? stats.currentMonth.totalEarningsNet : stats.currentMonth.totalEarnings
  }

  private var showBeforeTaxRow: Bool {
    stats.tax.enabled && stats.currentMonth.totalEarnings != stats.currentMonth.totalEarningsNet
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.mlg) {
      earningsHeader

      Divider()
        .overlay(Color.tidexSeparator)  // swiftlint:disable:this no_magic_numbers

      metricStrip
    }
    .statsPanelSurface(
      padding: Spacing.lg,
      cornerRadius: CornerRadius.card,
      shadowLevel: .card
    )
  }

  @ViewBuilder
  private var earningsHeader: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {  // swiftlint:disable:this closure_body_length
      HStack(alignment: .top, spacing: Spacing.sm) {  // swiftlint:disable:this closure_body_length
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
          .minimumScaleFactor(0.45)  // swiftlint:disable:this no_magic_numbers
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
            Image(systemName: "info.circle")
              .font(.tidexTitle2)
              .foregroundColor(.tidexTextMuted)
              .frame(width: 44, height: 44)  // swiftlint:disable:this no_magic_numbers
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel(Text(.statsCurrencyBreakdownShow))
        }
      }

      VStack(alignment: .leading, spacing: Spacing.xs) {
        if showBeforeTaxRow {
          StatsLedgerValueRow(
            label: .statsBeforeTax,
            value: formatCurrency(stats.currentMonth.totalEarnings)
          )
        }

        if let percentageChange = stats.percentageChange {
          MonthlyEarningsChangeBadge(percentageChange: percentageChange)
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
        .fill(Color.tidexBorderSubtle.opacity(0.55))  // swiftlint:disable:this no_magic_numbers
        .frame(width: 1, height: 44)  // swiftlint:disable:this no_magic_numbers

      StatsLedgerMetric(
        label: .statsShifts,
        value: "\(stats.currentMonth.shiftCount)",
        systemImage: "calendar"
      )
      .padding(.leading, Spacing.md)
    }
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
        Image(systemName: systemImage)  // swiftlint:disable:this accessibility_label_for_image
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
        .minimumScaleFactor(0.7)  // swiftlint:disable:this no_magic_numbers
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
        .minimumScaleFactor(0.75)  // swiftlint:disable:this no_magic_numbers
    }
    .padding(.vertical, Spacing.xxxs)
  }
}

#Preview {
  StatsView()
    .environmentObject(AppCoordinator.shared)
}  // swiftlint:disable:this file_length
