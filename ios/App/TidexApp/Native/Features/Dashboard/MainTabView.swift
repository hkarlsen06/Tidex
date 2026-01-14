import SwiftUI

/// Main tab view for authenticated users
/// This is the home screen after successful login
/// Currently a placeholder - will be expanded with full dashboard functionality
struct MainTabView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.localization) private var localization

    @State private var selectedTab: Tab = .home

    enum Tab: String, CaseIterable {
        case home
        case shifts
        case add
        case stats
        case sharing

        var icon: String {
            switch self {
            case .home: return "house.fill"
            case .shifts: return "calendar"
            case .add: return "plus.circle.fill"
            case .stats: return "chart.bar.xaxis"
            case .sharing: return "person.2.fill"
            }
        }

        var localizationKey: String {
            switch self {
            case .home: return "tabs.home"
            case .shifts: return "tabs.shifts"
            case .add: return "tabs.add"
            case .stats: return "tabs.stats"
            case .sharing: return "tabs.sharing"
            }
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem {
                    Label(localization.string(Tab.home.localizationKey), systemImage: Tab.home.icon)
                }
                .tag(Tab.home)

            ShiftsPlaceholderView()
                .tabItem {
                    Label(localization.string(Tab.shifts.localizationKey), systemImage: Tab.shifts.icon)
                }
                .tag(Tab.shifts)

            AddShiftPlaceholderView()
                .tabItem {
                    Label(localization.string(Tab.add.localizationKey), systemImage: Tab.add.icon)
                }
                .tag(Tab.add)

            StatsPlaceholderView()
                .tabItem {
                    Label(localization.string(Tab.stats.localizationKey), systemImage: Tab.stats.icon)
                }
                .tag(Tab.stats)

            SharingPlaceholderView()
                .tabItem {
                    Label(localization.string(Tab.sharing.localizationKey), systemImage: Tab.sharing.icon)
                }
                .tag(Tab.sharing)
        }
        .tint(.tidexBlue)
    }
}

// MARK: - Dashboard View

struct DashboardView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.localization) private var localization

    @StateObject private var viewModel = DashboardViewModel()
    @StateObject private var countdownManager = CountdownManager()

    var body: some View {
        NavigationStack {
            ZStack {
                // Background matching splash/loading screens
                Color.tidexLaunchBackground
                    .ignoresSafeArea()

                if viewModel.isLoading && viewModel.dashboardData == nil {
                    // Only show full loading view on initial load
                    loadingView
                } else if let error = viewModel.error {
                    errorView(error: error)
                } else if let data = viewModel.dashboardData {
                    dashboardContent(data: data)
                } else {
                    emptyStateView
                }
            }
            .navigationTitle(localization.string("dashboard.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.tidexLaunchBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await viewModel.loadDashboard() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.tidexBlue)
                    }
                }
            }
        }
        .task {
            await viewModel.loadDashboard()
        }
        .onChange(of: viewModel.dashboardData) { _, newData in
            configureCountdown(with: newData)
        }
        .onDisappear {
            countdownManager.stop()
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

    // MARK: - Dashboard Content

    @ViewBuilder
    private func dashboardContent(data: DashboardData) -> some View {
        // Fixed layout with pull-to-refresh and swipe gestures
        // No ScrollView - content is fixed height, gestures don't conflict
        PullToRefreshContainer(onRefresh: {
            await viewModel.refresh()
        }) {
            MonthSwipeContainer(
                onSwipeLeft: {
                    Task { await viewModel.goToNextMonth() }
                },
                onSwipeRight: {
                    Task { await viewModel.goToPreviousMonth() }
                },
                isEnabled: !viewModel.isLoading
            ) {
                // Use VStack with .top alignment and fixed spacing
                // This prevents Spacer-based layout shifts during transitions
                VStack(alignment: .center, spacing: 0) {
                    // Animated Month Navigation Header
                    AnimatedMonthHeader(
                        monthName: viewModel.displayMonthName,
                        year: viewModel.displayYear,
                        phase: transitionPhase,
                        isCurrentMonth: viewModel.isCurrentMonth,
                        config: .default,
                        onPrevious: {
                            Task { await viewModel.goToPreviousMonth() }
                        },
                        onNext: {
                            Task { await viewModel.goToNextMonth() }
                        },
                        onReturnToCurrent: {
                            Task { await viewModel.goToCurrentMonth() }
                        },
                        isLoading: viewModel.isLoading,
                        backToTodayText: localization.string("dashboard.backToToday")
                    )
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 24) // Fixed spacing instead of Spacer

                    // Animated card content with horizontal slide transition
                    animatedCardContent(data: data)
                        .padding(.horizontal, 24)

                    // Push remaining content to fill space, but cards stay anchored to top
                    Spacer(minLength: 0)

                    #if DEBUG
                    // Sign out button (development only)
                    signOutButton
                        .padding(.horizontal, 24)
                        .padding(.bottom, 12)
                    #endif
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(viewModel.isLoading ? 0.6 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: viewModel.isLoading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    taxEnabled: data.previousMonthTaxEnabled
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
                FeaturedShiftCard(
                    shift: featuredShift,
                    isToday: data.isFeaturedShiftToday,
                    isBestShift: data.featuredShiftIsBestShift,
                    countdownText: countdownManager.shiftCountdownText
                )
            } else {
                EmptyShiftCard(isBestShift: data.featuredShiftIsBestShift)
            }
        }
    }

    // Note: Month navigation header now uses AnimatedMonthHeader from MonthTransition.swift
    // This provides smooth vertical text transitions similar to the Next.js MonthPicker

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .tidexBlue))
                .scaleEffect(1.2)

            Text(localization.string("common.loading"))
                .font(.system(size: 14))
                .foregroundColor(.tidexTextSecondary)
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 48))
                .foregroundColor(.tidexTextMuted)

            Text(localization.string("dashboard.noShifts"))
                .font(.system(size: 16))
                .foregroundColor(.tidexTextSecondary)
                .multilineTextAlignment(.center)

            Button {
                Task { await viewModel.loadDashboard() }
            } label: {
                Text(localization.string("common.retry"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.tidexBlue)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.tidexBlue.opacity(0.1))
                    .cornerRadius(8)
            }
        }
        .padding(.horizontal, 40)
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
                    .padding(.vertical, 10)
                    .background(Color.tidexBlue.opacity(0.1))
                    .cornerRadius(8)
            }
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Sign Out Button (Debug)

    private var signOutButton: some View {
        Button {
            Task {
                await coordinator.signOut()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                Text(localization.string("dashboard.signOut"))
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.tidexError)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color.tidexError.opacity(0.1))
            .cornerRadius(8)
        }
        .padding(.top, 20)
    }
}

