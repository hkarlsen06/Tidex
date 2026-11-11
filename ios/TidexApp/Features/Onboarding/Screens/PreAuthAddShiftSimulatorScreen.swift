import SwiftUI

/// Pre-auth demo of the Add tab. A date is already picked, so choosing times is the one step
/// before the screen shows what the shift pays and offers to save it.
struct PreAuthAddShiftSimulatorScreen: View {
  let onCurrencyChanged: (String) -> Void
  let onSave: (PreAuthDemoShift) -> Void
  let onSkip: () -> Void
  let onBack: () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var viewModel: PreAuthAddShiftSimulatorViewModel
  @State private var focusedTimeField: TimeInputField?

  private enum ScrollTarget {
    case times
  }

  init(
    initialCurrency: String,
    onCurrencyChanged: @escaping (String) -> Void,
    onSave: @escaping (PreAuthDemoShift) -> Void,
    onSkip: @escaping () -> Void,
    onBack: @escaping () -> Void
  ) {
    self.onCurrencyChanged = onCurrencyChanged
    self.onSave = onSave
    self.onSkip = onSkip
    self.onBack = onBack
    _viewModel = State(
      wrappedValue: PreAuthAddShiftSimulatorViewModel(initialCurrency: initialCurrency))
  }

  var body: some View {
    // The panel sits below the scroll view, not in its safe area, so the scroll view gets
    // shorter as the panel grows and can scroll the chosen times into view above it.
    VStack(spacing: 0) {
      GeometryReader { geometry in
        ScrollViewReader { proxy in
          ScrollView {
            content(usesColumns: geometry.size.width >= 700 && !dynamicTypeSize.isAccessibilitySize)
          }
          .scrollBounceBehavior(.basedOnSize)
          .scrollDismissesKeyboard(.interactively)
          .task(id: viewModel.pay != nil) {
            // Scrolling only works once the panel's growth has settled and the scroll view is short.
            guard viewModel.pay != nil else { return }
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            MotionTokens.animate(.feedback, reduceMotion: reduceMotion) {
              proxy.scrollTo(ScrollTarget.times, anchor: .bottom)
            }
          }
        }
      }
      resultPanel
        .fixedSize(horizontal: false, vertical: true)
    }
    .background(Color.tidexBackground.ignoresSafeArea())
    .safeAreaInset(edge: .top, spacing: 0) {
      header
    }
    .userCurrency(viewModel.currency)
    .motionAnimation(.emphasis, value: viewModel.pay, reduceMotion: reduceMotion)
  }

  private func save() {
    guard let shift = viewModel.shift else { return }
    focusedTimeField = nil
    OnboardingFirstShiftCarryoverStore.write(
      dates: viewModel.selectedDates,
      startTime: viewModel.startTime,
      endTime: viewModel.endTime
    )
    onSave(shift)
  }

  private func selectCurrency(_ currency: String) {
    guard currency != viewModel.currency else { return }
    viewModel.applyCurrency(currency)
    onCurrencyChanged(viewModel.currency)
  }
}

extension PreAuthAddShiftSimulatorScreen {
  private func content(usesColumns: Bool) -> some View {
    let layout =
      usesColumns
      ? AnyLayout(HStackLayout(alignment: .top, spacing: Spacing.xl))
      : AnyLayout(VStackLayout(spacing: Spacing.sm))
    return layout {
      VStack(alignment: .leading, spacing: Spacing.xs) {
        Text(verbatim: "\(viewModel.displayMonthName) \(viewModel.displayYear)")
          .font(.tidexHeadline)
          .foregroundStyle(Color.tidexTextPrimary)
          .accessibilityAddTraits(.isHeader)
          .padding(.horizontal, Spacing.xs)

        AddShiftCalendarView(viewModel: viewModel)
      }
      .frame(maxWidth: usesColumns ? 400 : .infinity)

      TimeRangePicker(
        startTime: $viewModel.startTime,
        endTime: $viewModel.endTime,
        focusedFieldBinding: $focusedTimeField,
        presetRanges: viewModel.presetTimeRanges
      )
      .frame(maxWidth: usesColumns ? 360 : .infinity)
      .id(ScrollTarget.times)
    }
    .padding(.horizontal, Spacing.xs)
    .padding(.bottom, Spacing.sm)
    .frame(maxWidth: usesColumns ? 820 : AdaptiveMaxWidth.tabContent)
    .frame(maxWidth: .infinity)
  }

  /// Back and Skip at the edges and the currency between them. Large text stacks the currency
  /// under them so the three never overlap.
  @ViewBuilder
  private var header: some View {
    Group {
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: Spacing.xs) {
          HStack(spacing: Spacing.sm) {
            backButton
            Spacer(minLength: 0)
            skipButton
          }
          currencySelector
        }
      } else {
        ZStack {
          HStack(spacing: Spacing.sm) {
            backButton
            Spacer(minLength: 0)
            skipButton
          }
          currencySelector
        }
      }
    }
    .padding(.horizontal, Spacing.sm)
    .padding(.bottom, Spacing.xs)
    .frame(maxWidth: AdaptiveMaxWidth.tabContent)
    .frame(maxWidth: .infinity)
    .background(Color.tidexBackground)
  }

  private var backButton: some View {
    PreAuthBackButton(action: onBack)
  }

  private var skipButton: some View {
    Button {
      Haptics.play(.light)
      onSkip()
    } label: {
      Text(.onboardingSkip)
        .font(.tidexLabelStrong)
        .foregroundStyle(Color.tidexBlueText)
        .padding(.horizontal, Spacing.xs)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("onboarding.demo.skip")
  }

  private var currencySelector: some View {
    OnboardingCurrencyCapsuleSelector(
      selectedCurrency: Binding(get: { viewModel.currency }, set: selectCurrency)
    )
    .fixedSize()
  }

  private var resultPanel: some View {
    VStack(spacing: Spacing.sm) {
      if let pay = viewModel.pay {
        PreAuthDemoPaySummary(pay: pay, hourlyRate: viewModel.hourlyRate, currency: viewModel.currency)
          .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
      } else {
        Text(.onboardingAddSimulatorInstruction)
          .font(.tidexBodyMedium)
          .foregroundStyle(Color.tidexTextSecondary)
          .multilineTextAlignment(.center)
          .frame(maxWidth: .infinity)
          .transition(.opacity)
      }

      OnboardingButton(
        title: viewModel.selectedDates.count > 1
          ? String(localized: .onboardingAddSimulatorSaveMany)
          : String(localized: .onboardingAddSimulatorSaveOne),
        isEnabled: viewModel.pay != nil,
        action: save
      )
      .accessibilityIdentifier("onboarding.demo.save")
    }
    .padding(.horizontal, Spacing.lg)
    .padding(.top, Spacing.sm)
    .padding(.bottom, Spacing.xs)
    .frame(maxWidth: AdaptiveMaxWidth.tabContent)
    .frame(maxWidth: .infinity)
    .background(Color.tidexBackground)
  }
}

#Preview {
  PreAuthAddShiftSimulatorScreen(
    initialCurrency: "kr",
    onCurrencyChanged: { _ in },
    onSave: { _ in },
    onSkip: {},
    onBack: {}
  )
}
