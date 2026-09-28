import SwiftUI
import UIKit

/// Add Shift screen, pushed onto the current tab's navigation stack - form for creating new shifts
/// Supports both single shifts and recurring shift patterns
struct AddShiftView: View {
  private static let payManagerCompactDetent: PresentationDetent = .height(395)
  private static let jobPickerMaxNameWidth: CGFloat = 140
  /// Space kept free for the two rows of bottom controls.
  private static let bottomControlsInset: CGFloat =
    MonthPickerLayout.height * 2 + Spacing.xs + MonthPickerLayout.bottomPadding

  @Environment(AppCoordinator.self) private var coordinator
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private let addShiftCoordinator = AddShiftCoordinator.shared
  @State private var viewModel = AddShiftViewModel()
  @State private var workSetupPresentationViewModel = WorkSetupPresentationViewModel()
  /// Called after saving so the presenter can pop the screen.
  /// Receives the created dates in single mode, and nil for recurring shifts and events.
  var onShiftsCreated: (_ singleDates: Set<String>?) -> Void = { _ in }
  @State private var isKeyboardVisible = false
  @State private var focusedTimeField: TimeInputField?
  @State private var keyboardHeight: CGFloat = 0
  @State private var showStartFreshConfirmation = false
  @State private var showSubmitRequirementsAlert = false
  @State private var showAddJobSheet = false
  @State private var openJobsAndPaySettingsAfterPickerDismiss = false
  @State private var showPaySettings = false
  @State private var paySettingsDetent: PresentationDetent = Self.payManagerCompactDetent

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

  private func refreshWorkSetupPresentationState() {
    workSetupPresentationViewModel.refresh(
      userId: coordinator.userId,
      initialSyncComplete: coordinator.initialSyncComplete
    )
  }

  private var shouldShowWorkSetupRequiredPlaceholder: Bool {
    workSetupPresentationViewModel.shouldShowPlaceholder
  }

  private func loadAddShiftContent() async {
    guard !shouldShowWorkSetupRequiredPlaceholder else { return }
    await viewModel.loadData()
  }

  private func prepareVisibleAddShiftContent() {
    guard !shouldShowWorkSetupRequiredPlaceholder else { return }
    viewModel.onShiftsCreated = { completion in
      switch completion {
      case .single(let dates):
        onShiftsCreated(dates)

      case .recurring, .event:
        onShiftsCreated(nil)
      }
    }

    // Check for pre-selected date when the screen opens
    // (e.g., when user taps empty day in Shifts calendar)
    applyPendingPreselectedDateWithoutAnimation()
    handleDeepLink(coordinator.pendingDeepLink)
  }

