import Observation
import SwiftUI
// swiftlint:disable:next sorted_imports
import os.log

let scheduleViewLogger: Logger = Logger(subsystem: "no.tidex.app", category: "ShiftsView")

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

/// Shifts tab view - displays list of user's shifts grouped by week
/// Supports month navigation, pull-to-refresh, swipe gestures, and calendar/list view toggle
internal struct ShiftsView: View {  // swiftlint:disable:this type_body_length
  @Environment(AppCoordinator.self) var coordinator
  @Environment(\.accessibilityReduceMotion) var reduceMotion: Bool
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize: DynamicTypeSize

  /// Binding to the selected tab for navigation (to switch to Add tab)
  @Binding internal var selectedTab: MainTabView.Tab

  @State var viewModel: ShiftsViewModel = ShiftsViewModel()
  private let calendarSubscriptionStore: CalendarSubscriptionStore =
    CalendarSubscriptionStore.shared
  @State private var workSetupPresentationViewModel: WorkSetupPresentationViewModel =
    WorkSetupPresentationViewModel()
  let celebrationManager: CelebrationManager = CelebrationManager.shared
  private let syncStatusManager: SyncStatusManager = SyncStatusManager.shared
  let shiftsToolbarCoordinator = ShiftsToolbarCoordinator.shared
  @State var operationErrorMessage: String?

  // Sheet state for shift details (using item-based presentation to fix first-tap bug)
  @State var selectedShift: ShiftWithComputations?
  @State var selectedEvent: EventSheetSelection?
  @State private var addShiftPath: [AddShiftRoute] = []
  @State var showDeleteConfirmation: Bool = false
  @State var shiftToDelete: ShiftWithComputations?
  @State var showEventDeleteConfirmation: Bool = false
  @State var eventToDelete: EventRow?

  // Edit mode state (when opening from swipe action)
  @State var shiftToEditDirectly: ShiftWithComputations?

  // State for day shifts sheet (when tapping a calendar day)
  @State var selectedDayForSheet: DayItemSelection?
  @State var selectedDaySheetContentHeight: CGFloat =
    ContentSizedSheetMetrics.defaultContentHeight

  // Recurring shift editor state
  @State private var recurringShiftToEdit: RecurringShiftRow?
  @State private var showCalendarSubscriptionSettings: Bool = false

  // Action to run once the currently-presented sheet finishes dismissing, so two sheets
  // never race to present at once (see `performPendingSheetAction`).
  @State private var pendingSheetAction: PendingScheduleSheetAction?

  // List scroll state (hidden until scrolled to today to prevent flash)
  @State var listReady: Bool = false
  @State var scrollToTodayWhenCurrentMonthLoads: Bool = false

  // Deep link navigation state
  @State var highlightedDateISO: String?
  @State var highlightedShiftIds: Set<String> = []
  @State var deepLinkAction: AppCoordinator.ShiftDeepLinkAction = .open
  @State var deepLinkHighlightDates: Set<String> = []
  @State var deepLinkHighlightClearTask: Task<Void, Never>?

  // Share functionality state
  @State var showingShareDestinationPicker: Bool = false
  @State var showingShareOptions: Bool = false
  @State private var showingSendToChatSheet: Bool = false
  @Environment(\.colorScheme) var colorScheme: ColorScheme

  // View mode toggle (calendar vs list) - persisted across app launches
  @AppStorage("shiftsViewMode") var showListView: Bool = false
  @ScaledMetric(relativeTo: .largeTitle) var errorIconSize: CGFloat = 48
  @State var selectedListJobId: String?
  @State var filteredListShiftsCache: [ShiftWithComputations] = []
  @State var shiftListItemsCache: [ShiftListItem] = []
  @State var weekGroupsWithPlaceholderCache: [ListWeekGroup] = []
  /// False only for a user with no shifts at all, who sees the first-shift prompt.
  @State var hasAnyShifts: Bool = true

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

  @Environment(\.horizontalSizeClass) var horizontalSizeClass
  @State var availableSize = CGSize.zero

