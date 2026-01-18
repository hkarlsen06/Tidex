import SwiftUI

/// Helper struct for day sheet selection (must be Identifiable for .sheet(item:))
private struct DayShiftSelection: Identifiable {
    let id = UUID()
    let dateISO: String
    let shifts: [ShiftWithComputations]
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

    // State for day shifts sheet (when tapping a calendar day)
    @State private var selectedDayForSheet: DayShiftSelection?

    // Celebration state
    @State private var showConfetti = false

    // View mode toggle (calendar vs list) - persisted across app launches
    @AppStorage("shiftsViewMode") private var showListView = false

    // Haptic feedback
    private let selectionHaptic = UISelectionFeedbackGenerator()
    private let impactHaptic = UIImpactFeedbackGenerator(style: .medium)
    private let celebrationHaptic = UINotificationFeedbackGenerator()

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                // Background that fills entire screen including safe areas
                Color.tidexBackground
                    .ignoresSafeArea()

                // Main layout: content area + month picker at bottom
                VStack(spacing: 0) {
                    // Content area - fills available space above month picker
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

                    // Month picker - ALWAYS visible for navigation (liquid glass style)
                    // Matches tab bar dimensions exactly
                    AnimatedMonthHeader(
                        monthName: viewModel.displayMonthName,
                        year: viewModel.displayYear,
                        phase: transitionPhase,
                        isCurrentMonth: viewModel.isCurrentMonth,
                        config: .default,
                        onPrevious: {
                            // Reset appearance tracker for fresh animations
                            AppearanceTracker.shared.reset()
                            viewModel.goToPreviousMonth()
                        },
                        onNext: {
                            // Reset appearance tracker for fresh animations
                            AppearanceTracker.shared.reset()
                            viewModel.goToNextMonth()
                        },
                        onReturnToCurrent: {
                            // Reset appearance tracker for fresh animations
                            AppearanceTracker.shared.reset()
                            viewModel.goToCurrentMonth()
                        },
                        isLoading: viewModel.isLoading,
                        backToTodayText: localization.string("dashboard.backToToday")
                    )
                    .frame(height: 56)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 30))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
            }
            .navigationTitle(localization.string(AppTab.shifts.titleKey))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.tidexBackground, for: .navigationBar)
            .toolbar {
                // View mode toggle (calendar/list)
                ToolbarItem(placement: .topBarLeading) {
                    viewModeToggleButton
                }
                // Selection mode toggle (only in calendar view) - spacer separates it
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
                }
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

    // MARK: - View Mode Toggle Button

    /// Toggle button to switch between calendar and list views
    @ViewBuilder
    private var viewModeToggleButton: some View {
        Button {
            selectionHaptic.selectionChanged()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                showListView.toggle()
                // Exit selection mode when switching to list view
                if showListView {
                    viewModel.isSelectionModeEnabled = false
                }
            }
        } label: {
            Image(systemName: showListView ? "calendar" : "list.bullet")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.tidexTextPrimary)
        }
        .buttonStyle(.plain)
        .contentTransition(.symbolEffect(.replace))
    }

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
        if showListView {
            // List view mode - just the shift cards without calendar
            listViewContent
        } else {
            // Calendar view mode - calendar + shift list below
            calendarViewContent
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

                    // Calendar content
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
                                newlyAddedDates: celebrationManager.newlyAddedDates
                            )
                            .padding(.horizontal, 16)
                        }
                        Spacer()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - List View Content

    @ViewBuilder
    private var listViewContent: some View {
        if viewModel.shifts.isEmpty {
            // Empty state - use ScrollView for pull-to-refresh
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
            }
            .refreshable {
                AppearanceTracker.shared.reset()
                await viewModel.refresh()
            }
        } else {
            // Shift list - List has its own scrolling, don't wrap in ScrollView
            shiftListContent
                .refreshable {
                    AppearanceTracker.shared.reset()
                    await viewModel.refresh()
                }
        }
    }

    // MARK: - Shift List Content (shared between calendar and list modes)

    @ViewBuilder
    private var shiftListContent: some View {
        // ARCHITECTURE: Using native List with .swipeActions() for reliable gesture handling
        // This is Apple's designed solution - no custom gesture conflicts with scrolling
        // Styled with .listRowBackground() and .listRowSeparator(.hidden) for custom look
        List {
            ForEach(viewModel.weekGroups) { weekGroup in
                Section {
                    ForEach(weekGroup.shifts) { shift in
                        shiftCardRow(shift: shift)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .listRowBackground(Color.tidexBackground)
                            .listRowSeparator(.hidden)
                            // Native swipe actions - works perfectly with List scrolling
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    selectionHaptic.selectionChanged()
                                    handleShiftTapped(shift)
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
        .background(Color.tidexBackground)
    }

    /// Individual shift card row (visual content only - swipe actions are on List row)
    @ViewBuilder
    private func shiftCardRow(shift: ShiftWithComputations) -> some View {
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
                    .padding(.vertical, 10)
                    .background(Color.tidexBlue.opacity(0.1))
                    .cornerRadius(8)
            }
        }
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
