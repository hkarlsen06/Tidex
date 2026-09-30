import SwiftUI

/// Lists one month of the user's shifts so one can be attached to a chat message.
/// The picker keeps its own month, so browsing here does not move the Schedule tab.
struct FriendsComposerShiftCalendarPicker: View {
  let onSelectShift: (ShiftWithComputations) async -> Bool

  @Environment(\.dismiss) private var dismiss
  @State private var monthContext: SharedMonthContext
  @State private var viewModel: ShiftsViewModel
  @State private var selectingShiftID: String?

  init(onSelectShift: @escaping (ShiftWithComputations) async -> Bool) {
    self.onSelectShift = onSelectShift
    let monthContext = SharedMonthContext()
    _monthContext = State(initialValue: monthContext)
    _viewModel = State(initialValue: ShiftsViewModel(monthContext: monthContext))
  }

  private var transitionPhase: MonthTransitionPhase {
    MonthTransitionPhase(
      year: viewModel.committedYear,
      month: viewModel.committedMonth,
      direction: viewModel.navigationDirection
    )
  }

  /// The view model also loads the padding days the calendar shows, so keep only this month.
  private var monthShifts: [ShiftWithComputations] {
    let prefix = String(format: "%04d-%02d-", viewModel.committedYear, viewModel.committedMonth)
    return viewModel.shifts
      .filter { $0.shiftDate.hasPrefix(prefix) }
      .sorted { ($0.shiftDate, $0.startTime) < ($1.shiftDate, $1.startTime) }
  }

  /// In the current month, start at the next shift since that is the one most often shared.
  private var initialScrollTargetID: String? {
    guard viewModel.isCurrentMonth else { return nil }
    let today = todayISO()
    return monthShifts.first { $0.shiftDate >= today }?.id
  }

  var body: some View {
    NavigationStack {
      content
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.tidexBackground.ignoresSafeArea())
        .contentShape(Rectangle())
        .monthSwipeGesture(onSwipeLeft: goToNextMonth, onSwipeRight: goToPreviousMonth)
        .navigationTitle(.friendsChatComposerShiftPickerTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .topBarLeading) {
            Button(String(localized: .commonCancel)) {
              dismiss()
            }
            .foregroundColor(.tidexBlueText)
          }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
          bottomMonthPicker
        }
    }
    .userCurrency(viewModel.currency)
    .interactiveDismissDisabled(selectingShiftID != nil)
    .task {
      await viewModel.loadShifts()
    }
  }

  @ViewBuilder
  private var content: some View {
    if monthShifts.isEmpty {
      if viewModel.isLoading {
        ProgressView()
          .controlSize(.large)
      } else if let error = viewModel.error {
        errorState(error)
      } else {
        emptyState
      }
    } else {
      shiftList
    }
  }

  private var shiftList: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(spacing: Spacing.sm) {
          ForEach(monthShifts) { shift in
            shiftRow(shift)
              .id(shift.id)
          }
        }
        .frame(maxWidth: AdaptiveMaxWidth.tabContent)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
      }
      .allowsHitTesting(selectingShiftID == nil)
      .task(id: initialScrollTargetID) {
        guard let initialScrollTargetID else { return }
        proxy.scrollTo(initialScrollTargetID, anchor: .top)
      }
    }
  }

  private func shiftRow(_ shift: ShiftWithComputations) -> some View {
    let job = viewModel.jobForShift(shift)
    let isSelecting = selectingShiftID == shift.id

    return ShiftRowCard(
      shift: shift,
      isToday: shift.shiftDate == todayISO(),
      showJobIndicator: viewModel.shouldShowJobIndicators,
      jobName: job?.name,
      jobColorHex: job?.color,
      onTap: { select(shift) }
    )
    .opacity(selectingShiftID == nil || isSelecting ? 1 : 0.5)
    .overlay {
      if isSelecting {
        ProgressView()
      }
    }
  }

  private var emptyState: some View {
    VStack(spacing: Spacing.md) {
      Image(systemName: "calendar.badge.minus")
        .font(.largeTitle)
        .foregroundColor(.tidexTextMuted)
        .accessibilityHidden(true)
      Text(.shiftsEmptyNoShiftsThisMonth)
        .font(.tidexBodyMedium)
        .foregroundColor(.tidexTextPrimary)
        .multilineTextAlignment(.center)
    }
    .padding(Spacing.lg)
  }

  private func errorState(_ error: Error) -> some View {
    VStack(spacing: Spacing.md) {
      Image(systemName: "exclamationmark.triangle")
        .font(.largeTitle)
        .foregroundColor(.tidexWarning)
        .accessibilityHidden(true)
      Text(.shiftsLoadError)
        .font(.tidexBodyMedium)
        .foregroundColor(.tidexTextPrimary)
      Text(error.localizedDescription)
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextSecondary)
        .multilineTextAlignment(.center)
      Button(String(localized: .commonRetry)) {
        Task { await viewModel.loadShifts() }
      }
      .font(.tidexLabel)
      .foregroundColor(.tidexBlueText)
    }
    .padding(Spacing.lg)
  }

  private var bottomMonthPicker: some View {
    AnimatedMonthHeader(
      monthName: viewModel.displayMonthName,
      year: viewModel.committedYear,
      phase: transitionPhase,
      config: .default,
      onPrevious: goToPreviousMonth,
      onNext: goToNextMonth,
      onNavigateToMonth: { year, month in
        monthContext.navigateTo(year: year, month: month)
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

  private func select(_ shift: ShiftWithComputations) {
    guard selectingShiftID == nil else { return }

    Haptics.play(.selection)
    selectingShiftID = shift.id

    Task {
      // On success the composer closes this sheet itself. On failure it shows the
      // error in the composer, so close the sheet either way.
      _ = await onSelectShift(shift)
      selectingShiftID = nil
      dismiss()
    }
  }

  private func goToPreviousMonth() {
    guard selectingShiftID == nil else { return }
    monthContext.goToPreviousMonth()
  }

  private func goToNextMonth() {
    guard selectingShiftID == nil else { return }
    monthContext.goToNextMonth()
  }
}
