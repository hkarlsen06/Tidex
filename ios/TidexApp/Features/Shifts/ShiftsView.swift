import SwiftUI
import os.log

private let logger = Logger(subsystem: "no.tidex.app", category: "ShiftsView")

/// Helper struct for day sheet selection (must be Identifiable for .sheet(item:))
private struct DayItemSelection: Identifiable {
  let id = UUID()
  let dateISO: String
  let items: [DayPresentationItem]
}

private struct EventSheetSelection: Identifiable {
  let id = UUID()
  let event: EventRow
  let startInEditMode: Bool
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
struct ShiftsView: View {
  @EnvironmentObject private var coordinator: AppCoordinator
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// Binding to the selected tab for navigation (to switch to Add tab)
  @Binding var selectedTab: MainTabView.Tab

  @StateObject private var viewModel = ShiftsViewModel()
  @ObservedObject private var celebrationManager = CelebrationManager.shared
  @ObservedObject private var syncStatusManager = SyncStatusManager.shared
  @State private var operationErrorMessage: String?

  // Sheet state for shift details (using item-based presentation to fix first-tap bug)
  @State private var selectedShift: ShiftWithComputations?
  @State private var selectedEvent: EventSheetSelection?
  @State private var showDeleteConfirmation = false
  @State private var shiftToDelete: ShiftWithComputations?
  @State private var showEventDeleteConfirmation = false
  @State private var eventToDelete: EventRow?

  // Edit mode state (when opening from swipe action)
  @State private var shiftToEditDirectly: ShiftWithComputations?

  // State for day shifts sheet (when tapping a calendar day)
  @State private var selectedDayForSheet: DayItemSelection?
  @State private var selectedDaySheetContentHeight: CGFloat =
    ContentSizedSheetMetrics.defaultContentHeight

  // Recurring shift editor state
  @State private var recurringShiftToEdit: RecurringShiftRow?

  // List scroll state (hidden until scrolled to today to prevent flash)
  @State private var listReady = false

  // Deep link navigation state
  @State private var highlightedDateISO: String?
  @State private var deepLinkAction: AppCoordinator.ShiftDeepLinkAction = .open
  @State private var deepLinkHighlightDate: String?  // Date to visually highlight (for widget deeplinks)

  // Share functionality state
  @State private var showingShareDestinationPicker = false
  @State private var showingShareOptions = false
  @State private var showingSendToChatSheet = false
  @State private var shareImage: UIImage?
  @State private var shareImageURL: URL?
  @Environment(\.colorScheme) private var colorScheme

  // View mode toggle (calendar vs list) - persisted across app launches
  @AppStorage("shiftsViewMode") private var showListView = false
  @State private var tabTransitionOffset: CGFloat = 0
  @State private var tabTransitionOpacity: Double = 1
  @State private var selectedListJobId: String?
  @State private var filteredListShiftsCache: [ShiftWithComputations] = []
  @State private var shiftListItemsCache: [ShiftListItem] = []
  @State private var weekGroupsWithPlaceholderCache: [ListWeekGroup] = []

  // Haptic feedback
  private let selectionHaptic = UISelectionFeedbackGenerator()
  private let impactHaptic = UIImpactFeedbackGenerator(style: .medium)
  private let workSetupStatusService = WorkSetupStatusService.shared

  // Orientation tracking for iPad landscape layout
  @ObservedObject private var orientationTracker = OrientationTracker.shared

  /// Whether to show iPad landscape side-by-side layout (calendar + list)
  private var isIPadLandscape: Bool {
    UIDevice.current.userInterfaceIdiom == .pad && orientationTracker.isLandscape
  }

  /// Whether running on iPhone-sized idiom.
  private var isIPhone: Bool {
    UIDevice.current.userInterfaceIdiom == .phone
  }

  private var workSetupPresentationState: WorkSetupPresentationState? {
    guard let userId = coordinator.getCurrentUserId() else { return nil }
    return workSetupStatusService.presentationState(
      for: userId,
      initialSyncComplete: coordinator.initialSyncComplete
    )
  }

  private var shouldShowWorkSetupRequiredPlaceholder: Bool {
    workSetupPresentationState?.shouldShowPlaceholder == true
  }

  // MARK: - Body

