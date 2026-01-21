import SwiftUI

/// Helper struct for day sheet selection (must be Identifiable for .sheet(item:))
private struct DayShiftSelection: Identifiable {
    let id = UUID()
    let dateISO: String
    let shifts: [ShiftWithComputations]
}

/// Represents an item in the shifts list - either a shift card or today's placeholder
private enum ShiftListItem: Identifiable {
    case shift(ShiftWithComputations)
    case todayPlaceholder

    var id: String {
        switch self {
        case .shift(let shift):
            return shift.id
        case .todayPlaceholder:
            return "today-placeholder"
        }
    }

    /// The date for sorting purposes
    var sortDate: String {
        switch self {
        case .shift(let shift):
            return shift.shiftDate
        case .todayPlaceholder:
            return todayISO()
        }
    }
}

/// Shifts tab view - displays list of user's shifts grouped by week
/// Supports month navigation, pull-to-refresh, swipe gestures, and calendar/list view toggle
struct ShiftsView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.localization) private var localization

    /// Binding to the selected tab for navigation (to switch to Add tab)
    @Binding var selectedTab: MainTabView.Tab

    @StateObject private var viewModel = ShiftsViewModel()
    @ObservedObject private var celebrationManager = CelebrationManager.shared

    // Sheet state for shift details (using item-based presentation to fix first-tap bug)
    @State private var selectedShift: ShiftWithComputations?
    @State private var showDeleteConfirmation = false
    @State private var shiftToDelete: ShiftWithComputations?

    // Edit mode state (when opening from swipe action)
    @State private var shiftToEditDirectly: ShiftWithComputations?

    // State for day shifts sheet (when tapping a calendar day)
    @State private var selectedDayForSheet: DayShiftSelection?

    // Recurring shift editor state
    @State private var recurringShiftToEdit: RecurringShiftRow?

    // Celebration state
    @State private var showConfetti = false

    // Deep link navigation state
    @State private var highlightedDateISO: String?
    @State private var deepLinkAction: AppCoordinator.ShiftDeepLinkAction = .open
    @State private var deepLinkHighlightDate: String?  // Date to visually highlight (for widget deeplinks)

    // View mode toggle (calendar vs list) - persisted across app launches
    @AppStorage("shiftsViewMode") private var showListView = false

    // Haptic feedback
    private let selectionHaptic = UISelectionFeedbackGenerator()
    private let impactHaptic = UIImpactFeedbackGenerator(style: .medium)
    private let celebrationHaptic = UINotificationFeedbackGenerator()

    // iPad detection - hide logo on iPad
    private var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    // Orientation tracking for iPad landscape layout
    @ObservedObject private var orientationTracker = OrientationTracker.shared

    /// Whether to show iPad landscape side-by-side layout (calendar + list)
    private var isIPadLandscape: Bool {
        isIPad && orientationTracker.isLandscape
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // Background that fills entire screen including safe areas
                Color.tidexBackground
                    .ignoresSafeArea()

                // Content area - fills entire screen, content scrolls behind month picker
                Group {
                    if let error = viewModel.error {
                        errorView(error: error)
                    } else if viewModel.isLoading && viewModel.shifts.isEmpty {
                        loadingView
                    } else {
                        // Unified content view - handles both empty and populated states
                        // This ensures StaggeredCardsContainer persists across month changes
                        shiftsContent
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Month picker is now in shared overlay in MainTabView
            }
            .navigationBarTitleDisplayMode(.inline)
            .iPadToolbarBackground(Color.tidexBackground)
            .toolbar {
                if !isIPad {
                    ToolbarItem(placement: .principal) {
                        Image("TidexWordmark")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 22)
                    }
                }
                // Refresh button
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task {
                            AppearanceTracker.shared.reset()
                            await viewModel.refresh()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.tidexTextPrimary)
                    }
                    .disabled(viewModel.isLoading)
                    .opacity(viewModel.isLoading ? 0.5 : 1.0)
                }
                // Selection mode toggle (only in calendar view)
                if !showListView {
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
            .iPadToolbarTransaction()
        }
        .task {
            await viewModel.loadShifts()
        }
        .onReceive(NotificationCenter.default.publisher(for: .shiftsDidChange)) { _ in
            // Reload shifts when they change (e.g., after adding a shift)
            Task {
                await viewModel.reloadFromLocal()
            }
        }
        // Pass user's currency to all child views
        .userCurrency(viewModel.currency)
        // Shift details sheet (item-based to guarantee data availability)
        .sheet(item: $selectedShift) { shift in
            ShiftDetailsSheet(
                shift: shift,
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
            ShiftDetailsSheet(
                shift: shift,
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
        // Delete confirmation alert
        .alert(
            shiftToDelete?.isVirtual == true
                ? localization.string("shifts.excludeConfirmTitle")
                : localization.string("shifts.deleteConfirmTitle"),
            isPresented: $showDeleteConfirmation,
            presenting: shiftToDelete
        ) { shift in
            Button(localization.string("common.cancel"), role: .cancel) {
                shiftToDelete = nil
            }
            Button(
                shift.isVirtual
                    ? localization.string("shifts.excludeButton")
                    : localization.string("shifts.deleteButton"),
                role: .destructive
            ) {
                Task {
                    await deleteShift(shift)
                }
            }
        } message: { shift in
            Text(shift.isVirtual
                ? localization.string("shifts.excludeConfirmMessage")
                : localization.string("shifts.deleteConfirmMessage"))
        }
        .onAppear {
            selectionHaptic.prepare()
            impactHaptic.prepare()
            celebrationHaptic.prepare()
            // Handle any pending deep link on initial appearance
            handleDeepLink(coordinator.pendingDeepLink)
        }
        // Exit selection mode when switching to list view (toggle is in shared overlay)
        .onChange(of: showListView) { _, isListView in
            if isListView {
                viewModel.isSelectionModeEnabled = false
            }
        }
        // Confetti overlay for celebration when shifts are added
        .overlay {
            ConfettiView(isActive: showConfetti) {
                showConfetti = false
                celebrationManager.confettiDidShow()
            }
            .allowsHitTesting(false)
        }
        // Trigger celebration when shifts are added (check on view appear and when month matches)
        .onChange(of: celebrationManager.shouldShowConfetti) { _, shouldShow in
            if shouldShow && celebrationManager.shouldShowConfetti(forYear: viewModel.displayYear, month: viewModel.displayMonth) {
                triggerCelebration()
            }
        }
        .onChange(of: viewModel.displayMonth) { _, _ in
            // Check if we should show confetti for the newly navigated month
            if celebrationManager.shouldShowConfetti(forYear: viewModel.displayYear, month: viewModel.displayMonth) {
                triggerCelebration()
            }
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
                print("[ShiftsView] Shifts finished loading, checking for deep link date: \(dateISO)")
                selectShiftFromDeepLink(dateISO: dateISO, shifts: viewModel.shifts)
            }
        }
        // Also watch for shifts array changes (handles cases where shifts update without loading state change)
        .onChange(of: viewModel.shifts) { _, shifts in
            if let dateISO = highlightedDateISO, !shifts.isEmpty {
                selectShiftFromDeepLink(dateISO: dateISO, shifts: shifts)
            }
        }
        // Day shifts sheet (when tapping a calendar day)
        .sheet(item: $selectedDayForSheet) { daySelection in
            DayShiftsSheet(
                dateISO: daySelection.dateISO,
                shifts: daySelection.shifts,
                onShiftTapped: { shift in
                    selectedDayForSheet = nil
                    // Small delay before showing details to allow sheet dismiss animation
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        selectedShift = shift
                    }
                }
            )
            .presentationDetents([.medium])
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
    }

    // MARK: - Celebration

    /// Trigger celebration effects (confetti + haptic)
    private func triggerCelebration() {
        // Small delay to allow view to render
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            // Haptic feedback
            celebrationHaptic.notificationOccurred(.success)

            // Show confetti
            showConfetti = true
        }
    }

    // MARK: - Deep Link Handling

    /// Handle pending deep link from widget or notification
    private func handleDeepLink(_ deepLink: AppCoordinator.DeepLink?) {
        guard case .shifts(let dates, let action) = deepLink,
              let dateISO = dates?.first else { return }

        // Avoid processing the same deep link twice
        if highlightedDateISO == dateISO {
            print("[ShiftsView] Deep link already being processed for: \(dateISO)")
            return
        }

        print("[ShiftsView] Handling deep link for date: \(dateISO), action: \(action.rawValue)")

        // Store the action to use when selecting the shift
        deepLinkAction = action

        // Parse the date to extract year and month
        guard let date = Date.fromISODateString(dateISO) else {
            print("[ShiftsView] Failed to parse date: \(dateISO)")
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
            print("[ShiftsView] Navigating to \(targetYear)-\(targetMonth)")
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
            print("[ShiftsView] Invalid date format: \(dateISO)")
            highlightedDateISO = nil
            return
        }

        let calendar = Calendar.current
        let targetYear = calendar.component(.year, from: targetDate)
        let targetMonth = calendar.component(.month, from: targetDate)

        // Make sure we're on the correct month before trying to find the shift
        guard viewModel.displayYear == targetYear && viewModel.displayMonth == targetMonth else {
            print("[ShiftsView] Not on target month yet (current: \(viewModel.displayYear)-\(viewModel.displayMonth), target: \(targetYear)-\(targetMonth))")
            // Keep highlightedDateISO - month navigation is still in progress
            return
        }

        // Find shifts on the target date
        let shiftsOnDate = shifts.filter { $0.shiftDate == dateISO }

        guard !shiftsOnDate.isEmpty else {
            print("[ShiftsView] No shifts found for date: \(dateISO) (shifts loaded: \(shifts.count))")
            // Clear highlighted date - we're on the right month but there's no shift
            // This handles the case where the shift was deleted
            highlightedDateISO = nil
            return
        }

        print("[ShiftsView] Found \(shiftsOnDate.count) shift(s) on \(dateISO), action: \(deepLinkAction.rawValue)")

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
                print("[ShiftsView] Highlight-only mode - showing visual highlight for \(dateISO)")
                withAnimation(.easeInOut(duration: 0.3)) {
                    deepLinkHighlightDate = dateISO
                }
                // Auto-clear highlight after 3 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    withAnimation(.easeOut(duration: 0.5)) {
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
                selectedDayForSheet = DayShiftSelection(dateISO: dateISO, shifts: shiftsOnDate)
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

            // Reload to reflect changes
            await viewModel.reloadFromLocal()

            // Post notification for other views
            NotificationCenter.default.post(name: .shiftsDidChange, object: nil)

            shiftToDelete = nil
        } catch {
            // Error handling - could show an alert here
            print("Failed to delete shift: \(error.localizedDescription)")
        }
    }

    // MARK: - Tap Handlers

    /// Handle shift card tap - simply set the item to present
    /// Using .sheet(item:) guarantees the data is available when sheet shows
    private func handleShiftTapped(_ shift: ShiftWithComputations) {
        selectedShift = shift
    }

    /// Handle calendar day tap with single-shift auto-navigation
    private func handleDayTapped(dateISO: String, shifts: [ShiftWithComputations]) {
        if shifts.count == 1, let singleShift = shifts.first {
            // Single shift: go directly to shift details
            selectedShift = singleShift
        } else {
            // Multiple shifts: show day sheet
            selectedDayForSheet = DayShiftSelection(dateISO: dateISO, shifts: shifts)
        }
    }

    // MARK: - Selection Mode Toggle Button

    /// Toggle button for selection mode (calendar view only)
    @ViewBuilder
    private var selectionModeToggleButton: some View {
        Button {
            selectionHaptic.selectionChanged()
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                viewModel.isSelectionModeEnabled.toggle()
            }
        } label: {
            Image(systemName: viewModel.isSelectionModeEnabled ? "checkmark.circle.fill" : "checkmark.circle")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(viewModel.isSelectionModeEnabled ? .tidexBrandPrimary : .tidexTextPrimary)
        }
        .buttonStyle(.plain)
        .contentTransition(.symbolEffect(.replace))
    }

    // MARK: - Transition Phase

    /// Current transition phase for animations
    private var transitionPhase: MonthTransitionPhase {
        MonthTransitionPhase(
            year: viewModel.displayYear,
            month: viewModel.displayMonth,
            direction: viewModel.navigationDirection
        )
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
        HStack(spacing: 48) {
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
        MonthSwipeContainer(
            onSwipeLeft: {
                AppearanceTracker.shared.reset()
                viewModel.goToNextMonth()
            },
            onSwipeRight: {
                AppearanceTracker.shared.reset()
                viewModel.goToPreviousMonth()
            },
            isEnabled: !viewModel.isSelectionModeEnabled
        ) {
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
                        StaggeredCardsContainer(phase: transitionPhase, config: .default) {
                            ShiftsCalendarView(
                                shifts: viewModel.shifts,
                                month: displayedMonthDate,
                                year: viewModel.displayYear,
                                monthNumber: viewModel.displayMonth,
                                currency: viewModel.currency,
                                showEarnings: true,
                                phase: transitionPhase,
                                onDayTapped: { dateISO, shiftsOnDay in
                                    viewModel.handleDayTapped(dateISO: dateISO, shiftsOnDay: shiftsOnDay)
                                },
                                selectedDates: $viewModel.selectedDates,
                                confirmingDelete: viewModel.confirmingDelete,
                                isDeleting: viewModel.isDeleting,
                                selectedEarnings: viewModel.selectedEarnings,
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
                                    let shiftsOnDate = viewModel.selectedDateShifts
                                    if shiftsOnDate.count == 1, let shift = shiftsOnDate.first {
                                        selectedShift = shift
                                    } else if let dateISO = viewModel.selectedDates.first {
                                        selectedDayForSheet = DayShiftSelection(dateISO: dateISO, shifts: shiftsOnDate)
                                    }
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
                                    if !viewModel.selectedDates.isEmpty {
                                        viewModel.clearSelection()
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
                                deepLinkHighlightDate: deepLinkHighlightDate
                            )
                            .padding(.horizontal, 16)
                        }
                        Spacer()
                    }
                    // Offset for month picker overlay
                    .padding(.bottom, MonthPickerLayout.height + MonthPickerLayout.bottomPadding)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    /// Shifts list panel for iPad landscape (right side)
    @ViewBuilder
    private var shiftsPanelForIPad: some View {
        if viewModel.shifts.isEmpty && !viewModel.isCurrentMonth {
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
                .padding(.horizontal, 16)
                .padding(.top, 40)
                .padding(.bottom, MonthPickerLayout.height + MonthPickerLayout.bottomPadding + 16)
            }
            .refreshable {
                AppearanceTracker.shared.reset()
                await viewModel.refresh()
            }
        } else {
            // Shift list
            List {
                ForEach(weekGroupsWithPlaceholder, id: \.weekKey) { weekGroup in
                    Section {
                        ForEach(weekGroup.items) { item in
                            listItemRow(item: item)
                        }
                    } header: {
                        WeekHeaderView(
                            weekNumber: weekGroup.weekNumber,
                            totalGross: weekGroup.totalGross
                        )
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
                        .listRowBackground(Color.tidexBackground)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .contentMargins(.bottom, MonthPickerLayout.height + MonthPickerLayout.bottomPadding + 16, for: .scrollContent)
            .refreshable {
                AppearanceTracker.shared.reset()
                await viewModel.refresh()
            }
        }
    }

    // MARK: - Calendar View Content

    @ViewBuilder
    private var calendarViewContent: some View {
        // MonthSwipeContainer handles horizontal swipes for month navigation
        // Swipes are DISABLED when selection mode is enabled (drag-to-select takes priority)
        MonthSwipeContainer(
            onSwipeLeft: {
                AppearanceTracker.shared.reset()
                viewModel.goToNextMonth()
            },
            onSwipeRight: {
                AppearanceTracker.shared.reset()
                viewModel.goToPreviousMonth()
            },
            isEnabled: !viewModel.isSelectionModeEnabled
        ) {
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
                        StaggeredCardsContainer(phase: transitionPhase, config: .default) {
                            ShiftsCalendarView(
                                shifts: viewModel.shifts,
                                month: displayedMonthDate,
                                year: viewModel.displayYear,
                                monthNumber: viewModel.displayMonth,
                                currency: viewModel.currency,
                                showEarnings: true,
                                phase: transitionPhase,
                                onDayTapped: { dateISO, shiftsOnDay in
                                    viewModel.handleDayTapped(dateISO: dateISO, shiftsOnDay: shiftsOnDay)
                                },
                                selectedDates: $viewModel.selectedDates,
                                confirmingDelete: viewModel.confirmingDelete,
                                isDeleting: viewModel.isDeleting,
                                selectedEarnings: viewModel.selectedEarnings,
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
                                    // Show DayShiftsSheet for multiple shifts, or direct details for single
                                    let shiftsOnDate = viewModel.selectedDateShifts
                                    if shiftsOnDate.count == 1, let shift = shiftsOnDate.first {
                                        selectedShift = shift
                                    } else if let dateISO = viewModel.selectedDates.first {
                                        selectedDayForSheet = DayShiftSelection(dateISO: dateISO, shifts: shiftsOnDate)
                                    }
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

                                    // If shifts are selected, just clear the selection
                                    if !viewModel.selectedDates.isEmpty {
                                        viewModel.clearSelection()
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
                                deepLinkHighlightDate: deepLinkHighlightDate
                            )
                            .frame(maxWidth: AdaptiveMaxWidth.tabContent)
                            .padding(.horizontal, 16)
                        }
                        Spacer()
                    }
                    // Offset for month picker overlay so content centers in available space
                    .padding(.bottom, MonthPickerLayout.height + MonthPickerLayout.bottomPadding)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - List View Content

    @ViewBuilder
    private var listViewContent: some View {
        // Show empty state only when there are no shifts AND it's not current month
        // (current month with no shifts shows just the today placeholder card in the list)
        if viewModel.shifts.isEmpty && !viewModel.isCurrentMonth {
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
                .padding(.horizontal, 16)
                .padding(.top, 40)
                // Add bottom padding for floating MonthPicker
                .padding(.bottom, MonthPickerLayout.height + MonthPickerLayout.bottomPadding + 16)
            }
            .refreshable {
                AppearanceTracker.shared.reset()
                await viewModel.refresh()
            }
        } else {
            // Shift list (includes today placeholder for current month if no shift today)
            shiftListContent
                .refreshable {
                    AppearanceTracker.shared.reset()
                    await viewModel.refresh()
                }
        }
    }

    // MARK: - Shift List Content (shared between calendar and list modes)

    /// Build flat list of items (shifts + placeholder) sorted by date
    private var shiftListItems: [ShiftListItem] {
        var items: [ShiftListItem] = viewModel.shifts.map { .shift($0) }

        // Add today's placeholder if current month and no shift today
        if viewModel.isCurrentMonth {
            let today = todayISO()
            let hasShiftToday = viewModel.shifts.contains { $0.shiftDate == today }
            if !hasShiftToday {
                items.append(.todayPlaceholder)
            }
        }

        // Sort by date
        return items.sorted { $0.sortDate < $1.sortDate }
    }

    /// Group list items by ISO week (preserves placeholder in correct position)
    private var weekGroupsWithPlaceholder: [(weekKey: String, weekNumber: Int, totalGross: Double, items: [ShiftListItem])] {
        var calendar = Calendar(identifier: .iso8601)
        calendar.firstWeekday = 2  // Monday
        calendar.minimumDaysInFirstWeek = 4

        var weekMap: [String: (weekNumber: Int, year: Int, totalGross: Double, items: [ShiftListItem])] = [:]

        for item in shiftListItems {
            guard let date = Date.fromISODateString(item.sortDate) else { continue }

            let weekOfYear = calendar.component(.weekOfYear, from: date)
            let yearForWeek = calendar.component(.yearForWeekOfYear, from: date)
            let weekKey = "\(yearForWeek)-W\(String(format: "%02d", weekOfYear))"

            // Calculate gross (only for shifts)
            let itemGross: Double
            if case .shift(let shift) = item {
                itemGross = shift.grossPay
            } else {
                itemGross = 0
            }

            if var existing = weekMap[weekKey] {
                existing.items.append(item)
                existing.totalGross += itemGross
                weekMap[weekKey] = existing
            } else {
                weekMap[weekKey] = (weekNumber: weekOfYear, year: yearForWeek, totalGross: itemGross, items: [item])
            }
        }

        // Convert to array and sort
        return weekMap.map { (weekKey: $0.key, weekNumber: $0.value.weekNumber, totalGross: $0.value.totalGross, items: $0.value.items) }
            .sorted { $0.weekKey < $1.weekKey }
    }

    @ViewBuilder
    private var shiftListContent: some View {
        // ARCHITECTURE: Using native List with .swipeActions() for reliable gesture handling
        // This is Apple's designed solution - no custom gesture conflicts with scrolling
        // Styled with .listRowBackground() and .listRowSeparator(.hidden) for custom look
        List {
            ForEach(weekGroupsWithPlaceholder, id: \.weekKey) { weekGroup in
                Section {
                    ForEach(weekGroup.items) { item in
                        listItemRow(item: item)
                    }
                } header: {
                    WeekHeaderView(
                        weekNumber: weekGroup.weekNumber,
                        totalGross: weekGroup.totalGross
                    )
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color.tidexBackground)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .frame(maxWidth: AdaptiveMaxWidth.tabContent)
        .frame(maxWidth: .infinity)
        // Add bottom padding so last items can scroll above the floating MonthPicker
        .contentMargins(.bottom, MonthPickerLayout.height + MonthPickerLayout.bottomPadding + 16, for: .scrollContent)
    }

    /// Render a single list item (shift or placeholder)
    @ViewBuilder
    private func listItemRow(item: ShiftListItem) -> some View {
        switch item {
        case .shift(let shift):
            shiftCardRow(shift: shift)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowBackground(Color.tidexBackground)
                .listRowSeparator(.hidden)
                // Native swipe actions - works perfectly with List scrolling
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button {
                        selectionHaptic.selectionChanged()
                        // Open sheet directly in edit mode
                        shiftToEditDirectly = shift
                    } label: {
                        Label("Edit", systemImage: "pencil")
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
                        Label("Delete", systemImage: "trash")
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
            .listRowBackground(Color.tidexBackground)
            .listRowSeparator(.hidden)
        }
    }

    /// Individual shift card row (visual content only - swipe actions are on List row)
    @ViewBuilder
    private func shiftCardRow(shift: ShiftWithComputations) -> some View {
        let isNextUpcoming = viewModel.nextUpcomingShift?.id == shift.id

        VStack(spacing: 8) {
            ShiftRowCard(
                shift: shift,
                isToday: shift.shiftDate == todayISO(),
                hasConflict: viewModel.conflictingShiftIds.contains(shift.id),
                excludedFromTotal: viewModel.excludedFromTotalIds.contains(shift.id),
                onTap: {
                    selectionHaptic.selectionChanged()
                    handleShiftTapped(shift)
                }
            )

            // Show countdown text below next upcoming shift
            if isNextUpcoming {
                NextShiftCountdownText(shift: shift)
            }
        }
    }

    /// Convert displayed year/month to a Date for the calendar
    private var displayedMonthDate: Date {
        var components = DateComponents()
        components.year = viewModel.displayYear
        components.month = viewModel.displayMonth
        components.day = 1
        return Calendar.current.date(from: components) ?? Date()
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .tidexBlue))
                .scaleEffect(1.2)

            Text(localization.string("common.loading"))
                .font(.system(size: 14))
                .foregroundColor(.tidexTextSecondary)
        }
        .frame(maxWidth: AdaptiveMaxWidth.tabContent)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error View

    @ViewBuilder
    private func errorView(error: Error) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.tidexWarning)

            Text(localization.string("shifts.loadError"))
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.tidexTextPrimary)

            Text(error.localizedDescription)
                .font(.system(size: 14))
                .foregroundColor(.tidexTextSecondary)
                .multilineTextAlignment(.center)

            Button {
                Task { await viewModel.loadShifts() }
            } label: {
                Text(localization.string("common.retry"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.tidexBlue)
                    .padding(.horizontal, 20)
                    .padding(.vertical, Spacing.sm)
                    .background(Color.tidexBlue.opacity(0.1))
                    .cornerRadius(8)
            }
        }
        .frame(maxWidth: AdaptiveMaxWidth.tabContent)
        .padding(.horizontal, 40)
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
                .environment(\.localization, LocalizationManager.shared)
        }
    }

    return PreviewWrapper()
}
