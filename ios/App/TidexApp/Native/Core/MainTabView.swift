import SwiftUI

// MARK: - Tab Reselection Notification

extension Notification.Name {
    /// Posted when a tab is tapped while already selected
    static let tabReselected = Notification.Name("tabReselected")
}

/// Main tab view for authenticated users
/// This is the home screen after successful login
/// Currently a placeholder - will be expanded with full dashboard functionality
struct MainTabView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @ObservedObject private var addShiftCoordinator = AddShiftCoordinator.shared
    @ObservedObject private var monthContext = SharedMonthContext.shared
    @ObservedObject private var impersonationManager = ImpersonationManager.shared

    @State private var selectedTab: Tab = .home

    // State for shared month picker overlay
    @State private var isKeyboardVisible = false
    @State private var sharingHasSelectedSharer = false

    // State for feedback deep link sheets
    @State private var showFeedbackSheet = false
    @State private var showAdminFeedbackSheet = false

    // State for Wagey AI chat sheet (home tab)
    @State private var showWageySheet = false

    // View mode toggle (calendar vs list) - persisted across app launches
    // Shared with ShiftsView via @AppStorage
    @AppStorage("shiftsViewMode") private var showListView = false

    // Haptic feedback for toggle
    private let selectionHaptic = UISelectionFeedbackGenerator()

    // iPad detection - tab bar is at top on iPad, so month picker doesn't need extra bottom padding
    private var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

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

        var localizationKey: LocalizedStringResource {
            switch self {
            case .home: return .tabsHome
            case .shifts: return .tabsShifts
            case .add: return .tabsAdd
            case .stats: return .tabsStats
            case .sharing: return .tabsSharing
            }
        }
    }

    /// Custom binding that detects tab reselection and posts notification
    /// For the Add tab, tapping while already selected triggers the add action
    private var tabSelection: Binding<Tab> {
        Binding(
            get: { selectedTab },
            set: { newTab in
                // Haptic feedback for all tab interactions
                selectionHaptic.selectionChanged()

                if newTab == selectedTab {
                    if newTab == .add {
                        // Add tab tapped while already on it - trigger add action
                        addShiftCoordinator.triggerAdd()
                    } else {
                        // Other tab tapped again - post notification for scroll-to-top etc.
                        NotificationCenter.default.post(
                            name: .tabReselected,
                            object: nil,
                            userInfo: ["tab": newTab]
                        )
                    }
                } else {
                    selectedTab = newTab
                }
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Impersonation banner - shown when admin is impersonating another user
            if impersonationManager.isImpersonating {
                ImpersonationBanner(
                    targetName: impersonationManager.impersonatedUserName ?? "Unknown",
                    expiresAt: impersonationManager.expiresAt,
                    onStop: {
                        Task {
                            try? await impersonationManager.stopImpersonation()
                        }
                    }
                )
            }

            ZStack(alignment: .bottom) {
                // Background that fills entire screen including safe areas
                // Prevents black bars from showing behind tab content
                Color.tidexBackground
                    .ignoresSafeArea()

                TabView(selection: tabSelection) {
                    DashboardView(selectedTab: $selectedTab)
                        .tabItem {
                            Label(String(localized: Tab.home.localizationKey), systemImage: Tab.home.icon)
                        }
                        .tag(Tab.home)

                    ShiftsView(selectedTab: $selectedTab)
                        .tabItem {
                            Label(String(localized: Tab.shifts.localizationKey), systemImage: Tab.shifts.icon)
                        }
                        .tag(Tab.shifts)

                    AddShiftView(selectedTab: $selectedTab, isKeyboardVisible: $isKeyboardVisible)
                        .tabItem {
                            Label(String(localized: Tab.add.localizationKey), systemImage: Tab.add.icon)
                        }
                        .tag(Tab.add)

                    StatsView(selectedTab: $selectedTab)
                        .tabItem {
                            Label(String(localized: Tab.stats.localizationKey), systemImage: Tab.stats.icon)
                        }
                        .tag(Tab.stats)

                    SharingView(selectedTab: $selectedTab, hasSelectedSharer: $sharingHasSelectedSharer)
                        .tabItem {
                            Label(String(localized: Tab.sharing.localizationKey), systemImage: Tab.sharing.icon)
                        }
                        .tag(Tab.sharing)
                }
                .tint(.tidexBlue)

                // Shared month picker overlay - floats above tab bar
                if shouldShowMonthPicker {
                    sharedMonthPickerOverlay
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: selectedTab)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: shouldShowMonthPicker)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showListView)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: impersonationManager.isImpersonating)
        .onChange(of: coordinator.pendingDeepLink) { _, deepLink in
            handlePendingDeepLink(deepLink)
        }
        .onAppear {
            // Handle any pending deep link on initial appearance
            handlePendingDeepLink(coordinator.pendingDeepLink)
            selectionHaptic.prepare()
        }
        .sheet(isPresented: $showFeedbackSheet) {
            NavigationStack {
                FeedbackSettingsView()
            }
        }
        .sheet(isPresented: $showAdminFeedbackSheet) {
            AdminSettingsView(initialTab: .feedback)
        }
        .sheet(isPresented: $showWageySheet) {
            WageyView()
        }
    }

    // MARK: - Month Picker Visibility

    /// Whether to show the month picker based on current tab and state
    private var shouldShowMonthPicker: Bool {
        switch selectedTab {
        case .home, .shifts, .stats:
            return true
        case .add:
            // Hide when keyboard is visible
            return !isKeyboardVisible
        case .sharing:
            // Only show when a sharer is selected
            return sharingHasSelectedSharer
        }
    }

    // MARK: - Shared Month Picker Overlay

    @ViewBuilder
    private var sharedMonthPickerOverlay: some View {
        HStack(spacing: 8) {
            // Wagey button - only on Home tab
            if selectedTab == .home {
                Button {
                    Haptics.play(.light)
                    showWageySheet = true
                } label: {
                    Image(systemName: "sparkles")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.tidexBlue)
                        .frame(width: MonthPickerLayout.height, height: MonthPickerLayout.height)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular, in: .rect(cornerRadius: MonthPickerLayout.cornerRadius))
                .transition(.scale.combined(with: .opacity))
            }

            // View mode toggle button - only on Shifts tab
            if selectedTab == .shifts {
                Button {
                    selectionHaptic.selectionChanged()
                    showListView.toggle()
                } label: {
                    Image(systemName: showListView ? "calendar" : "list.bullet")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(monthContext.hasConflictsInMonth ? .tidexWarning : .tidexBlue)
                        .frame(width: MonthPickerLayout.height, height: MonthPickerLayout.height)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contentTransition(.symbolEffect(.replace))
                .glassEffect(
                    monthContext.hasConflictsInMonth ? .regular.tint(Color.tidexWarning.opacity(0.3)) : .regular,
                    in: .rect(cornerRadius: MonthPickerLayout.cornerRadius)
                )
                .transition(.scale.combined(with: .opacity))
                .animation(.easeInOut(duration: 0.2), value: monthContext.hasConflictsInMonth)
            }

            // Month picker
            AnimatedMonthHeader(
                monthName: monthContext.displayMonthName,
                year: monthContext.displayYear,
                phase: transitionPhase,
                config: .default,
                onPrevious: {
                    AppearanceTracker.shared.reset()
                    monthContext.goToPreviousMonth()
                },
                onNext: {
                    AppearanceTracker.shared.reset()
                    monthContext.goToNextMonth()
                },
                onNavigateToMonth: { year, month in
                    AppearanceTracker.shared.reset()
                    monthContext.navigateTo(year: year, month: month)
                },
                isLoading: false
            )
            .frame(maxWidth: .infinity)  // Fill available width for consistent sizing
            .frame(height: MonthPickerLayout.height)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: MonthPickerLayout.cornerRadius))
        }
        .frame(maxWidth: AdaptiveMaxWidth.tabContent)
        .frame(maxWidth: .infinity)  // Fill screen width, then constrain to tabContent max
        .padding(.horizontal, MonthPickerLayout.horizontalPadding)
        // Position above tab bar (49pt on iPhone) + original bottom padding (8pt)
        // On iPad, tab bar is at top so no extra padding needed
        .padding(.bottom, isIPad ? MonthPickerLayout.bottomPadding : 49 + MonthPickerLayout.bottomPadding)
    }

    /// Current transition phase for month picker animations
    private var transitionPhase: MonthTransitionPhase {
        MonthTransitionPhase(
            year: monthContext.displayYear,
            month: monthContext.displayMonth,
            direction: monthContext.navigationDirection
        )
    }

    // MARK: - Deep Link Handling

    /// Handle pending deep link from AppCoordinator
    /// Switches to the appropriate tab based on the deep link type
    private func handlePendingDeepLink(_ deepLink: AppCoordinator.DeepLink?) {
        guard let deepLink = deepLink else { return }

        switch deepLink {
        case .sharing, .sharingManage:
            // Switch to sharing tab - SharingView will handle the specific navigation
            if selectedTab != .sharing {
                selectedTab = .sharing
            }
        case .shifts:
            // Switch to shifts tab - ShiftsView will handle the specific navigation
            if selectedTab != .shifts {
                selectedTab = .shifts
            }
        case .addShift:
            // Switch to add tab - AddShiftView will handle preselected date
            if selectedTab != .add {
                selectedTab = .add
            }
        case .feedback:
            // Open feedback sheet for users viewing their feedback responses
            showFeedbackSheet = true
            coordinator.clearPendingDeepLink()
        case .adminFeedback:
            // Open admin panel with feedback tab for admins viewing new feedback
            showAdminFeedbackSheet = true
            coordinator.clearPendingDeepLink()
        }
        // Note: We don't clear the deep link here for tab-based navigation - the destination view will consume and clear it
    }
}

