import AppIntents
import SwiftUI

struct StatsView: View {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  @Environment(AppCoordinator.self) private var coordinator
  @ScaledMetric(relativeTo: .largeTitle) private var errorIconSize: CGFloat = 48

  @State private var viewModel = StatsViewModel()  // swiftlint:disable:this explicit_type_interface
  @State private var workSetupPresentationViewModel = WorkSetupPresentationViewModel()  // swiftlint:disable:this explicit_type_interface line_length
  @State private var showExportSettings = false  // swiftlint:disable:this explicit_type_interface
  /// True while a finger scrubs the pace chart, so the drag cannot also change month.
  @State private var isScrubbing = false  // swiftlint:disable:this explicit_type_interface
  /// False only for a user with no shifts at all, who sees one add-shift action instead of empty charts.
  @State private var hasAnyShifts = true  // swiftlint:disable:this explicit_type_interface
  @State private var addShiftPath: [AddShiftRoute] = []  // swiftlint:disable:this explicit_type_interface

  /// Shared refresh action used by pull-to-refresh and sync retry UI.
  private func refreshStatsContent() async {  // swiftlint:disable:this type_contents_order
    AppearanceTracker.shared.reset()
    await viewModel.refresh()
  }

  private var displayedStats: StatsData {
    viewModel.stats
      ?? StatsData.empty(year: viewModel.displayYear, month: viewModel.displayMonth)
  }

  private var displayedCurrency: String {
    displayedStats.currentMonthCurrencyAggregate?.primary.currency ?? viewModel.currency
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

  private func loadStatsContent() async {  // swiftlint:disable:this type_contents_order
    guard !shouldShowWorkSetupRequiredPlaceholder else { return }  // swiftlint:disable:this conditional_returns_on_newline line_length
    await viewModel.loadStats()
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
    .task {
      refreshWorkSetupPresentationState()
      refreshHasAnyShifts()
      await loadStatsContent()
    }
    .onAppear {
      refreshWorkSetupPresentationState()
      // Teaches Siri that the user checks earnings, so it can suggest the shortcut.
      _ = EarningsIntent(period: .thisMonth).donate()
    }
    .onReceive(NotificationCenter.default.publisher(for: .shiftsDidChange)) { _ in
      let hadShifts = hasAnyShifts  // swiftlint:disable:this explicit_type_interface
      refreshHasAnyShifts()
      // Stats doesn't reload on shift changes, so load it after the first shift is added.
      guard !hadShifts, hasAnyShifts else { return }  // swiftlint:disable:this conditional_returns_on_newline
      Task {
        await loadStatsContent()
      }
    }
    .onChange(of: coordinator.initialSyncComplete) { _, _ in
      refreshHasAnyShifts()
      let shouldLoadAfterSetupCompleted = refreshWorkSetupPresentationState()  // swiftlint:disable:this explicit_type_interface line_length
      guard shouldLoadAfterSetupCompleted else { return }  // swiftlint:disable:this conditional_returns_on_newline
      Task {
        await loadStatsContent()
      }
    }
    .onChange(of: coordinator.userId) { _, _ in
      refreshWorkSetupPresentationState()
    }
    .onReceive(NotificationCenter.default.publisher(for: .workSetupDataDidChange)) { _ in
      let shouldLoadAfterSetupCompleted = refreshWorkSetupPresentationState()  // swiftlint:disable:this explicit_type_interface line_length
      guard shouldLoadAfterSetupCompleted else { return }  // swiftlint:disable:this conditional_returns_on_newline
      Task {
        await loadStatsContent()
      }
    }
    .onChange(of: viewModel.stats?.focusMonth) { oldMonth, _ in
      // The month swaps in place, so VoiceOver gets no other cue that it changed.
      guard oldMonth != nil else { return }  // swiftlint:disable:this conditional_returns_on_newline
      announceDisplayedMonth()
    }
  }

  private var tabRootContent: some View {
    ZStack {
      TidexAppBackground()

      // The month picker sits in the shared overlay above the tab bar.
      Group {
        if shouldShowWorkSetupRequiredPlaceholder {
          WorkSetupRequiredPlaceholder()
        } else if let error = viewModel.error, viewModel.stats == nil,
          let message = ErrorTranslations.translate(error)
        {
          errorView(message: message)
        } else if !hasAnyShifts {
          FirstShiftEmptyState {
            coordinator.pendingDeepLink = .addShift(mode: nil, date: nil)
          }
          .padding(.bottom, MonthPickerLayout.totalBottomInset)
        } else {
          statsContent(stats: displayedStats)
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

  // MARK: - Stats Content

  private func statsContent(stats: StatsData) -> some View {  // swiftlint:disable:this type_contents_order
    let lattice = StatsLattice(stats: stats, now: .now, calendar: .gregorianCurrent)  // swiftlint:disable:this explicit_type_interface line_length
    return ScrollView {
      StatsContent(
        lattice: lattice,
        onSelectMonth: { month in
          viewModel.goToMonth(year: lattice.month.year, month: month)
        },
        onExport: { showExportSettings = true },
        onScrubbingChange: { isScrubbing = $0 }
      )
      .statsContentFrame()
      .contentShape(Rectangle())
      .monthSwipeGesture(
        onSwipeLeft: { viewModel.goToNextMonth() },
        onSwipeRight: { viewModel.goToPreviousMonth() },
        edgeExclusion: 24,  // swiftlint:disable:this no_magic_numbers
        isEnabled: !isScrubbing
      )
    }
    .userCurrency(displayedCurrency)
    .refreshable {
      await refreshStatsContent()
    }
  }

  private func announceDisplayedMonth() {  // swiftlint:disable:this type_contents_order
    let hero = StatsLattice(stats: displayedStats, now: .now, calendar: .gregorianCurrent).hero  // swiftlint:disable:this explicit_type_interface line_length
    let month = StatsFormat.monthName(hero.month, withYear: hero.showsYear)  // swiftlint:disable:this explicit_type_interface line_length
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
  StatsView()
    .environment(AppCoordinator.shared)
}
