import SwiftUI
import UIKit

/// Add Shift tab view - form for creating new shifts
/// Supports both single shifts and recurring shift patterns
struct AddShiftView: View {
  @EnvironmentObject private var coordinator: AppCoordinator
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @StateObject private var viewModel = AddShiftViewModel()
  @Binding var selectedTab: MainTabView.Tab
  @Binding var isKeyboardVisible: Bool
  @State private var focusedTimeField: TimeInputField?
  @State private var keyboardHeight: CGFloat = 0
  @State private var tabTransitionOffset: CGFloat = 0
  @State private var tabTransitionOpacity: Double = 1
  @State private var showStartFreshConfirmation = false
  @State private var showSingleSuccessBanner = false
  @State private var showAddConfetti = false
  @State private var singleSuccessDismissTask: Task<Void, Never>?
  private let workSetupStatusService = WorkSetupStatusService.shared

  /// Whether running on iPhone-sized idiom.
  private var isIPhone: Bool {
    UIDevice.current.userInterfaceIdiom == .phone
  }

  /// Title for current mode
  private var modeTitle: String {
    switch viewModel.mode {
    case .single:
      return String(localized: .addShiftSingleTitle)
    case .recurring:
      return String(localized: .addShiftRecurringTitle)
    case .events:
      return String(localized: .addShiftEventsTitle)
    }
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

  var body: some View {
    NavigationStack {
      ZStack(alignment: .bottom) {
        // Background that fills entire screen including safe areas
        TidexAppBackground()

        if shouldShowWorkSetupRequiredPlaceholder {
          WorkSetupRequiredPlaceholder()
        } else {
          // Content area - different layouts for single vs recurring mode
          GeometryReader { geometry in
            let availableHeight = geometry.size.height - (MonthPickerLayout.totalBottomInset)

            ScrollViewReader { scrollProxy in
              switch viewModel.mode {
              case .single:
                // Single mode: Fixed layout with centered calendar
                // Uses manual offset for keyboard avoidance to handle 6-week months
                PullToRefreshContainer(onRefresh: {
                  await refreshAddContent()
                }) {
                  VStack(spacing: 0) {
                    Spacer()

                    SingleShiftContent(
                      viewModel: viewModel, scrollProxy: scrollProxy,
                      focusedTimeField: $focusedTimeField
                    )
                    .frame(maxWidth: isIPhone ? .infinity : AdaptiveMaxWidth.tabContent)
                    .padding(.horizontal, isIPhone ? Spacing.xs : Spacing.md)
                    .offset(y: tabTransitionOffset)
                    .opacity(tabTransitionOpacity)

                    Spacer()
                  }
                  .padding(.bottom, MonthPickerLayout.totalBottomInset)
                  .contentShape(Rectangle())
                  .monthSwipeGesture(
                    onSwipeLeft: { viewModel.goToNextMonth() },
                    onSwipeRight: { viewModel.goToPreviousMonth() },
                    isEnabled: true
                  )
                  .offset(y: focusedTimeField != nil ? -keyboardHeight : 0)
                  .motionAnimation(
                    .subtle, value: focusedTimeField != nil, reduceMotion: reduceMotion)
                }
                .ignoresSafeArea(.keyboard)
                .onTapGesture {
                  hideKeyboard()
                }

              case .recurring:
                // Recurring mode: Scrollable content (more elements)
                ScrollView {
                  VStack(spacing: Spacing.lg) {
                    RecurringShiftContent(
                      viewModel: viewModel, scrollProxy: scrollProxy,
                      focusedTimeField: $focusedTimeField)
                  }
                  .frame(maxWidth: isIPhone ? .infinity : AdaptiveMaxWidth.tabContent)
                  .padding(.horizontal, isIPhone ? Spacing.xs : Spacing.md)
                  .padding(.top, Spacing.md)
                  .frame(maxWidth: .infinity)
                  .frame(minHeight: availableHeight, alignment: .center)
                  .offset(y: tabTransitionOffset)
                  .opacity(tabTransitionOpacity)
                }
                .refreshable {
                  await refreshAddContent()
                }
                .scrollDismissesKeyboard(.interactively)
                .contentMargins(
                  .bottom, MonthPickerLayout.totalBottomInset + Spacing.md, for: .scrollContent
                )
                .onTapGesture {
                  hideKeyboard()
                }
              case .events:
                ScrollView {
                  VStack(spacing: Spacing.lg) {
                    EventContent(viewModel: viewModel, focusedTimeField: $focusedTimeField)
                  }
                  .frame(maxWidth: isIPhone ? .infinity : AdaptiveMaxWidth.tabContent)
                  .padding(.horizontal, isIPhone ? Spacing.xs : Spacing.md)
                  .padding(.top, Spacing.md)
                  .frame(maxWidth: .infinity)
                  .frame(minHeight: availableHeight, alignment: .top)
                  .offset(y: tabTransitionOffset)
                  .opacity(tabTransitionOpacity)
                }
                .refreshable {
                  await refreshAddContent()
                }
                .scrollDismissesKeyboard(.interactively)
                .contentMargins(
                  .bottom, MonthPickerLayout.totalBottomInset + Spacing.md, for: .scrollContent
                )
                .onTapGesture {
                  hideKeyboard()
                }
              }
            }
          }
          ConfettiView(isActive: showAddConfetti, launchYRatio: 0.2) {
            showAddConfetti = false
          }
          .allowsHitTesting(false)

          if !isKeyboardVisible {
            if let error = viewModel.error {
              ErrorBanner(
                message: error,
                onRetry: {
                  Task {
                    switch viewModel.mode {
                    case .single:
                      await viewModel.submitSingleShifts()
                    case .recurring:
                      await viewModel.submitRecurringShift()
                    case .events:
                      await viewModel.submitEvent()
                    }
                  }
                },
                onDismiss: { viewModel.error = nil }
              )
              .frame(maxWidth: isIPhone ? .infinity : AdaptiveMaxWidth.tabContent)
              .padding(.horizontal, isIPhone ? Spacing.xs : Spacing.md)
              .padding(.bottom, MonthPickerLayout.totalBottomInset + Spacing.xs)
              .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if showSingleSuccessBanner {
              SuccessBanner(
                message: String(localized: .addShiftSingleSuccessSaved),
                style: .toast,
                actionTitle: .addShiftSingleViewShifts,
                onAction: {
                  dismissSingleSaveSuccessBanner()
                  selectedTab = .shifts
                },
                onDismiss: {
                  dismissSingleSaveSuccessBanner()
                }
              )
              .frame(maxWidth: isIPhone ? .infinity : AdaptiveMaxWidth.tabContent)
              .padding(.horizontal, isIPhone ? Spacing.xs : Spacing.md)
              .padding(.top, Spacing.xs)
              .frame(maxHeight: .infinity, alignment: .top)
              .transition(.move(edge: .top).combined(with: .opacity))
            }
          }
        }
      }
      .navigationBarTitleDisplayMode(.inline)
      .iPadToolbarBackground()
      .toolbar {
        if !shouldShowWorkSetupRequiredPlaceholder {
          ToolbarItem(placement: .topBarLeading) {
            ShiftModeToggle(mode: $viewModel.mode, style: .toolbar)
              .fixedSize()
          }
        }
        if !shouldShowWorkSetupRequiredPlaceholder {
          ToolbarItem(placement: .topBarTrailing) {
            Button {
              presentStartFreshConfirmation()
            } label: {
              Image(systemName: "arrow.uturn.backward.circle.fill")
                .font(.tidexHeadline)
                .foregroundColor(viewModel.hasContent ? .tidexTextPrimary : .tidexTextMuted)
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.hasContent)
            .accessibilityLabel(Text(.commonBack))
          }
          ToolbarSpacer(.fixed, placement: .topBarTrailing)
          ToolbarItem(placement: .topBarTrailing) {
            AddShiftToolbarTotals(totals: viewModel.toolbarTotals)
              .fixedSize(horizontal: true, vertical: false)
          }
          .sharedBackgroundVisibility(.hidden)
        }
      }
      .overlay(alignment: .bottomTrailing) {
        if isKeyboardVisible && !shouldShowWorkSetupRequiredPlaceholder {
          Button(keyboardButtonLabel) {
            handleKeyboardButtonTap()
          }
          .font(.tidexLabelStrong)
          .foregroundColor(.tidexTextPrimary)
          .padding(.horizontal, Spacing.md)
          .padding(.vertical, Spacing.xsm)
          .tidexGlass(shape: .capsule, tint: .tidexBlue.opacity(0.3))
          .padding(.trailing, Spacing.md)
          .padding(.bottom, Spacing.xs)
        }
      }
      .iPadToolbarTransaction()
      .userCurrency(viewModel.currency)
    }
    .task {
      guard !shouldShowWorkSetupRequiredPlaceholder else { return }
      await viewModel.loadData()
    }
    .onAppear {
      guard !shouldShowWorkSetupRequiredPlaceholder else { return }
      viewModel.onShiftsCreated = { completion in
        switch completion {
        case .single(let dates):
          coordinator.pendingDeepLink = .shifts(
            dates: dates.sorted(),
            shiftIds: nil,
            action: .highlight
          )
          selectedTab = .shifts
        case .recurring:
          selectedTab = .shifts
        case .event:
          selectedTab = .shifts
        }
      }

      // Check for pre-selected date when tab becomes visible
      // (e.g., when user taps empty day in Shifts calendar)
      applyPendingPreselectedDateWithoutAnimation()
      handleDeepLink(coordinator.pendingDeepLink)
    }
    .onChange(of: viewModel.error) { _, newError in
      if newError != nil {
        dismissSingleSaveSuccessBanner()
      }
    }
    .onChange(of: viewModel.mode) { _, newMode in
      if newMode != .single {
        dismissSingleSaveSuccessBanner()
      }
    }
    .onChange(of: coordinator.pendingDeepLink) { _, deepLink in
      guard !shouldShowWorkSetupRequiredPlaceholder else { return }
      handleDeepLink(deepLink)
    }
    .onChange(of: selectedTab) { oldTab, newTab in
      if newTab == .add, oldTab == .shifts {
        applyPendingPreselectedDateWithoutAnimation()
        tabTransitionOffset = 28
        tabTransitionOpacity = 0.92
        MotionTokens.animate(.navigationPush, reduceMotion: reduceMotion) {
          tabTransitionOffset = 0
          tabTransitionOpacity = 1
        }
      }

      if newTab == .add, oldTab != .add {
        applyPendingPreselectedDateWithoutAnimation()
      }

      if oldTab == .add, newTab != .add {
        focusedTimeField = nil
        isKeyboardVisible = false
        keyboardHeight = 0
      }
    }
    .onDisappear {
      focusedTimeField = nil
      isKeyboardVisible = false
      keyboardHeight = 0
      showAddConfetti = false
      dismissSingleSaveSuccessBanner()
      viewModel.onShiftsCreated = nil
    }
    .sheet(isPresented: $viewModel.showPreviewSheet) {
      RecurringPreviewSheet(viewModel: viewModel)
    }
    .sheet(isPresented: $viewModel.showMonthLimitSheet) {
      MonthLimitSheet(
        existingMonths: viewModel.existingShiftMonths,
        targetMonth: viewModel.targetMonth,
        onDeleteShifts: {
          await viewModel.deleteShiftsInOtherMonths()
        },
        onDeleteComplete: {
          viewModel.onDeleteComplete()
        },
        onUpgradeComplete: {
          viewModel.onUpgradeComplete()
        }
      )
    }
    .sheet(isPresented: $viewModel.showSubmitJobChooser) {
      AddShiftJobChooserSheet(
        jobs: viewModel.submissionJobs,
        onSelect: { jobId in
          viewModel.selectJobForShiftCreation(jobId)
        },
        onCancel: {
          viewModel.dismissJobSelection()
        }
      )
    }
    .confirmationDialog(
      String(localized: .addShiftStartFreshConfirmTitle),
      isPresented: $showStartFreshConfirmation,
      titleVisibility: .visible
    ) {
      Button(String(localized: .addShiftStartFreshConfirmAction), role: .destructive) {
        focusedTimeField = nil
        hideKeyboard()
        viewModel.startFresh()
      }
      Button(String(localized: .commonCancel), role: .cancel) {}
    } message: {
      Text(.addShiftStartFreshConfirmMessage)
    }
    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification))
    { notification in
      guard selectedTab == .add else { return }
      if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey]
        as? CGRect
      {
        keyboardHeight = keyboardFrame.height
      }
      MotionTokens.animate(.subtle, reduceMotion: reduceMotion) {
        isKeyboardVisible = true
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification))
    { _ in
      guard selectedTab == .add else { return }
      MotionTokens.animate(.subtle, reduceMotion: reduceMotion) {
        isKeyboardVisible = false
        keyboardHeight = 0
      }
    }
  }

  // MARK: - Deep Link Handling

  private func handleDeepLink(_ deepLink: AppCoordinator.DeepLink?) {
    guard case .addShift(let mode) = deepLink else { return }
    if let mode {
      viewModel.applyDeepLinkMode(mode)
    }
    applyPendingPreselectedDateWithoutAnimation()
    coordinator.clearPendingDeepLink()
  }

  private func applyPendingPreselectedDateWithoutAnimation() {
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction) {
      viewModel.checkPreselectedDate()
    }
  }

  private func refreshAddContent() async {
    await viewModel.refreshData()
  }

  private func hideKeyboard() {
    UIApplication.shared.sendAction(
      #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
  }

  /// Show the "start fresh" confirmation when there is form content to clear.
  private func presentStartFreshConfirmation() {
    guard viewModel.hasContent else { return }
    focusedTimeField = nil
    hideKeyboard()
    showStartFreshConfirmation = true
  }

  /// Label for keyboard accessory button - "Next" when in start field, "Done" otherwise
  private var keyboardButtonLabel: String {
    if focusedTimeField == .start {
      return String(localized: .commonNext)
    }
    return String(localized: .commonDone)
  }

  /// Handle keyboard button tap - advance to next field or dismiss
  private func handleKeyboardButtonTap() {
    if focusedTimeField == .start {
      // Move to end time field
      focusedTimeField = .end
    } else {
      // Dismiss keyboard
      focusedTimeField = nil
      hideKeyboard()
    }
  }

  private func showSingleSaveSuccessBanner() {
    dismissSingleSaveSuccessBanner()
    withAnimation {
      showSingleSuccessBanner = true
    }

    singleSuccessDismissTask = Task {
      do {
        try await Task.sleep(nanoseconds: 4_000_000_000)
        guard !Task.isCancelled else { return }
        await MainActor.run {
          withAnimation {
            showSingleSuccessBanner = false
          }
          singleSuccessDismissTask = nil
        }
      } catch {
        // Task cancelled.
      }
    }
  }

  private func dismissSingleSaveSuccessBanner() {
    singleSuccessDismissTask?.cancel()
    singleSuccessDismissTask = nil
    if showSingleSuccessBanner {
      withAnimation {
        showSingleSuccessBanner = false
      }
    }
  }

  private func showAddConfettiCelebration() {
    showAddConfetti = false
    Task { @MainActor in
      await Task.yield()
      showAddConfetti = true
    }
  }
}

