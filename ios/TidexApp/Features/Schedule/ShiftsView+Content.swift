import Observation
import SwiftUI
import os.log

extension ShiftsView {

  // MARK: - Bottom Toolbar

  func publishToolbarState() {
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
  var shiftsContent: some View {
    if usesWideCalendarLayout && !showListView {
      // Wide layout: calendar and shift list side by side.
      wideCalendarContent
    } else if showListView {
      // List view mode - just the shift cards without calendar
      listViewContent
    } else {
      // Calendar view mode - calendar + shift list below
      calendarViewContent
    }
  }

  // MARK: - Wide calendar content

  /// Calendar and shift list share the available width.
  @ViewBuilder
  private var wideCalendarContent: some View {
    HStack(spacing: Spacing.xxxl) {
      Spacer()

      // Left side: Calendar
      calendarPanelForWideLayout
        .frame(maxWidth: min(500, max(350, availableSize.height * 0.6)))

      // Right side: Shifts list
      shiftsPanelForWideLayout
        .frame(maxWidth: 480)

      Spacer()
    }
  }

  /// Calendar panel in the wide layout.
  @ViewBuilder
  private var calendarPanelForWideLayout: some View {
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
            .accessibilityHidden(true)

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
                beginShiftOperation(.copy)
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
                beginShiftOperation(.move)
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

  func refreshHasAnyShifts() {
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

  /// Shift list beside the calendar.
  @ViewBuilder
  private var shiftsPanelForWideLayout: some View {
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
                  .id(item.id)
              }
            } header: {
              WeekHeaderView(
                weekNumber: weekGroup.weekNumber,
                totalGross: weekGroup.totalGross
              )
              .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
              .listRowBackground(Color.clear)
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
      GeometryReader { geometry in  // swiftlint:disable:this closure_body_length
        let calendarWidth =
          geometry.size.width >= 700
          ? min(AdaptiveMaxWidth.tabContent, max(350, geometry.size.height * 0.7))
          : AdaptiveMaxWidth.tabContent
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
            .accessibilityHidden(true)

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
                beginShiftOperation(.copy)
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
                beginShiftOperation(.move)
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
            .frame(maxWidth: calendarWidth)
            .padding(.horizontal, horizontalSizeClass == .regular ? Spacing.md : Spacing.xs)
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
    showListView || usesWideCalendarLayout
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
  func recomputeListDerivedDataIfNeeded(force: Bool = false) {
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
          withAnimation(reduceMotion ? nil : .default) { scrollToTodayItem(using: proxy) }
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
            .id(item.id)
        }
      } header: {
        WeekHeaderView(
          weekNumber: weekGroup.weekNumber,
          totalGross: weekGroup.totalGross
        )
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
        .listRowBackground(Color.clear)
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
      withAnimation(reduceMotion ? nil : .default) { scrollToTodayItem(using: proxy) }
    } else if let firstId = weekGroupsWithPlaceholder.first?.items.first?.id {
      withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo(firstId, anchor: .top) }
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

  /// Opens the Add screen in single mode, optionally with a date selected.
  /// A date opens it directly, because this view re-renders whenever `pendingDeepLink`
  /// changes, and Add would set and then clear it. Add switches to single mode for the date.
  private func openAddShift(preselectedDate dateISO: String? = nil) {
    guard let dateISO else {
      coordinator.pendingDeepLink = .addShift(mode: .single, date: nil)
      return
    }
    SharedMonthContext.shared.preselectedDate = dateISO
    AddShiftNavigator.shared.hostTab = .shifts
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
          .foregroundStyle(Color.tidexTextMuted)
        Text(.jobsFilterTitle)
          .font(.tidexLabel)
          .foregroundStyle(Color.tidexTextSecondary)
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
      } else {
        Text(title)
          .font(.tidexFootnoteStrong)
          .foregroundStyle(isSelected ? Color.tidexTextOnBrand : Color.tidexTextPrimary)
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
  func errorView(message: String) -> some View {
    VStack(spacing: Spacing.md) {
      Image(systemName: "exclamationmark.triangle")
        .font(.system(size: errorIconSize))
        .foregroundStyle(Color.tidexWarning)
        .accessibilityHidden(true)

      Text(.shiftsLoadError)
        .font(.tidexBodyMedium)
        .foregroundStyle(Color.tidexTextPrimary)

      Text(message)
        .font(.tidexSubheadline)
        .foregroundStyle(Color.tidexTextSecondary)
        .multilineTextAlignment(.center)
        .announcesToVoiceOver(message)

      Button {
        Task { await viewModel.loadShifts() }
      } label: {
        Text(.commonRetry)
          .font(.tidexLabel)
          .foregroundStyle(Color.tidexBlueText)
          .padding(.horizontal, Spacing.mlg)
          .padding(.vertical, Spacing.sm)
          .background(Color.tidexBlue.opacity(0.1))
          .clipShape(.rect(cornerRadius: CornerRadius.sm))
      }
    }
    .frame(maxWidth: AdaptiveMaxWidth.tabContent)
    .padding(.horizontal, Spacing.xxl)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