  var usesWideCalendarLayout: Bool {
    availableSize.width >= 800 && availableSize.width > availableSize.height
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

  var shouldShowWorkSetupRequiredPlaceholder: Bool {
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
    } else if let error = viewModel.error, viewModel.shifts.isEmpty,
      let message = ErrorTranslations.translate(error)
    {
      errorView(message: message)
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
    NavigationStack(path: $addShiftPath) {
      ZStack(alignment: .bottom) {
        // Background that fills entire screen including safe areas
        TidexAppBackground()

        // Content area - fills entire screen, content scrolls behind month picker
        mainContentLayer
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .onGeometryChange(for: CGSize.self) {
            $0.size
          } action: {
            availableSize = $0
          }

        // Month picker is now in shared overlay in MainTabView

        if !shouldShowWorkSetupRequiredPlaceholder {
          syncStatusOverlay
        }
      }
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        shiftsToolbarContent
      }
      .navigationDestination(for: AddShiftRoute.self) { _ in AddShiftScreen(tab: .shifts) }
      .addShiftRoute(on: .shifts, path: $addShiftPath)
      .onAppear {
        publishToolbarState()
      }
      .onChange(of: showListView) { _, _ in
        publishToolbarState()
      }
      .onChange(of: shouldShowWorkSetupRequiredPlaceholder) { _, _ in
        publishToolbarState()
      }
      .adaptiveToolbarTransaction()
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
            showsCalendarSubscriptionCTA: calendarSubscriptionStore.canOfferSetup,
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
            showsCalendarSubscriptionCTA: calendarSubscriptionStore.canOfferSetup,
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
        .onChange(of: usesWideCalendarLayout) { _, usesColumns in
          if usesColumns {
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
        // The month grid can't reflow at accessibility text sizes, so start in the list.
        // Only a first launch or a switch into these sizes changes the saved choice.
        .onAppear {
          if dynamicTypeSize.isAccessibilitySize,
            UserDefaults.standard.object(forKey: "shiftsViewMode") == nil
          {
            showListView = true
          }
        }
        .onChange(of: dynamicTypeSize) { oldSize, newSize in
          if newSize.isAccessibilitySize, !oldSize.isAccessibilitySize {
            showListView = true
          }
        }
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
            scheduleViewLogger.debug(
              " Shifts finished loading, checking for deep link date: \(dateISO)")
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
              if let operation = daySelection.operation {
                startShiftOperation(operation, shift: shift)
              } else {
                pendingSheetAction = .shiftDetails(shift)
              }
              selectedDayForSheet = nil
            },
            onEventTapped: { event in
              pendingSheetAction = .eventDetails(
                EventSheetSelection(event: event, startInEditMode: false))
              selectedDayForSheet = nil
            },
            measuredContentHeight: $selectedDaySheetContentHeight,
            title: daySelection.operation?.title
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
          .presentationDetents([.height(250), .large])
          .presentationDragIndicator(.visible)
        }
        // Calendar share options sheet
        .sheet(isPresented: $showingShareOptions) {
          CalendarShareOptionsSheet(
            title: .shiftsShareMonthTitle,
            earningsImage: renderCalendarImage(includeEarnings: true),
            hiddenEarningsImage: renderCalendarImage(includeEarnings: false)
          )
          .presentationDetents([.height(260), .large])
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

  /// Helper struct for day sheet selection (must be Identifiable for .sheet(item:))
  struct DayItemSelection: Identifiable {
    let id: UUID = UUID()
    let dateISO: String
    let items: [DayPresentationItem]
    var operation: ScheduleShiftOperation?
  }

  enum ScheduleShiftOperation {
    case copy
    case move

    var title: LocalizedStringResource {
      switch self {
      case .copy: .commonCopy
      case .move: .shiftsMove
      }
    }
  }

  /// Represents an item in the shifts list - either a shift card or today's placeholder
  enum ShiftListItem: Identifiable {
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

  struct EventSheetSelection: Identifiable {
    let id: UUID = UUID()
    let event: EventRow
    let startInEditMode: Bool
  }

  struct ListWeekGroup: Identifiable {
    let weekKey: String
    let weekNumber: Int
    let totalGross: Double
    let items: [ShiftListItem]
    let isOutsideMonth: Bool

    var id: String { weekKey }
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
