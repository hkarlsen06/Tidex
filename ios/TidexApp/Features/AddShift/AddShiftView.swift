import SwiftUI
import UIKit

/// Add Shift tab view - form for creating new shifts
/// Supports both single shifts and recurring shift patterns
struct AddShiftView: View {
  @EnvironmentObject private var coordinator: AppCoordinator
  @StateObject private var viewModel = AddShiftViewModel()
  @Binding var selectedTab: MainTabView.Tab
  @Binding var isKeyboardVisible: Bool
  @State private var focusedTimeField: TimeInputField?
  @State private var keyboardHeight: CGFloat = 0
  @State private var tabTransitionOffset: CGFloat = 0
  @State private var tabTransitionOpacity: Double = 1

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
                  .frame(maxWidth: AdaptiveMaxWidth.tabContent)
                  .padding(.horizontal, Spacing.md)
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
                .animation(.easeInOut(duration: 0.25), value: focusedTimeField != nil)
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
                .frame(maxWidth: AdaptiveMaxWidth.tabContent)
                .padding(.horizontal, Spacing.md)
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
          .frame(maxWidth: AdaptiveMaxWidth.tabContent)
          .padding(.horizontal, Spacing.md)
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
        }
        ToolbarItem(placement: .topBarTrailing) {
          UserMenuButton(
            displayName: coordinator.userDisplayName,
            avatarUrl: coordinator.userAvatarUrl
          )
        }
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
      withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
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
    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
      if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey]
        as? CGRect {
        keyboardHeight = keyboardFrame.height
      }
      withAnimation(.easeInOut(duration: 0.25)) {
        isKeyboardVisible = true
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
      withAnimation(.easeInOut(duration: 0.25)) {
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

  var body: some View {
    VStack(spacing: 0) {
      AddShiftCalendarView(
        viewModel: viewModel,
        onReset: {
          viewModel.startFresh()
          if focusedTimeField != nil {
            focusedTimeField = nil
          }
        }
      )

      TimeRangePicker(
        startTime: $viewModel.startTime,
        endTime: $viewModel.endTime,
        scrollProxy: scrollProxy,
        scrollId: "singleTimePicker",
        focusedFieldBinding: $focusedTimeField
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

  var body: some View {
    VStack(spacing: Spacing.mlg) {
      DurationPicker(endCondition: $viewModel.endCondition)

      RepeatIntervalPicker(interval: $viewModel.repeatInterval)

      // Time picker above calendar for better UX
      TimeRangePicker(
        startTime: $viewModel.startTime,
        endTime: $viewModel.endTime,
        scrollProxy: scrollProxy,
        scrollId: "recurringTimePicker",
        focusedFieldBinding: $focusedTimeField
      )

      Divider()
        .background(Color.tidexBorder)

      // Chip bar with preallocated space to prevent layout shifts
      WeekdayChipBar(
        selectedDays: viewModel.selectedDays,
        onRemove: { weekday in
          viewModel.removeAnchor(weekday: weekday)
        }
      )

      RecurringCalendarView(
        viewModel: viewModel,
        onReset: {
          viewModel.startFresh()
          if focusedTimeField != nil {
            focusedTimeField = nil
          }
        }
      )
    }
    // Extra bottom padding to clear the month picker
    .padding(.bottom, Spacing.bottomScrollMargin)
  }
}

// MARK: - Preview

#Preview {
  AddShiftView(selectedTab: .constant(.add), isKeyboardVisible: .constant(false))
    .environmentObject(AppCoordinator.shared)
}
