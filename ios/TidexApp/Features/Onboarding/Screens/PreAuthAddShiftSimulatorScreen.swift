import SwiftUI
import UIKit

/// Pre-auth onboarding simulator that mirrors the Add tab single-shift flow.
struct PreAuthAddShiftSimulatorScreen: View {
  let initialCurrency: String
  let onCurrencyChanged: (String) -> Void
  let onContinue:
    (_ fromTotals: CalendarHeaderTotals?, _ toTotals: CalendarHeaderTotals?, _ currency: String)
      -> Void
  let onSkip: () -> Void
  let onBaselineReady: (_ baselineTotals: CalendarHeaderTotals?, _ currency: String) -> Void
  let isPreloaded: Bool

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @State private var viewModel: PreAuthAddShiftSimulatorViewModel
  @State private var focusedTimeField: TimeInputField?
  @State private var relaxFocusInAddStage = false
  @State private var focusRelaxToken = 0
  @State private var hasAcknowledgedTotals = false
  @State private var hintShimmerTrigger = 0

  init(
    initialCurrency: String,
    onCurrencyChanged: @escaping (String) -> Void,
    onContinue:
      @escaping (
        _ fromTotals: CalendarHeaderTotals?, _ toTotals: CalendarHeaderTotals?, _ currency: String
      ) -> Void,
    onSkip: @escaping () -> Void,
    onBaselineReady:
      @escaping (_ baselineTotals: CalendarHeaderTotals?, _ currency: String) -> Void,
    isPreloaded: Bool = false
  ) {
    self.initialCurrency = initialCurrency
    self.onCurrencyChanged = onCurrencyChanged
    self.onContinue = onContinue
    self.onSkip = onSkip
    self.onBaselineReady = onBaselineReady
    self.isPreloaded = isPreloaded
    _viewModel = State(
      wrappedValue: PreAuthAddShiftSimulatorViewModel(initialCurrency: initialCurrency))
  }

  /// Whether running on iPhone-sized idiom.
  private var isIPhone: Bool {
    UIDevice.current.userInterfaceIdiom == .phone
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
          .transition(.opacity.combined(with: .scale(scale: 0.94)))
          .zIndex(3)
      }
    }
    .onTapGesture {
      focusedTimeField = nil
      hideKeyboard()
    }
    .onAppear {
      guard !isPreloaded else { return }
      onBaselineReady(viewModel.baselineToolbarTotals, viewModel.currency)
      OnboardingCurrencyCarryoverStore.writePreferredCurrency(viewModel.currency)
      scheduleFocusRelaxIfNeeded()
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
        triggerHintShimmer()
      }
    }
    .onChange(of: focusStage) { _, _ in
      guard !isPreloaded else { return }
      scheduleFocusRelaxIfNeeded()
      triggerHintShimmer()
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
    onContinue(
      viewModel.baselineToolbarTotals,
      viewModel.toolbarTotals ?? viewModel.baselineToolbarTotals,
      viewModel.currency
    )
  }

  private func handleTotalsAcknowledged() {
    guard focusStage == .totals else { return }

    Haptics.play(.light)
    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
      hasAcknowledgedTotals = true
    }
  }

  private func handleCurrencySelection(_ selectedCurrency: String) {
    guard selectedCurrency != viewModel.currency else { return }

    viewModel.applyCurrency(selectedCurrency)
    onCurrencyChanged(viewModel.currency)
    OnboardingCurrencyCarryoverStore.writePreferredCurrency(viewModel.currency)
    onBaselineReady(viewModel.baselineToolbarTotals, viewModel.currency)
  }

  private func syncCurrencyFromParent(_ selectedCurrency: String) {
    guard selectedCurrency != viewModel.currency else { return }
    viewModel.applyCurrency(selectedCurrency)
    onBaselineReady(viewModel.baselineToolbarTotals, viewModel.currency)
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
    let currentToken = focusRelaxToken
    relaxFocusInAddStage = false

    guard focusStage == .add else { return }

    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
      guard currentToken == focusRelaxToken, focusStage == .add else { return }
      withAnimation(.easeOut(duration: 0.28)) {
        relaxFocusInAddStage = true
      }
    }
  }
}

