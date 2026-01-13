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

    var body: some View {
        NavigationStack {
            ZStack {
                Color.tidexDarkBackground
                    .ignoresSafeArea()

                if viewModel.isLoading {
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
            .toolbarBackground(Color.tidexDarkBackground, for: .navigationBar)
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
    }

    // MARK: - Dashboard Content

    @ViewBuilder
    private func dashboardContent(data: DashboardData) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                // Payroll Card (Previous Month)
                PayrollCard(
                    payrollDate: data.payrollDate,
                    label: localization.string(data.payrollHasPassed ? "dashboard.previousPayout" : "dashboard.nextPayout"),
                    gross: data.previousMonthGross,
                    net: data.previousMonthNet,
                    tax: data.previousMonthTax,
                    taxEnabled: data.previousMonthTaxEnabled
                )

                // Total Card (Current Month)
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

                // Next Shift Card
                if let nextShift = data.nextShift {
                    NextShiftCard(
                        shift: nextShift,
                        isToday: data.isNextShiftToday
                    )
                }

                #if DEBUG
                // Sign out button (development only)
                signOutButton
                #endif
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
    }

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

    var body: some View {
        NavigationStack {
            PlaceholderContent(
                icon: "calendar",
                title: localization.string("tabs.shifts"),
                description: localization.string("placeholder.shiftsDescription")
            )
            .navigationTitle(localization.string("tabs.shifts"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.tidexDarkBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

struct AddShiftPlaceholderView: View {
    @Environment(\.localization) private var localization

    var body: some View {
        NavigationStack {
            PlaceholderContent(
                icon: "plus.circle.fill",
                title: localization.string("placeholder.addShift"),
                description: localization.string("placeholder.addShiftDescription")
            )
            .navigationTitle(localization.string("placeholder.addShift"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.tidexDarkBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

struct StatsPlaceholderView: View {
    @Environment(\.localization) private var localization

    var body: some View {
        NavigationStack {
            PlaceholderContent(
                icon: "chart.bar.xaxis",
                title: localization.string("tabs.stats"),
                description: localization.string("placeholder.statsDescription")
            )
            .navigationTitle(localization.string("tabs.stats"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.tidexDarkBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

struct SharingPlaceholderView: View {
    @Environment(\.localization) private var localization

    var body: some View {
        NavigationStack {
            PlaceholderContent(
                icon: "person.2.fill",
                title: localization.string("tabs.sharing"),
                description: localization.string("placeholder.sharingDescription")
            )
            .navigationTitle(localization.string("tabs.sharing"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.tidexDarkBackground, for: .navigationBar)
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
            Color.tidexDarkBackground
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
