import SwiftUI

/// Screen 3: How It Works
/// Creates narrative tension through progressive visual hierarchy
/// - Step 1 feels "already done" (active state with pulse)
/// - Steps 2-3 are dimmed future states
/// - Vertical connector creates flow
/// - Outcome whisper at bottom reminds user of the payoff
struct HowItWorksScreen: View {
  let totalFrom: CalendarHeaderTotals?
  let totalTo: CalendarHeaderTotals?
  let currency: String
  let isActive: Bool
  let shouldShowConfetti: Bool
  let shouldAnimateTotalFromPrevious: Bool
  let totalCardSeed: Int
  let isExiting: Bool
  let showsTitle: Bool

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var step1Visible = false
  @State private var step2Visible = false
  @State private var shiftPreviewVisible = false
  @State private var step3Visible = false
  @State private var totalCardVisible = false
  @State private var outcomeVisible = false
  @State private var isConfettiActive = false
  @State private var lastConfettiSeed = -1
  @State private var entranceSequenceID = 0
  @State private var focusedStepIndex: Int?
  @State private var hasCompletedFocusSequence = false
  @State private var step1TitleFocusTrigger = 0
  @State private var step2TitleFocusTrigger = 0
  @State private var step3TitleFocusTrigger = 0

  /// Steps that are not in focus lose color instead of opacity, so their text keeps its contrast.
  static let dimmedSaturation: Double = 0.35

  private let titleFocusStartDelay: TimeInterval = 0.7
  private let perStepTitleFocusDuration: TimeInterval = 1.32

  init(
    totalFrom: CalendarHeaderTotals? = nil,
    totalTo: CalendarHeaderTotals? = nil,
    currency: String = OnboardingCurrencyResolver.detectDefaultCurrency(),
    isActive: Bool = false,
    shouldShowConfetti: Bool = false,
    shouldAnimateTotalFromPrevious: Bool = false,
    totalCardSeed: Int = 0,
    isExiting: Bool = false,
    showsTitle: Bool = true
  ) {
    self.totalFrom = totalFrom
    self.totalTo = totalTo
    self.currency = currency
    self.isActive = isActive
    self.shouldShowConfetti = shouldShowConfetti
    self.shouldAnimateTotalFromPrevious = shouldAnimateTotalFromPrevious
    self.totalCardSeed = totalCardSeed
    self.isExiting = isExiting
    self.showsTitle = showsTitle
  }

  var body: some View {
    let featuredShift = Self.makeOnboardingFeaturedShift(currency: currency)
    let isStep2Dimmed = shouldDimStep(at: 1)
    let isStep3Dimmed = shouldDimStep(at: 2)

    VStack(spacing: 0) {
      if showsTitle {
        titleView
      }

      VStack(spacing: 0) {
        stepsTimeline(featuredShift: featuredShift, isStep2Dimmed: isStep2Dimmed)

        Spacer()
          .frame(height: 20)

        totalCard(isStep3Dimmed: isStep3Dimmed)

        Spacer()
          .frame(height: 20)

        outcomeWhisper
      }
      .padding(.top, showsTitle ? 0 : Spacing.sm)
      .frame(maxWidth: .infinity)
      .scrollsOnOverflow(alignment: showsTitle ? .center : .top)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .overlay {
      confettiOverlay
    }
    .onAppear {
      guard isActive else { return }
      runEntranceSequence()
      triggerConfettiIfNeeded()
    }
    .onChange(of: isActive) { _, active in
      if active {
        runEntranceSequence()
        triggerConfettiIfNeeded()
      } else {
        resetEntranceState()
      }
    }
    .onChange(of: totalCardSeed) { _, _ in
      guard isActive else { return }
      runEntranceSequence()
      triggerConfettiIfNeeded()
    }
    .userCurrency(currency)
  }

  private func triggerConfettiIfNeeded() {
    guard shouldShowConfetti, totalCardSeed != lastConfettiSeed else { return }
    lastConfettiSeed = totalCardSeed

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
      isConfettiActive = true
    }
  }

