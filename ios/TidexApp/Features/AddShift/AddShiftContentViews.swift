import SwiftUI
import UIKit

// MARK: - Single Shift Content

struct SingleShiftContent: View {
  @Bindable var viewModel: AddShiftViewModel
  var scrollProxy: ScrollViewProxy
  @Binding var focusedTimeField: TimeInputField?
  var usesColumns = false
  var calendarMaxWidth: CGFloat = .infinity

  var body: some View {
    let layout =
      usesColumns
      ? AnyLayout(HStackLayout(spacing: Spacing.xl))
      : AnyLayout(VStackLayout(spacing: Spacing.xs))
    layout {
      VStack(spacing: Spacing.xs) {
        CalendarHeaderRow(totals: viewModel.toolbarTotals, secondaryStyle: .delta)
        AddShiftCalendarView(viewModel: viewModel)
      }
      .frame(maxWidth: calendarMaxWidth)

      timeControls
        .frame(maxWidth: usesColumns ? 360 : .infinity)
    }
  }

  private var timeControls: some View {
    VStack(spacing: Spacing.xs) {
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

  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  var body: some View {
    ZStack(alignment: .bottom) {
      // Background that fills entire screen including safe areas
      TidexAppBackground()

      if showsWorkSetupPlaceholder {
        WorkSetupRequiredPlaceholder()
      } else {
        // Content area - different layouts for single vs recurring mode
        modeContent
          .clipped()
          .padding(.bottom, isKeyboardVisible ? 0 : bottomControlsInset)

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
          availableWidth: geometry.size.width,
          availableHeight: max(
            0, geometry.size.height - geometry.safeAreaInsets.top - geometry.safeAreaInsets.bottom
          )
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
      .frame(maxWidth: AdaptiveMaxWidth.tabContent)
      .padding(.horizontal, horizontalSizeClass == .regular ? Spacing.md : Spacing.xs)
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
  let availableWidth: CGFloat
  let availableHeight: CGFloat
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  private var usesColumns: Bool {
    availableWidth >= 700 && !dynamicTypeSize.isAccessibilitySize
  }

  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

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
  private var singleContent: some View {
    ScrollView {
      VStack(spacing: 0) {
        Spacer()

        SingleShiftContent(
          viewModel: viewModel, scrollProxy: scrollProxy,
          focusedTimeField: $focusedTimeField,
          usesColumns: usesColumns,
          calendarMaxWidth: usesColumns ? 400 : min(500, max(336, availableHeight * 0.6))
        )
        .frame(maxWidth: usesColumns ? 820 : AdaptiveMaxWidth.tabContent)
        .padding(.horizontal, horizontalSizeClass == .regular ? Spacing.md : Spacing.xs)
        .onGeometryChange(for: CGSize.self) {
          $0.size
        } action: { _ in
          revealFocusedTimeFields()
        }

        Spacer()
      }
      // Fill exactly the space above the controls, so it only scrolls on screens
      // too small for the calendar.
      .frame(maxWidth: .infinity, minHeight: availableHeight)
      .contentShape(Rectangle())
      .monthSwipeGesture(
        onSwipeLeft: { viewModel.goToNextMonth() },
        onSwipeRight: { viewModel.goToPreviousMonth() },
        isEnabled: true
      )
    }
    .scrollBounceBehavior(.basedOnSize)
    .scrollIndicators(.hidden)
    .onChange(of: focusedTimeField) { _, _ in
      revealFocusedTimeFields()
    }
    .onChange(of: CGSize(width: availableWidth, height: availableHeight)) { _, _ in
      revealFocusedTimeFields()
    }
  }

  private func revealFocusedTimeFields() {
    DispatchQueue.main.async {
      guard let focusedTimeField else { return }
      MotionTokens.animate(.subtle, reduceMotion: reduceMotion) {
        scrollProxy.scrollTo(
          TimeRangePicker.FieldScrollID(pickerID: "singleTimePicker", field: focusedTimeField),
          anchor: focusedTimeField == .start ? .top : .bottom
        )
      }
    }
  }

  /// Recurring mode: scrollable content (more elements)
  private var recurringContent: some View {
    ScrollView {
      VStack(spacing: Spacing.lg) {
        RecurringShiftContent(
          viewModel: viewModel, scrollProxy: scrollProxy,
          focusedTimeField: $focusedTimeField)
      }
      .frame(maxWidth: AdaptiveMaxWidth.tabContent)
      .padding(.horizontal, horizontalSizeClass == .regular ? Spacing.md : Spacing.xs)
      .padding(.top, Spacing.md)
      .frame(maxWidth: .infinity)
      .frame(minHeight: availableHeight, alignment: .center)
    }
    .scrollDismissesKeyboard(.interactively)
    .contentMargins(
      .bottom, Spacing.md, for: .scrollContent
    )
  }

  private var eventContent: some View {
    ScrollView {
      VStack(spacing: Spacing.lg) {
        EventContent(viewModel: viewModel, focusedTimeField: $focusedTimeField)
      }
      .frame(maxWidth: AdaptiveMaxWidth.tabContent)
      .padding(.horizontal, horizontalSizeClass == .regular ? Spacing.md : Spacing.xs)
      .padding(.top, Spacing.md)
      .frame(maxWidth: .infinity)
      .frame(minHeight: availableHeight, alignment: .top)
    }
    .scrollDismissesKeyboard(.interactively)
    .contentMargins(
      .bottom, Spacing.md, for: .scrollContent
    )
  }
}