// MARK: - Single Shift Content

private struct SingleShiftContent: View {
  @ObservedObject var viewModel: AddShiftViewModel
  var scrollProxy: ScrollViewProxy
  @Binding var focusedTimeField: TimeInputField?

  private var leadingJobAccessory: AnyView? {
    guard viewModel.submissionJobs.count > 1 else { return nil }
    return AnyView(
      AddShiftJobSelectionChip(
        selectedJob: viewModel.selectedJob,
        onTap: { viewModel.presentJobSelection() }
      )
    )
  }

  var body: some View {
    VStack(spacing: Spacing.xs) {
      AddShiftCalendarView(viewModel: viewModel)

      if viewModel.shouldShowSingleTimeScopeHint {
        HStack(spacing: Spacing.xxxs) {
          Image(systemName: "info.circle")
            .font(.tidexMicro)
          Text(.addShiftSingleTimeScopeHint)
            .font(.tidexMicro)
            .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundColor(.tidexTextMuted)
        .frame(maxWidth: .infinity, alignment: .leading)
      }

      TimeRangePicker(
        startTime: $viewModel.startTime,
        endTime: $viewModel.endTime,
        scrollProxy: scrollProxy,
        scrollId: "singleTimePicker",
        focusedFieldBinding: $focusedTimeField,
        leadingChipAccessory: leadingJobAccessory
      )
    }
  }
}

// MARK: - Recurring Shift Content

private struct RecurringShiftContent: View {
  @ObservedObject var viewModel: AddShiftViewModel
  var scrollProxy: ScrollViewProxy
  @Binding var focusedTimeField: TimeInputField?

