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
  @StateObject private var viewModel: PreAuthAddShiftSimulatorViewModel
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
    _viewModel = StateObject(
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

  @ViewBuilder
  private var topHeader: some View {
    ZStack(alignment: .center) {
      HStack(spacing: Spacing.sm) {
        Button {
          UIImpactFeedbackGenerator(style: .light).impactOccurred()
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

        Spacer(minLength: 0)

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

  private func handleAddTap() {
    guard isAddButtonEnabled else { return }

    focusedTimeField = nil
    hideKeyboard()

    UINotificationFeedbackGenerator().notificationOccurred(.success)
    onContinue(
      viewModel.baselineToolbarTotals,
      viewModel.toolbarTotals ?? viewModel.baselineToolbarTotals,
      viewModel.currency
    )
  }

  private func handleTotalsAcknowledged() {
    guard focusStage == .totals else { return }

    UIImpactFeedbackGenerator(style: .light).impactOccurred()
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

private struct OnboardingHintShimmerText: View {
  let text: String
  let trigger: Int

  @State private var shimmerStartDate: Date?
  @State private var isShimmerActive = false
  @State private var cycleToken = 0

  private let shimmerDuration = PreAuthSimulatorAnimationTiming.hintSweepDuration
  private let shimmerCleanupDelay = PreAuthSimulatorAnimationTiming.hintCleanupDelay

  var body: some View {
    Group {
      if isShimmerActive {
        TimelineView(.animation) { context in
          shimmerText(styledText(at: context.date))
        }
      } else {
        shimmerText(staticText)
      }
    }
    .onChange(of: trigger) { _, _ in
      runShimmerCycle()
    }
    .onDisappear {
      cycleToken += 1
      isShimmerActive = false
      shimmerStartDate = nil
    }
  }

  private var staticText: AttributedString {
    var attributed = AttributedString(text)
    let basePointSize = UIFont.preferredFont(forTextStyle: .footnote).pointSize
    attributed.font = .system(size: basePointSize, weight: .regular, design: .default)
    attributed.foregroundColor = .tidexTextMuted
    return attributed
  }

  private func shimmerText(_ attributed: AttributedString) -> some View {
    Text(attributed)
      .multilineTextAlignment(.center)
      .lineLimit(3)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .center)
  }

  private func styledText(at currentDate: Date) -> AttributedString {
    var attributed = AttributedString(text)
    let characterCount = max(text.count, 1)
    let basePointSize = UIFont.preferredFont(forTextStyle: .footnote).pointSize

    guard
      isShimmerActive,
      let shimmerStartDate
    else {
      attributed.font = .system(size: basePointSize, weight: .regular, design: .default)
      attributed.foregroundColor = .tidexTextMuted
      return attributed
    }

    let elapsed = max(currentDate.timeIntervalSince(shimmerStartDate), 0)
    let progress = CGFloat(min(elapsed / shimmerDuration, 1))
    let radius = max(CGFloat(characterCount) * 0.24, 4)
    let startCenter = -radius
    let endCenter = CGFloat(max(characterCount - 1, 1)) + radius
    let center = startCenter + ((endCenter - startCenter) * progress)

    var charIndex = 0
    var stringIndex = text.startIndex

    while stringIndex < text.endIndex {
      let nextIndex = text.index(after: stringIndex)
      let charRange = stringIndex..<nextIndex
      if let attributedRange = Range(charRange, in: attributed) {
        let distance = abs(CGFloat(charIndex) - center)
        let intensity = max(0, 1 - (distance / radius))
        let weight: Font.Weight =
          intensity > 0.6 ? .bold : (intensity > 0.25 ? .semibold : .regular)
        let size = basePointSize * (1 + (0.09 * intensity))
        let color: Color = intensity > 0.08 ? .tidexBlue : .tidexTextMuted

        attributed[attributedRange].font = .system(size: size, weight: weight, design: .default)
        attributed[attributedRange].foregroundColor = color
      }
      stringIndex = nextIndex
      charIndex += 1
    }

    return attributed
  }

  private func runShimmerCycle() {
    cycleToken += 1
    let token = cycleToken
    shimmerStartDate = Date()
    isShimmerActive = true

    DispatchQueue.main.asyncAfter(deadline: .now() + shimmerDuration + shimmerCleanupDelay) {
      guard token == cycleToken else { return }
      isShimmerActive = false
      shimmerStartDate = nil
    }
  }
}

private enum PreAuthSimulatorAnimationTiming {
  static let hintSweepDuration: TimeInterval = 1.28
  static let hintCleanupDelay: TimeInterval = 0.08
  static let totalsIndicatorStartDelay: TimeInterval = hintSweepDuration + hintCleanupDelay
}

private enum PreAuthSimulatorFocusStage {
  case calendar
  case times
  case totals
  case add
}

extension View {
  @ViewBuilder
  fileprivate func simulatorFocusStyle(isFocused: Bool, reduceTransparency: Bool) -> some View {
    if isFocused {
      self
        .opacity(1)
        .saturation(1)
        .blur(radius: 0)
    } else {
      self
        .opacity(0.55)
        .saturation(0.45)
        .blur(radius: reduceTransparency ? 0 : 1.5)
    }
  }
}

/// Blue focus indicator under totals: dot -> line to the right -> dot again from the left.
private struct TotalsFocusSweepIndicator: View {
  let isActive: Bool
  let reduceMotion: Bool
  let trackWidth: CGFloat

  @State private var cycleToken = 0
  @State private var hasPlayedCurrentActivation = false
  @State private var leadingProgress: CGFloat = 0
  @State private var trailingProgress: CGFloat = 0
  @State private var indicatorOpacity: CGFloat = 0

  private let dotDiameter: CGFloat = 7
  private let lineHeight: CGFloat = 5
  private let expandDuration: TimeInterval = 0.54
  private let collapseDuration: TimeInterval = 0.58
  private let fadeOutDuration: TimeInterval = 0.18
  private let startDelay = PreAuthSimulatorAnimationTiming.totalsIndicatorStartDelay

  var body: some View {
    let travel = trackWidth - dotDiameter
    let startX = travel * leadingProgress
    let endX = travel * trailingProgress
    let width = max(dotDiameter, (endX - startX) + dotDiameter)

    Capsule(style: .continuous)
      .fill(Color.tidexBlue)
      .frame(width: width, height: lineHeight)
      .offset(x: startX)
      .frame(width: trackWidth, height: dotDiameter, alignment: .leading)
      .opacity(indicatorOpacity)
      .allowsHitTesting(false)
      .accessibilityHidden(true)
      .onAppear {
        syncAnimationState()
      }
      .onChange(of: isActive) { _, _ in
        syncAnimationState()
      }
      .onDisappear {
        cycleToken += 1
      }
  }

  private func syncAnimationState() {
    cycleToken += 1
    let token = cycleToken

    if !isActive {
      withAnimation(.easeOut(duration: 0.2)) {
        leadingProgress = 0
        trailingProgress = 0
        indicatorOpacity = 0
      }
      hasPlayedCurrentActivation = false
      return
    }

    guard !hasPlayedCurrentActivation else { return }

    leadingProgress = 0
    trailingProgress = 0
    indicatorOpacity = 0

    hasPlayedCurrentActivation = true

    runSingleCycle(token: token)
  }

  private func runSingleCycle(token: Int) {
    guard token == cycleToken, isActive else { return }

    DispatchQueue.main.asyncAfter(deadline: .now() + startDelay) {
      guard token == cycleToken, isActive else { return }

      guard !reduceMotion else {
        indicatorOpacity = 1
        return
      }

      indicatorOpacity = 1
      withAnimation(.easeInOut(duration: expandDuration)) {
        trailingProgress = 1
      }

      DispatchQueue.main.asyncAfter(deadline: .now() + expandDuration) {
        guard token == cycleToken, isActive else { return }
        withAnimation(.easeInOut(duration: collapseDuration)) {
          leadingProgress = 1
        }
      }

      DispatchQueue.main.asyncAfter(deadline: .now() + expandDuration + collapseDuration) {
        guard token == cycleToken, isActive else { return }
        withAnimation(.easeOut(duration: fadeOutDuration)) {
          indicatorOpacity = 0
        }
      }
    }
  }
}

/// Compact earnings display used in the simulator toolbar.
private struct PreAuthSimulatorToolbarTotals: View {
  let totals: CalendarHeaderTotals?
  let baselinePrimary: Double?
  let showDelta: Bool

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

          if let delta = deltaAmount {
            HStack(alignment: .center, spacing: Spacing.xxxs) {
              Image(systemName: "plus")
                .font(.caption2.weight(.bold))

              animatedAmount(
                delta,
                lastDisplayed: lastDisplayedSecondary,
                onUpdate: { lastDisplayedSecondary = $0 }
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
    .animation(.spring(response: 0.26, dampingFraction: 0.86), value: totals?.primary)
    .animation(.spring(response: 0.26, dampingFraction: 0.86), value: deltaAmount)
  }

  private var deltaAmount: Double? {
    guard showDelta, let currentPrimary = totals?.primary, let baselinePrimary else { return nil }
    let delta = max(currentPrimary - baselinePrimary, 0)
    return delta > 0 ? delta : nil
  }

  @ViewBuilder
  private func animatedAmount(
    _ amount: Double?,
    lastDisplayed: Double,
    onUpdate: @escaping (Double) -> Void
  ) -> some View {
    if let amount, amount > 0 {
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

#Preview {
  PreAuthAddShiftSimulatorScreen(
    initialCurrency: "kr",
    onCurrencyChanged: { _ in },
    onContinue: { _, _, _ in },
    onSkip: {},
    onBaselineReady: { _, _ in }
  )
}
