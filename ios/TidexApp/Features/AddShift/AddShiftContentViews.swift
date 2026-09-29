import SwiftUI
import UIKit

// MARK: - Single Shift Content

struct SingleShiftContent: View {
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
            .accessibilityHidden(true)
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

struct RecurringShiftContent: View {
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

// MARK: - Back Swipe

/// Turns off the full-width back swipe while the screen is in the window, so a right swipe
/// on the calendar or month picker changes month instead of popping the screen.
/// The edge swipe and back button still go back.
struct FullWidthBackSwipeBlocker: UIViewRepresentable {
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

/// Content of the add screen: mode body, submit error and the bottom controls.
struct AddShiftScreenContent: View {
  /// Space kept free for the two rows of bottom controls at regular text sizes.
  private static let minimumControlsInset: CGFloat =
    MonthPickerLayout.height * 2 + Spacing.xs + MonthPickerLayout.bottomPadding

  let viewModel: AddShiftViewModel
  let showsWorkSetupPlaceholder: Bool
  let isKeyboardVisible: Bool
  let keyboardHeight: CGFloat
  @Binding var focusedTimeField: TimeInputField?
  let onBackgroundTap: () -> Void
  let onStartFresh: () -> Void
  let onSave: () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  /// Height of the bottom controls, which grow with the text size.
  @State private var measuredControlsHeight: CGFloat = 0

  private var bottomControlsInset: CGFloat {
    max(Self.minimumControlsInset, measuredControlsHeight)
  }

  private var isIPhone: Bool {
    UIDevice.current.userInterfaceIdiom == .phone
  }

  var body: some View {
    ZStack(alignment: .bottom) {
      // Background that fills entire screen including safe areas
      TidexAppBackground()

      if showsWorkSetupPlaceholder {
        WorkSetupRequiredPlaceholder()
      } else {
        // Content area - different layouts for single vs recurring mode
        modeContent

        if !isKeyboardVisible {
          submitErrorBanner

          AddShiftBottomControls(
            viewModel: viewModel,
            onStartFresh: onStartFresh,
            onSave: onSave
          )
          .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
          } action: { height in
            measuredControlsHeight = height
          }
          .transition(.opacity)
        }
      }
    }
  }

  private var modeContent: some View {
    GeometryReader { geometry in
      ScrollViewReader { scrollProxy in
        AddShiftModeContent(
          viewModel: viewModel,
          focusedTimeField: $focusedTimeField,
          scrollProxy: scrollProxy,
          keyboardHeight: keyboardHeight,
          availableHeight: geometry.size.height - bottomControlsInset,
          bottomControlsInset: bottomControlsInset
        )
        .onTapGesture(perform: onBackgroundTap)
      }
    }
  }

  @ViewBuilder
  private var submitErrorBanner: some View {
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
      .padding(.bottom, bottomControlsInset + Spacing.xs)
      .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
    }
  }
}

/// Scrollable body of the add screen for the current mode.
struct AddShiftModeContent: View {
  @Bindable var viewModel: AddShiftViewModel
  @Binding var focusedTimeField: TimeInputField?
  let scrollProxy: ScrollViewProxy
  let keyboardHeight: CGFloat
  let availableHeight: CGFloat
  let bottomControlsInset: CGFloat
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var isIPhone: Bool {
    UIDevice.current.userInterfaceIdiom == .phone
  }

  var body: some View {
    switch viewModel.mode {
    case .single:
      singleContent

    case .recurring:
      recurringContent

    case .events:
      eventContent
    }
  }

  /// Single mode: centered calendar that only scrolls when it doesn't fit.
  /// No pull-to-refresh, so dragging down never fights the back gesture.
  /// Uses manual offset for keyboard avoidance to handle 6-week months
  private var singleContent: some View {
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
      .frame(maxWidth: .infinity, minHeight: availableHeight)
      .padding(.bottom, bottomControlsInset)
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
  }

  /// Recurring mode: scrollable content (more elements)
  private var recurringContent: some View {
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
      .bottom, bottomControlsInset + Spacing.md, for: .scrollContent
    )
  }

  private var eventContent: some View {
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
      .bottom, bottomControlsInset + Spacing.md, for: .scrollContent
    )
  }
}