  private var leadingJobAccessory: AnyView? {
    guard viewModel.submissionJobs.count > 1 else { return nil }
    return AnyView(
      AddShiftJobSelectionChip(
        selectedJob: viewModel.selectedJob,
        onTap: { viewModel.presentJobSelection() }
      )
    )
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.mlg) {
      titleSection

      RecurringCalendarView(viewModel: viewModel)
        .monthSwipeGesture(
          onSwipeLeft: { viewModel.goToNextMonth() },
          onSwipeRight: { viewModel.goToPreviousMonth() },
          isEnabled: true
        )

      // Chip bar showing selected anchor days
      WeekdayChipBar(
        selectedDays: viewModel.selectedDays,
        onRemove: { weekday in
          viewModel.removeAnchor(weekday: weekday)
        }
      )

      Divider()
        .background(Color.tidexBorder)

      TimeRangePicker(
        startTime: $viewModel.startTime,
        endTime: $viewModel.endTime,
        scrollProxy: scrollProxy,
        scrollId: "recurringTimePicker",
        focusedFieldBinding: $focusedTimeField,
        leadingChipAccessory: leadingJobAccessory
      )

      RepeatIntervalPicker(interval: $viewModel.repeatInterval)

      Divider()
        .background(Color.tidexBorder)

      DurationPicker(endCondition: $viewModel.endCondition)
    }
    // Extra bottom padding to clear the month picker
    .padding(.bottom, Spacing.bottomScrollMargin)
  }

