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
    }
  }

  var body: some View {
    NavigationStack {
      ZStack(alignment: .bottom) {
        // Background that fills entire screen including safe areas
        Color.tidexBackground
          .ignoresSafeArea()

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
              .monthSwipeGesture(
                onSwipeLeft: { viewModel.goToNextMonth() },
                onSwipeRight: { viewModel.goToPreviousMonth() },
                isEnabled: true
              )
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

        // Error display - positioned above the shared month picker
        if let error = viewModel.error, !isKeyboardVisible {
          ErrorBanner(
            message: error,
            onRetry: {
              Task {
                switch viewModel.mode {
                case .single:
                  await viewModel.submitSingleShifts()
                case .recurring:
                  await viewModel.submitRecurringShift()
                }
              }
            },
            onDismiss: { viewModel.error = nil }
          )
          .frame(maxWidth: isIPhone ? .infinity : AdaptiveMaxWidth.tabContent)
          .padding(.horizontal, isIPhone ? Spacing.xs : Spacing.md)
          .padding(.bottom, MonthPickerLayout.totalBottomInset + Spacing.xs)
          .transition(.move(edge: .bottom).combined(with: .opacity))
        }
      }
      .navigationBarTitleDisplayMode(.inline)
      .iPadToolbarBackground()
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          ShiftModeToggle(mode: $viewModel.mode, style: .toolbar)
            .fixedSize()
        }
        ToolbarItem(placement: .principal) {
          Text(.tabsAdd)
            .font(.headline)
            .foregroundColor(.tidexTextPrimary)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        ToolbarItem(placement: .topBarTrailing) {
          HStack(spacing: Spacing.xs) {
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

            AddShiftToolbarTotals(totals: viewModel.toolbarTotals)
          }
          .fixedSize(horizontal: true, vertical: false)
        }
        .sharedBackgroundVisibility(.hidden)
      }
      .overlay(alignment: .bottomTrailing) {
        if isKeyboardVisible {
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
      await viewModel.loadData()
    }
    .onAppear {
      viewModel.onShiftsCreated = {
        selectedTab = .shifts
      }

      // Check for pre-selected date when tab becomes visible
      // (e.g., when user taps empty day in Shifts calendar)
      viewModel.checkPreselectedDate()
      handleDeepLink(coordinator.pendingDeepLink)
    }
    .onChange(of: coordinator.pendingDeepLink) { _, deepLink in
      handleDeepLink(deepLink)
    }
    .onChange(of: selectedTab) { oldTab, newTab in
      guard newTab == .add, oldTab == .shifts else { return }
      tabTransitionOffset = 28
      tabTransitionOpacity = 0.92
      MotionTokens.animate(.navigationPush, reduceMotion: reduceMotion) {
        tabTransitionOffset = 0
        tabTransitionOpacity = 1
      }
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
    guard case .addShift = deepLink else { return }
    viewModel.checkPreselectedDate()
    coordinator.clearPendingDeepLink()
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
    VStack(spacing: Spacing.sm) {
      AddShiftCalendarView(viewModel: viewModel)

      TimeRangePicker(
        startTime: $viewModel.startTime,
        endTime: $viewModel.endTime,
        scrollProxy: scrollProxy,
        scrollId: "singleTimePicker",
        focusedFieldBinding: $focusedTimeField,
        leadingChipAccessory: leadingJobAccessory
      )
      .padding(.top, Spacing.sm)
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
    VStack(spacing: Spacing.mlg) {
      RecurringCalendarView(viewModel: viewModel)

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
