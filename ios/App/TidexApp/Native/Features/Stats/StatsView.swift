import SwiftUI

/// Stats tab view - displays statistics and analytics
/// Shows monthly earnings, hours, shifts, and goal progress
struct StatsView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.localization) private var localization

    /// Binding to the selected tab for navigation
    @Binding var selectedTab: MainTabView.Tab

    @StateObject private var viewModel = StatsViewModel()

    // Haptic feedback
    private let selectionHaptic = UISelectionFeedbackGenerator()

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // Background
                Color.tidexBackground
                    .ignoresSafeArea()

                // Main content
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

                // Floating month picker
                AnimatedMonthHeader(
                    monthName: viewModel.displayMonthName,
                    year: viewModel.displayYear,
                    phase: transitionPhase,
                    isCurrentMonth: viewModel.isCurrentMonth,
                    config: .default,
                    onPrevious: {
                        viewModel.goToPreviousMonth()
                    },
                    onNext: {
                        viewModel.goToNextMonth()
                    },
                    onReturnToCurrent: {
                        viewModel.goToCurrentMonth()
                    },
                    onNavigateToMonth: { year, month in
                        SharedMonthContext.shared.navigateTo(year: year, month: month)
                    },
                    isLoading: viewModel.isLoading,
                    backToTodayText: localization.string("dashboard.backToToday")
                )
                .frame(height: MonthPickerLayout.height)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: MonthPickerLayout.cornerRadius))
                .padding(.horizontal, MonthPickerLayout.horizontalPadding)
                .padding(.bottom, MonthPickerLayout.bottomPadding)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.tidexBackground, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Image("TidexWordmark")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 22)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    UserMenuButton(
                        displayName: coordinator.userDisplayName,
                        avatarUrl: coordinator.userAvatarUrl
                    )
                }
            }
        }
        .task {
            await viewModel.loadStats()
        }
        .onAppear {
            selectionHaptic.prepare()
        }
    }

    // MARK: - Transition Phase

    /// Current transition phase for animations
    private var transitionPhase: MonthTransitionPhase {
        MonthTransitionPhase(
            year: viewModel.displayYear,
            month: viewModel.displayMonth,
            direction: viewModel.navigationDirection
        )
    }

    // MARK: - Stats Content

    @ViewBuilder
    private func statsContent(stats: StatsData) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                // Monthly Earnings Card (large)
                MonthlyEarningsCard(
                    grossEarnings: stats.currentMonth.totalEarnings,
                    netEarnings: stats.currentMonth.totalEarningsNet,
                    taxEnabled: stats.tax.enabled,
                    percentageChange: stats.percentageChange
                )

                // Hours and Shifts cards (side by side)
                HStack(spacing: 12) {
                    HoursStatCard(hours: stats.currentMonth.totalHours)
                    ShiftsStatCard(count: stats.currentMonth.shiftCount)
                }

                // Monthly Goal Card
                if stats.monthlyGoal.enabled {
                    MonthlyGoalCard(goal: stats.monthlyGoal)
                } else {
                    MonthlyGoalEmptyCard()
                }

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
                   employment.monthlyData.contains(where: { $0.averagePercentage > 0 }) {
                    EmploymentPercentageChart(data: employment)
                } else {
                    EmploymentPercentageChartEmpty()
                }

                // Bottom spacing for floating month picker
                Spacer()
                    .frame(height: MonthPickerLayout.height + MonthPickerLayout.bottomPadding + 24)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
        .refreshable {
            await viewModel.refresh()
        }
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
                    title: localization.string("stats.charts.weeklyChart.thisWeek"),
                    highlightToday: true
                )
            } else {
                WeeklyBarChartEmpty(
                    title: localization.string("stats.charts.weeklyChart.thisWeek")
                )
            }
        } else if let bestWeek = stats.bestWeek {
            // Past month: show "Best Week"
            let hasData = bestWeek.weekData.contains { $0.earnings > 0 }
            if hasData {
                let title = localization.string("stats.charts.weeklyChart.bestWeek")
                    .replacingOccurrences(of: "{week}", with: "\(bestWeek.weekNumber)")
                WeeklyBarChart(
                    data: bestWeek.weekData,
                    title: title,
                    highlightToday: false
                )
            } else {
                // Past month with no shifts in best week (shouldn't happen, but handle gracefully)
                WeeklyBarChartEmpty(
                    title: localization.string("stats.charts.weeklyChart.thisWeek")
                )
            }
        } else {
            // No weekly data available (past month with no shifts)
            WeeklyBarChartEmpty(
                title: localization.string("stats.charts.weeklyChart.thisWeek")
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
            VStack(spacing: 16) {
                // Skeleton for Monthly Earnings Card
                skeletonCard(height: 200)

                // Skeleton for Hours and Shifts cards
                HStack(spacing: 12) {
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
                    .frame(height: MonthPickerLayout.height + MonthPickerLayout.bottomPadding + 24)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
        .refreshable {
            await viewModel.refresh()
        }
    }

    @ViewBuilder
    private func skeletonCard(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color.tidexSurfacePrimary)
            .frame(height: height)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.tidexBorderSubtle, lineWidth: 1)
            )
            .shimmer(isActive: true)
    }

    // MARK: - Error View

    @ViewBuilder
    private func errorView(error: Error) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.tidexTextMuted)

            Text(localization.string("stats.errors.couldNotUpdate"))
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.tidexTextSecondary)
                .multilineTextAlignment(.center)

            Button {
                Task {
                    await viewModel.refresh()
                }
            } label: {
                Text(localization.string("common.retry"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.tidexBlue)
                    .cornerRadius(8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

#Preview {
    StatsView(selectedTab: .constant(.stats))
        .environmentObject(AppCoordinator.shared)
        .environment(\.localization, LocalizationManager.shared)
}
