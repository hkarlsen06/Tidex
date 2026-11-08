import SwiftUI
import UIKit

/// Pre-auth onboarding simulator that mirrors the Add tab single-shift flow.
struct PreAuthAddShiftSimulatorScreen: View {
  let initialCurrency: String
  let onCurrencyChanged: (String) -> Void
  let onContinue: () -> Void
  let onSkip: () -> Void
  let isPreloaded: Bool
  let onBack: () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var viewModel: PreAuthAddShiftSimulatorViewModel
  @State private var focusedTimeField: TimeInputField?
  @State private var relaxFocusInAddStage = false
  @State private var focusRelaxToken = 0
  @State private var hasAcknowledgedTotals = false
  @State private var hintShimmerTrigger = 0

  init(
    initialCurrency: String,
    onCurrencyChanged: @escaping (String) -> Void,
    onContinue: @escaping () -> Void,
    onSkip: @escaping () -> Void,
    isPreloaded: Bool = false,
    onBack: @escaping () -> Void = {}
  ) {
    self.initialCurrency = initialCurrency
    self.onCurrencyChanged = onCurrencyChanged
    self.onContinue = onContinue
    self.onSkip = onSkip
    self.isPreloaded = isPreloaded
    self.onBack = onBack
    _viewModel = State(
      wrappedValue: PreAuthAddShiftSimulatorViewModel(initialCurrency: initialCurrency))
  }

  private var simulatorSubtitle: String {
    String(localized: .onboardingAddSimulatorSubtitle)
  }

  private var simulatorHint: String {
    switch focusStage {
    case .calendar:
      return String(localized: .onboardingAddSimulatorFocusCalendar)

    case .times:
      return String(localized: .onboardingAddSimulatorFocusTimes)

    case .totals:
      return String(localized: .onboardingAddSimulatorFocusTotals)

    case .add:
      return String(localized: .onboardingAddSimulatorFocusAdd)
    }
  }

  private var focusStage: PreAuthSimulatorFocusStage {
    if viewModel.selectedDates.isEmpty {
      return .calendar
    }
    guard viewModel.canContinue else {
      return .times
    }
    if !hasAcknowledgedTotals {
      return .totals
    }
    return .add
  }

  private var shouldDimNonFocusedSections: Bool {
    !(focusStage == .add && relaxFocusInAddStage)
  }

  private var isAddButtonEnabled: Bool {
    viewModel.canContinue && focusStage == .add
  }

  private var shouldShowTotalsAcknowledgement: Bool {
    focusStage == .totals
  }

  var body: some View {
    ZStack {
      Color.tidexBackground
        .ignoresSafeArea()

      simulatorContent
    }
    .safeAreaInset(edge: .top, spacing: 0) {
      topHeader
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      bottomShell
    }
    .overlay(alignment: .bottom) {
      if shouldShowTotalsAcknowledgement {
        totalsAcknowledgementButton
          .padding(.bottom, MonthPickerLayout.bottomPadding + Spacing.sm)
          .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.94)))
          .zIndex(3)
      }
    }
    .onTapGesture {
      focusedTimeField = nil
      hideKeyboard()
    }
    .onAppear {
      guard !isPreloaded else { return }
      OnboardingCurrencyCarryoverStore.writePreferredCurrency(viewModel.currency)
      scheduleFocusRelaxIfNeeded()
    }
    .task {
      guard !isPreloaded else { return }
      do { try await Task.sleep(for: .seconds(1)) } catch { return }
      triggerHintShimmer()
    }
    .task(id: focusRelaxToken) {
      guard !isPreloaded, focusStage == .add else { return }
      do { try await Task.sleep(for: .seconds(1.4)) } catch { return }
      withAnimation(reduceMotion ? nil : .easeOut(duration: 0.28)) {
        relaxFocusInAddStage = true
      }
    }
    .onChange(of: focusStage) { _, _ in
      guard !isPreloaded else { return }
      scheduleFocusRelaxIfNeeded()
      triggerHintShimmer()
      // The hint and the totals button change without moving VoiceOver focus, so say what to do next.
      AccessibilityNotification.Announcement(simulatorHint).post()
    }
    .onChange(of: initialCurrency) { _, newCurrency in
      syncCurrencyFromParent(newCurrency)
    }
    .userCurrency(viewModel.currency)
    .animation(
      reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85),
      value: viewModel.canContinue
    )
    .animation(
      reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.86),
      value: focusStage
    )
  }

  private func handleAddTap() {
    guard isAddButtonEnabled else { return }

    focusedTimeField = nil
    hideKeyboard()

    Haptics.play(.success)
    OnboardingFirstShiftCarryoverStore.write(
      dates: viewModel.selectedDates,
      startTime: viewModel.startTime,
      endTime: viewModel.endTime
    )
    onContinue()
  }

  private func handleTotalsAcknowledged() {
    guard focusStage == .totals else { return }

    Haptics.play(.light)
    withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.86)) {
      hasAcknowledgedTotals = true
    }
  }

  private func handleCurrencySelection(_ selectedCurrency: String) {
    guard selectedCurrency != viewModel.currency else { return }

    viewModel.applyCurrency(selectedCurrency)
    onCurrencyChanged(viewModel.currency)
    OnboardingCurrencyCarryoverStore.writePreferredCurrency(viewModel.currency)
  }

  private func syncCurrencyFromParent(_ selectedCurrency: String) {
    guard selectedCurrency != viewModel.currency else { return }
    viewModel.applyCurrency(selectedCurrency)
  }

  private func triggerHintShimmer() {
    hintShimmerTrigger += 1
  }

  private func hideKeyboard() {
    UIApplication.shared.sendAction(
      #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
  }

  private func scheduleFocusRelaxIfNeeded() {
    focusRelaxToken += 1
    relaxFocusInAddStage = false
  }
}