extension PreAuthAddShiftSimulatorScreen {
  private var simulatorContent: some View {
    VStack(spacing: Spacing.sm) {
      Spacer(minLength: 0)

      VStack(alignment: .center, spacing: Spacing.sm) {
        Text(simulatorSubtitle)
          .font(.tidexBody.weight(.bold))
          .foregroundColor(.tidexBlue)
          .multilineTextAlignment(.center)
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .center)
          .layoutPriority(1)
          .padding(.top, Spacing.sm)

        calendarAndTimes

        OnboardingHintShimmerText(
          text: simulatorHint,
          trigger: hintShimmerTrigger
        )
        .layoutPriority(1)
      }
      .frame(maxWidth: isIPhone ? .infinity : AdaptiveMaxWidth.tabContent)
      .padding(.horizontal, isIPhone ? Spacing.xs : Spacing.md)

      Spacer(minLength: 0)
    }
  }

  private var calendarAndTimes: some View {
    VStack(spacing: 0) {
      AddShiftCalendarView(viewModel: viewModel)
        .simulatorFocusStyle(
          isFocused: !shouldDimNonFocusedSections || focusStage == .calendar,
          reduceTransparency: reduceTransparency
        )

      TimeRangePicker(
        startTime: $viewModel.startTime,
        endTime: $viewModel.endTime,
        focusedFieldBinding: $focusedTimeField,
        presetRanges: viewModel.presetTimeRanges
      )
      .padding(.top, Spacing.sm)
      .simulatorFocusStyle(
        isFocused: !shouldDimNonFocusedSections || focusStage == .times,
        reduceTransparency: reduceTransparency
      )
    }
  }

  @ViewBuilder
  private var topHeader: some View {
    ZStack(alignment: .center) {
      HStack(spacing: Spacing.sm) {
        skipButton

        Spacer(minLength: 0)

        toolbarTotals
      }

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
    .frame(maxWidth: isIPhone ? .infinity : AdaptiveMaxWidth.tabContent)
    .padding(.horizontal, isIPhone ? Spacing.sm : Spacing.md)
    .padding(.top, Spacing.xxxs)
    .padding(.bottom, Spacing.sm)
    .frame(maxWidth: .infinity)
    .background(Color.tidexBackground)
  }

  private var skipButton: some View {
    Button {
      Haptics.play(.light)
      onSkip()
    } label: {
      Image(systemName: "forward.end.fill")
        .font(.system(size: 15, weight: .semibold))
        .foregroundColor(.tidexTextSecondary)
        .frame(width: 46, height: 34)
        .background(Color.tidexSurfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.pill, style: .continuous))
    }
    .buttonStyle(SnappyButtonStyle())
    .accessibilityLabel(Text(.onboardingSkip))
  }

  private var toolbarTotals: some View {
    PreAuthSimulatorToolbarTotals(
      totals: viewModel.toolbarTotals,
      baselinePrimary: viewModel.baselineToolbarTotals?.primary,
      showDelta: viewModel.canContinue
    )
    .fixedSize(horizontal: true, vertical: false)
    .simulatorFocusStyle(
      isFocused: !shouldDimNonFocusedSections || focusStage == .totals,
      reduceTransparency: reduceTransparency
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
        .simulatorFocusStyle(
          isFocused: !shouldDimNonFocusedSections,
          reduceTransparency: reduceTransparency
        )

        Button {
          handleAddTap()
        } label: {
          Image(systemName: "plus")
            .font(.tidexHeadline)
            .foregroundColor(isAddButtonEnabled ? .tidexBlue : .tidexTextMuted)
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
        .simulatorFocusStyle(
          isFocused: !shouldDimNonFocusedSections || focusStage == .add,
          reduceTransparency: reduceTransparency
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
      .foregroundColor(.tidexBlue)
      .lineLimit(1)
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
    onContinue: { _, _, _ in },
    onSkip: {},
    onBaselineReady: { _, _ in }
  )
}
