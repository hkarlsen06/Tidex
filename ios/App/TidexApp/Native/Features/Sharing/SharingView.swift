import SwiftUI

/// Sharing tab view - displays shifts from users who share with the current user
/// Fetches shared shifts from the Next.js API for proper payroll computation
struct SharingView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.localization) private var localization
    @Environment(\.userCurrency) private var currency

    /// Binding to the selected tab for navigation
    @Binding var selectedTab: MainTabView.Tab

    @StateObject private var viewModel = SharingViewModel()

    /// State for showing the manage sharing sheet
    @State private var showManageSheet = false

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
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.tidexBackground, for: .navigationBar)
            .toolbar {
                // Back button when viewing a sharer
                ToolbarItem(placement: .topBarLeading) {
                    if viewModel.selectedSharer != nil {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewModel.deselectSharer()
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 16, weight: .semibold))
                                Text(localization.string("common.back"))
                                    .font(.system(size: 17))
                            }
                            .foregroundColor(.tidexBlue)
                        }
                    }
                }

                // Title area - show sharer info or just title
                ToolbarItem(placement: .principal) {
                    if let sharer = viewModel.selectedSharer {
                        HStack(spacing: 8) {
                            if let urlString = sharer.avatarUrl, let url = URL(string: urlString) {
                                CachedAsyncImage(url: url) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 28, height: 28)
                                        .clipShape(Circle())
                                } placeholder: {
                                    sharerInitialsAvatar(sharer: sharer)
                                }
                            } else {
                                sharerInitialsAvatar(sharer: sharer)
                            }
                            Text(sharer.displayName)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.tidexTextPrimary)
                        }
                    } else {
                        Text(localization.string(AppTab.sharing.titleKey))
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.tidexTextPrimary)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    // Only show when not viewing a sharer
                    if viewModel.selectedSharer == nil {
                        // User menu only
                        UserMenuButton(
                            displayName: coordinator.userDisplayName,
                            avatarUrl: coordinator.userAvatarUrl
                        )
                    }
                }
            }
            .refreshable {
                await viewModel.refresh()
            }
        }
        .task {
            await viewModel.loadSharers()
        }
        .onReceive(NotificationCenter.default.publisher(for: .tabReselected)) { notification in
            // Handle tab reselection - if sharing tab is tapped again while viewing a sharer,
            // navigate back to the sharer list
            guard let tab = notification.userInfo?["tab"] as? MainTabView.Tab,
                  tab == .sharing,
                  viewModel.selectedSharer != nil else {
                return
            }

            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.deselectSharer()
            }
        }
        .sheet(isPresented: $showManageSheet) {
            ManageSharingSheet(onVisibilityChange: {
                // Refresh sharers list when visibility changes (block/unblock)
                Task {
                    await viewModel.loadSharers(forceRefreshPreviews: true)
                }
            })
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
            VStack(spacing: 16) {
                // Manage sharing button row
                HStack {
                    Spacer()
                    Button(action: {
                        showManageSheet = true
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 14))
                            Text(localization.string("sharing.manageTitle"))
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(.tidexBlue)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.tidexBlue.opacity(0.1))
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, 16)

                // Sharer list
                SharerListView(
                    sharers: viewModel.sharers,
                    selectedSharer: viewModel.selectedSharer,
                    shiftPreviews: viewModel.shiftPreviews,
                    isLoading: viewModel.isLoadingSharers,
                    isLoadingPreviews: viewModel.isLoadingPreviews,
                    onSelectSharer: { sharer in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.selectSharer(sharer)
                        }
                    }
                )
            }
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Shared Shifts View

    @ViewBuilder
    private var sharedShiftsView: some View {
        if let sharer = viewModel.selectedSharer {
            // MonthSwipeContainer handles horizontal swipes for month navigation
            MonthSwipeContainer(
                onSwipeLeft: {
                    viewModel.goToNextMonth()
                },
                onSwipeRight: {
                    viewModel.goToPreviousMonth()
                }
            ) {
                SharedShiftsListView(
                    sharer: sharer,
                    shifts: viewModel.sharedShifts,
                    totalHours: viewModel.totalHours,
                    shiftCount: viewModel.shiftCount,
                    year: viewModel.displayYear,
                    month: viewModel.displayMonth,
                    isLoading: viewModel.isLoadingShifts,
                    lastCacheTime: viewModel.lastCacheTime
                )
            }
        }
    }

    // MARK: - Helper Views

    private func sharerInitialsAvatar(sharer: SharedUser) -> some View {
        Circle()
            .fill(Color.tidexBlue.opacity(0.2))
            .frame(width: 28, height: 28)
            .overlay(
                Text(sharer.initials)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.tidexBlue)
            )
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
    struct PreviewWrapper: View {
        @State private var selectedTab: MainTabView.Tab = .sharing

        var body: some View {
            SharingView(selectedTab: $selectedTab)
                .environmentObject(AppCoordinator.shared)
                .environment(\.localization, LocalizationManager.shared)
                .environment(\.userCurrency, "kr")
        }
    }

    return PreviewWrapper()
}