  var body: some View {
    Group {
      ZStack(alignment: .bottom) {
        // Background that fills entire screen including safe areas
        TidexAppBackground()

        if shouldShowWorkSetupRequiredPlaceholder {
          WorkSetupRequiredPlaceholder()
        } else {
          // Content area - different layouts for single vs recurring mode
          GeometryReader { geometry in
            let availableHeight = geometry.size.height - Self.bottomControlsInset

            ScrollViewReader { scrollProxy in
              switch viewModel.mode {
              case .single:
                // Single mode: centered calendar that only scrolls when it doesn't fit.
                // No pull-to-refresh, so dragging down never fights the back gesture.
                // Uses manual offset for keyboard avoidance to handle 6-week months
                ScrollView {
                  VStack(spacing: 0) {
                    Spacer()

                    SingleShiftContent(
                      viewModel: viewModel, scrollProxy: scrollProxy,
                      focusedTimeField: $focusedTimeField
                    )
                    .frame(maxWidth: isIPhone ? .infinity : AdaptiveMaxWidth.tabContent)
                    .padding(.horizontal, isIPhone ? Spacing.xs : Spacing.md)

                    Spacer()
                  }
                  // Fill exactly the space above the controls, so it only scrolls on screens
                  // too small for the calendar.
                  .frame(minHeight: availableHeight)
                  .padding(.bottom, Self.bottomControlsInset)
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
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
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
                }
                .scrollDismissesKeyboard(.interactively)
                .contentMargins(
                  .bottom, Self.bottomControlsInset + Spacing.md, for: .scrollContent
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
                }
                .scrollDismissesKeyboard(.interactively)
                .contentMargins(
                  .bottom, Self.bottomControlsInset + Spacing.md, for: .scrollContent
                )
                .onTapGesture {
                  hideKeyboard()
                }
              }
            }
          }
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
              .padding(.bottom, Self.bottomControlsInset + Spacing.xs)
              .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            bottomControls
              .transition(.opacity)
          }
        }
      }
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        if !shouldShowWorkSetupRequiredPlaceholder {
          ToolbarItem(placement: .topBarTrailing) {
            ShiftModeToggle(mode: $viewModel.mode, style: .toolbar)
              .fixedSize()
          }
        }
      }
      .overlay(alignment: .bottomTrailing) {
        if isKeyboardVisible, !shouldShowWorkSetupRequiredPlaceholder {
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
    .background(FullWidthBackSwipeBlocker())
    .disabled(viewModel.isLoading)
    .task {
      refreshWorkSetupPresentationState()
      await loadAddShiftContent()
    }
    .onAppear {
      refreshWorkSetupPresentationState()
      prepareVisibleAddShiftContent()
    }
    .onChange(of: coordinator.initialSyncComplete) { _, completed in
      refreshWorkSetupPresentationState()
      guard completed, !shouldShowWorkSetupRequiredPlaceholder else { return }
      prepareVisibleAddShiftContent()
      Task {
        await loadAddShiftContent()
      }
    }
    .onChange(of: coordinator.userId) { _, _ in
      refreshWorkSetupPresentationState()
    }
    .onReceive(NotificationCenter.default.publisher(for: .workSetupDataDidChange)) { _ in
      refreshWorkSetupPresentationState()
      guard !shouldShowWorkSetupRequiredPlaceholder else { return }
      prepareVisibleAddShiftContent()
      Task {
        await loadAddShiftContent()
      }
    }
    .onChange(of: coordinator.pendingDeepLink) { _, deepLink in
      guard !shouldShowWorkSetupRequiredPlaceholder else { return }
      handleDeepLink(deepLink)
    }
    .onDisappear {
      focusedTimeField = nil
      isKeyboardVisible = false
      keyboardHeight = 0
      viewModel.onShiftsCreated = nil
      // An unconsumed add link (for example while work setup is required) would
      // otherwise block the next identical request from reopening the sheet.
      if case .addShift = coordinator.pendingDeepLink {
        coordinator.clearPendingDeepLink()
      }
    }
    .sheet(isPresented: $viewModel.showPreviewSheet) {
      RecurringPreviewSheet(viewModel: viewModel)
    }
    .sheet(
      isPresented: $viewModel.showSubmitJobChooser,
      onDismiss: {
        guard openJobsAndPaySettingsAfterPickerDismiss else { return }
        openJobsAndPaySettingsAfterPickerDismiss = false
        paySettingsDetent = Self.payManagerCompactDetent
        showPaySettings = true
      }
    ) {
      JobChooserSheet(
        jobs: viewModel.submissionJobs,
        configuredJobIds: viewModel.configuredJobIds,
        onAddJob: {
          viewModel.dismissJobSelection()
          showAddJobSheet = true
        },
        onOpenSettings: {
          openJobsAndPaySettingsAfterPickerDismiss = true
          viewModel.dismissJobSelection()
        },
        onSelect: { jobId in
          viewModel.selectJobForShiftCreation(jobId)
          viewModel.dismissJobSelection()
        },
        onCancel: {
          viewModel.dismissJobSelection()
        }
      )
    }
    .sheet(isPresented: $showPaySettings) {
      SettingsView(
        initialDestination: .pay(jobId: nil),
        sheetPresentationDetent: $paySettingsDetent,
        directPayManagerCompactDetent: Self.payManagerCompactDetent
      )
      .presentationDetents(
        [Self.payManagerCompactDetent, .large], selection: $paySettingsDetent
      )
      .presentationDragIndicator(.visible)
    }
    .sheet(isPresented: $showAddJobSheet) {
      AddJobSheet(
        initialCurrency: viewModel.jobCreationInitialCurrency,
        initialPayrollDay: viewModel.jobCreationInitialPayrollDay,
        setupDismissTitle: String(localized: .settingsPaySetupLaterButton),
        onSaveBasics: { input in
          await viewModel.createBasicJobForSetup(input: input)
        }
      ) { input in
        await viewModel.createConfiguredJob(input: input)
      }
    }
    .sheet(item: $viewModel.paySetupRequest) { request in
      JobPaySetupSheet(
        job: request.job,
        initialCurrency: request.job.currency,
        dismissTitle: String(localized: .settingsPaySetupLaterButton)
      ) { input in
        await viewModel.completePaySetup(for: request.job, input: input)
      }
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
    .alert(
      String(localized: .addShiftSubmitRequirementsTitle),
      isPresented: $showSubmitRequirementsAlert
    ) {
      Button(String(localized: .commonOk), role: .cancel) {}
    } message: {
      Text(submitRequirementsMessage)
    }
    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification))
    { notification in
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
      MotionTokens.animate(.subtle, reduceMotion: reduceMotion) {
        isKeyboardVisible = false
        keyboardHeight = 0
      }
    }
  }