  private func runEntranceSequence() {
    entranceSequenceID += 1
    let sequenceID = entranceSequenceID

    resetEntranceState()

    // Reduce Motion: show the final state at once, without the staggered entrance or focus dimming.
    guard !reduceMotion else {
      step1Visible = true
      step2Visible = true
      shiftPreviewVisible = true
      step3Visible = true
      totalCardVisible = true
      outcomeVisible = true
      hasCompletedFocusSequence = true
      return
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
      guard sequenceID == entranceSequenceID else { return }
      step1Visible = true
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
      guard sequenceID == entranceSequenceID else { return }
      step2Visible = true
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
      guard sequenceID == entranceSequenceID else { return }
      shiftPreviewVisible = true
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.56) {
      guard sequenceID == entranceSequenceID else { return }
      step3Visible = true
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.82) {
      guard sequenceID == entranceSequenceID else { return }
      totalCardVisible = true
    }

    // Outcome fades in last.
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.05) {
      guard sequenceID == entranceSequenceID else { return }
      withAnimation(.easeOut(duration: 0.5)) {
        outcomeVisible = true
      }
    }

    scheduleStepFocusSequence(sequenceID: sequenceID)
  }

  private func resetEntranceState() {
    step1Visible = false
    step2Visible = false
    shiftPreviewVisible = false
    step3Visible = false
    totalCardVisible = false
    outcomeVisible = false
    focusedStepIndex = nil
    hasCompletedFocusSequence = false
    step1TitleFocusTrigger = 0
    step2TitleFocusTrigger = 0
    step3TitleFocusTrigger = 0
  }

  private func shouldDimStep(at index: Int) -> Bool {
    guard
      !hasCompletedFocusSequence,
      let focusedStepIndex
    else {
      return false
    }

    return focusedStepIndex != index
  }

  private func scheduleStepFocusSequence(sequenceID: Int) {
    for step in 0..<3 {
      let delay = titleFocusStartDelay + (Double(step) * perStepTitleFocusDuration)
      DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
        guard sequenceID == entranceSequenceID else { return }
        withAnimation(.easeInOut(duration: 0.26)) {
          focusedStepIndex = step
        }

        DispatchQueue.main.async {
          switch step {
          case 0:
            step1TitleFocusTrigger += 1

          case 1:
            step2TitleFocusTrigger += 1

          case 2:
            step3TitleFocusTrigger += 1

          default:
            break
          }
        }
      }
    }

    let sequenceCompletionDelay = titleFocusStartDelay + (3 * perStepTitleFocusDuration)
    DispatchQueue.main.asyncAfter(deadline: .now() + sequenceCompletionDelay) {
      guard sequenceID == entranceSequenceID else { return }
      withAnimation(.easeOut(duration: 0.25)) {
        focusedStepIndex = nil
        hasCompletedFocusSequence = true
      }
    }
  }
}

extension HowItWorksScreen {
  private var titleView: some View {
    Text(.onboardingHowTitle)
      .font(.tidexScreenTitle)
      .foregroundColor(.tidexTextPrimary)
      .multilineTextAlignment(.center)
      .lineSpacing(2)
      .accessibilityAddTraits(.isHeader)
      .frame(maxWidth: AdaptiveMaxWidth.tabContent)
      .padding(.horizontal, Spacing.md)
      .padding(.top, Spacing.md)
      .padding(.bottom, Spacing.md)
      .onboardingHowExitStep(isExiting: isExiting, delay: 0.00)
  }

  /// Steps as a progression timeline, not a list.
  /// Centered as a unit with constrained width for iPad.
  private func stepsTimeline(featuredShift: ShiftWithComputations, isStep2Dimmed: Bool)
    -> some View
  {
    VStack(alignment: .leading, spacing: 0) {
      firstStep
        .padding(.bottom, Spacing.xxl)

      secondStep

      OnboardingHowItWorksShiftPreviewCard(
        shift: featuredShift,
        isVisible: shiftPreviewVisible,
        isDimmedForFocus: isStep2Dimmed
      )

      thirdStep
    }
    .frame(maxWidth: AdaptiveMaxWidth.tabContent)
    .padding(.horizontal, Spacing.md)
    .onboardingHowExitStep(isExiting: isExiting, delay: 0.045)
  }

  private var firstStep: some View {
    StepItem(
      icon: "clock.badge.checkmark",
      title: String(localized: .onboardingHowStep1Title),
      description: String(localized: .onboardingHowStep1Desc),
      index: 0,
      isVisible: step1Visible,
      progressState: .active,
      showConnector: false,
      isDimmedForFocus: shouldDimStep(at: 0),
      titleFocusTrigger: step1TitleFocusTrigger
    )
    .frame(maxWidth: AdaptiveMaxWidth.content, alignment: .leading)
  }

  private var secondStep: some View {
    StepItem(
      icon: "banknote",
      title: String(localized: .onboardingHowStep2Title),
      description: String(localized: .onboardingHowStep2Desc),
      index: 0,
      isVisible: step2Visible,
      progressState: .upcoming,
      showConnector: false,
      isDimmedForFocus: shouldDimStep(at: 1),
      titleFocusTrigger: step2TitleFocusTrigger
    )
    .frame(maxWidth: AdaptiveMaxWidth.content, alignment: .leading)
  }

