import SwiftUI
import UIKit

/// Pre-auth onboarding simulator that mirrors the Add tab single-shift flow.
struct PreAuthAddShiftSimulatorScreen: View {
  let onContinue:
    (_ fromTotals: CalendarHeaderTotals?, _ toTotals: CalendarHeaderTotals?, _ currency: String)
      -> Void
  let onSkip: () -> Void
  let onBaselineReady: (_ baselineTotals: CalendarHeaderTotals?, _ currency: String) -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @StateObject private var viewModel = PreAuthAddShiftSimulatorViewModel()
  @State private var focusedTimeField: TimeInputField?
  @State private var relaxFocusInAddStage = false
  @State private var focusRelaxToken = 0

  /// Whether running on iPhone-sized idiom.
  private var isIPhone: Bool {
    UIDevice.current.userInterfaceIdiom == .phone
  }

  private var simulatorSubtitle: String {
    String(localized: "onboarding.add_simulator.subtitle", table: "Localizable")
  }

  private var simulatorHint: String {
    switch focusStage {
    case .calendar:
      return String(localized: "onboarding.add_simulator.focus.calendar", table: "Localizable")
    case .times:
      return String(localized: "onboarding.add_simulator.focus.times", table: "Localizable")
    case .add:
      return String(localized: "onboarding.add_simulator.focus.add", table: "Localizable")
    }
  }

  private var focusStage: PreAuthSimulatorFocusStage {
    if viewModel.selectedDates.isEmpty {
      return .calendar
    }
    if viewModel.canContinue {
      return .add
    }
    return .times
  }

  private var shouldDimNonFocusedSections: Bool {
    !(focusStage == .add && relaxFocusInAddStage)
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

          Text(simulatorHint)
            .font(.tidexFootnote)
            .foregroundColor(.tidexTextMuted)
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .center)
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
    .onTapGesture {
      focusedTimeField = nil
      hideKeyboard()
    }
    .onAppear {
      onBaselineReady(viewModel.baselineToolbarTotals, viewModel.currency)
      scheduleFocusRelaxIfNeeded()
    }
    .onChange(of: focusStage) { _, _ in
      scheduleFocusRelaxIfNeeded()
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
          onSkip()
        } label: {
          Text(.onboardingSkip)
            .font(.tidexBodyMedium)
            .foregroundColor(.tidexTextSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.9)
            .allowsTightening(true)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xxxs)
        }
        .fixedSize(horizontal: true, vertical: false)
        .buttonStyle(.plain)
        .tidexGlass(shape: .capsule, interactive: true)

        Spacer(minLength: 0)

        PreAuthSimulatorToolbarTotals(
          totals: viewModel.toolbarTotals,
          baselinePrimary: viewModel.baselineToolbarTotals?.primary,
          showDelta: viewModel.canContinue
        )
        .fixedSize(horizontal: true, vertical: false)
      }

      Text(.tabsAdd)
        .font(.headline)
        .foregroundColor(.tidexTextPrimary)
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
            .foregroundColor(viewModel.canContinue ? .tidexBlue : .tidexTextMuted)
            .frame(width: MonthPickerLayout.height, height: MonthPickerLayout.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canContinue)
        .tidexGlass(
          shape: .rect(cornerRadius: MonthPickerLayout.cornerRadius),
          tint: viewModel.canContinue ? Color.tidexBlue.opacity(0.2) : nil,
          clear: true,
          interactive: viewModel.canContinue,
          disabled: !viewModel.canContinue
        )
        .opacity(viewModel.canContinue ? 1.0 : 0.6)
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
    guard viewModel.canContinue else { return }

    focusedTimeField = nil
    hideKeyboard()

    UINotificationFeedbackGenerator().notificationOccurred(.success)
    onContinue(
      viewModel.baselineToolbarTotals,
      viewModel.toolbarTotals ?? viewModel.baselineToolbarTotals,
      viewModel.currency
    )
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

private enum PreAuthSimulatorFocusStage {
  case calendar
  case times
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
    onContinue: { _, _, _ in },
    onSkip: {},
    onBaselineReady: { _, _ in }
  )
}