  @ViewBuilder
  private var mainContentLayer: some View {
    if shouldShowWorkSetupRequiredPlaceholder {
      WorkSetupRequiredPlaceholder()
    } else if let error = viewModel.error {
      errorView(error: error)
    } else {
      // Unified content view - handles both empty and populated states
      // This ensures StaggeredCardsContainer persists across month changes
      shiftsContent
    }
  }

  @ToolbarContentBuilder
  private var shiftsToolbarContent: some ToolbarContent {
    // Share button (only in calendar view, not list view)
    if !showListView && !shouldShowWorkSetupRequiredPlaceholder {
      ToolbarItem(placement: .topBarLeading) {
        Button {
          startCalendarShare()
        } label: {
          Image(systemName: "square.and.arrow.up")
            .font(.tidexBodyMedium)
            .foregroundColor(.tidexTextPrimary)
            .offset(y: -1)
        }
      }
    }

    // Selection mode toggle (only in calendar view)
    if !showListView && !shouldShowWorkSetupRequiredPlaceholder {
      ToolbarSpacer(.fixed, placement: .topBarLeading)
      ToolbarItem(placement: .topBarLeading) {
        selectionModeToggleButton
      }
    }

    // User menu on trailing side
    ToolbarItem(placement: .topBarTrailing) {
      UserMenuButton(
        displayName: coordinator.userDisplayName,
        avatarUrl: coordinator.userAvatarUrl
      )
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
      }
      .navigationBarTitleDisplayMode(.inline)
      .iPadToolbarBackground()
      .toolbar {
        shiftsToolbarContent
      }
      .iPadToolbarTransaction()
    }
  }

  var body: some View {
    bodyWithSecondarySheets
  }

  private var baseBody: AnyView {
    AnyView(navigationContent)
  }

