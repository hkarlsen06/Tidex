import AppIntents
import Combine
import SwiftUI

struct StatsView: View {  // swiftlint:disable:this explicit_acl explicit_top_level_acl type_body_length
  /// The tab stays alive behind the other tabs, so it is told when it is the one on screen.
  let isSelected: Bool  // swiftlint:disable:this explicit_acl
  /// Owned by the tab view, which shows a year instead of a month in the floating picker.
  @Binding var period: StatsPeriod  // swiftlint:disable:this explicit_acl

  @Environment(AppCoordinator.self) private var coordinator
  @Environment(\.accessibilityReduceMotion) private var reduceMotion  // swiftlint:disable:this explicit_type_interface line_length
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass  // swiftlint:disable:this explicit_type_interface line_length
  @ScaledMetric(relativeTo: .largeTitle) private var errorIconSize: CGFloat = 48

  @State private var viewModel = StatsViewModel()  // swiftlint:disable:this explicit_type_interface
  @State private var workSetupPresentationViewModel = WorkSetupPresentationViewModel()  // swiftlint:disable:this explicit_type_interface line_length
  @State private var showExportSettings = false  // swiftlint:disable:this explicit_type_interface
  /// True while a finger scrubs the pace chart, so the drag cannot also change month.
  @State private var isScrubbing = false  // swiftlint:disable:this explicit_type_interface
  /// False only for a user with no shifts at all, who sees one add-shift action instead of empty charts.
  @State private var hasAnyShifts = true  // swiftlint:disable:this explicit_type_interface
  @State private var addShiftPath: [AddShiftRoute] = []  // swiftlint:disable:this explicit_type_interface
  @State private var scrollPosition = ScrollPosition(edge: .top)  // swiftlint:disable:this explicit_type_interface
  @State private var isScrolledDown = false  // swiftlint:disable:this explicit_type_interface
  private let syncStatusManager = SyncStatusManager.shared  // swiftlint:disable:this explicit_type_interface

  /// Shared refresh action used by pull-to-refresh and sync retry UI.
  private func refreshStatsContent() async {  // swiftlint:disable:this type_contents_order
    AppearanceTracker.shared.reset()
    await viewModel.refresh()
  }

  private var displayedStats: StatsData {
    viewModel.stats
      ?? StatsData.empty(year: viewModel.displayYear, month: viewModel.displayMonth)
  }

  private var displayedYearStats: YearStatsData {
    viewModel.yearStats ?? YearStatsData.empty(year: viewModel.displayYear)
  }

  private var displayedCurrency: String {
    let aggregate: JobCurrencyAggregateResolution? =
      switch period {
      case .month: displayedStats.currentMonthCurrencyAggregate
      case .year: displayedYearStats.currencyAggregate
      }
    return aggregate?.primary.currency ?? viewModel.currency
  }

  private var hasDisplayedData: Bool {
    switch period {
    case .month: viewModel.stats != nil
    case .year: viewModel.yearStats != nil
    }
  }

  @discardableResult
  private func refreshWorkSetupPresentationState() -> Bool {  // swiftlint:disable:this type_contents_order
    let wasShowingPlaceholder: Bool = shouldShowWorkSetupRequiredPlaceholder
    workSetupPresentationViewModel.refresh(
      userId: coordinator.userId,
      initialSyncComplete: coordinator.initialSyncComplete
    )
    return wasShowingPlaceholder && !shouldShowWorkSetupRequiredPlaceholder
  }

  private var shouldShowWorkSetupRequiredPlaceholder: Bool {
    workSetupPresentationViewModel.shouldShowPlaceholder
  }

  private func refreshHasAnyShifts() {  // swiftlint:disable:this type_contents_order
    hasAnyShifts = ShiftsRepository.shared.hasAnyShifts(
      for: coordinator.userId,
      initialSyncComplete: coordinator.initialSyncComplete
    )
  }