// MARK: - Placeholder Views

/// Generic placeholder tab view that reduces duplication
/// Used for tabs that are not yet implemented
struct PlaceholderTabView: View {
    let icon: String
    let titleKey: LocalizedStringResource
    let descriptionKey: LocalizedStringResource
    let supportsRefresh: Bool

    @EnvironmentObject private var coordinator: AppCoordinator
    
    init(
        icon: String,
        titleKey: LocalizedStringResource,
        descriptionKey: LocalizedStringResource,
        supportsRefresh: Bool = true
    ) {
        self.icon = icon
        self.titleKey = titleKey
        self.descriptionKey = descriptionKey
        self.supportsRefresh = supportsRefresh
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    // Background that fills entire screen including safe areas
                    // Prevents black bars from showing in status bar and home indicator areas
                    Color.tidexBackground
                        .ignoresSafeArea()

                    ScrollView {
                        PlaceholderContent(
                            icon: icon,
                            title: String(localized: titleKey),
                            description: String(localized: descriptionKey)
                        )
                        .frame(maxWidth: .infinity, minHeight: geometry.size.height - 200)
                    }
                    .applyRefreshable(enabled: supportsRefresh)
                }
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
    }
}

// MARK: - Refreshable Extension

private extension View {
    @ViewBuilder
    func applyRefreshable(enabled: Bool) -> some View {
        if enabled {
            self.refreshable {
                // Placeholder for future data refresh
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        } else {
            self
        }
    }
}

// MARK: - Concrete Placeholder Views

/// These type aliases maintain backwards compatibility while using the generic PlaceholderTabView
struct ShiftsPlaceholderView: View {
    var body: some View {
        PlaceholderTabView(
            icon: "calendar",
            titleKey: .tabsShifts,
            descriptionKey: .placeholderShiftsDescription
        )
    }
}

struct AddShiftPlaceholderView: View {
    var body: some View {
        PlaceholderTabView(
            icon: "plus.circle.fill",
            titleKey: .tabsAdd,
            descriptionKey: .placeholderAddShiftDescription,
            supportsRefresh: false
        )
    }
}

struct StatsPlaceholderView: View {
    var body: some View {
        PlaceholderTabView(
            icon: "chart.bar.xaxis",
            titleKey: .tabsStats,
            descriptionKey: .placeholderStatsDescription
        )
    }
}

struct SharingPlaceholderView: View {
    var body: some View {
        PlaceholderTabView(
            icon: "person.2.fill",
            titleKey: .tabsSharing,
            descriptionKey: .placeholderSharingDescription
        )
    }
}

#Preview {
    MainTabView()
        .environmentObject(AppCoordinator.shared)
}
