import SwiftUI
import UIKit

/// Add Shift tab view - form for creating new shifts
/// Supports both single shifts and recurring shift patterns
struct AddShiftView: View {
    @Environment(\.localization) private var localization
    @StateObject private var viewModel = AddShiftViewModel()
    @Binding var selectedTab: MainTabView.Tab

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

                // Scrollable content area - fills available space
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
                        .padding(.vertical, 24)
                        // Add bottom padding to account for fixed month picker
                        .padding(.bottom, 100)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onTapGesture {
                        hideKeyboard()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Fixed bottom area with month picker
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
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.tidexBackground, for: .navigationBar)
            .toolbar {
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
                    ShiftModeToggle(mode: $viewModel.mode)
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
            AddShiftCalendarView(viewModel: viewModel)

            TimeRangePicker(
                startTime: $viewModel.startTime,
                endTime: $viewModel.endTime,
                scrollProxy: scrollProxy,
                scrollId: "singleTimePicker"
            )

            AddShiftButton(viewModel: viewModel, mode: .single)
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

            AddShiftButton(viewModel: viewModel, mode: .recurring)
        }
    }
}

// MARK: - Add Shift Button

/// Full-width add shift button placed below the time picker
private struct AddShiftButton: View {
    @ObservedObject var viewModel: AddShiftViewModel
    let mode: AddShiftMode
    @Environment(\.localization) private var localization

    private var canSubmit: Bool {
        switch mode {
        case .single:
            return viewModel.canSubmitSingle
        case .recurring:
            return viewModel.canSubmitRecurring
        }
    }

    /// Count of selected items
    private var count: Int {
        switch mode {
        case .single:
            return viewModel.selectedDates.count
        case .recurring:
            return viewModel.selectedDays.count
        }
    }

    /// Button title based on mode and selection count
    private var buttonTitle: String {
        switch mode {
        case .single:
            if count <= 1 {
                return localization.string("addShift.addShift")
            } else {
                // "Legg til {count} vakter" / "Add {count} shifts"
                return localization.string("addShift.addShifts")
                    .replacingOccurrences(of: "{count}", with: "\(count)")
            }
        case .recurring:
            return localization.string("addShift.previewShifts")
        }
    }

    var body: some View {
        Button(action: handleSubmit) {
            HStack(spacing: 8) {
                if viewModel.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Image(systemName: mode == .single ? "plus" : "eye")
                        .font(.system(size: 16, weight: .semibold))

                    Text(buttonTitle)
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .foregroundColor(canSubmit ? .white : .tidexTextMuted)
            .background(canSubmit ? Color.tidexBlue : Color.tidexSurfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .disabled(!canSubmit || viewModel.isLoading)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: canSubmit)
    }

    private func handleSubmit() {
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        switch mode {
        case .single:
            Task {
                await viewModel.submitSingleShifts()
            }
        case .recurring:
            viewModel.showPreview()
        }
    }
}

// MARK: - Preview

#Preview {
    AddShiftView(selectedTab: .constant(.add))
        .environmentObject(AppCoordinator.shared)
        .environment(\.localization, LocalizationManager.shared)
}
