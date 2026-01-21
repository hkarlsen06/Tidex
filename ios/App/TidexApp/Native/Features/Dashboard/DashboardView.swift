import SwiftUI

/// Dashboard view showing the main financial overview
/// Displays payroll, total earnings, and featured shift cards
struct DashboardView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.localization) private var localization

    /// Binding to the selected tab for navigation
    @Binding var selectedTab: MainTabView.Tab

    @StateObject private var viewModel = DashboardViewModel()
    @StateObject private var countdownManager = CountdownManager()

    // iPad detection - hide logo on iPad
    private var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

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
            }
            .navigationBarTitleDisplayMode(.inline)
            .iPadToolbarBackground(Color.tidexBackground)
            .toolbar {
                if !isIPad {
                    ToolbarItem(placement: .principal) {
                        Image("TidexWordmark")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 22)
                    }
                }
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
                }
            }
        }
        .onChange(of: viewModel.dashboardData) { _, newData in
            configureCountdown(with: newData)
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
    }

    // MARK: - Countdown Configuration

    private func configureCountdown(with data: DashboardData?) {
        guard let data = data else {
            countdownManager.stop()
            return
        }

        let isNorwegian = localization.currentLocale == .norwegian

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
            payrollDate: data.payrollDate,
            isNorwegian: isNorwegian
        )
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

    // MARK: - Card Content

    /// Card content with pull-to-refresh and swipe gestures
    /// Month picker is handled separately in the main body so it's always visible
    @ViewBuilder
    private func cardContent(data: DashboardData) -> some View {
        PullToRefreshContainer(onRefresh: {
            await viewModel.refresh()
        }) {
            MonthSwipeContainer(
                onSwipeLeft: {
                    viewModel.goToNextMonth()
                },
                onSwipeRight: {
                    viewModel.goToPreviousMonth()
                },
                isEnabled: true  // Always enabled - navigation is now non-blocking
            ) {
                // Cards centered in available space (between toolbar and month picker)
                GeometryReader { geometry in
                    VStack(spacing: 0) {
                        Spacer()

                        // Animated card content - centered vertically
                        animatedCardContent(data: data)
                            .frame(maxWidth: AdaptiveMaxWidth.tabContent)
                            .padding(.horizontal, 16)

                        Spacer()
                    }
                    // Offset for month picker overlay so content centers in available space
                    .padding(.bottom, MonthPickerLayout.height + MonthPickerLayout.bottomPadding)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    // Make entire VStack hit-testable for gesture propagation
                    .contentShape(Rectangle())
                }
                // Make GeometryReader hit-testable
                .contentShape(Rectangle())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Pass user's currency to all child views
        .userCurrency(data.currency)
    }

    // MARK: - Animated Card Content

    @ViewBuilder
    private func animatedCardContent(data: DashboardData) -> some View {
        // Determine payroll label based on whether viewing current month
        let payrollLabel: String = {
            if viewModel.isCurrentMonth {
                return localization.string(data.payrollHasPassed ? "dashboard.previousPayout" : "dashboard.nextPayout")
            } else {
                // For non-current months, show generic "Payroll" label
                return localization.string("dashboard.payroll")
            }
        }()

        // Calculate progress through the month until payroll (matches Next.js behavior)
        // Only show for current month when payroll hasn't passed yet
        let payrollProgress: Double? = {
            guard viewModel.isCurrentMonth && !data.payrollHasPassed else { return nil }

            let now = Date()
            let calendar = Calendar.current

            // Get start of the current month
            guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) else {
                return nil
            }

            // Get start of the payroll day
            let payrollDayStart = calendar.startOfDay(for: data.payrollDate)

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

        // Use StaggeredCardsContainer for smooth horizontal slide animation
        // Cards are stacked with TotalCard as the visual anchor (centered in available space)
        // Other cards position themselves above/below with consistent spacing
        StaggeredCardsContainer(phase: transitionPhase, config: .default) {
            VStack(spacing: 12) {
                // Payroll countdown text - fixed height to prevent layout shift
                Text(countdownManager.payrollCountdownText ?? " ")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.tidexTextSecondary)
                    .opacity(countdownManager.payrollCountdownText != nil ? 1 : 0)
                    .frame(height: 20)

                // Payroll Card (Previous Month relative to displayed month)
                PayrollCard(
                    payrollDate: data.payrollDate,
                    label: payrollLabel,
                    gross: data.previousMonthGross,
                    net: data.previousMonthNet,
                    tax: data.previousMonthTax,
                    taxEnabled: data.previousMonthTaxEnabled,
                    progress: payrollProgress
                )

                // Total Card (Displayed Month) - THE ANCHOR
                // This card's position should remain stable during transitions
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

                // Featured Shift Card - fixed height container to prevent layout shift
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
                let shiftProgress: Double? = countdownManager.isShiftActive ? countdownManager.shiftProgress : nil
                FeaturedShiftCard(
                    shift: featuredShift,
                    isToday: data.isFeaturedShiftToday,
                    isBestShift: data.featuredShiftIsBestShift,
                    countdownText: countdownManager.shiftCountdownText,
                    progress: shiftProgress
                )
            } else {
                EmptyShiftCard(isBestShift: data.featuredShiftIsBestShift)
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
                    VStack(spacing: 12) {
                        // Placeholder for payroll countdown text
                        Color.clear
                            .frame(height: 20)

                        // Payroll Card skeleton
                        PayrollCard(
                            payrollDate: Date(),
                            label: localization.string("dashboard.nextPayout"),
                            gross: 0,
                            net: nil,
                            tax: nil,
                            taxEnabled: false,
                            isLoading: true
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
                        EmptyShiftCard(isBestShift: false, isLoading: true)
                    }
                    .frame(maxWidth: AdaptiveMaxWidth.tabContent)
                    .padding(.horizontal, 16)

                    Spacer()
                }
                // Offset for month picker overlay so content centers in available space
                .padding(.bottom, MonthPickerLayout.height + MonthPickerLayout.bottomPadding)
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
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.tidexWarning)

            Text(localization.string("dashboard.loadError"))
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.tidexTextPrimary)

            Text(error.localizedDescription)
                .font(.system(size: 14))
                .foregroundColor(.tidexTextSecondary)
                .multilineTextAlignment(.center)

            Button {
                Task { await viewModel.loadDashboard() }
            } label: {
                Text(localization.string("common.retry"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.tidexBlue)
                    .padding(.horizontal, 20)
                    .padding(.vertical, Spacing.sm)
                    .background(Color.tidexBlue.opacity(0.1))
                    .cornerRadius(8)
            }
        }
        .frame(maxWidth: AdaptiveMaxWidth.tabContent)
        .padding(.horizontal, 40)
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var selectedTab: MainTabView.Tab = .home

        var body: some View {
            DashboardView(selectedTab: $selectedTab)
                .environmentObject(AppCoordinator.shared)
                .environment(\.localization, LocalizationManager.shared)
        }
    }

    return PreviewWrapper()
}