  var body: some View {  // swiftlint:disable:this explicit_acl
    NavigationStack(path: $addShiftPath) {
      tabRootContent
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          TabTitleToolbarItem(title: .tabsStats)
          if viewModel.shouldShowJobFilter, !shouldShowWorkSetupRequiredPlaceholder {
            ToolbarItem(placement: .topBarTrailing) {
              jobFilterMenu
            }
          }
        }
        .navigationDestination(for: AddShiftRoute.self) { _ in AddShiftScreen(tab: .stats) }
        .addShiftRoute(on: .stats, path: $addShiftPath)
        .adaptiveToolbarTransaction()
    }
    .sheet(isPresented: $showExportSettings) {
      SettingsView(initialDestination: .data)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
    .onChange(of: isSelected, initial: true) { _, selected in
      viewModel.setOnScreen(selected)
    }
    .onChange(of: period, initial: true) { oldPeriod, newPeriod in
      viewModel.setPeriod(newPeriod)
      guard oldPeriod != newPeriod else { return }  // swiftlint:disable:this conditional_returns_on_newline
      // Also the haptic for a tapped month row, which always switches to the month.
      Haptics.play(.selection)
      isScrolledDown = false
      withAnimation(reduceMotion ? nil : .default) {
        scrollPosition.scrollTo(edge: .top)
      }
    }
    .onAppear {
      // Also the first load. A load in `.task` would be cancelled when the tab is covered.
      reloadAfterDataChange()
      // Teaches Siri that the user checks earnings, so it can suggest the shortcut.
      _ = EarningsIntent(period: .thisMonth).donate()
    }
    // Every outside change that can make the numbers out of date. Add a new one here.
    // The view model reloads for its own month and job filter changes.
    .onReceive(statsDataChanges) { _ in
      reloadAfterDataChange()
    }
    .onChange(of: coordinator.initialSyncComplete) { _, _ in
      reloadAfterDataChange()
    }
    .onChange(of: syncStatusManager.lastSuccessfulSyncSummary) { _, summary in
      // Stats shows the same money as Home, so it reloads for the same synced tables.
      // Its own pull to refresh reloads after its sync.
      guard let summary, summary.userId == coordinator.userId,
        summary.dashboardChangeContext != nil,
        !(summary.reason == .manualRefresh && isSelected)
      else { return }
      reloadAfterDataChange()
    }
    .onChange(of: coordinator.userId) { _, _ in
      refreshWorkSetupPresentationState()
    }
    .onReceive(NotificationCenter.default.publisher(for: .tabReselected)) { notification in
      guard notification.userInfo?["tab"] as? MainTabView.Tab == .stats else { return }  // swiftlint:disable:this conditional_returns_on_newline line_length
      handleTabReselected()
    }
    .onChange(of: viewModel.stats?.focusMonth) { oldMonth, _ in
      // The month swaps in place, so VoiceOver gets no other cue that it changed.
      guard oldMonth != nil else { return }  // swiftlint:disable:this conditional_returns_on_newline
      announceDisplayedMonth()
    }
    .onChange(of: viewModel.yearStats?.year) { oldYear, _ in
      guard oldYear != nil else { return }  // swiftlint:disable:this conditional_returns_on_newline
      announceDisplayedYear()
    }
  }

