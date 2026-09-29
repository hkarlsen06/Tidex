import SwiftUI

private struct FriendsComposerShiftDaySelection: Identifiable {
  let id = UUID()
  let dateISO: String
  let shifts: [ShiftWithComputations]
}

struct FriendsComposerShiftCalendarPicker: View {
  let onSelectShift: (ShiftWithComputations) async -> Bool

  @Environment(\.dismiss) private var dismiss
  @State private var viewModel = ShiftsViewModel()
  @State private var selectedDates: Set<String> = []
  @State private var selectedDayForSheet: FriendsComposerShiftDaySelection?
  @State private var selectedDaySheetContentHeight: CGFloat =
    ContentSizedSheetMetrics.defaultContentHeight
  @State private var isSelectingShift = false

  private var transitionPhase: MonthTransitionPhase {
    MonthTransitionPhase(
      year: viewModel.committedYear,
      month: viewModel.committedMonth,
      direction: viewModel.navigationDirection
    )
  }

  private var displayedMonthDate: Date {
    var components = DateComponents()
    components.year = viewModel.committedYear
    components.month = viewModel.committedMonth
    components.day = 1
    return Calendar.gregorianCurrent.date(from: components) ?? .now
  }

  private var isIPhone: Bool {
    UIDevice.current.userInterfaceIdiom == .phone
  }

  var body: some View {
    NavigationStack {
      GeometryReader { geometry in
        pickerContent(size: geometry.size)
      }
      .navigationTitle(
        .friendsChatComposerShiftPickerTitle
      )
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button(String(localized: .commonCancel)) {
            dismiss()
          }
          .foregroundColor(.tidexBlue)
        }
      }
      .safeAreaInset(edge: .bottom, spacing: 0) {
        bottomMonthPicker
      }
    }
    .interactiveDismissDisabled(isSelectingShift)
    .task {
      await viewModel.loadShifts()
    }
    .sheet(item: $selectedDayForSheet) { daySelection in
      DayShiftsSheet(
        dateISO: daySelection.dateISO,
        shifts: daySelection.shifts,
        onShiftTapped: { shift in
          selectShift(shift, dismissDaySheet: true)
        },
        measuredContentHeight: $selectedDaySheetContentHeight,
        excludedFromTotalIds: viewModel.excludedFromTotalIds
      )
      .presentationDetents([
        .height(ContentSizedSheetMetrics.detentHeight(for: selectedDaySheetContentHeight))
      ])
      .presentationDragIndicator(.visible)
      .interactiveDismissDisabled(isSelectingShift)
    }
  }

  private func pickerContent(size: CGSize) -> some View {
    ZStack {
      Color.tidexBackground
        .ignoresSafeArea()

      VStack {
        Spacer()

        calendarView
          .frame(maxWidth: isIPhone ? .infinity : AdaptiveMaxWidth.tabContent)
          .padding(.horizontal, isIPhone ? Spacing.xs : Spacing.md)
          .padding(.bottom, MonthPickerLayout.totalBottomInset)
          .allowsHitTesting(!isSelectingShift)

        Spacer()
      }

      if isSelectingShift {
        ProgressView()
          .controlSize(.large)
      }
    }
    .frame(width: size.width, height: size.height)
    .contentShape(Rectangle())
    .monthSwipeGesture(
      onSwipeLeft: {
        goToNextMonth()
      },
      onSwipeRight: {
        goToPreviousMonth()
      },
      isEnabled: true
    )
  }

  private var calendarView: some View {
    ShiftsCalendarView(
      shifts: viewModel.shifts,
      month: displayedMonthDate,
      year: viewModel.committedYear,
      monthNumber: viewModel.committedMonth,
      currency: viewModel.currency,
      showEarnings: true,
      jobs: viewModel.activeJobs,
      showsActionBar: false,
      phase: transitionPhase,
      onDayTapped: handleDayTapped(dateISO:shiftsOnDay:),
      onSwipeLeft: goToNextMonth,
      onSwipeRight: goToPreviousMonth,
      selectedDates: $selectedDates,
      confirmingDelete: false,
      isDeleting: false,
      selectedEarnings: nil,
      selectedCurrencyAggregate: nil,
      selectedHasTaxEnabled: false,
      onDelete: nil,
      onConfirmDelete: nil,
      onCancelDelete: nil,
      onCopy: nil,
      onDetails: nil,
      onEdit: nil,
      onMove: nil,
      onClearSelection: nil,
      onEmptyDayTapped: nil,
      isCopyMode: false,
      isMoveMode: false,
      isCopying: false,
      isMoving: false,
      onCopyToDate: nil,
      onMoveToDate: nil,
      onCancelCopyMove: nil,
      newlyAddedDates: [],
      deepLinkHighlightDates: [],
      conflictDates: viewModel.conflictDates,
      excludedFromTotalIds: viewModel.excludedFromTotalIds
    )
  }

  private func handleDayTapped(dateISO: String, shiftsOnDay: [ShiftWithComputations]) {
    guard !isSelectingShift else { return }

    if shiftsOnDay.count == 1, let shift = shiftsOnDay.first {
      selectShift(shift, dismissDaySheet: false)
    } else if !shiftsOnDay.isEmpty {
      selectedDaySheetContentHeight = ContentSizedSheetMetrics.estimatedCardListContentHeight(
        cardCount: shiftsOnDay.count,
        includesSummaryHeader: true
      )
      selectedDayForSheet = FriendsComposerShiftDaySelection(
        dateISO: dateISO,
        shifts: shiftsOnDay
      )
    }
  }

  private func selectShift(_ shift: ShiftWithComputations, dismissDaySheet: Bool) {
    guard !isSelectingShift else { return }

    isSelectingShift = true
    if dismissDaySheet {
      selectedDayForSheet = nil
    }
    dismiss()

    Task {
      _ = await onSelectShift(shift)
      await MainActor.run {
        isSelectingShift = false
      }
    }
  }

  private var bottomMonthPicker: some View {
    AnimatedMonthHeader(
      monthName: viewModel.displayMonthName,
      year: viewModel.displayYear,
      phase: transitionPhase,
      config: .default,
      onPrevious: {
        goToPreviousMonth()
      },
      onNext: {
        goToNextMonth()
      },
      onNavigateToMonth: { year, month in
        AppearanceTracker.shared.reset()
        SharedMonthContext.shared.navigateTo(year: year, month: month)
      },
      isLoading: false
    )
    .frame(maxWidth: AdaptiveMaxWidth.tabContent)
    .frame(maxWidth: .infinity)
    .frame(height: MonthPickerLayout.height)
    .tidexGlass(
      shape: .rect(cornerRadius: MonthPickerLayout.cornerRadius),
      clear: true,
      interactive: true
    )
    .padding(.horizontal, MonthPickerLayout.horizontalPadding)
    .padding(.top, Spacing.xs)
    .padding(.bottom, MonthPickerLayout.bottomPadding)
    .background {
      Color.tidexBackground
        .ignoresSafeArea(edges: .bottom)
    }
  }

  private func goToPreviousMonth() {
    AppearanceTracker.shared.reset()
    viewModel.goToPreviousMonth()
  }

  private func goToNextMonth() {
    AppearanceTracker.shared.reset()
    viewModel.goToNextMonth()
  }
}
