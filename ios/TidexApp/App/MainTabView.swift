// swiftlint:disable:next blanket_disable_command
// swiftlint:disable closure_body_length conditional_returns_on_newline
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable explicit_acl explicit_enum_raw_value explicit_top_level_acl
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable explicit_type_interface extension_access_modifier file_length file_types_order identifier_name
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable multiline_arguments_brackets multiline_call_arguments no_empty_block no_magic_numbers
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable prefer_asset_symbols required_deinit
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable strict_fileprivate switch_case_on_newline type_body_length
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable type_contents_order
import StoreKit
import SwiftUI

// MARK: - Tab Reselection Notification

extension Notification.Name {
  /// Posted when a tab is tapped while already selected
  static let tabReselected = Notification.Name("tabReselected")

  /// Posted by the screenshot prompt overlay when user taps "Use Share Button"
  static let screenshotPromptUseShareButton = Notification.Name("screenshotPromptUseShareButton")
}

/// Root tab view for signed-in users: Home, Schedule, Stats, Friends and the user's profile.
/// The plus button beside the month picker pushes the Add screen onto the current tab.
/// Saving there closes it on Schedule.
struct MainTabView: View {
  @Environment(AppCoordinator.self) private var coordinator
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.requestReview) private var requestReview
  private let shiftsToolbarCoordinator = ShiftsToolbarCoordinator.shared
  private let impersonationManager = ImpersonationManager.shared
  @Bindable private var celebrationManager = ShiftCompletionCelebrationManager.shared
  private let addShiftNavigator = AddShiftNavigator.shared
  private let friendsMessagesRepository = FriendsMessagesRepository.shared

  @State private var selectedTab: Tab = .home
  @State private var loadedTabs: Set<Tab> = [.home]
  /// Each loaded tab's bottom safe-area inset, which includes the tab bar.
  @State private var tabBottomInsets: [Tab: CGFloat] = [:]
  /// The selected tab's inset. A tab reports only after its first layout, so on a first
  /// visit the month picker keeps its place until the new tab reports.
  @State private var monthPickerInset: CGFloat = 0

  // Tracks whether the first re-tap on a scrollable tab already triggered scroll-to-top.
  // On the next re-tap, we navigate to the current month instead.
  @State private var pendingCurrentMonthTab: Tab?

  @State private var friendsHasSelectedSharer = false
  /// Whether Stats shows a month or a year. Each launch starts on the month.
  @State private var statsPeriod: StatsPeriod = .month
  @State private var profileRequest: SettingsView.TabRequest?
  /// The user's photo, sized and rounded for the profile tab item.
  @State private var profileTabAvatar: UIImage?

  // State for feedback deep link sheets
  @State private var showFeedbackSheet = false
  @State private var showAdminFeedbackSheet = false
  @State private var adminSheetInitialTab: AdminTab = .feedback
  @State private var adminSheetInitialReportId: String?

  /// The invite link waiting for the user's answer. Its sheet closes the pending invite.
  @State private var inviteConfirmation: InviteConfirmationModel?
  @State private var presentedInviterId: String?

  // Screenshot share prompt state (presented as overlay to keep content visible)
  @State private var showScreenshotPrompt = false
  @State private var stopImpersonationError: String?

  @State private var unreadFriendsCount = 0
  @State private var unreadRefreshTask: Task<Void, Never>?

  // View mode toggle (calendar vs list) - persisted across app launches
  // Shared with ShiftsView via @AppStorage
  @AppStorage("shiftsViewMode") private var showListView = false

  // Haptic feedback for tab taps. Tapping the already-selected tab doesn't change
  // `selectedTab`, so a counter drives the feedback instead of the tab value itself.
  @State private var tabInteractionTick = 0
  // Temporary investigation switch; keep false for docs-aligned glass behavior.
  private let disableHeavyCompositingForHangInvestigation = false

  private var shouldReduceEffects: Bool {
    reduceMotion || disableHeavyCompositingForHangInvestigation
  }

  enum Tab: String, CaseIterable, Hashable {
    case home
    case shifts
    case stats
    // The raw value is persisted as the startup tab and synced, so it keeps the old name.
    case friends = "sharing"
    case profile

    /// Resolves a stored startup tab. Values from removed tabs, such as "add", fall back to Home.
    static func startupTab(rawValue: String?) -> Self {
      rawValue.flatMap(Self.init(rawValue:)) ?? .home
    }
  }

  init() {
    let startupTab = Tab.startupTab(
      rawValue: UserDefaults.standard.string(forKey: AppCoordinator.startupTabCacheKey))
    _selectedTab = State(initialValue: startupTab)
    _loadedTabs = State(initialValue: [startupTab])
  }

  /// Custom binding that detects tab reselection
  /// Re-tapping the Schedule list scrolls to top first, then goes to today
  private var tabSelection: Binding<Tab> {
    Binding(
      get: { selectedTab },
      set: { newTab in
        tabInteractionTick += 1

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
              do {
                try await impersonationManager.stopImpersonation()
              } catch {
                stopImpersonationError = ErrorTranslations.translate(error)
              }
            }
          )
        }

        ZStack(alignment: .bottom) {
          // Background that fills entire screen including safe areas
          // Prevents black bars from showing behind tab content.
          TidexAppBackground()

          TabView(selection: tabSelection) {
            SwiftUI.Tab(
              String(localized: .tabsHome),
              systemImage: "house.fill",
              value: Tab.home
            ) {
              tabHost(for: .home) {
                DashboardView(selectedTab: tabSelection)
              }
            }

            SwiftUI.Tab(
              String(localized: .tabsShifts),
              systemImage: "calendar",
              value: Tab.shifts
            ) {
              tabHost(for: .shifts) {
                ShiftsView(selectedTab: tabSelection)
              }
            }

            SwiftUI.Tab(
              String(localized: .tabsStats),
              systemImage: "chart.bar.xaxis",
              value: Tab.stats
            ) {
              tabHost(for: .stats) {
                StatsView(isSelected: selectedTab == .stats, period: $statsPeriod)
                  .id(coordinator.userId)
              }
            }

            SwiftUI.Tab(
              String(localized: .tabsSharing),
              systemImage: "person.2.fill",
              value: Tab.friends
            ) {
              tabHost(for: .friends) {
                FriendsView(
                  selectedTab: tabSelection, hasSelectedSharer: $friendsHasSelectedSharer)
              }
            }
            .badge(unreadFriendsCount)

            SwiftUI.Tab(value: Tab.profile) {
              tabHost(for: .profile) {
                SettingsView(tabRequest: $profileRequest)
              }
            } label: {
              Label {
                Text(profileTabTitle)
                  .accessibilityLabel(Text(verbatim: profileTabAccessibilityLabel))
              } icon: {
                if let profileTabAvatar {
                  Image(uiImage: profileTabAvatar)
                    .renderingMode(.original)
                } else {
                  Image(systemName: "person.crop.circle.fill")
                }
              }
            }
          }

          monthPickerLayer
        }
        .onChange(of: addShiftNavigator.isClosingOnSchedule) { _, isClosing in
          if isClosing {
            closeAddShiftOnSchedule()
          }
        }
        .motionAnimation(.navigationPush, value: selectedTab, reduceMotion: shouldReduceEffects)
        .motionAnimation(.pageTransition, value: showListView, reduceMotion: shouldReduceEffects)
      }
      .motionAnimation(
        .pageTransition, value: impersonationManager.isImpersonating,
        reduceMotion: shouldReduceEffects)

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
    .firstShiftConfetti()
    .sheet(
      isPresented: $celebrationManager.isSheetPresented,
      onDismiss: {
        celebrationManager.dismissCelebration(userId: coordinator.userId)
        guard let userId = coordinator.userId else { return }
        ReviewRequestManager.shared.requestReviewIfEligible(
          userId: userId,
          requestReview: { requestReview() }
        )
      }
    ) {
      if let data = celebrationManager.celebrationData {
        CelebrationOverlay(data: data)
      }
    }
    .sensoryFeedback(.selection, trigger: tabInteractionTick)
    .task {
      scheduleUnreadFriendsCountRefresh()
    }
    .task(id: coordinator.userAvatarUrl) {
      profileTabAvatar = await Self.loadTabAvatar(from: coordinator.userAvatarUrl)
    }
    .onReceive(NotificationCenter.default.publisher(for: .friendsThreadDidUpdate)) { _ in
      scheduleUnreadFriendsCountRefresh()
    }
    // Screenshot detection - prompt user to use share button instead
    .onReceive(
      NotificationCenter.default.publisher(for: UIApplication.userDidTakeScreenshotNotification)
    ) { _ in
      // Debug builds ignore screenshots so development screenshots don't trigger the prompt
      #if !DEBUG
        // Only show prompt when shifts tab is active and in calendar view (where share button is visible)
        if selectedTab == .shifts, !showListView, !showScreenshotPrompt, !showFeedbackSheet,
          !showAdminFeedbackSheet, addShiftNavigator.hostTab != .shifts
        {
          showScreenshotPrompt = true
        }
      #endif
    }
    .onChange(of: coordinator.pendingDeepLink) { _, deepLink in
      handlePendingDeepLink(deepLink)
    }
    .onChange(of: coordinator.userId) { _, _ in
      scheduleUnreadFriendsCountRefresh()
      handlePendingDeepLink(coordinator.pendingDeepLink)
      presentPendingInvite()
    }
    .onAppear {
      // Handle any pending deep link on initial appearance
      loadedTabs.insert(selectedTab)
      handlePendingDeepLink(coordinator.pendingDeepLink)
      // An invite opened before sign-up or during onboarding.
      presentPendingInvite()
    }
    .sheet(item: $inviteConfirmation, onDismiss: closePresentedInvite) { model in
      InviteConfirmationSheet(model: model) { activateTab(.friends) }
    }
    .onReceive(NotificationCenter.default.publisher(for: .tidexDidBecomeActive)) { _ in
      scheduleUnreadFriendsCountRefresh()
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
      NavigationStack {
        AdminSettingsView(
          initialTab: adminSheetInitialTab,
          initialReportId: adminSheetInitialReportId
        )
      }
    }
    .alert(
      String(localized: .commonError),
      isPresented: Binding(
        get: { stopImpersonationError != nil },
        set: { if !$0 { stopImpersonationError = nil } }
      )
    ) {
      Button(String(localized: .commonOk), role: .cancel) {}
    } message: {
      Text(stopImpersonationError ?? "")
    }
  }

  /// Loads the user's photo from the image cache or network as a small round tab icon.
  private static func loadTabAvatar(from urlString: String?) async -> UIImage? {
    guard let urlString, let url = URL(string: urlString) else { return nil }
    let maxPixelSize: CGFloat = 120
    var image = ImageCache.shared.get(for: url, maxPixelSize: maxPixelSize)
    if image == nil {
      image = await ImageCache.shared.getFromDisk(for: url, maxPixelSize: maxPixelSize)
    }
    if image == nil, let (data, _) = try? await URLSession.shared.data(from: url) {
      image = ImageCache.decodedImage(from: data, maxPixelSize: maxPixelSize)
      if let image {
        ImageCache.shared.set(image, for: url, maxPixelSize: maxPixelSize)
      }
    }
    return image.map(roundTabIcon(from:))
  }

  /// Crops a photo to a circle the size of a tab bar symbol, keeping its original colors.
  private static func roundTabIcon(from image: UIImage) -> UIImage {
    let side: CGFloat = 26
    let bounds = CGRect(x: 0, y: 0, width: side, height: side)
    let scale = max(side / image.size.width, side / image.size.height)
    let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
    let drawRect = CGRect(
      x: (side - drawSize.width) / 2, y: (side - drawSize.height) / 2,
      width: drawSize.width, height: drawSize.height)
    return UIGraphicsImageRenderer(bounds: bounds).image { _ in
      UIBezierPath(ovalIn: bounds).addClip()
      image.draw(in: drawRect)
    }
    .withRenderingMode(.alwaysOriginal)
  }

  /// The profile tab is labelled with the user's first name.
  private var profileTabTitle: String {
    let firstName = coordinator.userDisplayName.split(separator: " ").first.map(String.init)
    return firstName ?? String(localized: .tabsProfile)
  }

  /// The tab shows the first name, so VoiceOver also says what the tab is.
  private var profileTabAccessibilityLabel: String {
    let profileTitle = String(localized: .tabsProfile)
    return profileTabTitle == profileTitle ? profileTitle : "\(profileTabTitle), \(profileTitle)"
  }

  private func refreshUnreadFriendsCount() async {
    guard let viewerUserId = coordinator.getCurrentUserId(), !viewerUserId.isEmpty else {
      unreadFriendsCount = 0
      NotificationService.shared.setApplicationBadgeCount(0)
      return
    }

    let directThreads =
      await friendsMessagesRepository
      .getThreadsOffMain(for: viewerUserId)
      .filter { $0.kind == .direct }
    guard !Task.isCancelled else { return }

    unreadFriendsCount =
      directThreads
      .reduce(0) { $0 + $1.unreadCount }
    await NotificationService.shared.refreshApplicationBadgeCount(viewerUserId: viewerUserId)
  }

  private func scheduleUnreadFriendsCountRefresh() {
    unreadRefreshTask?.cancel()
    unreadRefreshTask = Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(120))
      guard !Task.isCancelled else { return }
      await refreshUnreadFriendsCount()
    }
  }

  // MARK: - Month Picker Visibility

  /// Whether to show the month picker based on current tab and state
  private var shouldShowMonthPicker: Bool {
    // The Add screen has its own month picker.
    guard addShiftNavigator.hostTab != selectedTab else { return false }
    switch selectedTab {
    case .home, .shifts, .stats:
      return true

    case .friends:
      // Only show when a friend's calendar is open
      return friendsHasSelectedSharer

    case .profile:
      return false
    }
  }

  /// One month picker for every tab, so switching tabs morphs its controls instead of
  /// replacing the picker. Its bottom padding is the inset the selected tab reported.
  private var monthPickerLayer: some View {
    Group {
      if shouldShowMonthPicker {
        MonthPickerControls(
          period: selectedTab == .stats ? $statsPeriod : nil,
          showsViewModeToggle: showsViewModeToggle,
          showsAddButton: showsAddButton,
          onAddShift: { addShiftNavigator.hostTab = selectedTab }
        )
        .transition(MotionTokens.transition(.pageTransition, reduceMotion: shouldReduceEffects))
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    .padding(.bottom, monthPickerInset)
    .ignoresSafeArea(edges: .bottom)
    .motionAnimation(
      .pageTransition, value: shouldShowMonthPicker, reduceMotion: shouldReduceEffects)
  }

  private var showsViewModeToggle: Bool {
    switch selectedTab {
    case .shifts: return shiftsToolbarCoordinator.canShowLeadingActions
    case .friends: return friendsHasSelectedSharer
    case .home, .stats, .profile: return false
    }
  }

  private var showsAddButton: Bool {
    switch selectedTab {
    case .home: return true
    case .shifts: return shiftsToolbarCoordinator.canShowLeadingActions
    case .stats, .friends, .profile: return false
    }
  }

  // MARK: - Tab Reselection

  private func handleTabReselection(_ tab: Tab) {
    if addShiftNavigator.hostTab == tab {
      // Like any pushed screen, re-tapping the tab goes back to its root.
      addShiftNavigator.hostTab = nil
      pendingCurrentMonthTab = nil
    } else if tab == .stats || tab == .friends || tab == .profile {
      NotificationCenter.default.post(
        name: .tabReselected, object: nil, userInfo: ["tab": tab])
    } else if tab == .shifts, showListView, pendingCurrentMonthTab != tab {
      // First re-tap scrolls the list to the top, like other iOS lists.
      NotificationCenter.default.post(
        name: .tabReselected, object: nil, userInfo: ["tab": tab])
      pendingCurrentMonthTab = tab
    } else {
      // The next re-tap goes to today, switching month first if needed.
      SharedMonthContext.shared.goToCurrentMonth()
      NotificationCenter.default.post(
        name: .tabReselected, object: nil,
        userInfo: ["tab": tab, "scrollToToday": true])
      pendingCurrentMonthTab = nil
    }
  }

  // MARK: - Deep Link Handling

  // swiftlint:disable cyclomatic_complexity
  /// Handle pending deep link from AppCoordinator
  /// Switches to the appropriate tab based on the deep link type
  private func handlePendingDeepLink(_ deepLink: AppCoordinator.DeepLink?) {
    guard let deepLink else { return }

    switch deepLink {
    case .sharing, .sharingManage, .friendChat:
      // FriendsView handles the specific navigation
      activateTab(.friends)

    case .shifts:
      // ShiftsView handles the specific navigation
      activateTab(.shifts)

    case .clockOut:
      // DashboardView clocks out, then clears the link.
      activateTab(.home)

    case .addShift:
      // Push Add onto the current tab. AddShiftView applies the mode and date,
      // then clears the link.
      addShiftNavigator.hostTab = selectedTab

    case .settings(let destination):
      activateTab(.profile)
      profileRequest = SettingsView.TabRequest(destination: destination?.settingsDestination)
      coordinator.clearPendingDeepLink()

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

    case .invite:
      // AppCoordinator saved it to PendingInviteStore, which also covers a signed-out open.
      coordinator.clearPendingDeepLink()
      presentPendingInvite()
    }
    // Note: We don't clear the deep link here for tab-based navigation - the destination view will consume and clear it
  }
  // swiftlint:enable cyclomatic_complexity

  private func presentPendingInvite() {
    guard inviteConfirmation == nil, let userId = coordinator.userId,
      let inviterId = PendingInviteStore.inviter(for: userId)
    else { return }
    OnboardingFunnelRecorder.shared.record("friend_invite_opened")
    presentedInviterId = inviterId
    inviteConfirmation = InviteConfirmationModel(inviterId: inviterId, viewerId: userId)
  }

  /// Clears the invite whose sheet closed, then shows a newer one opened meanwhile.
  private func closePresentedInvite() {
    if let presentedInviterId {
      PendingInviteStore.clear(inviterId: presentedInviterId)
    }
    presentedInviterId = nil
    presentPendingInvite()
  }

  private func activateTab(_ tab: Tab) {
    loadedTabs.insert(tab)
    selectedTab = tab
    if let inset = tabBottomInsets[tab] {
      monthPickerInset = inset
    }
  }

  private func closeAddShiftOnSchedule() {
    addShiftNavigator.isClosingOnSchedule = false
    activateTab(.shifts)
    pendingCurrentMonthTab = nil
    addShiftNavigator.hostTab = nil
  }

  @ViewBuilder
  private func tabHost<Content: View>(
    for tab: Tab,
    @ViewBuilder content: () -> Content
  ) -> some View {
    if loadedTabs.contains(tab) {
      content()
        // The tab's bottom safe area covers its tab bar, so the shared month picker
        // can sit above the tab bar without hardcoding the tab bar height.
        .onGeometryChange(for: CGFloat.self) {
          $0.safeAreaInsets.bottom
        } action: {
          tabBottomInsets[tab] = $0
          if tab == selectedTab { monthPickerInset = $0 }
        }
    } else {
      Color.clear
    }
  }
}

// MARK: - Month Picker Controls

/// Month picker above the tab bar, with the list toggle on its leading side
/// and the add button on its trailing side, each as its own glass control.
/// Stats puts its month or year choice on the leading side, and in year mode shows a year
/// picker in the same pill.
struct MonthPickerControls: View {
  /// Set only on Stats.
  var period: Binding<StatsPeriod>?
  let showsViewModeToggle: Bool
  let showsAddButton: Bool
  let onAddShift: () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private let monthContext = SharedMonthContext.shared
  @AppStorage("shiftsViewMode") private var showListView = false

  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  var body: some View {
    GlassEffectContainer(spacing: Spacing.xs) {
      HStack(spacing: Spacing.xs) {
        if showsViewModeToggle {
          viewModeToggleButton
        }

        if let period {
          // Gets its full width first. The pill shortens its month before the words here shrink.
          StatsPeriodPicker(period: period)
            .layoutPriority(1)
        }

        Group {
          switch period?.wrappedValue ?? .month {
          case .month: SharedMonthPicker()
          case .year: StatsYearPicker()
          }
        }
        .frame(minWidth: MonthPickerLayout.minimumWidth, maxWidth: .infinity)
        .frame(height: MonthPickerLayout.height)
        .tidexGlass(
          shape: .rect(cornerRadius: MonthPickerLayout.cornerRadius),
          interactive: true
        )

        if showsAddButton {
          addButton
        }
      }
    }
    .frame(maxWidth: AdaptiveMaxWidth.tabContent)
    .frame(maxWidth: .infinity)
    .padding(
      .horizontal,
      horizontalSizeClass == .regular
        ? MonthPickerLayout.horizontalPadding : MonthPickerLayout.tabBarAlignedHorizontalPadding
    )
    .padding(.bottom, MonthPickerLayout.bottomPadding)
  }

  private var viewModeToggleButton: some View {
    Button {
      showListView.toggle()
    } label: {
      Image(systemName: showListView ? "calendar" : "list.bullet")
        .font(.system(size: Spacing.iconSize, weight: .semibold))
        .foregroundStyle(
          monthContext.hasConflictsInMonth ? Color.tidexWarning : Color.tidexTextPrimary
        )
        .frame(width: MonthPickerLayout.height, height: MonthPickerLayout.height)
        .overlay(alignment: .topTrailing) {
          // The icon color alone would be the only sign of conflicts, so add a badge shape.
          if monthContext.hasConflictsInMonth {
            Image(systemName: "exclamationmark.circle.fill")
              .font(.caption2.weight(.bold))
              .foregroundStyle(Color.tidexWarning)
              .padding(Spacing.xxs)
          }
        }
        .contentShape(Rectangle())
        .accessibilityHidden(true)
    }
    .buttonStyle(.plain)
    .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
    .tidexGlass(
      shape: .rect(cornerRadius: MonthPickerLayout.cornerRadius),
      interactive: true
    )
    .accessibilityLabel(
      showListView ? Text(.shiftsViewModeShowCalendar) : Text(.shiftsViewModeShowList)
    )
    .accessibilityValue(
      monthContext.hasConflictsInMonth ? Text(.shiftsAccessibilityConflict) : Text(verbatim: "")
    )
    .sensoryFeedback(.selection, trigger: showListView)
  }

  private var addButton: some View {
    Button {
      Haptics.play(.selection)
      onAddShift()
    } label: {
      Image(systemName: "plus")
        .font(.system(size: Spacing.iconSize, weight: .semibold))
        .foregroundStyle(Color.tidexTextPrimary)
        .frame(width: MonthPickerLayout.height, height: MonthPickerLayout.height)
        .contentShape(Rectangle())
        .accessibilityHidden(true)
    }
    .buttonStyle(.plain)
    .tidexGlass(
      shape: .rect(cornerRadius: MonthPickerLayout.cornerRadius),
      interactive: true
    )
    .accessibilityLabel(Text(.shiftsEmptyAddShift))
    .accessibilityIdentifier("month-accessory.add-shift")
  }
}

extension AppCoordinator.SettingsDeepLinkDestination {
  fileprivate var settingsDestination: SettingsView.SettingsDestination {
    switch self {
    case .profile:
      return .profile

    case .security:
      return .security

    case .notifications:
      return .notifications

    case .appearance:
      return .appearance

    case .pay(let jobId):
      return .pay(jobId: jobId)

    case .recurringShifts:
      return .recurringShifts

    case .calendarSync:
      return .calendarSync()

    case .data:
      return .data

    case .feedback:
      return .feedback

    case .admin:
      return .admin
    }
  }
}

#Preview {
  MainTabView()
    .environment(AppCoordinator.shared)
}
