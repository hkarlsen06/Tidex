import StoreKit
import SwiftUI

// MARK: - Tab Reselection Notification

extension Notification.Name {
  /// Posted when a tab is tapped while already selected
  static let tabReselected = Notification.Name("tabReselected")

  /// Posted by the screenshot prompt overlay when user taps "Use Share Button"
  static let screenshotPromptUseShareButton = Notification.Name("screenshotPromptUseShareButton")
}

/// Main tab view for authenticated users
/// This is the home screen after successful login
/// Currently a placeholder - will be expanded with full dashboard functionality
struct MainTabView: View {
  private static let startupTabCacheKey = "defaultStartupTab"

  @EnvironmentObject private var coordinator: AppCoordinator
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.requestReview) private var requestReview
  @ObservedObject private var addShiftCoordinator = AddShiftCoordinator.shared
  @ObservedObject private var monthContext = SharedMonthContext.shared
  @ObservedObject private var impersonationManager = ImpersonationManager.shared
  @ObservedObject private var celebrationManager = ShiftCompletionCelebrationManager.shared
  private let friendsMessagesRepository = FriendsMessagesRepository.shared
  private let friendsRealtimeCoordinator = FriendsMessagingRealtimeCoordinator.shared

  @State private var selectedTab: Tab = .home
  @State private var loadedTabs: Set<Tab> = [.home]

  // Tracks whether the first re-tap on a scrollable tab already triggered scroll-to-top.
  // On the next re-tap, we navigate to the current month instead.
  @State private var pendingCurrentMonthTab: Tab?

  // State for shared month picker overlay
  @State private var isKeyboardVisible = false
  @State private var sharingHasSelectedSharer = false

  // State for feedback deep link sheets
  @State private var showFeedbackSheet = false
  @State private var showAdminFeedbackSheet = false
  @State private var adminSheetInitialTab: AdminTab = .feedback
  @State private var adminSheetInitialReportId: String?

  // State for Home-owned stats navigation
  @State private var showHomeStats = false

  // Screenshot share prompt state (presented as overlay to keep content visible)
  @State private var showScreenshotPrompt = false

  // Add tab disabled-submit guidance
  @State private var showAddSubmitRequirementsAlert = false
  @State private var unreadFriendsCount = 0
  @State private var unreadRefreshTask: Task<Void, Never>?
  @State private var lastHandledReselectionTab: Tab?
  @State private var lastHandledReselectionDate = Date.distantPast

  // View mode toggle (calendar vs list) - persisted across app launches
  // Shared with ShiftsView via @AppStorage
  @AppStorage("shiftsViewMode") private var showListView = false

  // Haptic feedback for toggle
  private let selectionHaptic = UISelectionFeedbackGenerator()
  // Temporary investigation switch; keep false for docs-aligned glass behavior.
  private let disableHeavyCompositingForHangInvestigation = false

  // iPad detection - tab bar is at top on iPad, so month picker doesn't need extra bottom padding
  private var isIPad: Bool {
    UIDevice.current.userInterfaceIdiom == .pad
  }

  private var shouldReduceEffects: Bool {
    reduceMotion || disableHeavyCompositingForHangInvestigation
  }

  enum Tab: String, CaseIterable, Hashable {
    case home
    case shifts
    case add
    case wagey
    case sharing

    var icon: String {
      switch self {
      case .home: return "speedometer"
      case .shifts: return "calendar"
      case .add: return "plus.circle.fill"
      case .wagey: return "sparkles"
      case .sharing: return "person.2.fill"
      }
    }

    var localizationKey: LocalizedStringResource {
      switch self {
      case .home: return .tabsHome
      case .shifts: return .tabsShifts
      case .add: return .tabsAdd
      case .wagey: return .tabsWagey
      case .sharing: return .tabsSharing
      }
    }

    static let orderedTabs: [Tab] = [.home, .shifts, .add, .wagey, .sharing]

    var index: Int {
      Self.orderedTabs.firstIndex(of: self) ?? 0
    }

    init?(index: Int) {
      guard Self.orderedTabs.indices.contains(index) else { return nil }
      self = Self.orderedTabs[index]
    }
  }

  init() {
    let cachedStartupTabRawValue = UserDefaults.standard.string(forKey: Self.startupTabCacheKey)
    let startupTab = Tab(rawValue: cachedStartupTabRawValue ?? "home") ?? .home
    _selectedTab = State(initialValue: startupTab)
    _loadedTabs = State(initialValue: [startupTab])
  }

  /// Custom binding that detects tab reselection
  /// Re-tapping scrollable tabs scrolls to top first, then navigates to current month
  private var tabSelection: Binding<Tab> {
    Binding(
      get: { selectedTab },
      set: { newTab in
        // Haptic feedback for all tab interactions
        selectionHaptic.selectionChanged()

        if newTab == selectedTab {
          handleTabReselection(newTab)
        } else {
          activateTab(newTab)
          pendingCurrentMonthTab = nil
        }
      }
    )
  }

  var body: some View {
    ZStack {
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
          // Prevents black bars from showing behind tab content.
          TidexAppBackground()

          TabView(selection: tabSelection) {
            tabHost(for: .home) {
              DashboardView(selectedTab: $selectedTab, showStatsView: $showHomeStats)
            }
            .tabItem {
              Label(String(localized: Tab.home.localizationKey), systemImage: Tab.home.icon)
            }
            .tag(Tab.home)

            tabHost(for: .shifts) {
              ShiftsView(selectedTab: $selectedTab)
            }
            .tabItem {
              Label(String(localized: Tab.shifts.localizationKey), systemImage: Tab.shifts.icon)
            }
            .tag(Tab.shifts)

            tabHost(for: .add) {
              AddShiftView(selectedTab: $selectedTab, isKeyboardVisible: $isKeyboardVisible)
            }
            .tabItem {
              Label(String(localized: Tab.add.localizationKey), systemImage: Tab.add.icon)
            }
            .tag(Tab.add)

            tabHost(for: .wagey) {
              WageyView(selectedTab: $selectedTab)
            }
            .tabItem {
              Label(String(localized: Tab.wagey.localizationKey), systemImage: Tab.wagey.icon)
            }
            .tag(Tab.wagey)

            tabHost(for: .sharing) {
              SharingView(
                selectedTab: $selectedTab, hasSelectedSharer: $sharingHasSelectedSharer)
            }
            .tabItem {
              Label(String(localized: Tab.sharing.localizationKey), systemImage: friendsTabIcon)
            }
            .tag(Tab.sharing)
          }
          .background(
            TabBarTapObserver(selectedIndex: selectedTab.index) { tappedIndex in
              guard let tappedTab = Tab(index: tappedIndex), tappedTab == selectedTab else {
                return
              }
              selectionHaptic.selectionChanged()
              handleTabReselection(tappedTab)
            }
          )
          .tint(.tidexBlue)

          // Shared month picker overlay - floats above tab bar
          if shouldShowMonthPicker {
            sharedMonthPickerOverlay
              .transition(monthPickerTransition)
          }
        }
        .motionAnimation(.navigationPush, value: selectedTab, reduceMotion: shouldReduceEffects)
        .motionAnimation(
          .pageTransition, value: shouldShowMonthPicker, reduceMotion: shouldReduceEffects
        )
        .motionAnimation(.pageTransition, value: showListView, reduceMotion: shouldReduceEffects)
      }
      .motionAnimation(
        .pageTransition, value: impersonationManager.isImpersonating,
        reduceMotion: shouldReduceEffects)

      // Celebration overlay - above everything including tab bar and month picker
      if celebrationManager.shouldShowCelebration,
        let data = celebrationManager.celebrationData
      {
        CelebrationOverlay(
          data: data,
          onDismiss: {
            guard let userId = coordinator.userId else { return }
            celebrationManager.dismissCelebration(userId: userId, month: Date.currentYearMonth())
            ReviewRequestManager.shared.requestReviewIfEligible(
              userId: userId,
              requestReview: { requestReview() }
            )
          }
        )
      }

      // Screenshot share prompt overlay - above tab bar, keeps content visible
      if showScreenshotPrompt {
        ScreenshotSharePromptOverlay(
          onDismiss: {
            showScreenshotPrompt = false
          },
          onUseShareButton: {
            showScreenshotPrompt = false
            NotificationCenter.default.post(name: .screenshotPromptUseShareButton, object: nil)
          }
        )
      }
    }
    .task {
      await startFriendsThreadListTrackingIfPossible()
      scheduleUnreadFriendsCountRefresh()
    }
    .onReceive(NotificationCenter.default.publisher(for: .friendsThreadDidUpdate)) { _ in
      scheduleUnreadFriendsCountRefresh()
    }
    // Screenshot detection - prompt user to use share button instead
    .onReceive(
      NotificationCenter.default.publisher(for: UIApplication.userDidTakeScreenshotNotification)
    ) { _ in
      // Only show prompt when shifts tab is active and in calendar view (where share button is visible)
      if selectedTab == .shifts
        && !showListView
        && !showScreenshotPrompt
        && !showFeedbackSheet
        && !showAdminFeedbackSheet
      {
        showScreenshotPrompt = true
      }
    }
    .onChange(of: coordinator.pendingDeepLink) { _, deepLink in
      handlePendingDeepLink(deepLink)
    }
    .onChange(of: coordinator.userId) { _, _ in
      Task {
        await startFriendsThreadListTrackingIfPossible()
        scheduleUnreadFriendsCountRefresh()
      }
      handlePendingDeepLink(coordinator.pendingDeepLink)
    }
    .onAppear {
      // Handle any pending deep link on initial appearance
      loadedTabs.insert(selectedTab)
      handlePendingDeepLink(coordinator.pendingDeepLink)
      selectionHaptic.prepare()
    }
    .onReceive(NotificationCenter.default.publisher(for: .tidexDidBecomeActive)) { _ in
      Task {
        await startFriendsThreadListTrackingIfPossible()
        scheduleUnreadFriendsCountRefresh()
      }
    }
    .onDisappear {
      unreadRefreshTask?.cancel()
      unreadRefreshTask = nil
    }
    .sheet(isPresented: $showFeedbackSheet) {
      NavigationStack {
        FeedbackSettingsView()
      }
    }
    .sheet(isPresented: $showAdminFeedbackSheet) {
      AdminSettingsView(
        initialTab: adminSheetInitialTab,
        initialReportId: adminSheetInitialReportId
      )
    }
    .alert(
      String(localized: .addShiftSubmitRequirementsTitle),
      isPresented: $showAddSubmitRequirementsAlert
    ) {
      Button(String(localized: .commonOk), role: .cancel) {}
    } message: {
      Text(addSubmitRequirementsMessage)
    }
  }

  private var friendsTabIcon: String {
    unreadFriendsCount > 0 ? "person.2.badge.fill" : Tab.sharing.icon
  }

  private func startFriendsThreadListTrackingIfPossible() async {
    guard let viewerUserId = coordinator.getCurrentUserId(), !viewerUserId.isEmpty else { return }
    await friendsRealtimeCoordinator.startThreadListSubscription(viewerUserId: viewerUserId)
  }

  private func refreshUnreadFriendsCount() {
    guard let viewerUserId = coordinator.getCurrentUserId(), !viewerUserId.isEmpty else {
      unreadFriendsCount = 0
      NotificationService.shared.setApplicationBadgeCount(0)
      return
    }

    unreadFriendsCount =
      friendsMessagesRepository
      .getThreads(for: viewerUserId)
      .filter { $0.kind == .direct }
      .reduce(0) { $0 + $1.unreadCount }
    Task { @MainActor in
      await NotificationService.shared.refreshApplicationBadgeCount(viewerUserId: viewerUserId)
    }
  }

  private func scheduleUnreadFriendsCountRefresh() {
    unreadRefreshTask?.cancel()
    unreadRefreshTask = Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(120))
      guard !Task.isCancelled else { return }
      refreshUnreadFriendsCount()
    }
  }

  // MARK: - Month Picker Visibility

  /// Whether to show the month picker based on current tab and state
  private var shouldShowMonthPicker: Bool {
    switch selectedTab {
    case .home, .shifts:
      return true
    case .add:
      // Hide when keyboard is visible
      return !isKeyboardVisible
    case .wagey:
      return false
    case .sharing:
      // Only show when a sharer is selected
      return sharingHasSelectedSharer
    }
  }

  // MARK: - Shared Month Picker Overlay

  @ViewBuilder
  private var sharedMonthPickerOverlay: some View {
    GlassEffectContainer(spacing: Spacing.xs) {
      HStack(spacing: Spacing.xs) {
        // Stats/Back button - only on Home
        if selectedTab == .home {
          Button {
            Haptics.play(.light)
            showHomeStats.toggle()
          } label: {
            Image(systemName: showHomeStats ? "chevron.left" : "chart.bar.xaxis")
              .font(.tidexTitle2)
              .foregroundColor(.tidexBlue)
              .frame(width: MonthPickerLayout.height, height: MonthPickerLayout.height)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .contentTransition(.symbolEffect(.replace))
          .tidexGlass(
            shape: .rect(cornerRadius: MonthPickerLayout.cornerRadius),
            clear: true,
            interactive: true,
            disabled: disableHeavyCompositingForHangInvestigation
          )
          .transition(.opacity)
          .accessibilityLabel(Text(showHomeStats ? .commonBack : .tabsStats))
        }

        // View mode toggle button - Shifts tab or Friends tab when viewing a friend
        if selectedTab == .shifts || (selectedTab == .sharing && sharingHasSelectedSharer) {
          Button {
            selectionHaptic.selectionChanged()
            showListView.toggle()
          } label: {
            Image(systemName: showListView ? "calendar" : "list.bullet")
              .font(.tidexButton)
              .foregroundColor(monthContext.hasConflictsInMonth ? .tidexWarning : .tidexBlue)
              .frame(width: MonthPickerLayout.height, height: MonthPickerLayout.height)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .contentTransition(.symbolEffect(.replace))
          .tidexGlass(
            shape: .rect(cornerRadius: MonthPickerLayout.cornerRadius),
            tint: monthContext.hasConflictsInMonth ? Color.tidexWarning.opacity(0.3) : nil,
            clear: true,
            interactive: true,
            disabled: disableHeavyCompositingForHangInvestigation
          )
          .transition(.opacity)
          .motionAnimation(
            .feedback, value: monthContext.hasConflictsInMonth, reduceMotion: shouldReduceEffects)
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
        .tidexGlass(
          shape: .rect(cornerRadius: MonthPickerLayout.cornerRadius),
          clear: true,
          interactive: true,
          disabled: disableHeavyCompositingForHangInvestigation
        )

        // Add button - only on Add tab
        if selectedTab == .add {
          Button {
            handleAddButtonTap()
          } label: {
            Group {
              if addShiftCoordinator.isLoading {
                ProgressView()
                  .progressViewStyle(CircularProgressViewStyle(tint: .tidexBlue))
                  .scaleEffect(0.9)
              } else {
                Image(systemName: "plus")
                  .font(.tidexHeadline)
                  .foregroundColor(addShiftCoordinator.canSubmit ? .tidexBlue : .tidexTextMuted)
              }
            }
            .frame(width: MonthPickerLayout.height, height: MonthPickerLayout.height)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .disabled(addShiftCoordinator.isLoading)
          .tidexGlass(
            shape: .rect(cornerRadius: MonthPickerLayout.cornerRadius),
            tint: addShiftCoordinator.canSubmit ? Color.tidexBlue.opacity(0.2) : nil,
            clear: true,
            interactive: true,
            disabled: disableHeavyCompositingForHangInvestigation
          )
          .opacity(addShiftCoordinator.canSubmit ? 1.0 : 0.6)
          .transition(.opacity)
          .accessibilityLabel(Text(.tabsAdd))
        }
      }
    }
    .frame(maxWidth: AdaptiveMaxWidth.tabContent)
    .frame(maxWidth: .infinity)  // Fill screen width, then constrain to tabContent max
    .padding(.horizontal, MonthPickerLayout.horizontalPadding)
    // Position above tab bar (49pt on iPhone) + original bottom padding (8pt)
    // On iPad, tab bar is at top so no extra padding needed
    .padding(
      .bottom, isIPad ? MonthPickerLayout.bottomPadding : 49 + MonthPickerLayout.bottomPadding)
  }

  private var monthPickerTransition: AnyTransition {
    MotionTokens.transition(.pageTransition, reduceMotion: shouldReduceEffects)
  }

  /// Whether this tab has scrollable list content that should scroll-to-top before navigating to current month
  private func tabHasScrollableContent(_ tab: Tab) -> Bool {
    switch tab {
    case .shifts: return showListView
    default: return false
    }
  }

  /// Current transition phase for month picker animations
  private var transitionPhase: MonthTransitionPhase {
    MonthTransitionPhase(
      year: monthContext.displayYear,
      month: monthContext.displayMonth,
      direction: monthContext.navigationDirection
    )
  }

  private func handleAddButtonTap() {
    guard !addShiftCoordinator.isLoading else { return }

    if addShiftCoordinator.canSubmit {
      selectionHaptic.selectionChanged()
      addShiftCoordinator.triggerAdd()
      return
    }

    Haptics.play(.warning)
    showAddSubmitRequirementsAlert = true
  }

  private func handleTabReselection(_ tab: Tab) {
    let now = Date()
    if lastHandledReselectionTab == tab, now.timeIntervalSince(lastHandledReselectionDate) < 0.2 {
      return
    }

    lastHandledReselectionTab = tab
    lastHandledReselectionDate = now

    if tab == .home, showHomeStats {
      showHomeStats = false
      pendingCurrentMonthTab = nil
    } else if tab == .add {
      addShiftCoordinator.triggerModeCycle()
      pendingCurrentMonthTab = nil
    } else if tab == .wagey {
      pendingCurrentMonthTab = nil
    } else if tab == .sharing {
      NotificationCenter.default.post(
        name: .tabReselected, object: nil, userInfo: ["tab": tab])
    } else if tabHasScrollableContent(tab) && pendingCurrentMonthTab != tab {
      NotificationCenter.default.post(
        name: .tabReselected, object: nil, userInfo: ["tab": tab])
      pendingCurrentMonthTab = tab
    } else if !monthContext.isCurrentMonth {
      monthContext.goToCurrentMonth()
      pendingCurrentMonthTab = nil
    } else {
      NotificationCenter.default.post(
        name: .tabReselected, object: nil,
        userInfo: ["tab": tab, "scrollToToday": true])
      pendingCurrentMonthTab = nil
    }
  }

  private var addSubmitRequirementsMessage: String {
    let blockers = addShiftCoordinator.submitBlockers
    guard !blockers.isEmpty else {
      return String(localized: .addShiftSubmitRequirementsGeneric)
    }

    return
      blockers
      .map { "- \(String(localized: submitRequirementMessageKey(for: $0)))" }
      .joined(separator: "\n")
  }

  private func submitRequirementMessageKey(
    for blocker: AddShiftSubmitBlocker
  ) -> LocalizedStringResource {
    switch blocker {
    case .noAvailableJob:
      return .addShiftSubmitRequirementsAddJobFirst
    case .noSelectedJob:
      return .addShiftSubmitRequirementsSelectJob
    case .noSingleDates:
      return .addShiftSubmitRequirementsSelectDate
    case .noRecurringDays:
      return .addShiftSubmitRequirementsSelectRecurringDay
    case .missingTimes:
      return .addShiftSubmitRequirementsSetTimes
    case .noEventDate:
      return .addShiftSubmitRequirementsSelectEventDate
    case .invalidEventDateRange:
      return .addShiftSubmitRequirementsValidEventRange
    case .missingEventNote:
      return .addShiftSubmitRequirementsEventNote
    }
  }

  // MARK: - Deep Link Handling

  /// Handle pending deep link from AppCoordinator
  /// Switches to the appropriate tab based on the deep link type
  private func handlePendingDeepLink(_ deepLink: AppCoordinator.DeepLink?) {
    guard let deepLink = deepLink else { return }

    switch deepLink {
    case .sharing, .sharingManage, .friendChat:
      // Switch to sharing tab - SharingView will handle the specific navigation
      if selectedTab != .sharing {
        activateTab(.sharing)
      }
    case .shifts:
      // Switch to shifts tab - ShiftsView will handle the specific navigation
      if selectedTab != .shifts {
        activateTab(.shifts)
      }
    case .addShift:
      // Switch to add tab - AddShiftView will handle preselected date
      if selectedTab != .add {
        activateTab(.add)
      }
    case .feedback:
      // Open feedback sheet for users viewing their feedback responses
      showFeedbackSheet = true
      coordinator.clearPendingDeepLink()
    case .adminFeedback:
      // Open admin panel with feedback tab for admins viewing new feedback
      adminSheetInitialTab = .feedback
      adminSheetInitialReportId = nil
      showAdminFeedbackSheet = true
      coordinator.clearPendingDeepLink()
    case .adminReport(let reportId):
      adminSheetInitialTab = .reports
      adminSheetInitialReportId = reportId
      showAdminFeedbackSheet = true
      coordinator.clearPendingDeepLink()
    }
    // Note: We don't clear the deep link here for tab-based navigation - the destination view will consume and clear it
  }

  private func activateTab(_ tab: Tab) {
    loadedTabs.insert(tab)
    selectedTab = tab
  }

  @ViewBuilder
  private func tabHost<Content: View>(
    for tab: Tab,
    @ViewBuilder content: () -> Content
  ) -> some View {
    if loadedTabs.contains(tab) {
      content()
    } else {
      Color.clear
    }
  }
}

private struct TabBarTapObserver: UIViewControllerRepresentable {
  let selectedIndex: Int
  let onTapSelectedIndex: (Int) -> Void

  func makeUIViewController(context: Context) -> Controller {
    let controller = Controller()
    controller.coordinator = context.coordinator
    return controller
  }

  func updateUIViewController(_ uiViewController: Controller, context: Context) {
    context.coordinator.selectedIndex = selectedIndex
    context.coordinator.onTapSelectedIndex = onTapSelectedIndex
    uiViewController.attachIfNeeded()
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(selectedIndex: selectedIndex, onTapSelectedIndex: onTapSelectedIndex)
  }

  final class Coordinator: NSObject {
    var selectedIndex: Int
    var onTapSelectedIndex: (Int) -> Void
    weak var tabBar: UITabBar?

    init(selectedIndex: Int, onTapSelectedIndex: @escaping (Int) -> Void) {
      self.selectedIndex = selectedIndex
      self.onTapSelectedIndex = onTapSelectedIndex
    }

    @objc func handleTabBarTap(_ gesture: UITapGestureRecognizer) {
      guard gesture.state == .ended, let tabBar else { return }

      let tapLocation = gesture.location(in: tabBar)
      let tabBarButtons = tabBar.subviews
        .filter { $0 is UIControl && !$0.isHidden && $0.alpha > 0.01 }
        .sorted { $0.frame.minX < $1.frame.minX }

      guard let tappedIndex = tabBarButtons.firstIndex(where: { $0.frame.contains(tapLocation) })
      else {
        return
      }

      guard tappedIndex == selectedIndex else { return }
      onTapSelectedIndex(tappedIndex)
    }
  }

  final class Controller: UIViewController {
    weak var coordinator: Coordinator?

    override func viewDidAppear(_ animated: Bool) {
      super.viewDidAppear(animated)
      attachIfNeeded()
    }

    override func viewDidLayoutSubviews() {
      super.viewDidLayoutSubviews()
      attachIfNeeded()
    }

    func attachIfNeeded() {
      guard let coordinator, let tabBar = tabBarController?.tabBar else { return }
      guard coordinator.tabBar !== tabBar else { return }

      coordinator.tabBar?.gestureRecognizers?
        .filter { ($0 as? UITapGestureRecognizer)?.name == "MainTabView.TabBarTapObserver" }
        .forEach { coordinator.tabBar?.removeGestureRecognizer($0) }

      let recognizer = UITapGestureRecognizer(
        target: coordinator, action: #selector(Coordinator.handleTabBarTap(_:)))
      recognizer.cancelsTouchesInView = false
      recognizer.name = "MainTabView.TabBarTapObserver"
      tabBar.addGestureRecognizer(recognizer)
      coordinator.tabBar = tabBar
    }

    deinit {
      coordinator?.tabBar?.gestureRecognizers?
        .filter { ($0 as? UITapGestureRecognizer)?.name == "MainTabView.TabBarTapObserver" }
        .forEach { coordinator?.tabBar?.removeGestureRecognizer($0) }
    }
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

extension View {
  @ViewBuilder
  fileprivate func applyRefreshable(enabled: Bool) -> some View {
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
