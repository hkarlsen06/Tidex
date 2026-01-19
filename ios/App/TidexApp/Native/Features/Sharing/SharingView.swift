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

    /// User ID to highlight in the manage sheet (from deep link)
    @State private var highlightUserId: String?

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
                            onNavigateToMonth: { year, month in
                                SharedMonthContext.shared.navigateTo(year: year, month: month)
                            },
                            isLoading: viewModel.isLoadingShifts,
                            backToTodayText: localization.string("dashboard.backToToday")
                        )
                        .frame(height: MonthPickerLayout.height)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: MonthPickerLayout.cornerRadius))
                        .padding(.horizontal, MonthPickerLayout.horizontalPadding)
                        .padding(.bottom, MonthPickerLayout.bottomPadding)
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

                // Title area - only show sharer info when viewing a sharer
                // (main title is now in content area)
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
                    }
                    // No title when on main friends list - title is now inline with content
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
        .sheet(isPresented: $showManageSheet, onDismiss: {
            // Clear highlight when sheet is dismissed
            highlightUserId = nil
        }) {
            ManageSharingSheet(
                highlightUserId: highlightUserId,
                onVisibilityChange: {
                    // Refresh sharers list when visibility changes (block/unblock)
                    Task {
                        await viewModel.loadSharers(forceRefreshPreviews: true)
                    }
                }
            )
        }
        .onChange(of: coordinator.pendingDeepLink) { _, deepLink in
            handlePendingDeepLink(deepLink)
        }
        .onAppear {
            // Handle any pending deep link on initial appearance
            handlePendingDeepLink(coordinator.pendingDeepLink)
        }
    }

    // MARK: - Deep Link Handling

    /// Handle pending deep link from AppCoordinator
    /// Navigates to a specific sharer or opens the manage modal
    private func handlePendingDeepLink(_ deepLink: AppCoordinator.DeepLink?) {
        guard let deepLink = deepLink else { return }

        switch deepLink {
        case .sharing(let sharerId):
            if let sharerId = sharerId {
                // Wait for sharers to load, then select the sharer
                Task {
                    // If sharers aren't loaded yet, wait for them
                    if viewModel.sharers.isEmpty && viewModel.isLoadingSharers {
                        // Wait a bit for loading to complete
                        try? await Task.sleep(nanoseconds: 500_000_000)
                    }

                    // Find and select the sharer
                    if let sharer = viewModel.sharers.first(where: { $0.id == sharerId }) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.selectSharer(sharer)
                        }
                    }
                }
            }
            coordinator.clearPendingDeepLink()

        case .sharingManage(let highlightId):
            // Open manage modal with optional highlight
            highlightUserId = highlightId
            showManageSheet = true
            coordinator.clearPendingDeepLink()

        case .shifts:
            // Not handled here - ShiftsView will handle this
            break
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
                // Title and manage button row
                HStack {
                    // "Friends" / "Venner" title
                    Text(localization.string("sharing.friendsTitle"))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.tidexTextPrimary)

                    Spacer()

                    // Liquid glass manage button
                    Button(action: {
                        showManageSheet = true
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 14))
                            Text(localization.string("sharing.manageTitle"))
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(.tidexTextPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .glassEffect(.regular.interactive(), in: .capsule)
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
