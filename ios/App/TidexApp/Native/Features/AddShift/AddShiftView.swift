import SwiftUI
import UIKit

/// Add Shift tab view - form for creating new shifts
/// Supports both single shifts and recurring shift patterns
struct AddShiftView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.localization) private var localization
    @StateObject private var viewModel = AddShiftViewModel()
    @Binding var selectedTab: MainTabView.Tab
    @State private var isKeyboardVisible = false

    /// Transition phase for AnimatedMonthHeader animations
    private var transitionPhase: MonthTransitionPhase {
        MonthTransitionPhase(
            year: viewModel.displayYear,
            month: viewModel.displayMonthNumber,
            direction: viewModel.navigationDirection
        )
    }

    /// Title for current mode
    private var modeTitle: String {
        switch viewModel.mode {
        case .single:
            return localization.string("addShift.singleTitle")
        case .recurring:
            return localization.string("addShift.recurringTitle")
        }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // Background that fills entire screen including safe areas
                Color.tidexBackground
                    .ignoresSafeArea()

                // Scrollable content area
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        VStack(spacing: 24) {
                            switch viewModel.mode {
                            case .single:
                                SingleShiftContent(viewModel: viewModel, scrollProxy: scrollProxy)
                            case .recurring:
                                RecurringShiftContent(viewModel: viewModel, scrollProxy: scrollProxy)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .frame(maxWidth: .infinity)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onTapGesture {
                        hideKeyboard()
                    }
                }

                // Fixed bottom area with month picker - hidden when keyboard is visible
                if !isKeyboardVisible {
                    VStack(spacing: 8) {
                        // Error display (if any)
                        if let error = viewModel.error {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundColor(.tidexError)

                                Text(error)
                                    .font(.system(size: 14))
                                    .foregroundColor(.tidexError)
                            }
                            .padding(.horizontal, 16)
                        }

                        // Month picker - same styling as Dashboard/Shifts/Sharing
                        AnimatedMonthHeader(
                            monthName: viewModel.displayMonthName,
                            year: viewModel.displayYear,
                            phase: transitionPhase,
                            isCurrentMonth: viewModel.isCurrentMonth,
                            config: .default,
                            onPrevious: {
                                viewModel.goToPreviousMonth()
                            },
                            onNext: {
                                viewModel.goToNextMonth()
                            },
                            onReturnToCurrent: {
                                viewModel.goToCurrentMonth()
                            },
                            onNavigateToMonth: { year, month in
                                SharedMonthContext.shared.navigateTo(year: year, month: month)
                            },
                            isLoading: viewModel.isLoading,
                            backToTodayText: localization.string("dashboard.backToToday")
                        )
                        .frame(height: MonthPickerLayout.height)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: MonthPickerLayout.cornerRadius))
                    }
                    .padding(.horizontal, MonthPickerLayout.horizontalPadding)
                    .padding(.bottom, MonthPickerLayout.bottomPadding)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.tidexBackground, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ShiftModeToggle(mode: $viewModel.mode)
                        .fixedSize()
                }
                ToolbarItem(placement: .principal) {
                    HStack {
                        Image("TidexWordmark")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 22)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    UserMenuButton(
                        displayName: coordinator.userDisplayName,
                        avatarUrl: coordinator.userAvatarUrl
                    )
                }
            }
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

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// MARK: - Single Shift Content

private struct SingleShiftContent: View {
    @ObservedObject var viewModel: AddShiftViewModel
    var scrollProxy: ScrollViewProxy
    @Environment(\.localization) private var localization

    var body: some View {
        VStack(spacing: 24) {
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

            AddShiftCalendarView(viewModel: viewModel)

            TimeRangePicker(
                startTime: $viewModel.startTime,
                endTime: $viewModel.endTime,
                scrollProxy: scrollProxy,
                scrollId: "singleTimePicker"
            )
        }
    }
}

// MARK: - Recurring Shift Content

private struct RecurringShiftContent: View {
    @ObservedObject var viewModel: AddShiftViewModel
    var scrollProxy: ScrollViewProxy
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
                scrollId: "recurringTimePicker"
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

// MARK: - Preview

#Preview {
    AddShiftView(selectedTab: .constant(.add))
        .environmentObject(AppCoordinator.shared)
        .environment(\.localization, LocalizationManager.shared)
}
