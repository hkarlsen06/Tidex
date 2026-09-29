import Observation
import SwiftUI
// swiftlint:disable:next sorted_imports
import os.log

private let kLogger: Logger = Logger(subsystem: "no.tidex.app", category: "ShiftsView")

@MainActor
@Observable
internal final class ShiftsToolbarCoordinator {
  internal static let shared = ShiftsToolbarCoordinator()

  /// Whether the month picker accessory shows the list toggle and add button for Schedule.
  internal private(set) var canShowLeadingActions = false

  private init() {
    // Singleton.
  }

  internal func update(canShowLeadingActions: Bool) {
    self.canShowLeadingActions = canShowLeadingActions
  }
}

/// Helper struct for day sheet selection (must be Identifiable for .sheet(item:))
private struct DayItemSelection: Identifiable {
  let id: UUID = UUID()
  let dateISO: String
  let items: [DayPresentationItem]
}

private struct EventSheetSelection: Identifiable {
  let id: UUID = UUID()
  let event: EventRow
  let startInEditMode: Bool
}

/// An action queued to run once the sheet that triggered it has finished dismissing.
/// Presenting a new sheet while another is still animating out is a no-op in SwiftUI,
/// so this replaces `DispatchQueue.main.asyncAfter` guesswork with a real `onDismiss` hook.
private enum PendingScheduleSheetAction {
  case shiftDetails(ShiftWithComputations)
  case eventDetails(EventSheetSelection)
  case shiftDelete(ShiftWithComputations)
  case eventDelete(EventRow)
  case recurringEdit(RecurringShiftRow)
  case calendarSubscriptionSettings
}

/// Represents an item in the shifts list - either a shift card or today's placeholder
private enum ShiftListItem: Identifiable {
  case shift(ShiftWithComputations)
  case event(EventPresentation)
  case todayPlaceholder

  var id: String {
    switch self {
    case .shift(let shift):
      return shift.id

    case .event(let event):
      return "event-\(event.id)"

    case .todayPlaceholder:
      return "today-placeholder"
    }
  }

  /// The date for sorting purposes
  var sortDate: String {
    switch self {
    case .shift(let shift):
      return shift.shiftDate

    case .event(let event):
      return event.coveredDateISO

    case .todayPlaceholder:
      return todayISO()
    }
  }

  var startSortKey: String {
    switch self {
    case .shift(let shift):
      return shift.startTime

    case .event(let event):
      return event.sortTime

    case .todayPlaceholder:
      return "99:99"
    }
  }

  var sortPriority: Int {
    switch self {
    case .event(let event):
      return event.isAllDay ? 0 : 1

    case .shift:
      return 1

    case .todayPlaceholder:
      return 2
    }
  }
}

private struct ListWeekGroup: Identifiable {
  let weekKey: String
  let weekNumber: Int
  let totalGross: Double
  let items: [ShiftListItem]
  let isOutsideMonth: Bool

  var id: String { weekKey }
}

/// Shifts tab view - displays list of user's shifts grouped by week
/// Supports month navigation, pull-to-refresh, swipe gestures, and calendar/list view toggle
internal struct ShiftsView: View {  // swiftlint:disable:this type_body_length
  @Environment(AppCoordinator.self) private var coordinator
  @Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize: DynamicTypeSize

  /// Binding to the selected tab for navigation (to switch to Add tab)
  @Binding internal var selectedTab: MainTabView.Tab

  @State private var viewModel: ShiftsViewModel = ShiftsViewModel()
  private let calendarSubscriptionStore: CalendarSubscriptionStore =
    CalendarSubscriptionStore.shared
  @State private var workSetupPresentationViewModel: WorkSetupPresentationViewModel =
    WorkSetupPresentationViewModel()
  private let celebrationManager: CelebrationManager = CelebrationManager.shared
  private let syncStatusManager: SyncStatusManager = SyncStatusManager.shared
  private let shiftsToolbarCoordinator = ShiftsToolbarCoordinator.shared
  @State private var operationErrorMessage: String?

  // Sheet state for shift details (using item-based presentation to fix first-tap bug)
  @State private var selectedShift: ShiftWithComputations?
  @State private var selectedEvent: EventSheetSelection?
  @State private var showDeleteConfirmation: Bool = false
  @State private var shiftToDelete: ShiftWithComputations?
  @State private var showEventDeleteConfirmation: Bool = false
  @State private var eventToDelete: EventRow?

  // Edit mode state (when opening from swipe action)
  @State private var shiftToEditDirectly: ShiftWithComputations?

  // State for day shifts sheet (when tapping a calendar day)
  @State private var selectedDayForSheet: DayItemSelection?
  @State private var selectedDaySheetContentHeight: CGFloat =
    ContentSizedSheetMetrics.defaultContentHeight

  // Recurring shift editor state
  @State private var recurringShiftToEdit: RecurringShiftRow?
  @State private var showCalendarSubscriptionSettings: Bool = false

  // Action to run once the currently-presented sheet finishes dismissing, so two sheets
  // never race to present at once (see `performPendingSheetAction`).
  @State private var pendingSheetAction: PendingScheduleSheetAction?

  // List scroll state (hidden until scrolled to today to prevent flash)
  @State private var listReady: Bool = false
  @State private var scrollToTodayWhenCurrentMonthLoads: Bool = false

  // Deep link navigation state
  @State private var highlightedDateISO: String?
  @State private var highlightedShiftIds: Set<String> = []
  @State private var deepLinkAction: AppCoordinator.ShiftDeepLinkAction = .open
  @State private var deepLinkHighlightDates: Set<String> = []
  @State private var deepLinkHighlightClearTask: Task<Void, Never>?

  // Share functionality state
  @State private var showingShareDestinationPicker: Bool = false
  @State private var showingShareOptions: Bool = false
  @State private var showingSendToChatSheet: Bool = false
  @Environment(\.colorScheme) private var colorScheme: ColorScheme

  // View mode toggle (calendar vs list) - persisted across app launches
  @AppStorage("shiftsViewMode") private var showListView: Bool = false
  @State private var selectedListJobId: String?
  @State private var filteredListShiftsCache: [ShiftWithComputations] = []
  @State private var shiftListItemsCache: [ShiftListItem] = []
  @State private var weekGroupsWithPlaceholderCache: [ListWeekGroup] = []
  /// False only for a user with no shifts at all, who sees the first-shift prompt.
  @State private var hasAnyShifts: Bool = true

  private func shouldKeepShiftDetailsOpen(
    after editResult: ShiftEditResult,
    originalShift: ShiftWithComputations
  ) -> Bool {
    editResult.noteWasEdited
      && editResult.customSupplements == nil
      && editResult.shiftDate == originalShift.shiftDate
      && editResult.startTime == String(originalShift.startTime.prefix(5))
      && editResult.endTime == String(originalShift.endTime.prefix(5))
  }

  private func openCalendarSubscriptionSetupFromShifts() {
    pendingSheetAction = .calendarSubscriptionSettings
    selectedShift = nil
    selectedEvent = nil
  }

  /// Runs the sheet queued by `pendingSheetAction`, called from the dismissed sheet's
  /// `onDismiss`. Attach this to every `.sheet` that can set `pendingSheetAction`.
  private func performPendingSheetAction() {
    guard let action = pendingSheetAction else { return }
    pendingSheetAction = nil
    switch action {
    case .shiftDetails(let shift):
      selectedShift = shift
    case .eventDetails(let selection):
      selectedEvent = selection
    case .shiftDelete(let shift):
      shiftToDelete = shift
      showDeleteConfirmation = true
    case .eventDelete(let event):
      eventToDelete = event
      showEventDeleteConfirmation = true
    case .recurringEdit(let recurring):
      recurringShiftToEdit = recurring
    case .calendarSubscriptionSettings:
      showCalendarSubscriptionSettings = true
    }
  }

  // Orientation tracking for iPad landscape layout
  private let orientationTracker: OrientationTracker = OrientationTracker.shared

  /// Whether to show iPad landscape side-by-side layout (calendar + list)
  private var isIPadLandscape: Bool {
    UIDevice.current.userInterfaceIdiom == .pad && orientationTracker.isLandscape
  }

  /// Whether running on iPhone-sized idiom.
  private var isIPhone: Bool {
    UIDevice.current.userInterfaceIdiom == .phone
  }