  private var bodyWithLifecycle: AnyView {
    AnyView(
      baseBody
        .task {
          guard !shouldShowWorkSetupRequiredPlaceholder else { return }
          await viewModel.loadShifts()
        }
        .onChange(of: coordinator.initialSyncComplete) { _, completed in
          guard !shouldShowWorkSetupRequiredPlaceholder else { return }
          guard completed else { return }
          Task {
            await viewModel.reloadFromLocal()
          }
        }
        .onChange(of: syncStatusManager.lastSuccessfulSync) { oldValue, newValue in
          guard !shouldShowWorkSetupRequiredPlaceholder else { return }
          guard oldValue != nil, newValue != nil else { return }
          guard selectedTab == .shifts else { return }
          Task {
            await viewModel.reloadFromLocal()
          }
        }
        .onReceive(NotificationCenter.default.publisher(for: .shiftsDidChange)) { notification in
          guard !shouldShowWorkSetupRequiredPlaceholder else { return }
          guard (notification.object as AnyObject?) !== viewModel else { return }
          // Reload shifts when they change (e.g., after adding a shift)
          Task {
            await viewModel.reloadFromLocal()
          }
        }
        .onChange(of: selectedTab) { oldTab, newTab in
          guard newTab == .shifts, oldTab != .shifts else { return }
          Task {
            await viewModel.reloadFromLocal()
          }
          if oldTab == .add {
            tabTransitionOffset = -28
            tabTransitionOpacity = 0.92
            MotionTokens.animate(.navigationPush, reduceMotion: reduceMotion) {
              tabTransitionOffset = 0
              tabTransitionOpacity = 1
            }
          }
        }
        .onAppear {
          guard !shouldShowWorkSetupRequiredPlaceholder else { return }
          recomputeListDerivedDataIfNeeded(force: true)
        }
        .onChange(of: selectedListJobId) { _, _ in
          recomputeListDerivedDataIfNeeded()
        }
        .onChange(of: viewModel.shifts) { _, _ in
          recomputeListDerivedDataIfNeeded()
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

  private var bodyWithPrimarySheetsAndAlerts: AnyView {
    AnyView(
      bodyWithLifecycle
        // Shift details sheet (item-based to guarantee data availability)
        .sheet(item: $selectedShift) { shift in
          let shiftJob = viewModel.shouldShowJobIndicators ? viewModel.jobForShift(shift) : nil
          ShiftDetailsSheet(
            shift: shift,
            jobName: shiftJob?.name,
            jobColorHex: shiftJob?.color,
            onDelete: {
              selectedShift = nil
              // Small delay before showing delete confirmation
              DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                shiftToDelete = shift
                showDeleteConfirmation = true
              }
            },
            onUpdate: { editResult in
              selectedShift = nil
              Task {
                await viewModel.updateShift(editResult)
              }
            },
            onEditRecurring: { recurringId in
              selectedShift = nil
              // Small delay to allow sheet to dismiss
              DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if let recurring = viewModel.getRecurringShift(id: recurringId) {
                  recurringShiftToEdit = recurring
                }
              }
            },
            tariffRules: viewModel.getTariffRules(for: shift.shiftDate)
          )
          .presentationDetents([.medium, .large])
          .presentationDragIndicator(.visible)
        }
        // Sheet for editing directly (opens in edit mode from swipe action)
        .sheet(item: $shiftToEditDirectly) { shift in
          let shiftJob = viewModel.shouldShowJobIndicators ? viewModel.jobForShift(shift) : nil
          ShiftDetailsSheet(
            shift: shift,
            jobName: shiftJob?.name,
            jobColorHex: shiftJob?.color,
            onDelete: {
              shiftToEditDirectly = nil
              DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                shiftToDelete = shift
                showDeleteConfirmation = true
              }
            },
            onUpdate: { editResult in
              shiftToEditDirectly = nil
              Task {
                await viewModel.updateShift(editResult)
              }
            },
            onEditRecurring: { recurringId in
              shiftToEditDirectly = nil
              DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if let recurring = viewModel.getRecurringShift(id: recurringId) {
                  recurringShiftToEdit = recurring
                }
              }
            },
            startInEditMode: true,
            tariffRules: viewModel.getTariffRules(for: shift.shiftDate)
          )
          .presentationDetents([.medium, .large])
          .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedEvent) { selection in
          EventDetailsSheet(
            event: selection.event,
            onDelete: {
              selectedEvent = nil
              DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                eventToDelete = selection.event
                showEventDeleteConfirmation = true
              }
            },
            onUpdate: { editResult in
              try await viewModel.updateEvent(editResult)
              selectedEvent = nil
            },
            onInlineReminderUpdate: { editResult in
              try await viewModel.updateEvent(editResult)
            },
            startInEditMode: selection.startInEditMode
          )
          .presentationDetents([.medium, .large])
          .presentationDragIndicator(.visible)
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
          selectionHaptic.prepare()
          impactHaptic.prepare()
          // Handle any pending deep link on initial appearance
          handleDeepLink(coordinator.pendingDeepLink)
        }
        // Handle view mode switch (toggle is in shared overlay)
        .onChange(of: showListView) { _, isListView in
          if isListView {
            viewModel.isSelectionModeEnabled = false
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
            selectShiftFromDeepLink(dateISO: dateISO, shifts: viewModel.shifts)
          }
        }
        // Deep link handling - navigate to specific date from widget
        .onChange(of: coordinator.pendingDeepLink) { _, deepLink in
          handleDeepLink(deepLink)
        }
        // When shifts finish loading, check if we should highlight/select a date from deep link
        .onChange(of: viewModel.isLoading) { _, isLoading in
          if !isLoading, let dateISO = highlightedDateISO {
            logger.debug(" Shifts finished loading, checking for deep link date: \(dateISO)")
            selectShiftFromDeepLink(dateISO: dateISO, shifts: viewModel.shifts)
          }
        }
        // Also watch for shifts array changes (handles cases where shifts update without loading state change)
        .onChange(of: viewModel.shifts) { _, shifts in
          if let dateISO = highlightedDateISO, !shifts.isEmpty {
            selectShiftFromDeepLink(dateISO: dateISO, shifts: shifts)
          }
        }
    )
  }

  private var bodyWithSecondarySheets: AnyView {
    AnyView(
      bodyWithStateObservers
        // Day shifts sheet (when tapping a calendar day)
        .sheet(item: $selectedDayForSheet) { daySelection in
          MixedDaySheet(
            dateISO: daySelection.dateISO,
            items: daySelection.items,
            excludedFromTotalIds: viewModel.excludedFromTotalIds,
            conflictingShiftIds: viewModel.conflictingShiftIds,
            showJobIndicators: viewModel.shouldShowJobIndicators,
            jobForShift: { shift in viewModel.jobForShift(shift) },
            onShiftTapped: { shift in
              selectedDayForSheet = nil
              DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                selectedShift = shift
              }
            },
            onEventTapped: { event in
              selectedDayForSheet = nil
              DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                selectedEvent = EventSheetSelection(event: event, startInEditMode: false)
              }
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
        .sheet(
          isPresented: $showingShareOptions,
          onDismiss: {
            // Check if we have a pending share action
            if let url = shareImageURL {
              presentShareSheet(with: [url])
            } else if let image = shareImage {
              presentShareSheet(with: [image])
            }
          }
        ) {
          CalendarShareOptionsSheet(
            onShowEarnings: {
              // Prepare the image first, then dismiss - share sheet shows on dismiss
              prepareCalendarImage(includeEarnings: true)
              showingShareOptions = false
            },
            onHideEarnings: {
              // Prepare the image first, then dismiss - share sheet shows on dismiss
              prepareCalendarImage(includeEarnings: false)
              showingShareOptions = false
            }
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
    impactHaptic.impactOccurred()
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

  /// Prepare the calendar image for sharing (called before dismissing options sheet)
  @MainActor
  private func prepareCalendarImage(includeEarnings: Bool) {
    // Render to image and save to temp file for better share sheet compatibility
    guard let image = renderCalendarImage(includeEarnings: includeEarnings),
      let pngData = image.pngData()
    else {
      shareImage = nil
      shareImageURL = nil
      return
    }

    let tempURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("calendar-\(viewModel.committedYear)-\(viewModel.committedMonth).png")

    do {
      try pngData.write(to: tempURL)
      shareImage = image
      shareImageURL = tempURL
    } catch {
      // Fallback to sharing image directly
      shareImage = image
      shareImageURL = nil
    }
  }

  /// Present the share sheet with the given items (called after options sheet dismisses)
  @MainActor
  private func presentShareSheet(with activityItems: [Any]) {
    // Clear the pending share state
    defer {
      shareImage = nil
      shareImageURL = nil
    }

    let activityVC = UIActivityViewController(
      activityItems: activityItems, applicationActivities: nil)

    // Get the root view controller and present
    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
      let rootVC = windowScene.windows.first?.rootViewController
    {
      // Find the topmost presented view controller
      var topVC = rootVC
      while let presented = topVC.presentedViewController {
        topVC = presented
      }
      // iPad requires popover configuration
      if let popover = activityVC.popoverPresentationController {
        popover.sourceView = topVC.view
        popover.sourceRect = CGRect(x: topVC.view.bounds.midX, y: 100, width: 0, height: 0)
        popover.permittedArrowDirections = .up
      }
      topVC.present(activityVC, animated: true)
    }
  }

  private enum CalendarSharePreparationError: LocalizedError {
    case unableToPrepareImage

    var errorDescription: String? {
      String(localized: "friends.chat.send_to_chat.prepare_image_failed", table: "Localizable")
    }
  }

  // MARK: - Deep Link Handling

  /// Handle pending deep link from widget or notification
  private func handleDeepLink(_ deepLink: AppCoordinator.DeepLink?) {
    guard case .shifts(let dates, let action) = deepLink,
      let dateISO = dates?.first
    else { return }

    // Avoid processing the same deep link twice
    if highlightedDateISO == dateISO {
      logger.debug(" Deep link already being processed for: \(dateISO)")
      return
    }

    logger.debug(" Handling deep link for date: \(dateISO), action: \(action.rawValue)")

    // Store the action to use when selecting the shift
    deepLinkAction = action

    // Parse the date to extract year and month
    guard let date = Date.fromISODateString(dateISO) else {
      logger.debug(" Failed to parse date: \(dateISO)")
      coordinator.clearPendingDeepLink()
      return
    }

    let calendar = Calendar.current
    let targetYear = calendar.component(.year, from: date)
    let targetMonth = calendar.component(.month, from: date)

    // Store the date to highlight/select once shifts are loaded
    // This persists across async operations until we successfully show the shift
    highlightedDateISO = dateISO

    // Clear the deep link immediately to prevent MainTabView from re-processing
    coordinator.clearPendingDeepLink()

    // Navigate to the correct month if not already there
    if viewModel.displayYear != targetYear || viewModel.displayMonth != targetMonth {
      logger.debug(" Navigating to \(targetYear)-\(targetMonth)")
      SharedMonthContext.shared.navigateTo(year: targetYear, month: targetMonth)
      // Shifts will load via the month change subscription
      // The onChange(of: viewModel.shifts) will then call selectShiftFromDeepLink
    } else if !viewModel.shifts.isEmpty {
      // Already on the correct month and shifts are loaded - select immediately
      selectShiftFromDeepLink(dateISO: dateISO, shifts: viewModel.shifts)
    }
    // If shifts are empty, the onChange(of: viewModel.shifts) will handle it when they load
  }

  /// Select or highlight shift for the given date once shifts are loaded
  private func selectShiftFromDeepLink(dateISO: String, shifts: [ShiftWithComputations]) {
    // Parse target date to verify we're looking at the correct month
    guard let targetDate = Date.fromISODateString(dateISO) else {
      logger.debug(" Invalid date format: \(dateISO)")
      highlightedDateISO = nil
      return
    }

    let calendar = Calendar.current
    let targetYear = calendar.component(.year, from: targetDate)
    let targetMonth = calendar.component(.month, from: targetDate)

    // Make sure we're on the correct committed month before trying to find the shift
    // (committed values indicate data is ready to display)
    guard viewModel.committedYear == targetYear && viewModel.committedMonth == targetMonth else {
      logger.debug(
        " Not on target month yet (committed: \(viewModel.committedYear)-\(viewModel.committedMonth), target: \(targetYear)-\(targetMonth))"
      )
      // Keep highlightedDateISO - month navigation is still in progress
      return
    }

    // Find shifts on the target date
    let shiftsOnDate = shifts.filter { $0.shiftDate == dateISO }

    guard !shiftsOnDate.isEmpty else {
      logger.debug(" No shifts found for date: \(dateISO) (shifts loaded: \(shifts.count))")
      // Clear highlighted date - we're on the right month but there's no shift
      // This handles the case where the shift was deleted
      highlightedDateISO = nil
      return
    }

    logger.debug(
      " Found \(shiftsOnDate.count) shift(s) on \(dateISO), action: \(deepLinkAction.rawValue)")

    // Capture the action before clearing state
    let action = deepLinkAction

    // Clear the highlighted date and reset action since we're handling it now
    highlightedDateISO = nil
    deepLinkAction = .open  // Reset to default

    // Small delay to allow view to stabilize after month navigation
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
      selectionHaptic.selectionChanged()

      // Only open sheets when action is .open (default behavior from notifications)
      // When action is .highlight (from widgets), show visual highlight instead
      if action == .highlight {
        logger.debug(" Highlight-only mode - showing visual highlight for \(dateISO)")
        MotionTokens.animate(.subtle, reduceMotion: reduceMotion) {
          deepLinkHighlightDate = dateISO
        }
        // Auto-clear highlight after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
          MotionTokens.animate(.subtle, reduceMotion: reduceMotion) {
            deepLinkHighlightDate = nil
          }
        }
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

  // MARK: - Delete Shift

  private func deleteShift(_ shift: ShiftWithComputations) async {
    impactHaptic.impactOccurred()

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
      NotificationCenter.default.post(name: .shiftsDidChange, object: nil)

      shiftToDelete = nil
    } catch {
      logger.error("Failed to delete shift: \(error.localizedDescription)")
      operationErrorMessage = ErrorTranslations.translate(error)
      shiftToDelete = nil
    }
  }

  private func deleteEvent(_ event: EventRow) async {
    impactHaptic.impactOccurred()

    do {
      try await viewModel.deleteEvent(id: event.id)
      eventToDelete = nil
    } catch {
      logger.error("Failed to delete event: \(error.localizedDescription)")
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
    guard let dateISO = viewModel.selectedDates.first else { return }
    presentDayItems(dateISO: dateISO, shifts: viewModel.selectedDateShifts)
  }

  // MARK: - Selection Mode Toggle Button

  /// Toggle button for selection mode (calendar view only)
  @ViewBuilder
  private var selectionModeToggleButton: some View {
    Button {
      selectionHaptic.selectionChanged()
      MotionTokens.animate(.emphasis, reduceMotion: reduceMotion) {
        viewModel.isSelectionModeEnabled.toggle()
      }
    } label: {
      Image(
        systemName: viewModel.isSelectionModeEnabled ? "checkmark.circle.fill" : "checkmark.circle"
      )
      .font(.tidexHeadline)
      .foregroundColor(viewModel.isSelectionModeEnabled ? .tidexBrandPrimary : .tidexTextPrimary)
    }
    .buttonStyle(.plain)
    .contentTransition(.symbolEffect(.replace))
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
    }) {
      GeometryReader { geometry in
        ZStack {
          // Background layer to dismiss selection when tapping outside calendar
          Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
              if !viewModel.selectedDates.isEmpty {
                viewModel.clearSelection()
              }
            }

          // Calendar content - centered
          VStack {
            Spacer()
            ShiftsCalendarView(
              shifts: viewModel.shifts,
              eventCoverageByDate: viewModel.eventCoverageByDate,
              month: displayedMonthDate,
              year: viewModel.committedYear,
              monthNumber: viewModel.committedMonth,
              currency: viewModel.currency,
              showEarnings: true,
              jobs: viewModel.activeJobs,
              phase: transitionPhase,
              onDayTapped: { dateISO, shiftsOnDay in
                if !shiftsOnDay.isEmpty {
                  viewModel.handleDayTapped(dateISO: dateISO, shiftsOnDay: shiftsOnDay)
                } else {
                  presentDayItems(dateISO: dateISO, shifts: shiftsOnDay)
                }
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
              onSelectDateRange: { dates in
                viewModel.handleDateRangeSelected(dates)
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
                if let dateISO = dateISO {
                  SharedMonthContext.shared.preselectedDate = dateISO
                  selectedTab = .add
                }
              },
              isCopyMode: viewModel.isCopyMode,
              isMoveMode: viewModel.isMoveMode,
              isCopying: viewModel.isCopying,
              isMoving: viewModel.isMoving,
              onCopyToDate: { targetDateISO in
                Task {
                  await viewModel.handleCopyToDate(targetDateISO)
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
              isSelectionModeEnabled: $viewModel.isSelectionModeEnabled,
              newlyAddedDates: celebrationManager.newlyAddedDates,
              deepLinkHighlightDate: deepLinkHighlightDate,
              conflictDates: viewModel.conflictDates,
              excludedFromTotalIds: viewModel.excludedFromTotalIds
            )
            .padding(.horizontal, Spacing.md)
            .offset(y: tabTransitionOffset)
            .opacity(tabTransitionOpacity)
            Spacer()
          }
          // Offset for month picker overlay
          .padding(.bottom, MonthPickerLayout.totalBottomInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      .contentShape(Rectangle())
      .monthSwipeGesture(
        onSwipeLeft: {
          AppearanceTracker.shared.reset()
          viewModel.goToNextMonth()
        },
        onSwipeRight: {
          AppearanceTracker.shared.reset()
          viewModel.goToPreviousMonth()
        },
        isEnabled: !viewModel.isSelectionModeEnabled
      )
    }
  }

  /// Shifts list panel for iPad landscape (right side)
  @ViewBuilder
  private var shiftsPanelForIPad: some View {
    if shiftListItems.isEmpty && !viewModel.isCurrentMonth {
      // Empty state for past/future months
      ScrollView {
        ShiftsEmptyState(
          isCurrentMonth: viewModel.isCurrentMonth,
          monthPeriod: viewModel.monthPeriod,
          monthName: viewModel.displayMonthName,
          onAddShift: {
            selectedTab = .add
          }
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
    }) {
      GeometryReader { geometry in
        // Calendar only - no list below. Tapping days opens day sheet.
        ZStack {
          // Background layer to dismiss selection when tapping outside calendar
          Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
              if !viewModel.selectedDates.isEmpty {
                viewModel.clearSelection()
              }
            }

          // Calendar content - centered between toolbar and month picker
          VStack {
            Spacer()
            ShiftsCalendarView(
              shifts: viewModel.shifts,
              eventCoverageByDate: viewModel.eventCoverageByDate,
              month: displayedMonthDate,
              year: viewModel.committedYear,
              monthNumber: viewModel.committedMonth,
              currency: viewModel.currency,
              showEarnings: true,
              jobs: viewModel.activeJobs,
              phase: transitionPhase,
              onDayTapped: { dateISO, shiftsOnDay in
                if !shiftsOnDay.isEmpty {
                  viewModel.handleDayTapped(dateISO: dateISO, shiftsOnDay: shiftsOnDay)
                } else {
                  presentDayItems(dateISO: dateISO, shifts: shiftsOnDay)
                }
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
              onSelectDateRange: { dates in
                viewModel.handleDateRangeSelected(dates)
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
                if let dateISO = dateISO {
                  SharedMonthContext.shared.preselectedDate = dateISO
                  selectedTab = .add
                }
              },
              isCopyMode: viewModel.isCopyMode,
              isMoveMode: viewModel.isMoveMode,
              isCopying: viewModel.isCopying,
              isMoving: viewModel.isMoving,
              onCopyToDate: { targetDateISO in
                Task {
                  await viewModel.handleCopyToDate(targetDateISO)
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
              isSelectionModeEnabled: $viewModel.isSelectionModeEnabled,
              newlyAddedDates: celebrationManager.newlyAddedDates,
              deepLinkHighlightDate: deepLinkHighlightDate,
              conflictDates: viewModel.conflictDates,
              excludedFromTotalIds: viewModel.excludedFromTotalIds
            )
            .frame(maxWidth: isIPhone ? .infinity : AdaptiveMaxWidth.tabContent)
            .padding(.horizontal, isIPhone ? Spacing.xs : Spacing.md)
            .offset(y: tabTransitionOffset)
            .opacity(tabTransitionOpacity)
            Spacer()
          }
          // Offset for month picker overlay so content centers in available space
          .padding(.bottom, MonthPickerLayout.totalBottomInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      .contentShape(Rectangle())
      .monthSwipeGesture(
        onSwipeLeft: {
          AppearanceTracker.shared.reset()
          viewModel.goToNextMonth()
        },
        onSwipeRight: {
          AppearanceTracker.shared.reset()
          viewModel.goToPreviousMonth()
        },
        isEnabled: !viewModel.isSelectionModeEnabled
      )
    }
  }

  // MARK: - List View Content

  @ViewBuilder
  private var listViewContent: some View {
    // Show empty state only when there are no shifts AND it's not current month
    // (current month with no shifts shows just the today placeholder card in the list)
    if shiftListItems.isEmpty && !viewModel.isCurrentMonth {
      // Empty state for past/future months with no shifts
      ScrollView {
        ShiftsEmptyState(
          isCurrentMonth: viewModel.isCurrentMonth,
          monthPeriod: viewModel.monthPeriod,
          monthName: viewModel.displayMonthName,
          onAddShift: {
            selectedTab = .add
          }
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
    viewModel.activeJobs.first(where: { $0.is_default })?.id
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
    guard force || shouldMaintainListDerivedData else { return }
    recomputeListDerivedData()
  }

  /// Recompute list-derived collections when upstream inputs change.
  private func recomputeListDerivedData() {
    let validJobIds = Set(viewModel.activeJobs.map(\.id))
    if let selectedListJobId, !validJobIds.contains(selectedListJobId) {
      self.selectedListJobId = nil
    }

    let filtered: [ShiftWithComputations]
    if let selectedListJobId {
      let defaultJobId = defaultActiveJobId
      filtered = viewModel.shifts.filter { shift in
        if shift.shift.job_id == selectedListJobId {
          return true
        }
        // Compatibility fallback for legacy rows that can still have nil job_id.
        return shift.shift.job_id == nil && selectedListJobId == defaultJobId
      }
    } else {
      filtered = viewModel.shifts
    }
    filteredListShiftsCache = filtered

    var items: [ShiftListItem] = filtered.map { .shift($0) }
    items.append(
      contentsOf: viewModel.events.map {
        .event(EventPresentation(event: $0, coveredDateISO: listCoveredDateISO(for: $0)))
      }
    )
    if viewModel.isCurrentMonth {
      let today = todayISO()
      let hasShiftToday = filtered.contains { $0.shiftDate == today }
      if !hasShiftToday {
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
    shiftListItemsCache = items

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
    weekGroupsWithPlaceholderCache = weekMap.map { entry in
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
    // ARCHITECTURE: Using native List with .swipeActions() for reliable gesture handling
    // This is Apple's designed solution - no custom gesture conflicts with scrolling
    // Styled with .listRowBackground() and .listRowSeparator(.hidden) for custom look
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
        guard let tab = notification.userInfo?["tab"] as? MainTabView.Tab,
          tab == .shifts, showListView
        else { return }
        let scrollToToday = notification.userInfo?["scrollToToday"] as? Bool ?? false
        if scrollToToday {
          withAnimation { scrollToTodayItem(using: proxy) }
        } else if let firstId = weekGroupsWithPlaceholder.first?.items.first?.id {
          withAnimation { proxy.scrollTo(firstId, anchor: .top) }
        }
      }
    }
  }

  /// Render a single list item (shift or placeholder)
  @ViewBuilder
  private func listItemRow(item: ShiftListItem) -> some View {
    switch item {
    case .shift(let shift):
      shiftCardRow(shift: shift)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        // Native swipe actions - works perfectly with List scrolling
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
          Button {
            selectionHaptic.selectionChanged()
            // Open sheet directly in edit mode
            shiftToEditDirectly = shift
          } label: {
            Label(String(localized: .shiftsActionsEdit), systemImage: "pencil")
          }
          .tint(.tidexBlue)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
          // Allow delete for both regular and virtual shifts
          Button(role: .destructive) {
            impactHaptic.impactOccurred()
            shiftToDelete = shift
            showDeleteConfirmation = true
          } label: {
            Label(String(localized: .shiftsActionsDelete), systemImage: "trash")
          }
          .tint(.red)
        }

    case .event(let event):
      EventRowCard(
        event: event.event,
        coveredDateISO: event.coveredDateISO,
        onTap: {
          selectionHaptic.selectionChanged()
          handleEventTapped(event.event)
        }
      )
      .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
      .listRowBackground(Color.clear)
      .listRowSeparator(.hidden)
      .swipeActions(edge: .leading, allowsFullSwipe: true) {
        Button {
          selectionHaptic.selectionChanged()
          handleEventTapped(event.event, startInEditMode: true)
        } label: {
          Label(String(localized: .shiftsActionsEdit), systemImage: "pencil")
        }
        .tint(.tidexBlue)
      }
      .swipeActions(edge: .trailing, allowsFullSwipe: false) {
        Button(role: .destructive) {
          impactHaptic.impactOccurred()
          eventToDelete = event.event
          showEventDeleteConfirmation = true
        } label: {
          Label(String(localized: .eventsDeleteButton), systemImage: "trash")
        }
        .tint(.red)
      }

    case .todayPlaceholder:
      TodayPlaceholderCard(onTap: {
        selectionHaptic.selectionChanged()
        // Navigate to add shift with today's date pre-selected
        SharedMonthContext.shared.preselectedDate = todayISO()
        selectedTab = .add
      })
      .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
      .listRowBackground(Color.clear)
      .listRowSeparator(.hidden)
    }
  }

  private func listCoveredDateISO(for event: EventRow) -> String {
    guard
      event.is_all_day,
      let monthStart = Calendar.current.date(
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
      Group {
        if isSelected {
          Text(title)
            .font(.tidexFootnoteStrong)
            .foregroundColor(.white)
        } else {
          WorkplaceNameText(
            name: title,
            colorHex: colorHex,
            font: .tidexFootnoteStrong,
            fallbackBadgeColor: isWorkplace ? .tidexBlue : nil
          )
        }
      }
      .padding(.horizontal, Spacing.sm)
      .padding(.vertical, Spacing.xs)
      .background(isSelected ? Color.tidexBrandPrimary : Color.tidexSurfaceSecondary)
      .clipShape(Capsule())
    }
    .buttonStyle(.plain)
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
        showJobIndicator: viewModel.shouldShowJobIndicators,
        jobName: shiftJob?.name,
        jobColorHex: shiftJob?.color,
        onTap: {
          selectionHaptic.selectionChanged()
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
      guard case .shift(let shift) = item else { return false }
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
    return Calendar.current.date(from: components) ?? Date()
  }

  // MARK: - Error View

  @ViewBuilder
  private func errorView(error: Error) -> some View {
    VStack(spacing: Spacing.md) {
      Image(systemName: "exclamationmark.triangle")
        .font(.system(size: 48))
        .foregroundColor(.tidexWarning)

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
        .environmentObject(AppCoordinator.shared)
    }
  }

  return PreviewWrapper()
}