extension PreAuthAddShiftSimulatorScreen {
  private var simulatorContent: some View {
    GeometryReader { geometry in
      simulatorBody(
        usesColumns: geometry.size.width >= 700 && !dynamicTypeSize.isAccessibilitySize)
    }
  }

  private func simulatorBody(usesColumns: Bool) -> some View {
    VStack(spacing: Spacing.sm) {
      Spacer(minLength: 0)

      VStack(alignment: .center, spacing: Spacing.sm) {
        Text(simulatorSubtitle)
          .font(.tidexBody.weight(.bold))
          .foregroundStyle(Color.tidexBlueText)
          .multilineTextAlignment(.center)
          .accessibilityAddTraits(.isHeader)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .center)
          .layoutPriority(1)
          .padding(.top, Spacing.sm)

        calendarAndTimes(usesColumns: usesColumns)

        OnboardingHintShimmerText(
          text: simulatorHint,
          trigger: hintShimmerTrigger
        )
        .layoutPriority(1)
      }
      .padding(.horizontal, Spacing.xs)
      .frame(maxWidth: usesColumns ? 820 : AdaptiveMaxWidth.tabContent)
      .frame(maxWidth: .infinity)

      Spacer(minLength: 0)
    }
    .scrollsOnOverflow()
  }

  private func calendarAndTimes(usesColumns: Bool) -> some View {
    let layout =
      usesColumns
      ? AnyLayout(HStackLayout(spacing: Spacing.xl))
      : AnyLayout(VStackLayout(spacing: 0))
    return layout {
      AddShiftCalendarView(viewModel: viewModel)
        .frame(maxWidth: usesColumns ? 400 : .infinity)
        .simulatorFocusStyle(
          isFocused: !shouldDimNonFocusedSections || focusStage == .calendar
        )

      TimeRangePicker(
        startTime: $viewModel.startTime,
        endTime: $viewModel.endTime,
        focusedFieldBinding: $focusedTimeField,
        presetRanges: viewModel.presetTimeRanges
      )
      .frame(maxWidth: usesColumns ? 360 : .infinity)
      .padding(.top, Spacing.sm)
      .simulatorFocusStyle(
        isFocused: !shouldDimNonFocusedSections || focusStage == .times
      )
    }
  }

  @ViewBuilder
  private var topHeader: some View {
    Group {
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: Spacing.sm) {
          HStack(spacing: Spacing.sm) {
            backButton
            skipButton
            Spacer(minLength: 0)
            currencySelector
          }

          toolbarTotals
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
      } else {
        ZStack(alignment: .center) {
          HStack(spacing: Spacing.sm) {
            backButton
            skipButton

            Spacer(minLength: 0)

            toolbarTotals
          }

          currencySelector
        }
      }
    }
    .padding(.horizontal, Spacing.sm)
    .frame(maxWidth: AdaptiveMaxWidth.tabContent)
    .padding(.top, Spacing.xxxs)
    .padding(.bottom, Spacing.sm)
    .frame(maxWidth: .infinity)
    .background(Color.tidexBackground)
  }

  private var currencySelector: some View {
    OnboardingCurrencyCapsuleSelector(
      selectedCurrency: Binding(
        get: { viewModel.currency },
        set: { selectedCurrency in
          handleCurrencySelection(selectedCurrency)
        }
      )
    )
    .fixedSize(horizontal: true, vertical: false)
  }

  private var backButton: some View {
    headerPillButton(systemName: "chevron.left", label: Text(.commonBack)) {
      onBack()
    }
  }

  private var skipButton: some View {
    headerPillButton(systemName: "forward.end.fill", label: Text(.onboardingSkip)) {
      onSkip()
    }
  }

  /// Icon pill with a 44pt touch target. The label is the spoken and Voice Control name.
  private func headerPillButton(
    systemName: String,
    label: Text,
    action: @escaping () -> Void
  ) -> some View {
    Button {
      Haptics.play(.light)
      action()
    } label: {
      Image(systemName: systemName)
        .font(.footnote.weight(.semibold))
        .foregroundStyle(Color.tidexTextSecondary)
        .accessibilityHidden(true)
        .frame(width: 46, height: 34)
        .background(Color.tidexSurfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.pill, style: .continuous))
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
    .buttonStyle(SnappyButtonStyle())
    .accessibilityLabel(label)
  }

  private var toolbarTotals: some View {
    PreAuthSimulatorToolbarTotals(
      totals: viewModel.toolbarTotals,
      baselinePrimary: viewModel.baselineToolbarTotals?.primary,
      showDelta: viewModel.canContinue
    )
    .fixedSize(horizontal: true, vertical: false)
    .simulatorFocusStyle(
      isFocused: !shouldDimNonFocusedSections || focusStage == .totals
    )
    .scaleEffect(focusStage == .totals ? 1.03 : 1.0)
    .overlay(alignment: .bottomTrailing) {
      GeometryReader { geometry in
        TotalsFocusSweepIndicator(
          isActive: focusStage == .totals,
          reduceMotion: reduceMotion,
          trackWidth: max(geometry.size.width, 44)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .offset(y: Spacing.sm)
      }
    }
  }

  @ViewBuilder
  private var bottomShell: some View {
    GlassEffectContainer(spacing: Spacing.xs) {
      HStack(spacing: Spacing.xs) {
        AnimatedMonthHeader(
          monthName: viewModel.displayMonthName,
          year: viewModel.displayYear,
          phase: viewModel.monthPhase,
          config: .default,
          onPrevious: {},
          onNext: {},
          onNavigateToMonth: nil,
          isLoading: false
        )
        .frame(maxWidth: .infinity)
        .frame(height: MonthPickerLayout.height)
        .tidexGlass(
          shape: .rect(cornerRadius: MonthPickerLayout.cornerRadius),
          clear: true,
          disabled: true
        )
        .opacity(0.65)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .simulatorFocusStyle(
          isFocused: !shouldDimNonFocusedSections
        )

        Button {
          handleAddTap()
        } label: {
          Image(systemName: "plus")
            .font(.tidexHeadline)
            .foregroundStyle(isAddButtonEnabled ? Color.tidexBlueText : Color.tidexTextMuted)
            .accessibilityHidden(true)
            .frame(width: MonthPickerLayout.height, height: MonthPickerLayout.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isAddButtonEnabled)
        .tidexGlass(
          shape: .rect(cornerRadius: MonthPickerLayout.cornerRadius),
          tint: isAddButtonEnabled ? Color.tidexBlue.opacity(0.2) : nil,
          clear: true,
          interactive: isAddButtonEnabled,
          disabled: !isAddButtonEnabled
        )
        .opacity(isAddButtonEnabled ? 1.0 : 0.6)
        .accessibilityLabel(Text(.tabsAdd))
        .accessibilityHint(Text(simulatorHint))
        .simulatorFocusStyle(
          isFocused: !shouldDimNonFocusedSections || focusStage == .add
        )
        .scaleEffect(focusStage == .add ? 1.02 : 1.0)
      }
    }
    .frame(maxWidth: AdaptiveMaxWidth.tabContent)
    .frame(maxWidth: .infinity)
    .padding(.horizontal, MonthPickerLayout.horizontalPadding)
    .padding(.bottom, MonthPickerLayout.bottomPadding)
    .background(Color.tidexBackground)
  }

  @ViewBuilder
  private var totalsAcknowledgementButton: some View {
    Button {
      handleTotalsAcknowledged()
    } label: {
      Text(
        String(localized: .onboardingAddSimulatorAcknowledgeTotals)
      )
      .font(.tidexBodyMedium)
      .foregroundStyle(Color.tidexBlueText)
      .multilineTextAlignment(.center)
      .padding(.horizontal, Spacing.md)
      .padding(.vertical, Spacing.xxxs)
    }
    .buttonStyle(.plain)
    .tidexGlass(shape: .capsule, interactive: true)
  }
}

#Preview {
  PreAuthAddShiftSimulatorScreen(
    initialCurrency: "kr",
    onCurrencyChanged: { _ in },
    onContinue: {},
    onSkip: {}
  )
}  // swiftlint:disable:this file_length
