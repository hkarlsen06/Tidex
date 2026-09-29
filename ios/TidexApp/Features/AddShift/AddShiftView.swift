import SwiftUI
import UIKit

/// Add Shift screen, pushed onto the current tab's navigation stack - form for creating new shifts
/// Supports both single shifts and recurring shift patterns
struct AddShiftView: View {
  private static let payManagerCompactDetent: PresentationDetent = .height(395)

  @Environment(AppCoordinator.self) private var coordinator
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private let addShiftCoordinator = AddShiftCoordinator.shared
  @State private var viewModel = AddShiftViewModel()
  @State private var workSetupPresentationViewModel = WorkSetupPresentationViewModel()
  /// Called after saving so the presenter can pop the screen.
  /// Receives the created dates in single mode, and nil for recurring shifts and events.
  var onShiftsCreated: (_ singleDates: Set<String>?) -> Void = { _ in }
  @State private var isKeyboardVisible = false
  @State private var focusedTimeField: TimeInputField?
  @State private var keyboardHeight: CGFloat = 0
  @State private var showStartFreshConfirmation = false
  @State private var showSubmitRequirementsAlert = false
  @State private var showAddJobSheet = false
  @State private var openJobsAndPaySettingsAfterPickerDismiss = false
  @State private var showPaySettings = false
  @State private var paySettingsDetent: PresentationDetent = Self.payManagerCompactDetent

  private func refreshWorkSetupPresentationState() {
    workSetupPresentationViewModel.refresh(
      userId: coordinator.userId,
      initialSyncComplete: coordinator.initialSyncComplete
    )
  }

  private var shouldShowWorkSetupRequiredPlaceholder: Bool {
    workSetupPresentationViewModel.shouldShowPlaceholder
  }

  private func loadAddShiftContent() async {
    guard !shouldShowWorkSetupRequiredPlaceholder else { return }
    await viewModel.loadData()
  }

  private func prepareVisibleAddShiftContent() {
    guard !shouldShowWorkSetupRequiredPlaceholder else { return }
    viewModel.onShiftsCreated = { completion in
      switch completion {
      case .single(let dates):
        onShiftsCreated(dates)

      case .recurring, .event:
        onShiftsCreated(nil)
      }
    }

    // Check for pre-selected date when the screen opens
    // (e.g., when user taps empty day in Shifts calendar)
    applyPendingPreselectedDateWithoutAnimation()
    handleDeepLink(coordinator.pendingDeepLink)
  }

  var body: some View {
    Group {
      AddShiftScreenContent(
        viewModel: viewModel,
        showsWorkSetupPlaceholder: shouldShowWorkSetupRequiredPlaceholder,
        isKeyboardVisible: isKeyboardVisible,
        keyboardHeight: keyboardHeight,
        focusedTimeField: $focusedTimeField,
        onBackgroundTap: hideKeyboard,
        onStartFresh: presentStartFreshConfirmation,
        onSave: handleSaveTap
      )
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        if !shouldShowWorkSetupRequiredPlaceholder {
          ToolbarItem(placement: .topBarTrailing) {
            ShiftModeToggle(mode: $viewModel.mode, style: .toolbar)
              .fixedSize()
          }
        }
      }
      .overlay(alignment: .bottomTrailing) {
        keyboardButton
      }
      .iPadToolbarTransaction()
      .userCurrency(viewModel.currency)
    }
    .background(FullWidthBackSwipeBlocker())
    .disabled(viewModel.isLoading)
    .task {
      refreshWorkSetupPresentationState()
      await loadAddShiftContent()
    }
    .onAppear {
      refreshWorkSetupPresentationState()
      prepareVisibleAddShiftContent()
    }
    .onChange(of: coordinator.initialSyncComplete) { _, completed in
      refreshWorkSetupPresentationState()
      guard completed, !shouldShowWorkSetupRequiredPlaceholder else { return }
      prepareVisibleAddShiftContent()
      Task {
        await loadAddShiftContent()
      }
    }
    .onChange(of: coordinator.userId) { _, _ in
      refreshWorkSetupPresentationState()
    }
    .onReceive(NotificationCenter.default.publisher(for: .workSetupDataDidChange)) { _ in
      refreshWorkSetupPresentationState()
      guard !shouldShowWorkSetupRequiredPlaceholder else { return }
      prepareVisibleAddShiftContent()
      Task {
        await loadAddShiftContent()
      }
    }
    .onChange(of: coordinator.pendingDeepLink) { _, deepLink in
      guard !shouldShowWorkSetupRequiredPlaceholder else { return }
      handleDeepLink(deepLink)
    }
    .onDisappear {
      focusedTimeField = nil
      isKeyboardVisible = false
      keyboardHeight = 0
      viewModel.onShiftsCreated = nil
      // An unconsumed add link (for example while work setup is required) would
      // otherwise block the next identical request from reopening the sheet.
      if case .addShift = coordinator.pendingDeepLink {
        coordinator.clearPendingDeepLink()
      }
    }
    .modifier(
      AddShiftSheetsModifier(
        viewModel: viewModel,
        showAddJobSheet: $showAddJobSheet,
        showPaySettings: $showPaySettings,
        openJobsAndPaySettingsAfterPickerDismiss: $openJobsAndPaySettingsAfterPickerDismiss,
        paySettingsDetent: $paySettingsDetent,
        compactDetent: Self.payManagerCompactDetent
      )
    )
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
    .alert(
      String(localized: .addShiftSubmitRequirementsTitle),
      isPresented: $showSubmitRequirementsAlert
    ) {
      Button(String(localized: .commonOk), role: .cancel) {}
    } message: {
      Text(submitRequirementsMessage)
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

  @ViewBuilder
  private var keyboardButton: some View {
    if isKeyboardVisible, !shouldShowWorkSetupRequiredPlaceholder {
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

  // MARK: - Deep Link Handling

  private func handleDeepLink(_ deepLink: AppCoordinator.DeepLink?) {
    guard case .addShift(let mode, let date) = deepLink else { return }
    if let date, Date.fromISODateString(date) != nil {
      SharedMonthContext.shared.preselectedDate = date
    }
    if let mode {
      viewModel.applyDeepLinkMode(mode)
    }
    applyPendingPreselectedDateWithoutAnimation()
    coordinator.clearPendingDeepLink()
  }

  private func applyPendingPreselectedDateWithoutAnimation() {
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction) {
      viewModel.checkPreselectedDate()
    }
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

  private func handleSaveTap() {
    guard !addShiftCoordinator.isLoading else { return }

    if addShiftCoordinator.canSubmit {
      Haptics.play(.selection)
      addShiftCoordinator.triggerAdd()
      return
    }

    Haptics.play(.warning)
    showSubmitRequirementsAlert = true
  }

  private var submitRequirementsMessage: String {
    let blockers = addShiftCoordinator.submitBlockers
    guard !blockers.isEmpty else {
      return String(localized: .addShiftSubmitRequirementsGeneric)
    }

    return
      blockers
      .map { "- \(String(localized: $0.requirementMessage))" }
      .joined(separator: "\n")
  }
}

// MARK: - Preview

#Preview {
  AddShiftView()
    .environment(AppCoordinator.shared)
}
