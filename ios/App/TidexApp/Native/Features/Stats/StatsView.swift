import SwiftUI

/// Stats tab view - displays statistics and analytics
/// Shows monthly earnings, hours, shifts, and goal progress
struct StatsView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.localization) private var localization

    /// Binding to the selected tab for navigation
    @Binding var selectedTab: MainTabView.Tab

    @StateObject private var viewModel = StatsViewModel()

    var body: some View {
        RefreshableTabScreenContainer(
            title: localization.string(AppTab.stats.titleKey),
            onRefresh: {
                await viewModel.refresh()
            }
        ) {
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
        }
        .task {
            await viewModel.loadStats()
        }
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

                // Bottom spacing for tab bar
                Spacer()
                    .frame(height: 24)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
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
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
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