  private var titleSection: some View {
    Text(.addShiftRecurringHeader)
      .font(.tidexScreenTitle)
      .foregroundColor(.tidexTextPrimary)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}

// MARK: - Event Content

private struct EventContent: View {
  @ObservedObject var viewModel: AddShiftViewModel
  @Binding var focusedTimeField: TimeInputField?
  @FocusState private var isTitleFieldFocused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.lg) {
      titleSection

      scheduleSection

      remindersSection
    }
  }

  private var titleSection: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      Text(.addShiftEventNoteTitle)
        .font(.tidexScreenTitle)
        .foregroundColor(.tidexTextPrimary)

      TextField(
        String(localized: "addShift.submitRequirements.eventNote", table: "Localizable"),
        text: $viewModel.eventNote,
        axis: .vertical
      )
      .focused($isTitleFieldFocused)
      .textFieldStyle(.plain)
      .font(.tidexBodyLarge)
      .foregroundColor(.tidexTextPrimary)
      .lineLimit(2...5)
      .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
      .padding(.horizontal, Spacing.md)
      .padding(.vertical, Spacing.md)
      .background(
        RoundedRectangle(cornerRadius: CornerRadius.lg)
          .fill(Color.tidexSurfaceSecondary)
      )
      .overlay {
        RoundedRectangle(cornerRadius: CornerRadius.lg)
          .stroke(
            isTitleFieldFocused ? Color.tidexBlue.opacity(0.45) : Color.tidexBorder, lineWidth: 1)
      }
    }
    .contentShape(Rectangle())
    .onTapGesture {
      focusedTimeField = nil
      isTitleFieldFocused = true
    }
  }

  private var scheduleSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      Divider()
        .background(Color.tidexBorder)

      allDayToggleRow

      Divider()
        .background(Color.tidexBorder)

      VStack(spacing: Spacing.md) {
        AddShiftCalendarView(
          viewModel: viewModel,
          selectedDatesOverride: viewModel.eventCalendarSelectedDates,
          previewEarningsOverride: [:],
          onToggleDateOverride: viewModel.toggleEventCalendarDate,
          showSelectionCheckmark: false,
          selectionEmphasis: .subtle
        )
        .monthSwipeGesture(
          onSwipeLeft: { viewModel.goToNextMonth() },
          onSwipeRight: { viewModel.goToPreviousMonth() },
          isEnabled: true
        )
        .simultaneousGesture(
          TapGesture().onEnded {
            isTitleFieldFocused = false
          }
        )

        if viewModel.isEventAllDay {
          eventRangeSummary
        } else {
          TimeRangePicker(
            startTime: $viewModel.startTime,
            endTime: $viewModel.endTime,
            scrollProxy: nil,
            scrollId: "eventTimePicker",
            focusedFieldBinding: $focusedTimeField,
            leadingChipAccessory: nil
          )
        }
      }
      .padding(.top, Spacing.md)
    }
  }

  private var allDayToggleRow: some View {
    HStack(alignment: .center, spacing: Spacing.sm) {
      Text(.addShiftEventAllDay)
        .font(.tidexBodyMedium)
        .foregroundColor(.tidexTextPrimary)

      Spacer(minLength: Spacing.sm)

      Toggle(String(localized: .addShiftEventAllDay), isOn: $viewModel.isEventAllDay)
        .labelsHidden()
        .tint(.tidexBlue)
    }
    .padding(.horizontal, Spacing.sm)
    .padding(.vertical, Spacing.xsm)
  }

  private var eventRangeSummary: some View {
    HStack(spacing: Spacing.xxxs) {
      Image(systemName: "arrow.left.and.right")
        .font(.tidexMicro)
      Text(rangeSummaryText)
        .font(.tidexMicro)
        .fixedSize(horizontal: false, vertical: true)
    }
    .foregroundColor(.tidexTextMuted)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var rangeSummaryText: String {
    if Calendar.current.isDate(viewModel.eventStartDate, inSameDayAs: viewModel.eventEndDate) {
      return viewModel.eventStartDate.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    return
      "\(viewModel.eventStartDate.formatted(.dateTime.day().month(.abbreviated))) - \(viewModel.eventEndDate.formatted(.dateTime.day().month(.abbreviated)))"
  }

  private var remindersSection: some View {
    EventReminderEditorSection(
      reminderTimes: $viewModel.eventReminderTimes,
      anchorTime: $viewModel.eventReminderAnchorTime,
      isAllDay: viewModel.isEventAllDay,
      isEditable: true,
      showsPastEventHint: false
    )
    .padding(Spacing.lg)
    .background(
      RoundedRectangle(cornerRadius: CornerRadius.xxl)
        .fill(Color.tidexSurfacePrimary)
    )
  }
}

private struct AddShiftJobSelectionChip: View {
  let selectedJob: Job?
  let onTap: () -> Void

  var body: some View {
    Button(action: onTap) {
      HStack(spacing: Spacing.xxxs) {
        if let selectedJob {
          WorkplaceNameText(
            name: selectedJob.name,
            colorHex: selectedJob.color,
            font: .tidexMonoCaption,
            fallbackBadgeColor: .tidexBlue,
            badgeHorizontalPadding: Spacing.xs,
            badgeVerticalPadding: 2
          )
          .lineLimit(1)
          .truncationMode(.tail)
        } else {
          HStack(spacing: Spacing.xxxs) {
            Image(systemName: "building.2")
              .font(.tidexCaptionRegular)
              .foregroundColor(.tidexBlue)

            Text(String(localized: "settings.pay.choose_workplace.title"))
              .font(.tidexMonoCaption)
              .foregroundColor(.tidexBlue)
          }
          .padding(.horizontal, Spacing.sm)
          .padding(.vertical, Spacing.xs)
          .background(Color.tidexBlue.opacity(0.12))
          .clipShape(Capsule())
        }

        Image(systemName: "chevron.down")
          .font(.tidexMicro)
          .foregroundColor(.tidexTextMuted)
      }
      .frame(height: 36)
    }
    .buttonStyle(.plain)
  }
}

private struct AddShiftJobChooserSheet: View {
  let jobs: [Job]
  let onSelect: (String) -> Void
  let onCancel: () -> Void

  private var detentHeight: CGFloat {
    let visibleRows = max(1, min(jobs.count, 4))
    return CGFloat(visibleRows) * 70 + 120
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: Spacing.sm) {
          ForEach(jobs, id: \.id) { job in
            Button {
              onSelect(job.id)
            } label: {
              HStack(spacing: Spacing.sm) {
                WorkplaceNameText(
                  name: job.name,
                  colorHex: job.color,
                  font: .tidexBodyMedium,
                  fallbackBadgeColor: .tidexBlue
                )

                Spacer()

                Image(systemName: "chevron.right")
                  .font(.tidexCaptionRegular)
                  .foregroundColor(.tidexTextMuted)
              }
              .padding(.horizontal, Spacing.md)
              .padding(.vertical, Spacing.md)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(Color.tidexSurfaceSecondary)
              .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
              .contentShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
          }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.sm)
        .padding(.bottom, Spacing.md)
      }
      .scrollIndicators(.hidden)
      .background(Color.tidexBackground)
      .navigationTitle(String(localized: "settings.pay.choose_workplace.title"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(String(localized: .commonCancel)) {
            onCancel()
          }
        }
      }
    }
    .presentationDetents([.height(detentHeight)])
    .presentationDragIndicator(.visible)
  }
}

