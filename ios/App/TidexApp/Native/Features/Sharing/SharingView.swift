import SwiftUI

/// Sharing tab view - displays shifts from users who share with the current user
/// Fetches shared shifts from the Next.js API for proper payroll computation
struct SharingView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.localization) private var localization
    @Environment(\.userCurrency) private var currency

    @StateObject private var viewModel = SharingViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                // Background that fills entire screen including safe areas
                Color.tidexBackground
                    .ignoresSafeArea()

                // Main layout
                VStack(spacing: 0) {
                    // Content area
                    contentView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Month picker - only visible when viewing a sharer's shifts
                    if viewModel.selectedSharer != nil {
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
                            isLoading: viewModel.isLoadingShifts,
                            backToTodayText: localization.string("dashboard.backToToday")
                        )
                        .frame(height: 56)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 30))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                    }
                }
            }
            .navigationTitle(localization.string(AppTab.sharing.titleKey))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.tidexBackground, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    UserMenuButton(
                        displayName: coordinator.userDisplayName,
                        avatarUrl: coordinator.userAvatarUrl
                    )
                }
            }
            .refreshable {
                await viewModel.refresh()
            }
        }
        .task {
            await viewModel.loadSharers()
        }
    }

    // MARK: - Content View

    @ViewBuilder
    private var contentView: some View {
        if viewModel.selectedSharer != nil {
            // Show shifts for selected sharer
            sharedShiftsView
        } else {
            // Show sharer list
            sharerListView
        }
    }

    // MARK: - Sharer List

    private var sharerListView: some View {
        ScrollView {
            SharerListView(
                sharers: viewModel.sharers,
                selectedSharer: viewModel.selectedSharer,
                isLoading: viewModel.isLoadingSharers,
                onSelectSharer: { sharer in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.selectSharer(sharer)
                    }
                }
            )
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Shared Shifts View

    @ViewBuilder
    private var sharedShiftsView: some View {
        if let sharer = viewModel.selectedSharer {
            SharedShiftsListView(
                sharer: sharer,
                shifts: viewModel.sharedShifts,
                totalHours: viewModel.totalHours,
                totalEarnings: viewModel.totalEarnings,
                shiftCount: viewModel.shiftCount,
                isLoading: viewModel.isLoadingShifts,
                lastCacheTime: viewModel.lastCacheTime,
                onBack: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.deselectSharer()
                    }
                }
            )
        }
    }

    // MARK: - Transition Phase

    private var transitionPhase: MonthTransitionPhase {
        MonthTransitionPhase(
            year: viewModel.displayYear,
            month: viewModel.displayMonth,
            direction: viewModel.navigationDirection
        )
    }
}

#Preview {
    SharingView()
        .environmentObject(AppCoordinator.shared)
        .environment(\.localization, LocalizationManager.shared)
        .environment(\.userCurrency, "kr")
}