  private var thirdStep: some View {
    StepItem(
      icon: "chart.line.uptrend.xyaxis",
      title: String(localized: .onboardingHowStep3Title),
      description: String(localized: .onboardingHowStep3Desc),
      index: 0,
      isVisible: step3Visible,
      progressState: .future,
      showConnector: false,
      isDimmedForFocus: shouldDimStep(at: 2),
      titleFocusTrigger: step3TitleFocusTrigger
    )
    .frame(maxWidth: AdaptiveMaxWidth.content, alignment: .leading)
  }

  private func totalCard(isStep3Dimmed: Bool) -> some View {
    OnboardingHowItWorksTotalCard(
      fromTotals: totalFrom,
      toTotals: totalTo
    )
    .frame(maxWidth: AdaptiveMaxWidth.tabContent)
    .padding(.horizontal, Spacing.md)
    .opacity(totalCardVisible ? 1 : 0)
    .saturation(isStep3Dimmed ? Self.dimmedSaturation : 1)
    .offset(y: totalCardVisible ? 0 : 16)
    .animation(
      reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.84),
      value: totalCardVisible
    )
    .animation(.easeInOut(duration: 0.26), value: isStep3Dimmed)
    .onboardingHowExitStep(isExiting: isExiting, delay: 0.085)
  }

  /// Outcome whisper - centered under the steps
  private var outcomeWhisper: some View {
    Text(.onboardingHowOutcome)
      .font(.tidexFootnoteMedium)
      .foregroundColor(.tidexBlueText)
      .opacity(outcomeVisible ? 1 : 0)
      .offset(y: outcomeVisible ? 0 : 8)
      .onboardingHowExitStep(isExiting: isExiting, delay: 0.125)
  }

  private var confettiOverlay: some View {
    GeometryReader { geometry in
      // Extend confetti region so particles reach the continue CTA zone.
      let confettiHeight =
        geometry.size.height
        + Spacing.buttonHeight
        + Spacing.xl
        + Spacing.md

      ConfettiView(isActive: isConfettiActive, launchYRatio: 0.12) {
        isConfettiActive = false
      }
      .frame(maxWidth: .infinity)
      .frame(height: confettiHeight, alignment: .top)
    }
  }

  private static func makeOnboardingFeaturedShift(currency: String) -> ShiftWithComputations {
    let current = Date.currentYearMonth()
    let day = min(12, Date.daysInMonth(year: current.year, month: current.month))
    let dateISO =
      Date.isoDateString(year: current.year, month: current.month, day: day)
      ?? "\(current.year)-\(current.month)-\(day)"

    let row = ShiftRow(
      id: "onboarding-how-featured",
      user_id: nil,
      shift_date: dateISO,
      start_time: "14:00",
      end_time: "22:00",
      custom_supplements: nil
    )

    let snapshot = WageSnapshot(
      id: "onboarding-how-snapshot",
      user_id: "onboarding-demo",
      from_date: nil,
      hourly_wage: OnboardingCurrencyResolver.defaultHourlyWage(for: currency),
      wage_level: nil,
      tariff_type_id: nil,
      supplements: SupplementRulesSnapshot(rules: []),
      tax_enabled: true,
      tax_percentage: 20,
      break_enabled: true,
      break_method: BreakMethod.proportional.rawValue,
      break_threshold_hours: 5.5,
      break_deduction_minutes: 30,
      created_at: nil
    )

    let computed = PayrollCalculator.computeShift(row, snapshot: snapshot)
    return ShiftWithComputations(
      shift: row,
      computed: computed,
      taxEnabled: snapshot.effectiveTaxEnabled,
      taxPercentage: snapshot.effectiveTaxPercentage
    )
  }
}

private struct OnboardingHowExitStepModifier: ViewModifier {
  let isExiting: Bool
  let delay: TimeInterval

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    content
      .opacity(isExiting ? 0 : 1)
      .offset(y: isExiting && !reduceMotion ? -24 : 0)
      .animation(
        .easeInOut(duration: 0.18).delay(delay),
        value: isExiting
      )
  }
}

extension View {
  func onboardingHowExitStep(isExiting: Bool, delay: TimeInterval) -> some View {
    modifier(OnboardingHowExitStepModifier(isExiting: isExiting, delay: delay))
  }
}

#Preview {
  HowItWorksScreen()
    .background(Color.tidexBackground)
}