// MARK: - Toolbar Totals

/// Compact earnings display for the Add tab toolbar trailing position.
/// Shows the combined monthly total (existing shifts + preview earnings).
private struct AddShiftToolbarTotals: View {
  let totals: CalendarHeaderTotals?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  @State private var lastDisplayedPrimary: Double = 0
  @State private var lastDisplayedSecondary: Double = 0

  var body: some View {
    Group {
      if let totals, let primary = totals.primary {
        VStack(alignment: .trailing, spacing: Spacing.micro) {
          animatedAmount(
            primary,
            lastDisplayed: lastDisplayedPrimary,
            onUpdate: { lastDisplayedPrimary = $0 }
          )
          .font(.tidexHeadline)
          .foregroundColor(.tidexTextPrimary)

          if let secondary = totals.secondary {
            HStack(alignment: .center, spacing: Spacing.xxxs) {
              Image(systemName: "plus")
                .font(.caption2.weight(.bold))

              animatedAmount(
                secondary,
                lastDisplayed: lastDisplayedSecondary,
                onUpdate: { lastDisplayedSecondary = $0 },
                allowsZero: true
              )
              .font(.tidexFootnote)
            }
            .foregroundColor(.tidexBlue)
            .transition(.offset(y: -4).combined(with: .opacity))
          }
        }
        .transition(.offset(x: 6).combined(with: .opacity))
      }
    }
    .motionAnimation(.emphasis, value: totals?.primary, reduceMotion: reduceMotion)
    .motionAnimation(.emphasis, value: totals?.secondary, reduceMotion: reduceMotion)
  }

  @ViewBuilder
  private func animatedAmount(
    _ amount: Double?,
    lastDisplayed: Double,
    onUpdate: @escaping (Double) -> Void,
    allowsZero: Bool = false
  ) -> some View {
    if let amount, allowsZero ? amount >= 0 : amount > 0 {
      CurrencyCountUpText(
        amount: amount,
        animateOnAppear: false,
        animateFrom: lastDisplayed > 0 ? lastDisplayed : nil
      )
      .onChange(of: amount) { _, newValue in
        onUpdate(newValue)
      }
      .onAppear {
        if lastDisplayed == 0 {
          onUpdate(amount)
        }
      }
    }
  }
}

// MARK: - Preview

#Preview {
  AddShiftView(selectedTab: .constant(.add), isKeyboardVisible: .constant(false))
    .environmentObject(AppCoordinator.shared)
}
