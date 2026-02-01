import SwiftUI
import UIKit

/// Add Shift tab view - form for creating new shifts
/// Supports both single shifts and recurring shift patterns
struct AddShiftView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.localization) private var localization
    @StateObject private var viewModel = AddShiftViewModel()
    @Binding var selectedTab: MainTabView.Tab
    @Binding var isKeyboardVisible: Bool
    @State private var focusedTimeField: NumericTimeInput.TimeField?

    /// Title for current mode
    private var modeTitle: String {
        switch viewModel.mode {
        case .single:
            return localization.string("addShift.singleTitle")
        case .recurring:
            return localization.string("addShift.recurringTitle")
        }
    }

    // iPad detection - hide logo on iPad
    private var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // Background that fills entire screen including safe areas
                Color.tidexBackground
                    .ignoresSafeArea()

                // Content area - different layouts for single vs recurring mode
                GeometryReader { geometry in
                    let availableHeight = geometry.size.height - (MonthPickerLayout.height + MonthPickerLayout.bottomPadding)

                    ScrollViewReader { scrollProxy in
                        switch viewModel.mode {
                        case .single:
                            // Single mode: Fixed layout with centered calendar
                            MonthSwipeContainer(
                                onSwipeLeft: { viewModel.goToNextMonth() },
                                onSwipeRight: { viewModel.goToPreviousMonth() },
                                isEnabled: true
                            ) {
                                VStack(spacing: 0) {
                                    Spacer()

                                    SingleShiftContent(viewModel: viewModel, scrollProxy: scrollProxy, focusedTimeField: $focusedTimeField)
                                        .frame(maxWidth: AdaptiveMaxWidth.tabContent)
                                        .padding(.horizontal, 16)

                                    Spacer()
                                }
                                .padding(.bottom, MonthPickerLayout.height + MonthPickerLayout.bottomPadding)
                                .contentShape(Rectangle())
                            }
                            .onTapGesture {
                                hideKeyboard()
                            }

                        case .recurring:
                            // Recurring mode: Scrollable content (more elements)
                            ScrollView {
                                VStack(spacing: 24) {
                                    // Draft restored banner
                                    if viewModel.hasDraft {
                                        DraftRestoredBanner(onStartFresh: {
                                            viewModel.startFresh()
                                        })
                                    }

                                    RecurringShiftContent(viewModel: viewModel, scrollProxy: scrollProxy, focusedTimeField: $focusedTimeField)
                                }
                                .frame(maxWidth: AdaptiveMaxWidth.tabContent)
                                .padding(.horizontal, 16)
                                .padding(.top, 16)
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: availableHeight, alignment: .center)
                            }
                            .monthSwipeGesture(
                                onSwipeLeft: { viewModel.goToNextMonth() },
                                onSwipeRight: { viewModel.goToPreviousMonth() },
                                isEnabled: true
                            )
                            .scrollDismissesKeyboard(.interactively)
                            .contentMargins(.bottom, MonthPickerLayout.height + MonthPickerLayout.bottomPadding + 16, for: .scrollContent)
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
                    .padding(.horizontal, 16)
                    .padding(.bottom, MonthPickerLayout.height + MonthPickerLayout.bottomPadding + 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.tidexBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .iPadToolbarBackground(Color.tidexBackground)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ShiftModeToggle(mode: $viewModel.mode)
                        .fixedSize()
                }
                if !isIPad {
                    ToolbarItem(placement: .principal) {
                        Image("TidexWordmark")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 22)
                    }
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
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.tidexTextPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glassEffect(.regular.tint(.tidexBlue.opacity(0.3)))
                    .padding(.trailing, 16)
                    .padding(.bottom, 8)
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
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation(.easeInOut(duration: 0.25)) {
                isKeyboardVisible = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeInOut(duration: 0.25)) {
                isKeyboardVisible = false
            }
        }
    }

    // MARK: - Deep Link Handling

    private func handleDeepLink(_ deepLink: AppCoordinator.DeepLink?) {
        guard case .addShift = deepLink else { return }
        viewModel.checkPreselectedDate()
        coordinator.clearPendingDeepLink()
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    /// Label for keyboard accessory button - "Next" when in start field, "Done" otherwise
    private var keyboardButtonLabel: String {
        if focusedTimeField == .start {
            return localization.string("common.next")
        }
        return localization.string("common.done")
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
    @Binding var focusedTimeField: NumericTimeInput.TimeField?
    @Environment(\.localization) private var localization

    var body: some View {
        // Calendar is the anchor - header and time picker positioned relative to it
        // Using overlay with alignment guides to position content outside calendar bounds
        AddShiftCalendarView(viewModel: viewModel)
            .overlay(alignment: .top) {
                // Header positioned above the calendar
                // Draft banner is included here so it stacks properly with the header
                VStack(spacing: 12) {
                    if viewModel.hasDraft {
                        DraftRestoredBanner(onStartFresh: {
                            viewModel.startFresh()
                        })
                    }

                    VStack(spacing: 4) {
                        Text(localization.string("addShift.headerTitle"))
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.tidexTextPrimary)

                        Text(localization.string("addShift.headerSubtitle"))
                            .font(.system(size: 15))
                            .foregroundColor(.tidexTextSecondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.bottom, 12)
                .alignmentGuide(.top) { d in d[.bottom] }
            }
            .overlay(alignment: .bottom) {
                // Time picker positioned below the calendar
                TimeRangePicker(
                    startTime: $viewModel.startTime,
                    endTime: $viewModel.endTime,
                    scrollProxy: scrollProxy,
                    scrollId: "singleTimePicker",
                    focusedFieldBinding: $focusedTimeField
                )
                .padding(.top, 12)
                .alignmentGuide(.bottom) { d in d[.top] }
            }
    }
}

// MARK: - Recurring Shift Content

private struct RecurringShiftContent: View {
    @ObservedObject var viewModel: AddShiftViewModel
    var scrollProxy: ScrollViewProxy
    @Binding var focusedTimeField: NumericTimeInput.TimeField?
    @Environment(\.localization) private var localization

    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 4) {
                Text(localization.string("addShift.headerTitle"))
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.tidexTextPrimary)

                Text(localization.string("addShift.headerSubtitle"))
                    .font(.system(size: 15))
                    .foregroundColor(.tidexTextSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 8)

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

            RecurringCalendarView(viewModel: viewModel)
        }
        // Extra bottom padding to clear the month picker
        .padding(.bottom, 80)
    }
}

// MARK: - Draft Restored Banner

private struct DraftRestoredBanner: View {
    let onStartFresh: () -> Void
    @Environment(\.localization) private var localization

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.counterclockwise.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(.tidexBlue)

            Text(localization.string("addShift.draftRestored"))
                .font(.system(size: 14))
                .foregroundColor(.tidexTextSecondary)

            Spacer()

            Button {
                onStartFresh()
            } label: {
                Text(localization.string("addShift.startFresh"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.tidexBlue)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.tidexBlue.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Preview

#Preview {
    AddShiftView(selectedTab: .constant(.add), isKeyboardVisible: .constant(false))
        .environmentObject(AppCoordinator.shared)
        .environment(\.localization, LocalizationManager.shared)
}