// MARK: - Placeholder Views

struct ShiftsPlaceholderView: View {
    @Environment(\.localization) private var localization
    @State private var isRefreshing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                PlaceholderContent(
                    icon: "calendar",
                    title: localization.string("tabs.shifts"),
                    description: localization.string("placeholder.shiftsDescription")
                )
                .frame(maxWidth: .infinity, minHeight: UIScreen.main.bounds.height - 200)
            }
            .refreshable {
                // Placeholder for future data refresh
                isRefreshing = true
                try? await Task.sleep(nanoseconds: 500_000_000)
                isRefreshing = false
            }
            .navigationTitle(localization.string("tabs.shifts"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.tidexLaunchBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

struct AddShiftPlaceholderView: View {
    @Environment(\.localization) private var localization

    var body: some View {
        NavigationStack {
            ScrollView {
                PlaceholderContent(
                    icon: "plus.circle.fill",
                    title: localization.string("placeholder.addShift"),
                    description: localization.string("placeholder.addShiftDescription")
                )
                .frame(maxWidth: .infinity, minHeight: UIScreen.main.bounds.height - 200)
            }
            .navigationTitle(localization.string("placeholder.addShift"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.tidexLaunchBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

struct StatsPlaceholderView: View {
    @Environment(\.localization) private var localization
    @State private var isRefreshing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                PlaceholderContent(
                    icon: "chart.bar.xaxis",
                    title: localization.string("tabs.stats"),
                    description: localization.string("placeholder.statsDescription")
                )
                .frame(maxWidth: .infinity, minHeight: UIScreen.main.bounds.height - 200)
            }
            .refreshable {
                // Placeholder for future data refresh
                isRefreshing = true
                try? await Task.sleep(nanoseconds: 500_000_000)
                isRefreshing = false
            }
            .navigationTitle(localization.string("tabs.stats"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.tidexLaunchBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

struct SharingPlaceholderView: View {
    @Environment(\.localization) private var localization
    @State private var isRefreshing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                PlaceholderContent(
                    icon: "person.2.fill",
                    title: localization.string("tabs.sharing"),
                    description: localization.string("placeholder.sharingDescription")
                )
                .frame(maxWidth: .infinity, minHeight: UIScreen.main.bounds.height - 200)
            }
            .refreshable {
                // Placeholder for future data refresh
                isRefreshing = true
                try? await Task.sleep(nanoseconds: 500_000_000)
                isRefreshing = false
            }
            .navigationTitle(localization.string("tabs.sharing"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.tidexLaunchBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

struct PlaceholderContent: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        ZStack {
            Color.tidexLaunchBackground
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 48))
                    .foregroundColor(.tidexTextMuted)

                Text(title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.tidexTextPrimary)

                Text(description)
                    .font(.system(size: 14))
                    .foregroundColor(.tidexTextSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 40)
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(AppCoordinator.shared)
        .environment(\.localization, LocalizationManager.shared)
}