  @discardableResult
  private func refreshWorkSetupPresentationState() -> Bool {
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

  private func loadShiftsContent() async {
    guard selectedTab == .shifts else {
      return
    }
    guard !shouldShowWorkSetupRequiredPlaceholder else {
      return
    }
    await calendarSubscriptionStore.refreshIfNeeded()
    await viewModel.loadShifts()
  }

  private func handleSuccessfulSyncSummary(_ summary: SyncCompletionSummary?) {
    guard let summary, summary.userId == coordinator.userId else {
      return
    }
    refreshHasAnyShifts()
    guard summary.reason != .appLaunch else {
      return
    }
    guard let context = summary.scheduleChangeContext else {
      return
    }

    guard !shouldShowWorkSetupRequiredPlaceholder else {
      viewModel.markLocalDataStale()
      return
    }

    guard !(summary.reason == .manualRefresh && selectedTab == .shifts) else {
      return
    }

    Task {
      await viewModel.handleExternalShiftsDidChange(context)
    }
  }

  private func shouldIgnoreWorkSetupNotification(_ notification: Notification) -> Bool {
    notification.userInfo?["syncReason"] as? String == SyncReason.manualRefresh.rawValue
      && notification.userInfo?["userId"] as? String == coordinator.userId
      && selectedTab == .shifts
  }

  // MARK: - Body

  @ViewBuilder
  private var mainContentLayer: some View {
    if shouldShowWorkSetupRequiredPlaceholder {
      WorkSetupRequiredPlaceholder()
    } else if let error = viewModel.error, viewModel.shifts.isEmpty {
      errorView(error: error)
    } else {
      // Unified content view - handles both empty and populated states
      // This ensures StaggeredCardsContainer persists across month changes
      shiftsContent
    }
  }

  @ToolbarContentBuilder
  private var shiftsToolbarContent: some ToolbarContent {
    TabTitleToolbarItem(title: .tabsShifts)
    if !showListView, !shouldShowWorkSetupRequiredPlaceholder {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          startCalendarShare()
        } label: {
          Image(systemName: "square.and.arrow.up")
            .accessibilityHidden(true)
            .offset(y: -1)
        }
        .accessibilityLabel(Text(.shiftsShareMonthTitle))
      }
    }
  }

  private var syncStatusOverlay: some View {
    VStack {
      SyncStatusIndicator {
        Task {
          await viewModel.refresh()
        }
      }
      .padding(.top, Spacing.xs)
      Spacer()
    }
  }

  private var navigationContent: some View {
    NavigationStack {
      ZStack(alignment: .bottom) {
        // Background that fills entire screen including safe areas
        TidexAppBackground()

        // Content area - fills entire screen, content scrolls behind month picker
        mainContentLayer
          .frame(maxWidth: .infinity, maxHeight: .infinity)

        // Month picker is now in shared overlay in MainTabView

        if !shouldShowWorkSetupRequiredPlaceholder {
          syncStatusOverlay
        }
      }
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        shiftsToolbarContent
      }
      .addShiftDestination(in: .shifts)
      .onAppear {
        publishToolbarState()
      }
      .onChange(of: showListView) { _, _ in
        publishToolbarState()
      }
      .onChange(of: shouldShowWorkSetupRequiredPlaceholder) { _, _ in
        publishToolbarState()
      }
      .iPadToolbarTransaction()
    }
  }

  internal var body: some View {
    bodyWithSecondarySheets
  }

  private var baseBody: AnyView {
    AnyView(navigationContent)
  }

  private var bodyWithLifecycle: AnyView {
    AnyView(
      baseBody
        .task {
          viewModel.setActiveTabVisible(selectedTab == .shifts)
          refreshWorkSetupPresentationState()
          refreshHasAnyShifts()
          await loadShiftsContent()
        }
        .onChange(of: coordinator.initialSyncComplete) { _, completed in
          refreshHasAnyShifts()
          let shouldLoadAfterSetupCompleted = refreshWorkSetupPresentationState()
          guard !shouldShowWorkSetupRequiredPlaceholder else {
            return
          }
          if shouldLoadAfterSetupCompleted {
            Task {
              await loadShiftsContent()
            }
          }
          guard completed else {
            return
          }
          viewModel.markLocalDataStale()
          guard selectedTab == .shifts else {
            return
          }
          Task {
            await viewModel.reloadFromLocal()
          }
        }
        .onChange(of: coordinator.userId) { _, _ in
          refreshWorkSetupPresentationState()
          viewModel.markLocalDataStale()
          guard selectedTab == .shifts else {
            return
          }
          guard !shouldShowWorkSetupRequiredPlaceholder else {
            return
          }
          Task {
            await viewModel.reloadFromLocal()
          }
        }
        .onReceive(NotificationCenter.default.publisher(for: .workSetupDataDidChange)) {
          notification in
          guard !shouldIgnoreWorkSetupNotification(notification) else {
            return
          }
          let shouldLoadAfterSetupCompleted = refreshWorkSetupPresentationState()
          viewModel.markLocalDataStale()
          guard !shouldShowWorkSetupRequiredPlaceholder else {
            return
          }
          if shouldLoadAfterSetupCompleted {
            Task {
              await loadShiftsContent()
            }
            return
          }
          guard selectedTab == .shifts else {
            return
          }
          Task {
            await viewModel.reloadFromLocal()
          }
        }
        .onChange(of: syncStatusManager.lastSuccessfulSyncSummary) { _, summary in
          handleSuccessfulSyncSummary(summary)
        }
        .onChange(of: selectedTab) { oldTab, newTab in
          viewModel.setActiveTabVisible(newTab == .shifts)
          guard newTab == .shifts, oldTab != .shifts else {
            return
          }
          refreshWorkSetupPresentationState()
          handleDeepLink(coordinator.pendingDeepLink)
        }
        .onAppear {
          viewModel.setActiveTabVisible(selectedTab == .shifts)
          refreshWorkSetupPresentationState()
          guard selectedTab == .shifts else {
            return
          }
          guard !shouldShowWorkSetupRequiredPlaceholder else {
            return
          }
          recomputeListDerivedDataIfNeeded()
        }
        .onChange(of: selectedListJobId) { _, _ in
          recomputeListDerivedDataIfNeeded()
        }
        .onChange(of: viewModel.shifts) { _, _ in
          refreshHasAnyShifts()
          recomputeListDerivedDataIfNeeded()
        }
        // A shift added or deleted in another month doesn't change `viewModel.shifts`.
        .onReceive(NotificationCenter.default.publisher(for: .shiftsDidChange)) { _ in
          refreshHasAnyShifts()
        }
        .onChange(of: viewModel.events) { _, _ in
          recomputeListDerivedDataIfNeeded()
        }
        .onChange(of: viewModel.excludedFromTotalIds) { _, _ in
          recomputeListDerivedDataIfNeeded()
        }
        .onChange(of: viewModel.committedYear) { _, _ in
          recomputeListDerivedDataIfNeeded()
        }
        .onChange(of: viewModel.committedMonth) { _, _ in
          recomputeListDerivedDataIfNeeded()
        }
        .onChange(of: viewModel.activeJobs) { _, _ in
          recomputeListDerivedDataIfNeeded()
        }
        // Pass user's currency to all child views
        .userCurrency(viewModel.currency)
    )
  }

  private func applyShiftEdit(
    _ editResult: ShiftEditResult,
    to shift: ShiftWithComputations,
    selection: Binding<ShiftWithComputations?>
  ) async throws {
    let shouldKeepSheetOpen = shouldKeepShiftDetailsOpen(
      after: editResult, originalShift: shift)
    try await viewModel.updateShift(editResult)
    if shouldKeepSheetOpen {
      if let refreshedShift = viewModel.getDisplayedShift(id: editResult.shiftId) {
        selection.wrappedValue = refreshedShift
      }
    } else {
      selection.wrappedValue = nil
    }
  }

  private func shiftDetailsSheet(
    for shift: ShiftWithComputations,
    selection: Binding<ShiftWithComputations?>,
    showsCalendarSubscriptionCTA: Bool,
    startInEditMode: Bool
  ) -> some View {
    let shiftJob = viewModel.shouldShowJobIndicators ? viewModel.jobForShift(shift) : nil
    return ShiftDetailsSheet(
      shift: shift,
      jobName: shiftJob?.name,
      jobColorHex: shiftJob?.color,
      onDelete: {
        pendingSheetAction = .shiftDelete(shift)
        selection.wrappedValue = nil
      },
      onUpdate: { editResult in
        try await applyShiftEdit(editResult, to: shift, selection: selection)
      },
      onUpdatePause: { pauseResult in
        selection.wrappedValue = nil
        Task {
          await viewModel.updateShiftPause(pauseResult)
        }
      },
      onEditRecurring: { recurringId in
        if let recurring = viewModel.getRecurringShift(id: recurringId) {
          pendingSheetAction = .recurringEdit(recurring)
        }
        selection.wrappedValue = nil
      },
      onStopRecurringAfterDate: { recurringId, occurrenceDate in
        try await viewModel.stopRecurringShiftAfterDate(
          recurringId: recurringId,
          occurrenceDate: occurrenceDate
        )
        selection.wrappedValue = nil
      },
      showsCalendarSubscriptionCTA: showsCalendarSubscriptionCTA,
      onShowInCalendarRequested: showsCalendarSubscriptionCTA
        ? { openCalendarSubscriptionSetupFromShifts() } : nil,
      startInEditMode: startInEditMode,
      tariffRules: viewModel.getTariffRules(for: shift.shiftDate)
    )
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.visible)
  }

  private var bodyWithPrimarySheetsAndAlerts: AnyView {
    AnyView(
      bodyWithLifecycle
        // Shift details sheet (item-based to guarantee data availability)
        .sheet(item: $selectedShift, onDismiss: performPendingSheetAction) { shift in
          shiftDetailsSheet(
            for: shift,
            selection: $selectedShift,
            showsCalendarSubscriptionCTA: !calendarSubscriptionStore.isActive,
            startInEditMode: false
          )
        }
        // Sheet for editing directly (opens in edit mode from swipe action)
        .sheet(item: $shiftToEditDirectly, onDismiss: performPendingSheetAction) { shift in
          shiftDetailsSheet(
            for: shift,
            selection: $shiftToEditDirectly,
            showsCalendarSubscriptionCTA: false,
            startInEditMode: true
          )
        }
        .sheet(item: $selectedEvent, onDismiss: performPendingSheetAction) { selection in
          EventDetailsSheet(
            event: selection.event,
            onDelete: {
              pendingSheetAction = .eventDelete(selection.event)
              selectedEvent = nil
            },
            onUpdate: { editResult in
              try await viewModel.updateEvent(editResult)
              selectedEvent = nil
            },
            onInlineReminderUpdate: { editResult in
              try await viewModel.updateEvent(editResult)
            },
            showsCalendarSubscriptionCTA: !calendarSubscriptionStore.isActive,
            onShowInCalendarRequested: {
              openCalendarSubscriptionSetupFromShifts()
            },
            startInEditMode: selection.startInEditMode
          )
          .presentationDetents([.medium, .large])
          .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showCalendarSubscriptionSettings) {
          SettingsView(
            initialDestination: .calendarSync(
              calendarSetupIntent: .setup(mode: .shiftsAndEvents, autoOpen: false)))
        }
        // Delete confirmation alert
        .alert(
          shiftToDelete?.isVirtual == true
            ? String(localized: .shiftsExcludeConfirmTitle)
            : String(localized: .shiftsDeleteConfirmTitle),
          isPresented: $showDeleteConfirmation,
          presenting: shiftToDelete
        ) { shift in
          Button(String(localized: .commonCancel), role: .cancel) {
            shiftToDelete = nil
          }
          Button(
            shift.isVirtual
              ? String(localized: .shiftsExcludeButton)
              : String(localized: .shiftsDeleteButton),
            role: .destructive
          ) {
            Task {
              await deleteShift(shift)
            }
          }
        } message: { shift in
          Text(
            shift.isVirtual
              ? String(localized: .shiftsExcludeConfirmMessage)
              : String(localized: .shiftsDeleteConfirmMessage))
        }
        .alert(
          String(localized: .eventsDeleteConfirmTitle),
          isPresented: $showEventDeleteConfirmation,
          presenting: eventToDelete
        ) { event in
          Button(String(localized: .commonCancel), role: .cancel) {
            eventToDelete = nil
          }
          Button(String(localized: .eventsDeleteButton), role: .destructive) {
            Task {
              await deleteEvent(event)
            }
          }
        } message: { _ in
          Text(.eventsDeleteConfirmMessage)
        }
        .alert(
          String(localized: .commonError),
          isPresented: .init(
            get: { operationErrorMessage != nil },
            set: { if !$0 { operationErrorMessage = nil } }
          )
        ) {
          Button(String(localized: .commonOk), role: .cancel) {
            operationErrorMessage = nil
          }
        } message: {
          if let operationErrorMessage {
            Text(operationErrorMessage)
          }
        }
    )
  }

  private var bodyWithStateObservers: AnyView {
    AnyView(
      bodyWithPrimarySheetsAndAlerts
        .onAppear {
          // Handle any pending deep link on initial appearance
          handleDeepLink(coordinator.pendingDeepLink)
        }
        // Handle view mode switch (toggle is in shared overlay)
        .onChange(of: showListView) { _, isListView in
          if isListView {
            viewModel.clearSelection()
            recomputeListDerivedDataIfNeeded(force: true)
          }
        }
        .onChange(of: orientationTracker.isLandscape) { _, isLandscape in
          if isLandscape {
            recomputeListDerivedDataIfNeeded(force: true)
          }
        }
        .onChange(of: viewModel.activeJobs) { _, jobs in
          guard !jobs.isEmpty else {
            selectedListJobId = nil
            return
          }
          if jobs.count <= 1 {
            selectedListJobId = nil
            return
          }
          if let selectedListJobId,
            !jobs.contains(where: { $0.id == selectedListJobId })
          {
            self.selectedListJobId = nil
          }
        }
        // Disable animations during view mode transition to prevent lag
        .animation(.none, value: showListView)
        // Listen for "use share button" from the screenshot prompt overlay (hosted in MainTabView)
        .onReceive(NotificationCenter.default.publisher(for: .screenshotPromptUseShareButton)) {
          _ in
          startCalendarShare()
        }
        .onChange(of: viewModel.committedMonth) { _, _ in
          // Check if we have a pending deep link for this month
          if let dateISO = highlightedDateISO, !viewModel.isLoading {
            selectShiftFromDeepLink(
              dateISO: dateISO,
              shiftIds: highlightedShiftIds,
              shifts: viewModel.shifts
            )
          }
        }
        // Deep link handling - navigate to specific date from widget
        .onChange(of: coordinator.pendingDeepLink) { _, deepLink in
          handleDeepLink(deepLink)
        }
        // When shifts finish loading, check if we should highlight/select a date from deep link
        .onChange(of: viewModel.isLoading) { _, isLoading in
          if !isLoading, let dateISO = highlightedDateISO {
            kLogger.debug(" Shifts finished loading, checking for deep link date: \(dateISO)")
            selectShiftFromDeepLink(
              dateISO: dateISO,
              shiftIds: highlightedShiftIds,
              shifts: viewModel.shifts
            )
          }
        }
        // Also watch for shifts array changes (handles cases where shifts update without loading state change)
        .onChange(of: viewModel.shifts) { _, shifts in
          if let dateISO = highlightedDateISO, !shifts.isEmpty {
            selectShiftFromDeepLink(
              dateISO: dateISO,
              shiftIds: highlightedShiftIds,
              shifts: shifts
            )
          }
        }
    )
  }

  private var bodyWithSecondarySheets: AnyView {
    AnyView(
      bodyWithStateObservers
        // Day shifts sheet (when tapping a calendar day)
        .sheet(item: $selectedDayForSheet, onDismiss: performPendingSheetAction) { daySelection in
          MixedDaySheet(
            dateISO: daySelection.dateISO,
            items: daySelection.items,
            excludedFromTotalIds: viewModel.excludedFromTotalIds,
            conflictingShiftIds: viewModel.conflictingShiftIds,
            showJobIndicators: viewModel.shouldShowJobIndicators,
            jobForShift: { shift in viewModel.jobForShift(shift) },
            onShiftTapped: { shift in
              pendingSheetAction = .shiftDetails(shift)
              selectedDayForSheet = nil
            },
            onEventTapped: { event in
              pendingSheetAction = .eventDetails(
                EventSheetSelection(event: event, startInEditMode: false))
              selectedDayForSheet = nil
            },
            measuredContentHeight: $selectedDaySheetContentHeight
          )
          .presentationDetents([
            .height(ContentSizedSheetMetrics.detentHeight(for: selectedDaySheetContentHeight))
          ])
          .presentationDragIndicator(.visible)
        }
        // Recurring shift editor sheet
        .sheet(item: $recurringShiftToEdit) { recurring in
          RecurringShiftEditorSheet(
            recurringShift: recurring,
            onSave: { editResult in
              recurringShiftToEdit = nil
              Task {
                await viewModel.updateRecurringShift(editResult)
              }
            },
            onDelete: {
              let recurringId = recurring.id
              recurringShiftToEdit = nil
              Task {
                await viewModel.deleteRecurringShift(recurringId)
              }
            }
          )
          .presentationDetents([.large])
          .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingShareDestinationPicker) {
          ShareDestinationSheet(
            title: .shiftsShareMonthTitle,
            onShareAsImage: {
              showingShareDestinationPicker = false
              showingShareOptions = true
            },
            onShareInChat: {
              showingShareDestinationPicker = false
              showingSendToChatSheet = true
            }
          )
          .presentationDetents([.height(250)])
          .presentationDragIndicator(.visible)
        }
        // Calendar share options sheet
        .sheet(isPresented: $showingShareOptions) {
          CalendarShareOptionsSheet(
            title: .shiftsShareMonthTitle,
            earningsImage: renderCalendarImage(includeEarnings: true),
            hiddenEarningsImage: renderCalendarImage(includeEarnings: false)
          )
          .presentationDetents([.height(260)])
          .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingSendToChatSheet) {
          if let viewerUserId = coordinator.getCurrentUserId() {
            SendAttachmentToChatSheet(
              viewerUserId: viewerUserId,
              buildAttachment: makeCalendarImageDraft(for:),
              onCompleted: { result in
                coordinator.pendingDeepLink = .friendChat(
                  threadId: result.threadId,
                  messageId: nil,
                  senderUserId: nil,
                  typingUserId: nil,
                  navigationRequestId: UUID()
                )
                showingSendToChatSheet = false
              }
            )
          }
        }
    )
  }

  // MARK: - Calendar Share

  private func startCalendarShare() {
    Haptics.play(.medium)
    if coordinator.getCurrentUserId() != nil {
      showingShareDestinationPicker = true
    } else {
      showingShareOptions = true
    }
  }

  private func makeShareableCalendar(includeEarnings: Bool) -> ShareableCalendarView {
    ShareableCalendarView(
      shifts: viewModel.shifts,
      year: viewModel.committedYear,
      month: viewModel.committedMonth,
      currency: viewModel.currency,
      includeEarnings: includeEarnings,
      excludedFromTotalIds: viewModel.excludedFromTotalIds,
      colorScheme: colorScheme
    )
  }

  private func renderCalendarImage(includeEarnings: Bool) -> UIImage? {
    makeShareableCalendar(includeEarnings: includeEarnings).renderAsImage()
  }

  private func makeCalendarImageDraft(for recipient: ShareRecipient) throws
    -> FriendsComposerAttachmentDraft
  {
    guard let image = renderCalendarImage(includeEarnings: recipient.canSeeOwnerEarnings),
      let compressed = ImageCompressor.compress(image)
    else {
      throw CalendarSharePreparationError.unableToPrepareImage
    }

    return .image(ImageAttachment(data: compressed.data, mediaType: compressed.mediaType))
  }

  private enum CalendarSharePreparationError: LocalizedError {
    case unableToPrepareImage

    var errorDescription: String? {
      String(localized: .friendsChatSendToChatPrepareImageFailed)
    }
  }

  // MARK: - Deep Link Handling

  /// Handle pending deep link from widget or notification
  private func handleDeepLink(_ deepLink: AppCoordinator.DeepLink?) {
    guard selectedTab == .shifts,
      case .shifts(let dates, let shiftIds, let action) = deepLink
    else {
      return
    }

    let sortedDates = dates?.sorted() ?? []
    let targetShiftIds = Set(shiftIds ?? [])
    let dateISO =
      sortedDates.first
      ?? viewModel.shifts.first(where: { targetShiftIds.contains($0.id) })?.shiftDate
    guard let dateISO else {
      return
    }

    // Avoid processing the same deep link twice
    if highlightedDateISO == dateISO {
      kLogger.debug(" Deep link already being processed for: \(dateISO)")
      coordinator.clearPendingDeepLink()
      return
    }

    kLogger.debug(" Handling deep link for date: \(dateISO), action: \(action.rawValue)")

    // Store the action to use when selecting the shift
    deepLinkAction = action
    highlightedShiftIds = targetShiftIds
    if action == .highlight {
      showDeepLinkHighlights(for: Set(sortedDates), shiftIds: targetShiftIds)
    }

    // Parse the date to extract year and month
    guard let date = Date.fromISODateString(dateISO) else {
      kLogger.debug(" Failed to parse date: \(dateISO)")
      highlightedShiftIds = []
      coordinator.clearPendingDeepLink()
      return
    }

    let calendar = Calendar.gregorianCurrent
    let targetYear = calendar.component(.year, from: date)
    let targetMonth = calendar.component(.month, from: date)

    // Store the date to highlight/select once shifts are loaded
    // This persists across async operations until we successfully show the shift
    highlightedDateISO = dateISO

    // Clear the deep link immediately to prevent MainTabView from re-processing
    coordinator.clearPendingDeepLink()

    navigateToDeepLinkMonth(
      dateISO: dateISO, year: targetYear, month: targetMonth, shiftIds: targetShiftIds)
  }

  private func navigateToDeepLinkMonth(
    dateISO: String,
    year targetYear: Int,
    month targetMonth: Int,
    shiftIds targetShiftIds: Set<String>
  ) {
    // Navigate to the correct month if not already there
    if viewModel.displayYear != targetYear || viewModel.displayMonth != targetMonth {
      kLogger.debug(" Navigating to \(targetYear)-\(targetMonth)")
      SharedMonthContext.shared.navigateTo(year: targetYear, month: targetMonth)
      // Shifts will load via the month change subscription
      // The onChange(of: viewModel.shifts) will then call selectShiftFromDeepLink
    } else if !viewModel.shifts.isEmpty {
      // Already on the correct month and shifts are loaded - select immediately
      selectShiftFromDeepLink(dateISO: dateISO, shiftIds: targetShiftIds, shifts: viewModel.shifts)
    }
    // If shifts are empty, the onChange(of: viewModel.shifts) will handle it when they load
  }

  /// Select or highlight shift for the given date once shifts are loaded
  private func selectShiftFromDeepLink(
    dateISO: String,
    shiftIds: Set<String>,
    shifts: [ShiftWithComputations]
  ) {
    // Parse target date to verify we're looking at the correct month
    guard let targetDate = Date.fromISODateString(dateISO) else {
      kLogger.debug(" Invalid date format: \(dateISO)")
      highlightedDateISO = nil
      highlightedShiftIds = []
      return
    }

    let calendar = Calendar.gregorianCurrent
    let targetYear = calendar.component(.year, from: targetDate)
    let targetMonth = calendar.component(.month, from: targetDate)

    // Make sure we're on the correct committed month before trying to find the shift
    // (committed values indicate data is ready to display)
    guard viewModel.committedYear == targetYear, viewModel.committedMonth == targetMonth else {
      kLogger.debug(
        " Not on target month yet (committed: \(viewModel.committedYear)-\(viewModel.committedMonth), target: \(targetYear)-\(targetMonth))"
      )
      // Keep highlightedDateISO - month navigation is still in progress
      return
    }

    let shiftsOnDate = shifts.filter { shift in
      shift.shiftDate == dateISO && (shiftIds.isEmpty || shiftIds.contains(shift.id))
    }

    guard !shiftsOnDate.isEmpty else {
      kLogger.debug(" No shifts found for date: \(dateISO) (shifts loaded: \(shifts.count))")
      // Clear highlighted date - we're on the right month but there's no shift
      // This handles the case where the shift was deleted
      highlightedDateISO = nil
      highlightedShiftIds = []
      return
    }

    kLogger.debug(
      " Found \(shiftsOnDate.count) shift(s) on \(dateISO), action: \(deepLinkAction.rawValue)")

    // Capture the action before clearing state
    let action = deepLinkAction

    // Clear the highlighted date and reset action since we're handling it now
    highlightedDateISO = nil
    highlightedShiftIds = []
    deepLinkAction = .open  // Reset to default

    // Small delay to allow view to stabilize after month navigation
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
      Haptics.play(.selection)

      // Only open sheets when action is .open (default behavior from notifications)
      // When action is .highlight (from widgets), show visual highlight instead
      if action == .highlight {
        kLogger.debug(" Highlight-only mode - showing visual highlight for \(dateISO)")
        showDeepLinkHighlights(for: [dateISO], shiftIds: shiftIds)
        return
      }

      if shiftsOnDate.count == 1, let shift = shiftsOnDate.first {
        // Single shift - open shift details directly
        selectedShift = shift
      } else {
        // Multiple shifts - open day sheet
        presentDaySheet(
          dateISO: dateISO,
          items: shiftsOnDate.map { DayPresentationItem.shift($0) }
        )
      }
    }
  }

  private func showDeepLinkHighlights(for dates: Set<String>, shiftIds: Set<String>) {
    guard !dates.isEmpty || !shiftIds.isEmpty else {
      return
    }
    deepLinkHighlightClearTask?.cancel()

    MotionTokens.animate(.subtle, reduceMotion: reduceMotion) {
      deepLinkHighlightDates = dates
      highlightedShiftIds = shiftIds
    }

    deepLinkHighlightClearTask = Task { @MainActor in
      do {
        try await Task.sleep(nanoseconds: 8_000_000_000)
      } catch {
        return
      }

      MotionTokens.animate(.subtle, reduceMotion: reduceMotion) {
        deepLinkHighlightDates.subtract(dates)
        highlightedShiftIds.subtract(shiftIds)
      }
      deepLinkHighlightClearTask = nil
    }
  }

  // MARK: - Delete Shift

  private func deleteShift(_ shift: ShiftWithComputations) async {
    Haptics.play(.medium)

    do {
      if shift.isVirtual {
        // Virtual shift: add date to exclusions of parent recurring shift
        guard let recurringId = shift.shift.recurring_id else {
          return
        }
        try await RecurringShiftsRepository.shared.addExclusion(
          id: recurringId,
          date: shift.shiftDate
        )
      } else {
        // Regular shift: mark for deletion
        try await ShiftsRepository.shared.deleteShift(id: shift.id)
      }

      // Post notification for other views
      NotificationCenter.default.postShiftsDidChange(
        context: .affecting(isoDate: shift.shiftDate)
      )

      shiftToDelete = nil
    } catch {
      kLogger.error("Failed to delete shift: \(error.localizedDescription)")
      operationErrorMessage = ErrorTranslations.translate(error)
      shiftToDelete = nil
    }
  }

  private func deleteEvent(_ event: EventRow) async {
    Haptics.play(.medium)

    do {
      try await viewModel.deleteEvent(event)
      eventToDelete = nil
    } catch {
      kLogger.error("Failed to delete event: \(error.localizedDescription)")
      operationErrorMessage = ErrorTranslations.translate(error)
      eventToDelete = nil
    }
  }

  // MARK: - Tap Handlers

  /// Handle shift card tap - simply set the item to present
  /// Using .sheet(item:) guarantees the data is available when sheet shows
  private func handleShiftTapped(_ shift: ShiftWithComputations) {
    selectedShift = shift
  }

  private func handleEventTapped(_ event: EventRow, startInEditMode: Bool = false) {
    selectedEvent = EventSheetSelection(event: event, startInEditMode: startInEditMode)
  }

  /// Present the items attached to a calendar day without changing selection.
  private func presentDayItems(dateISO: String, shifts: [ShiftWithComputations]) {
    let items = viewModel.mixedItems(for: dateISO)

    if items.count == 1, let singleItem = items.first {
      switch singleItem {
      case .shift(let shift):
        selectedShift = shift

      case .event(let event):
        handleEventTapped(event.event)
      }
    } else if !items.isEmpty {
      presentDaySheet(dateISO: dateISO, items: items)
    } else if !shifts.isEmpty {
      presentDaySheet(
        dateISO: dateISO,
        items: shifts.map { DayPresentationItem.shift($0) }
      )
    }
  }

  private func presentDaySheet(dateISO: String, items: [DayPresentationItem]) {
    selectedDaySheetContentHeight = ContentSizedSheetMetrics.estimatedCardListContentHeight(
      cardCount: items.count,
      includesSummaryHeader: false
    )
    selectedDayForSheet = DayItemSelection(dateISO: dateISO, items: items)
  }

  /// Open the selected day's details from the calendar action bar.
  private func handleSelectedDayDetails() {
    guard let dateISO = viewModel.selectedDates.first else {
      return
    }
    presentDayItems(dateISO: dateISO, shifts: viewModel.selectedDateShifts)
  }

  // MARK: - Bottom Toolbar

  private func publishToolbarState() {
    shiftsToolbarCoordinator.update(
      canShowLeadingActions: !shouldShowWorkSetupRequiredPlaceholder
    )
  }

  // MARK: - Transition Phase

  /// Current transition phase for animations
  /// Uses committed values to ensure calendar structure updates atomically with shift data
  private var transitionPhase: MonthTransitionPhase {
    MonthTransitionPhase(
      year: viewModel.committedYear,
      month: viewModel.committedMonth,
      direction: viewModel.navigationDirection
    )
  }

  /// Shared pull-to-refresh action used across calendar and list surfaces.
  private func refreshShiftsContent() async {
    AppearanceTracker.shared.reset()
    await viewModel.refresh()
  }

  // MARK: - Unified Shifts Content

  /// Single unified view that handles both populated and empty states
  /// This ensures StaggeredCardsContainer persists across month changes for consistent animation
  @ViewBuilder
  private var shiftsContent: some View {
    if isIPadLandscape {
      // iPad landscape: side-by-side layout (calendar left, list right)
      iPadLandscapeContent
    } else if showListView {
      // List view mode - just the shift cards without calendar
      listViewContent
    } else {
      // Calendar view mode - calendar + shift list below
      calendarViewContent
    }
  }

  // MARK: - iPad Landscape Content

  /// Side-by-side layout for iPad landscape: calendar on left, shifts list on right
  @ViewBuilder
  private var iPadLandscapeContent: some View {
    HStack(spacing: Spacing.xxxl) {
      Spacer()

      // Left side: Calendar
      calendarPanelForIPad
        .frame(maxWidth: 500)

      // Right side: Shifts list
      shiftsPanelForIPad
        .frame(maxWidth: 480)

      Spacer()
    }
  }

  /// Calendar panel for iPad landscape (left side)
  @ViewBuilder
  private var calendarPanelForIPad: some View {
    PullToRefreshContainer(onRefresh: {
      await refreshShiftsContent()
    }) {  // swiftlint:disable:this closure_body_length
      GeometryReader { _ in  // swiftlint:disable:this closure_body_length
        ZStack {  // swiftlint:disable:this closure_body_length
          // Background layer to dismiss selection when tapping outside calendar
          Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
              if !viewModel.selectedDates.isEmpty {
                viewModel.clearSelection()
              }
            }

          // Calendar content - centered
          VStack {  // swiftlint:disable:this closure_body_length
            Spacer()
            ShiftsCalendarView(
              shifts: viewModel.shifts,
              eventCoverageByDate: viewModel.eventCoverageByDate,
              presentation: viewModel.calendarPresentation,
              month: displayedMonthDate,
              year: viewModel.committedYear,
              monthNumber: viewModel.committedMonth,
              currency: viewModel.currency,
              showEarnings: true,
              jobs: viewModel.activeJobs,
              phase: transitionPhase,
              onDayTapped: { dateISO, shiftsOnDay in
                if viewModel.handleDayTapped(dateISO: dateISO, shiftsOnDay: shiftsOnDay) {
                  presentDayItems(dateISO: dateISO, shifts: shiftsOnDay)
                }
              },
              onSwipeLeft: {
                AppearanceTracker.shared.reset()
                viewModel.goToNextMonth()
              },
              onSwipeRight: {
                AppearanceTracker.shared.reset()
                viewModel.goToPreviousMonth()
              },
              selectedDates: $viewModel.selectedDates,
              confirmingDelete: viewModel.confirmingDelete,
              isDeleting: viewModel.isDeleting,
              selectedEarnings: viewModel.selectedEarnings,
              selectedCurrencyAggregate: viewModel.selectedCurrencyAggregate,
              selectedHasTaxEnabled: viewModel.selectedHasTaxEnabled,
              onDelete: {
                viewModel.confirmingDelete = true
              },
              onConfirmDelete: {
                Task {
                  await viewModel.deleteSelectedShifts()
                }
              },
              onCancelDelete: {
                viewModel.confirmingDelete = false
              },
              onCopy: {
                viewModel.initiateCopy()
              },
              onDetails: {
                handleSelectedDayDetails()
              },
              onEdit: {
                let shiftsOnDate = viewModel.selectedDateShifts
                if let shift = shiftsOnDate.first {
                  shiftToEditDirectly = shift
                }
              },
              onMove: {
                viewModel.initiateMove()
              },
              onClearSelection: {
                viewModel.clearSelection()
              },
              onDragSelect: { dates in
                viewModel.applyDragSelection(dates)
              },
              onEmptyDayTapped: { dateISO in
                if viewModel.isCopyMode || viewModel.isMoveMode {
                  viewModel.cancelCopyMoveMode()
                  return
                }
                // Ignore empty cell taps while dates are selected
                if !viewModel.selectedDates.isEmpty {
                  return
                }
                if let dateISO {
                  openAddShift(preselectedDate: dateISO)
                }
              },
              isCopyMode: viewModel.isCopyMode,
              isMoveMode: viewModel.isMoveMode,
              isCopying: viewModel.isCopying,
              isMoving: viewModel.isMoving,
              copyTargetDates: viewModel.copyTargetDates,
              copyPreviewEarnings: viewModel.copyPreviewEarnings,
              copyPreviewConflictDates: viewModel.copyPreviewConflictDates,
              onCopyToDate: { targetDateISO in
                viewModel.toggleCopyTargetDate(targetDateISO)
              },
              onFinishCopy: {
                Task {
                  await viewModel.finishCopyToSelectedDates()
                }
              },
              onMoveToDate: { targetDateISO in
                Task {
                  await viewModel.handleMoveToDate(targetDateISO)
                }
              },
              onCancelCopyMove: {
                viewModel.cancelCopyMoveMode()
              },
              newlyAddedDates: celebrationManager.newlyAddedDates,
              deepLinkHighlightDates: deepLinkHighlightDates,
              conflictDates: viewModel.conflictDates,
              excludedFromTotalIds: viewModel.excludedFromTotalIds
            )
            .padding(.horizontal, Spacing.md)
            Spacer()
          }
          // Offset for month picker overlay
          .padding(.bottom, MonthPickerLayout.totalBottomInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
  }

  /// Which empty state the list shows instead of its rows, if any.
  private var listEmptyState: ShiftsListEmptyState? {
    ShiftsListPlaceholderPolicy.emptyState(
      hasAnyShifts: hasAnyShifts,
      hasRows: shiftListItems.contains {
        if case .todayPlaceholder = $0 { false } else { true }
      },
      isCurrentMonth: viewModel.isCurrentMonth
    )
  }

  private func refreshHasAnyShifts() {
    hasAnyShifts = ShiftsRepository.shared.hasAnyShifts(
      for: coordinator.userId,
      initialSyncComplete: coordinator.initialSyncComplete
    )
  }

  /// Empty state for a user with no shifts at all, in any month, or for a past or future
  /// month with no shifts. An empty current month shows the today placeholder instead.
  @ViewBuilder
  private func scheduleEmptyState(
    _ state: ShiftsListEmptyState,
    monthName: String,
    isFutureMonth: Bool,
    onAddShift: @escaping () -> Void
  ) -> some View {
    if state == .firstShift {
      FirstShiftEmptyState(onAddShift: onAddShift)
    } else {
      monthEmptyState(monthName: monthName, isFutureMonth: isFutureMonth, onAddShift: onAddShift)
    }
  }

  @ViewBuilder
  private func monthEmptyState(
    monthName: String, isFutureMonth: Bool, onAddShift: @escaping () -> Void
  ) -> some View {
    let title =
      isFutureMonth
      ? String(localized: .shiftsEmptyNoShiftsInMonth(monthName))
      : String(localized: .shiftsEmptyNoShifts)
    let subtitle =
      isFutureMonth
      ? String(localized: .shiftsEmptyPlanAhead)
      : String(localized: .shiftsEmptyNoPastRecords(monthName.lowercased()))
    let iconName = isFutureMonth ? "calendar.badge.clock" : "clock.arrow.circlepath"

    ContentUnavailableView {
      Label(title, systemImage: iconName)
    } description: {
      Text(subtitle)
    } actions: {
      Button(action: onAddShift) {
        Label(String(localized: .shiftsEmptyAddShift), systemImage: "plus")
      }
      .buttonStyle(.borderedProminent)
      .tint(.tidexBlue)
      .accessibilityIdentifier("schedule-empty.add-shift")
    }
  }

  /// Shifts list panel for iPad landscape (right side)
  @ViewBuilder
  private var shiftsPanelForIPad: some View {
    if let listEmptyState {
      ScrollView {
        scheduleEmptyState(
          listEmptyState,
          monthName: viewModel.displayMonthName,
          isFutureMonth: viewModel.isFutureMonth,
          onAddShift: { openAddShift() }
        )
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.xxl)
        .padding(.bottom, MonthPickerLayout.totalBottomInset + Spacing.md)
      }
      .refreshable {
        await refreshShiftsContent()
      }
    } else {
      // Shift list
      ScrollViewReader { proxy in
        List {
          if shouldShowListJobFilter {
            Section {
              listJobFilterBar
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
          }

          ForEach(weekGroupsWithPlaceholder, id: \.weekKey) { weekGroup in
            Section {
              ForEach(weekGroup.items) { item in
                listItemRow(item: item)
                  .opacity(weekGroup.isOutsideMonth ? 0.4 : 1.0)
                  .id(item.id)
              }
            } header: {
              WeekHeaderView(
                weekNumber: weekGroup.weekNumber,
                totalGross: weekGroup.totalGross
              )
              .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
              .listRowBackground(Color.clear)
              .opacity(weekGroup.isOutsideMonth ? 0.4 : 1.0)
            }
          }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .contentMargins(
          .bottom, MonthPickerLayout.totalBottomInset + Spacing.md, for: .scrollContent
        )
        .refreshable {
          await refreshShiftsContent()
        }
        .opacity(listReady ? 1 : 0)
        .onAppear {
          scrollToTodayItem(using: proxy)
        }
        .onDisappear {
          listReady = false
        }
      }
    }
  }

  // MARK: - Calendar View Content

  @ViewBuilder
  private var calendarViewContent: some View {
    PullToRefreshContainer(onRefresh: {
      await refreshShiftsContent()
    }) {  // swiftlint:disable:this closure_body_length
      GeometryReader { _ in  // swiftlint:disable:this closure_body_length
        // Calendar only - no list below. Tapping days opens day sheet.
        ZStack {  // swiftlint:disable:this closure_body_length
          // Background layer to dismiss selection when tapping outside calendar
          Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
              if !viewModel.selectedDates.isEmpty {
                viewModel.clearSelection()
              }
            }

          // Calendar content - centered between toolbar and month picker
          VStack {  // swiftlint:disable:this closure_body_length
            Spacer()
            ShiftsCalendarView(
              shifts: viewModel.shifts,
              eventCoverageByDate: viewModel.eventCoverageByDate,
              presentation: viewModel.calendarPresentation,
              month: displayedMonthDate,
              year: viewModel.committedYear,
              monthNumber: viewModel.committedMonth,
              currency: viewModel.currency,
              showEarnings: true,
              jobs: viewModel.activeJobs,
              phase: transitionPhase,
              onDayTapped: { dateISO, shiftsOnDay in
                if viewModel.handleDayTapped(dateISO: dateISO, shiftsOnDay: shiftsOnDay) {
                  presentDayItems(dateISO: dateISO, shifts: shiftsOnDay)
                }
              },
              onSwipeLeft: {
                AppearanceTracker.shared.reset()
                viewModel.goToNextMonth()
              },
              onSwipeRight: {
                AppearanceTracker.shared.reset()
                viewModel.goToPreviousMonth()
              },
              selectedDates: $viewModel.selectedDates,
              confirmingDelete: viewModel.confirmingDelete,
              isDeleting: viewModel.isDeleting,
              selectedEarnings: viewModel.selectedEarnings,
              selectedCurrencyAggregate: viewModel.selectedCurrencyAggregate,
              selectedHasTaxEnabled: viewModel.selectedHasTaxEnabled,
              onDelete: {
                viewModel.confirmingDelete = true
              },
              onConfirmDelete: {
                Task {
                  await viewModel.deleteSelectedShifts()
                }
              },
              onCancelDelete: {
                viewModel.confirmingDelete = false
              },
              onCopy: {
                viewModel.initiateCopy()
              },
              onDetails: {
                handleSelectedDayDetails()
              },
              onEdit: {
                // Open shift directly in edit mode
                let shiftsOnDate = viewModel.selectedDateShifts
                if let shift = shiftsOnDate.first {
                  shiftToEditDirectly = shift
                }
              },
              onMove: {
                viewModel.initiateMove()
              },
              onClearSelection: {
                viewModel.clearSelection()
              },
              onDragSelect: { dates in
                viewModel.applyDragSelection(dates)
              },
              onEmptyDayTapped: { dateISO in
                // If in copy/move mode, handle that instead
                if viewModel.isCopyMode || viewModel.isMoveMode {
                  // Tapping outside valid dates cancels operation
                  viewModel.cancelCopyMoveMode()
                  return
                }

                // Ignore empty cell taps while dates are selected
                if !viewModel.selectedDates.isEmpty {
                  return
                }

                // No selection active - navigate to Add tab with date pre-selected
                if let dateISO {
                  openAddShift(preselectedDate: dateISO)
                }
              },
              isCopyMode: viewModel.isCopyMode,
              isMoveMode: viewModel.isMoveMode,
              isCopying: viewModel.isCopying,
              isMoving: viewModel.isMoving,
              copyTargetDates: viewModel.copyTargetDates,
              copyPreviewEarnings: viewModel.copyPreviewEarnings,
              copyPreviewConflictDates: viewModel.copyPreviewConflictDates,
              onCopyToDate: { targetDateISO in
                viewModel.toggleCopyTargetDate(targetDateISO)
              },
              onFinishCopy: {
                Task {
                  await viewModel.finishCopyToSelectedDates()
                }
              },
              onMoveToDate: { targetDateISO in
                Task {
                  await viewModel.handleMoveToDate(targetDateISO)
                }
              },
              onCancelCopyMove: {
                viewModel.cancelCopyMoveMode()
              },
              newlyAddedDates: celebrationManager.newlyAddedDates,
              deepLinkHighlightDates: deepLinkHighlightDates,
              conflictDates: viewModel.conflictDates,
              excludedFromTotalIds: viewModel.excludedFromTotalIds
            )
            .frame(maxWidth: isIPhone ? .infinity : AdaptiveMaxWidth.tabContent)
            .padding(.horizontal, isIPhone ? Spacing.xs : Spacing.md)
            if !hasAnyShifts {
              FirstShiftPrompt { openAddShift() }
                .frame(maxWidth: AdaptiveMaxWidth.tabContent)
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.md)
            }
            Spacer()
          }
          // Offset for month picker overlay so content centers in available space
          .padding(.bottom, MonthPickerLayout.totalBottomInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
  }

  // MARK: - List View Content

  @ViewBuilder
  private var listViewContent: some View {
    // An empty current month shows the today placeholder card in the list, unless the
    // user has no shifts at all
    if let listEmptyState {
      ScrollView {
        scheduleEmptyState(
          listEmptyState,
          monthName: viewModel.displayMonthName,
          isFutureMonth: viewModel.isFutureMonth,
          onAddShift: { openAddShift() }
        )
        .frame(maxWidth: AdaptiveMaxWidth.tabContent)
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.xxl)
        // Add bottom padding for floating MonthPicker
        .padding(.bottom, MonthPickerLayout.totalBottomInset + Spacing.md)
      }
      .refreshable {
        await refreshShiftsContent()
      }
    } else {
      // Shift list (includes today placeholder for current month if no shift today)
      shiftListContent
        .refreshable {
          await refreshShiftsContent()
        }
    }
  }

  // MARK: - Shift List Content (shared between calendar and list modes)

  private var shouldShowListJobFilter: Bool {
    viewModel.activeJobs.count > 1
  }

  private var shouldMaintainListDerivedData: Bool {
    showListView || isIPadLandscape
  }

  private var defaultActiveJobId: String? {
    viewModel.activeJobs.first(where: \.is_default)?.id
  }

  private var filteredListShifts: [ShiftWithComputations] {
    filteredListShiftsCache
  }

  private var shiftListItems: [ShiftListItem] {
    shiftListItemsCache
  }

  private var weekGroupsWithPlaceholder: [ListWeekGroup] {
    weekGroupsWithPlaceholderCache
  }

  /// Recompute list-derived collections when upstream inputs change.
  private func recomputeListDerivedDataIfNeeded(force: Bool = false) {
    guard force || shouldMaintainListDerivedData else {
      return
    }
    recomputeListDerivedData()
  }

  /// Recompute list-derived collections when upstream inputs change.
  private func recomputeListDerivedData() {
    let validJobIds = Set(viewModel.activeJobs.map(\.id))
    if let selectedListJobId, !validJobIds.contains(selectedListJobId) {
      self.selectedListJobId = nil
    }

    let listMonth = ScheduleListMonth(
      year: viewModel.committedYear, month: viewModel.committedMonth)
    let filtered = filteredListShifts(in: listMonth)
    filteredListShiftsCache = filtered

    let items = sortedListItems(filteredShifts: filtered, listMonth: listMonth)
    shiftListItemsCache = items

    weekGroupsWithPlaceholderCache = weekGroups(for: items)
  }

  private func filteredListShifts(in listMonth: ScheduleListMonth) -> [ShiftWithComputations] {
    let monthShifts = viewModel.shifts.filter { listMonth.contains($0.shiftDate) }
    guard let selectedListJobId else { return monthShifts }
    let defaultJobId = defaultActiveJobId
    return monthShifts.filter { shift in
      if shift.shift.job_id == selectedListJobId {
        return true
      }
      // Compatibility fallback for legacy rows that can still have nil job_id.
      return shift.shift.job_id == nil && selectedListJobId == defaultJobId
    }
  }

  private func sortedListItems(
    filteredShifts filtered: [ShiftWithComputations],
    listMonth: ScheduleListMonth
  ) -> [ShiftListItem] {
    var items: [ShiftListItem] = filtered.map { .shift($0) }
    items.append(
      contentsOf: viewModel.events.filter {
        listMonth.overlaps(start: $0.start_date, end: $0.end_date)
      }.map {
        .event(EventPresentation(event: $0, coveredDateISO: listCoveredDateISO(for: $0)))
      }
    )
    if viewModel.isCurrentMonth {
      let today = todayISO()
      if ShiftsListPlaceholderPolicy.shouldShowTodayPlaceholder(
        isCurrentMonth: viewModel.isCurrentMonth,
        filteredShifts: filtered,
        eventCoverageByDate: viewModel.eventCoverageByDate,
        todayISO: today
      ) {
        items.append(.todayPlaceholder)
      }
    }
    items.sort { lhs, rhs in
      if lhs.sortDate != rhs.sortDate {
        return lhs.sortDate < rhs.sortDate
      }
      if lhs.sortPriority != rhs.sortPriority {
        return lhs.sortPriority < rhs.sortPriority
      }
      if lhs.startSortKey != rhs.startSortKey {
        return lhs.startSortKey < rhs.startSortKey
      }
      return lhs.id < rhs.id
    }
    return items
  }

  private func weekGroups(for items: [ShiftListItem]) -> [ListWeekGroup] {
    var calendar = Calendar(identifier: .iso8601)
    calendar.firstWeekday = 2  // Monday
    calendar.minimumDaysInFirstWeek = 4

    var weekMap:
      [String: (weekNumber: Int, year: Int, totalGross: Double, items: [ShiftListItem])] = [:]

    for item in items {
      guard let date = Date.fromISODateString(item.sortDate) else { continue }

      let weekOfYear = calendar.component(.weekOfYear, from: date)
      let yearForWeek = calendar.component(.yearForWeekOfYear, from: date)
      let weekKey = "\(yearForWeek)-W\(String(format: "%02d", weekOfYear))"

      // Calculate gross (only for shifts, excluding conflicting shifts)
      let itemGross: Double
      if case .shift(let shift) = item {
        // Don't include excluded shifts in totals
        itemGross = viewModel.excludedFromTotalIds.contains(shift.id) ? 0 : shift.grossPay
      } else {
        itemGross = 0
      }

      if var existing = weekMap[weekKey] {
        existing.items.append(item)
        existing.totalGross += itemGross
        weekMap[weekKey] = existing
      } else {
        weekMap[weekKey] = (
          weekNumber: weekOfYear, year: yearForWeek, totalGross: itemGross, items: [item]
        )
      }
    }

    // Convert to array and sort
    let committedPrefix = String(
      format: "%04d-%02d", viewModel.committedYear, viewModel.committedMonth)
    return weekMap.map { entry in
      let isOutside = !entry.value.items.contains { $0.sortDate.hasPrefix(committedPrefix) }
      return ListWeekGroup(
        weekKey: entry.key, weekNumber: entry.value.weekNumber, totalGross: entry.value.totalGross,
        items: entry.value.items,
        isOutsideMonth: isOutside
      )
    }
    .sorted { $0.weekKey < $1.weekKey }
  }

  @ViewBuilder
  private var shiftListContent: some View {
    // Styled with .listRowBackground() and .listRowSeparator(.hidden) for custom look.
    // Row swipe actions use .swipeActions on each List row.
    ScrollViewReader { proxy in
      List {
        shiftListSections
      }
      .listStyle(.plain)
      .scrollContentBackground(.hidden)
      .background(Color.clear)
      .frame(maxWidth: AdaptiveMaxWidth.tabContent)
      .frame(maxWidth: .infinity)
      // Add bottom padding so last items can scroll above the floating MonthPicker
      .contentMargins(.bottom, MonthPickerLayout.totalBottomInset + Spacing.md, for: .scrollContent)
      .opacity(listReady ? 1 : 0)
      .onAppear {
        scrollToTodayItem(using: proxy)
      }
      .onDisappear {
        listReady = false
      }
      .onReceive(NotificationCenter.default.publisher(for: .tabReselected)) { notification in
        handleTabReselected(notification, proxy: proxy)
      }
      .onChange(of: viewModel.isCurrentMonth) { _, isCurrentMonth in
        guard isCurrentMonth, scrollToTodayWhenCurrentMonthLoads else { return }
        scrollToTodayWhenCurrentMonthLoads = false
        // Wait for the list rows of the new month before scrolling.
        Task { @MainActor in
          withAnimation { scrollToTodayItem(using: proxy) }
        }
      }
    }
  }

  @ViewBuilder
  private var shiftListSections: some View {
    if shouldShowListJobFilter {
      Section {
        listJobFilterBar
          .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
          .listRowBackground(Color.clear)
          .listRowSeparator(.hidden)
      }
    }

    ForEach(weekGroupsWithPlaceholder, id: \.weekKey) { weekGroup in
      Section {
        ForEach(weekGroup.items) { item in
          listItemRow(item: item)
            .opacity(weekGroup.isOutsideMonth ? 0.4 : 1.0)
            .id(item.id)
        }
      } header: {
        WeekHeaderView(
          weekNumber: weekGroup.weekNumber,
          totalGross: weekGroup.totalGross
        )
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
        .listRowBackground(Color.clear)
        .opacity(weekGroup.isOutsideMonth ? 0.4 : 1.0)
      }
    }
  }

  private func handleTabReselected(_ notification: Notification, proxy: ScrollViewProxy) {
    guard let tab = notification.userInfo?["tab"] as? MainTabView.Tab,
      tab == .shifts, showListView
    else { return }
    let scrollToToday = notification.userInfo?["scrollToToday"] as? Bool ?? false
    if scrollToToday, !viewModel.isCurrentMonth {
      // The current month is still loading; scroll once it is shown.
      scrollToTodayWhenCurrentMonthLoads = true
    } else if scrollToToday {
      withAnimation { scrollToTodayItem(using: proxy) }
    } else if let firstId = weekGroupsWithPlaceholder.first?.items.first?.id {
      withAnimation { proxy.scrollTo(firstId, anchor: .top) }
    }
  }

  /// Render a single list item (shift or placeholder)
  @ViewBuilder
  private func listItemRow(item: ShiftListItem) -> some View {
    switch item {
    case .shift(let shift):
      shiftListRow(shift)

    case .event(let event):
      eventListRow(event)

    case .todayPlaceholder:
      TodayPlaceholderCard(onTap: {
        Haptics.play(.selection)
        // Navigate to add shift with today's date pre-selected
        openAddShift(preselectedDate: todayISO())
      })
      .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
      .listRowBackground(Color.clear)
      .listRowSeparator(.hidden)
    }
  }

  private func shiftListRow(_ shift: ShiftWithComputations) -> some View {
    shiftCardRow(shift: shift)
      .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
      .listRowBackground(Color.clear)
      .listRowSeparator(.hidden)
      .swipeActions(edge: .leading) {
        Button {
          Haptics.play(.selection)
          shiftToEditDirectly = shift
        } label: {
          Label(String(localized: .shiftsActionsEdit), systemImage: "pencil")
        }
        .tint(.tidexBlue)
      }
      .swipeActions(edge: .trailing) {
        SwipeDeleteButton {
          Haptics.play(.medium)
          shiftToDelete = shift
          showDeleteConfirmation = true
        }
      }
  }

  private func eventListRow(_ event: EventPresentation) -> some View {
    EventRowCard(
      event: event.event,
      coveredDateISO: event.coveredDateISO,
      onTap: {
        Haptics.play(.selection)
        handleEventTapped(event.event)
      }
    )
    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
    .listRowBackground(Color.clear)
    .listRowSeparator(.hidden)
    .swipeActions(edge: .leading) {
      Button {
        Haptics.play(.selection)
        handleEventTapped(event.event, startInEditMode: true)
      } label: {
        Label(String(localized: .shiftsActionsEdit), systemImage: "pencil")
      }
      .tint(.tidexBlue)
    }
    .swipeActions(edge: .trailing) {
      SwipeDeleteButton {
        Haptics.play(.medium)
        eventToDelete = event.event
        showEventDeleteConfirmation = true
      }
    }
  }

  /// Opens the Add sheet in single mode, optionally with a date selected.
  private func openAddShift(preselectedDate dateISO: String? = nil) {
    SharedMonthContext.shared.preselectedDate = dateISO
    coordinator.pendingDeepLink = .addShift(mode: .single, date: dateISO)
  }

  private func listCoveredDateISO(for event: EventRow) -> String {
    guard
      event.is_all_day,
      let monthStart = Calendar.gregorianCurrent.date(
        from: DateComponents(year: viewModel.committedYear, month: viewModel.committedMonth, day: 1)
      )
    else {
      return event.start_date
    }

    let monthStartISO = monthStart.toISODateString()
    if event.start_date < monthStartISO, event.end_date >= monthStartISO {
      return monthStartISO
    }

    return event.start_date
  }

  @ViewBuilder
  private var listJobFilterBar: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      HStack(spacing: Spacing.xxxs) {
        Image(systemName: "line.3.horizontal.decrease.circle")
          .font(.tidexFootnote)
          .foregroundColor(.tidexTextMuted)
        Text(.jobsFilterTitle)
          .font(.tidexLabel)
          .foregroundColor(.tidexTextSecondary)
      }

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: Spacing.xs) {
          listJobFilterChip(
            title: String(localized: .jobsFilterAll),
            colorHex: nil,
            isWorkplace: false,
            isSelected: selectedListJobId == nil
          ) {
            selectedListJobId = nil
          }

          ForEach(viewModel.activeJobs) { job in
            listJobFilterChip(
              title: job.name,
              colorHex: job.color,
              isWorkplace: true,
              isSelected: selectedListJobId == job.id
            ) {
              selectedListJobId = job.id
            }
          }
        }
      }
    }
    .padding(.vertical, Spacing.xxxs)
  }

  @ViewBuilder
  private func listJobFilterChip(
    title: String,
    colorHex: String?,
    isWorkplace: Bool,
    isSelected: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      if isWorkplace {
        // The job color fills the whole chip; a ring marks the selected one.
        WorkplaceNameText(
          name: title,
          colorHex: colorHex,
          font: .tidexFootnoteStrong,
          fallbackBadgeColor: .tidexBlue,
          badgeCornerRadius: 999,  // SwiftUI clamps this to a capsule
          badgeHorizontalPadding: Spacing.sm,
          badgeVerticalPadding: Spacing.xs
        )
        .overlay {
          if isSelected {
            Capsule().strokeBorder(Color.tidexTextPrimary, lineWidth: 2)
          }
        }
        // Grey out the other jobs while one job is selected.
        .grayscale(selectedListJobId != nil && !isSelected ? 1 : 0)
        .opacity(selectedListJobId != nil && !isSelected ? 0.6 : 1)
      } else {
        Text(title)
          .font(.tidexFootnoteStrong)
          .foregroundColor(isSelected ? .white : .tidexTextPrimary)
          .padding(.horizontal, Spacing.sm)
          .padding(.vertical, Spacing.xs)
          .background(isSelected ? Color.tidexBrandPrimary : Color.tidexSurfaceSecondary)
          .clipShape(Capsule())
      }
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  /// Individual shift card row (visual content only - swipe actions are on List row)
  @ViewBuilder
  private func shiftCardRow(shift: ShiftWithComputations) -> some View {
    let isNextUpcoming = viewModel.nextUpcomingShift?.id == shift.id
    let shiftJob = viewModel.jobForShift(shift)

    VStack(spacing: Spacing.xs) {
      ShiftRowCard(
        shift: shift,
        isToday: shift.shiftDate == todayISO(),
        hasConflict: viewModel.conflictingShiftIds.contains(shift.id),
        excludedFromTotal: viewModel.excludedFromTotalIds.contains(shift.id),
        isDeepLinkHighlighted: highlightedShiftIds.contains(shift.id),
        showJobIndicator: viewModel.shouldShowJobIndicators,
        jobName: shiftJob?.name,
        jobColorHex: shiftJob?.color,
        onTap: {
          Haptics.play(.selection)
          handleShiftTapped(shift)
        }
      )

      // Show countdown text below next upcoming shift
      if isNextUpcoming {
        NextShiftCountdownText(shift: shift)
          .padding(.bottom, Spacing.sm)
      }
    }
  }

  /// Scroll the list to the top-most conflict card when conflicts exist,
  /// otherwise to today's shift card/placeholder, then reveal the list.
  private func scrollToTodayItem(using proxy: ScrollViewProxy) {
    if let conflictTargetId = shiftListItems.first(where: { item in
      guard case .shift(let shift) = item else {
        return false
      }
      return viewModel.conflictingShiftIds.contains(shift.id)
    })?.id {
      proxy.scrollTo(conflictTargetId, anchor: .top)
    } else if viewModel.isCurrentMonth {
      let today = todayISO()
      if let todayTargetId = shiftListItems.first(where: { $0.sortDate == today })?.id {
        proxy.scrollTo(todayTargetId, anchor: .top)
      }
    }
    listReady = true
  }

  /// Convert displayed year/month to a Date for the calendar
  /// Uses committed values to ensure calendar structure updates atomically with shift data
  private var displayedMonthDate: Date {
    var components = DateComponents()
    components.year = viewModel.committedYear
    components.month = viewModel.committedMonth
    components.day = 1
    return Calendar.gregorianCurrent.date(from: components) ?? Date()
  }

  // MARK: - Error View

  @ViewBuilder
  private func errorView(error: Error) -> some View {
    VStack(spacing: Spacing.md) {
      Image(systemName: "exclamationmark.triangle")
        .font(.system(size: 48))
        .foregroundColor(.tidexWarning)
        .accessibilityHidden(true)

      Text(.shiftsLoadError)
        .font(.tidexBodyMedium)
        .foregroundColor(.tidexTextPrimary)

      Text(error.localizedDescription)
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextSecondary)
        .multilineTextAlignment(.center)

      Button {
        Task { await viewModel.loadShifts() }
      } label: {
        Text(.commonRetry)
          .font(.tidexLabel)
          .foregroundColor(.tidexBlue)
          .padding(.horizontal, Spacing.mlg)
          .padding(.vertical, Spacing.sm)
          .background(Color.tidexBlue.opacity(0.1))
          .cornerRadius(CornerRadius.sm)
      }
    }
    .frame(maxWidth: AdaptiveMaxWidth.tabContent)
    .padding(.horizontal, Spacing.xxl)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

// MARK: - Preview

#Preview {
  struct PreviewWrapper: View {
    @State private var selectedTab: MainTabView.Tab = .shifts

    var body: some View {
      ShiftsView(selectedTab: $selectedTab)
        .environment(AppCoordinator.shared)
    }
  }

  return PreviewWrapper()
}  // swiftlint:disable:this file_length