  // MARK: - Deep Link Handling

  private func handleDeepLink(_ deepLink: AppCoordinator.DeepLink?) {
    guard case .addShift(let mode, let date) = deepLink else { return }
    if let date, Date.fromISODateString(date) != nil {
      SharedMonthContext.shared.preselectedDate = date
    }
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

  // MARK: - Bottom Controls

  /// Job picker and Add above, undo and month picker below, pinned to the bottom.
  @ViewBuilder
  private var bottomControls: some View {
    if !shouldShowWorkSetupRequiredPlaceholder {
      VStack(spacing: Spacing.xs) {
        HStack(spacing: Spacing.xs) {
          if viewModel.mode != .events {
            jobPickerButton
          }
          saveButton
        }

        HStack(spacing: Spacing.xs) {
          startFreshButton

          SharedMonthPicker()
            .frame(maxWidth: .infinity)
            .frame(height: MonthPickerLayout.height)
            .tidexGlass(
              shape: .rect(cornerRadius: MonthPickerLayout.cornerRadius),
              interactive: true
            )
        }
      }
      .frame(maxWidth: AdaptiveMaxWidth.tabContent)
      .padding(.horizontal, Spacing.md)
      .padding(.bottom, MonthPickerLayout.bottomPadding)
    }
  }

  /// Job color dot and name on plain glass, matching the other bottom controls.
  private var jobPickerButton: some View {
    Button {
      viewModel.presentJobSelection()
    } label: {
      HStack(spacing: Spacing.xs) {
        Circle()
          .fill(selectedJobColor)
          .frame(width: Spacing.xsm, height: Spacing.xsm)
          .accessibilityHidden(true)

        Text(viewModel.selectedJob?.name ?? String(localized: .settingsPayChooseJobTitle))
          .font(.tidexButton)
          .foregroundColor(.tidexTextPrimary)
          .lineLimit(1)
          .truncationMode(.tail)
          .frame(maxWidth: Self.jobPickerMaxNameWidth, alignment: .leading)
          .fixedSize(horizontal: true, vertical: false)

        Image(systemName: "chevron.up.chevron.down")
          .font(.tidexCaption)
          .foregroundColor(.tidexTextSecondary)
          .accessibilityHidden(true)
      }
      .padding(.horizontal, Spacing.md)
      .frame(height: MonthPickerLayout.height)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .tidexGlass(
      shape: .rect(cornerRadius: MonthPickerLayout.cornerRadius),
      interactive: true
    )
    .accessibilityIdentifier("add-shift.job-picker")
  }

  private var selectedJobColor: Color {
    guard let job = viewModel.selectedJob,
      let color = WorkplaceColor.hexToUIColor(job.color)
    else {
      return .tidexBlue
    }
    return Color(uiColor: color)
  }

  private var startFreshButton: some View {
    Button {
      Haptics.play(.selection)
      presentStartFreshConfirmation()
    } label: {
      Image(systemName: "arrow.uturn.backward.circle.fill")
        .font(.tidexHeadline)
        .foregroundColor(viewModel.hasContent ? .tidexTextPrimary : .tidexTextMuted)
        .frame(width: MonthPickerLayout.height, height: MonthPickerLayout.height)
        .contentShape(Rectangle())
        .accessibilityHidden(true)
    }
    .buttonStyle(.plain)
    .disabled(!viewModel.hasContent || addShiftCoordinator.isLoading)
    .tidexGlass(
      shape: .rect(cornerRadius: MonthPickerLayout.cornerRadius),
      interactive: true
    )
    .accessibilityLabel(Text(.addShiftStartFreshConfirmAction))
  }

  private var saveButton: some View {
    Button {
      handleSaveTap()
    } label: {
      Label(String(localized: .addShiftSubmitButton), systemImage: "plus")
        .font(.tidexButton)
        .lineLimit(1)
        .foregroundColor(addShiftCoordinator.canSubmit ? .tidexBlue : .tidexTextMuted)
        // Keep the width while saving so the month picker doesn't jump.
        .opacity(addShiftCoordinator.isLoading ? 0 : 1)
        .overlay {
          if addShiftCoordinator.isLoading {
            ProgressView()
              .progressViewStyle(CircularProgressViewStyle(tint: .tidexBlue))
              .scaleEffect(MonthPickerLayout.progressIndicatorScale)
          }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .padding(.horizontal, Spacing.md)
        .frame(maxWidth: .infinity)
        .frame(height: MonthPickerLayout.height)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(addShiftCoordinator.isLoading)
    .tidexGlass(
      shape: .rect(cornerRadius: MonthPickerLayout.cornerRadius),
      interactive: true
    )
    .opacity(
      addShiftCoordinator.canSubmit
        ? MonthPickerLayout.enabledOpacity
        : MonthPickerLayout.disabledOpacity
    )
    .accessibilityIdentifier("add-shift.save")
  }

  private func handleSaveTap() {
    guard !addShiftCoordinator.isLoading else { return }

    if addShiftCoordinator.canSubmit {
      Haptics.play(.selection)
      addShiftCoordinator.triggerAdd()
      return
    }

    Haptics.play(.warning)
    showSubmitRequirementsAlert = true
  }

  private var submitRequirementsMessage: String {
    let blockers = addShiftCoordinator.submitBlockers
    guard !blockers.isEmpty else {
      return String(localized: .addShiftSubmitRequirementsGeneric)
    }

    return
      blockers
      .map { "- \(String(localized: submitRequirementMessageKey(for: $0)))" }
      .joined(separator: "\n")
  }

  // swiftlint:disable:next cyclomatic_complexity
  private func submitRequirementMessageKey(
    for blocker: AddShiftSubmitBlocker
  ) -> LocalizedStringResource {
    switch blocker {
    case .noAvailableJob:
      return .addShiftSubmitRequirementsAddJobFirst

    case .noSelectedJob:
      return .addShiftSubmitRequirementsSelectJob

    case .noSingleDates:
      return .addShiftSubmitRequirementsSelectDate

    case .noRecurringDays:
      return .addShiftSubmitRequirementsSelectRecurringDay

    case .missingTimes:
      return .addShiftSubmitRequirementsSetTimes

    case .noEventDate:
      return .addShiftSubmitRequirementsSelectEventDate

    case .invalidEventDateRange:
      return .addShiftSubmitRequirementsValidEventRange

    case .eventCrossesMidnight:
      return .addShiftSubmitRequirementsEventSameDay

    case .missingEventNote:
      return .addShiftSubmitRequirementsEventNote
    }
  }
}

// MARK: - Single Shift Content

private struct SingleShiftContent: View {
  @Bindable var viewModel: AddShiftViewModel
  var scrollProxy: ScrollViewProxy
  @Binding var focusedTimeField: TimeInputField?

  var body: some View {
    VStack(spacing: Spacing.xs) {
      CalendarHeaderRow(totals: viewModel.toolbarTotals, secondaryStyle: .delta)

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
        chipsAboveInputs: true
      )
    }
  }
}

// MARK: - Recurring Shift Content

private struct RecurringShiftContent: View {
  @Bindable var viewModel: AddShiftViewModel
  var scrollProxy: ScrollViewProxy
  @Binding var focusedTimeField: TimeInputField?

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.mlg) {
      titleSection

      CalendarHeaderRow(totals: viewModel.toolbarTotals, secondaryStyle: .delta)

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
        chipsAboveInputs: true
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
  @Bindable var viewModel: AddShiftViewModel
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
        String(localized: .addShiftSubmitRequirementsEventNote),
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
            chipsAboveInputs: true
          )

          if viewModel.eventTimesCrossMidnight {
            EventTimeRangeHint()
              .padding(.horizontal, Spacing.sm)
          }
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
    if Calendar.gregorianCurrent.isDate(viewModel.eventStartDate, inSameDayAs: viewModel.eventEndDate) {
      return viewModel.eventStartDate.formatted(
        .dateTime.weekday(.wide).day().month(.wide).calendar(.gregorian))
    }

    let format = Date.FormatStyle.dateTime.day().month(.abbreviated).calendar(.gregorian)
    return "\(viewModel.eventStartDate.formatted(format)) - \(viewModel.eventEndDate.formatted(format))"
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

// MARK: - Back Swipe

/// Turns off the full-width back swipe while the screen is in the window, so a right swipe
/// on the calendar or month picker changes month instead of popping the screen.
/// The edge swipe and back button still go back.
private struct FullWidthBackSwipeBlocker: UIViewRepresentable {
  func makeUIView(context _: Context) -> BlockerView {
    BlockerView()
  }

  func updateUIView(_: BlockerView, context _: Context) {}

  final class BlockerView: UIView {
    private weak var blockedRecognizer: UIGestureRecognizer?

    override func didMoveToWindow() {
      super.didMoveToWindow()
      blockedRecognizer?.isEnabled = true
      blockedRecognizer = nil
      guard window != nil else { return }

      let navigationController =
        sequence(first: self as UIResponder, next: \.next)
        .first { $0 is UINavigationController } as? UINavigationController
      blockedRecognizer = navigationController?.interactiveContentPopGestureRecognizer
      blockedRecognizer?.isEnabled = false
    }
  }
}

// MARK: - Preview

#Preview {
  AddShiftView()
    .environment(AppCoordinator.shared)
}