  private var tabRootContent: some View {
    ZStack {
      TidexAppBackground()

      // The month picker sits in the shared overlay above the tab bar.
      Group {
        if shouldShowWorkSetupRequiredPlaceholder {
          WorkSetupRequiredPlaceholder()
        } else if let error = viewModel.error, !hasDisplayedData,
          let message = ErrorTranslations.translate(error)
        {
          errorView(message: message)
        } else if !hasAnyShifts {
          FirstShiftEmptyState {
            coordinator.pendingDeepLink = .addShift(mode: nil, date: nil)
          }
          .padding(.bottom, MonthPickerLayout.totalBottomInset)
        } else {
          statsContent
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)

      if !shouldShowWorkSetupRequiredPlaceholder {
        VStack {
          SyncStatusIndicator {
            Task {
              await refreshStatsContent()
            }
          }
          .padding(.top, Spacing.xs)
          Spacer()
        }
      }
    }
  }

  // MARK: - Reloading

  /// Notifications after which Stats can show out-of-date numbers. Foreground and the
  /// significant time change cover a new day, which moves today in the charts.
  private var statsDataChanges: some Publisher<Notification, Never> {
    Publishers.MergeMany(
      NotificationCenter.default.publisher(for: .shiftsDidChange),
      NotificationCenter.default.publisher(for: .workSetupDataDidChange),
      NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification),
      NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)
    )
  }

  private func reloadAfterDataChange() {  // swiftlint:disable:this type_contents_order
    refreshHasAnyShifts()
    refreshWorkSetupPresentationState()
    guard !shouldShowWorkSetupRequiredPlaceholder else { return }  // swiftlint:disable:this conditional_returns_on_newline line_length
    viewModel.reloadWhenOnScreen()
  }

  /// Like the Schedule list, a re-tap first scrolls up, and the next one goes to the current month.
  private func handleTabReselected() {  // swiftlint:disable:this type_contents_order
    guard isScrolledDown else {
      viewModel.goToCurrentMonth()
      return
    }
    // Cleared here too, in case the scroll view was replaced while scrolled down.
    isScrolledDown = false
    withAnimation(reduceMotion ? nil : .default) {
      scrollPosition.scrollTo(edge: .top)
    }
  }

  // MARK: - Stats Content

  private var statsPage: StatsContent.Page {
    switch period {
    case .month:
      .month(
        StatsLattice(stats: displayedStats, now: viewModel.computedAt, calendar: .gregorianCurrent))
    case .year:
      .year(
        StatsYearLattice(
          stats: displayedYearStats, now: viewModel.computedAt, calendar: .gregorianCurrent))
    }
  }

  private var statsContent: some View {
    ScrollView {
      StatsContent(
        page: statsPage,
        onSelectMonth: { month in
          viewModel.goToMonth(year: month.year, month: month.month)
          period = .month
        },
        onExport: { showExportSettings = true },
        onScrubbingChange: { isScrubbing = $0 }
      )
      .statsContentFrame()
      .contentShape(Rectangle())
      .monthSwipeGesture(
        onSwipeLeft: {
          if period == .year { viewModel.goToNextYear() } else { viewModel.goToNextMonth() }
        },
        onSwipeRight: {
          if period == .year { viewModel.goToPreviousYear() } else { viewModel.goToPreviousMonth() }
        },
        edgeExclusion: 24,  // swiftlint:disable:this no_magic_numbers
        isEnabled: !isScrubbing
      )
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      periodPicker
    }
    .scrollPosition($scrollPosition)
    .onScrollGeometryChange(for: Bool.self) { geometry in
      geometry.contentOffset.y + geometry.contentInsets.top > 1
    } action: { _, isScrolled in
      isScrolledDown = isScrolled
    }
    .userCurrency(displayedCurrency)
    .refreshable {
      await refreshStatsContent()
    }
  }

  /// Sits right above the floating month picker. The clear space under it is the picker's, so
  /// the scroll content clears both.
  private var periodPicker: some View {
    VStack(spacing: MonthPickerLayout.bottomPadding) {
      AdaptiveCalendarPicker(
        selection: $period,
        options: [
          CalendarPickerOption(value: StatsPeriod.month, title: .commonMonth),
          CalendarPickerOption(value: StatsPeriod.year, title: .commonYear),
        ]
      )
      .padding(Spacing.xxs)
      .tidexGlass(shape: .rect(cornerRadius: MonthPickerLayout.cornerRadius))
      .accessibilityIdentifier("stats.period")
      .frame(maxWidth: AdaptiveMaxWidth.tabContent)
      .frame(maxWidth: .infinity)
      .padding(
        .horizontal,
        horizontalSizeClass == .regular
          ? MonthPickerLayout.horizontalPadding : MonthPickerLayout.tabBarAlignedHorizontalPadding
      )
      Color.clear
        .frame(height: MonthPickerLayout.totalBottomInset)
        .accessibilityHidden(true)
    }
  }

  private func announceDisplayedYear() {  // swiftlint:disable:this type_contents_order
    let hero = StatsYearLattice(  // swiftlint:disable:this explicit_type_interface
      stats: displayedYearStats, now: viewModel.computedAt, calendar: .gregorianCurrent
    ).hero
    let amount = StatsFormat.money(hero.amount, currency: displayedCurrency)  // swiftlint:disable:this explicit_type_interface line_length
    let announcement: String = [String(displayedYearStats.year), amount].joined(separator: ", ")
    AccessibilityNotification.Announcement(announcement).post()
  }

  private func announceDisplayedMonth() {  // swiftlint:disable:this type_contents_order
    let hero = StatsLattice(
      stats: displayedStats, now: viewModel.computedAt, calendar: .gregorianCurrent
    ).hero  // swiftlint:disable:this explicit_type_interface line_length
    guard case .month(let focus, let showsYear) = hero.period else { return }  // swiftlint:disable:this conditional_returns_on_newline line_length
    let month = StatsFormat.monthName(focus, withYear: showsYear)  // swiftlint:disable:this explicit_type_interface
    let amount = StatsFormat.money(hero.amount, currency: displayedCurrency)  // swiftlint:disable:this explicit_type_interface line_length
    let announcement: String = [month, amount].joined(separator: ", ")
    AccessibilityNotification.Announcement(announcement).post()
  }

  // MARK: - Job Filter

  private var jobFilterMenu: some View {
    let selectedName = viewModel.selectedJobName ?? String(localized: .jobsFilterAll)  // swiftlint:disable:this explicit_type_interface line_length
    return Menu {
      Picker(selection: jobSelection) {
        Text(.jobsFilterAll)
          .tag(String?.none)
        ForEach(viewModel.activeJobs) { job in
          Text(verbatim: job.name)
            .tag(Optional(job.id))
        }
      } label: {
        Text(.jobsFilterTitle)
      }
      .pickerStyle(.inline)
    } label: {
      HStack(spacing: Spacing.xxs) {
        Text(verbatim: selectedName)
          .lineLimit(1)
        Image(systemName: "chevron.down")
          .font(.tidexCaptionStrong)
          .accessibilityHidden(true)
      }
      .font(.tidexLabel)
    }
    .accessibilityLabel(Text(.jobsFilterTitle))
    .accessibilityValue(Text(verbatim: selectedName))
  }

  private var jobSelection: Binding<String?> {
    Binding(
      get: { viewModel.selectedJobId },
      set: { jobId in
        Haptics.play(.selection)
        viewModel.selectJobFilter(jobId)
      }
    )
  }

  // MARK: - Error View

  @ViewBuilder
  private func errorView(message: String) -> some View {
    VStack(spacing: Spacing.md) {
      Image(systemName: "exclamationmark.triangle")
        .font(.system(size: errorIconSize))
        .foregroundStyle(Color.tidexTextMuted)
        .accessibilityHidden(true)

      Text(message)
        .font(.tidexBodyMedium)
        .foregroundStyle(Color.tidexTextSecondary)
        .multilineTextAlignment(.center)

      Button {
        Task {
          await refreshStatsContent()
        }
      } label: {
        Text(.commonRetry)
          .font(.tidexButton)
          .foregroundStyle(Color.tidexTextOnBrand)
          .padding(.horizontal, Spacing.lg)
          .padding(.vertical, Spacing.sm)
          .background(Color.tidexBlue)
          .clipShape(.rect(cornerRadius: CornerRadius.sm))
      }
    }
    .frame(maxWidth: AdaptiveMaxWidth.tabContent)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding()
    .announcesToVoiceOver(message)
  }
}

#Preview {
  StatsView(isSelected: true, period: .constant(.month))
    .environment(AppCoordinator.shared)
}
