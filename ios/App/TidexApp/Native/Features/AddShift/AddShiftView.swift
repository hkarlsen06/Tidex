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

    /// Subtitle hint for current mode
    private var modeSubtitle: String {
        switch viewModel.mode {
        case .single:
            return localization.string("addShift.singleSubtitle")
        case .recurring:
            return localization.string("addShift.recurringSubtitle")
        }
    }

    var body: some View {
        TabScreenContainer(
            title: localization.string(AppTab.add.titleKey),
            content: {
                ZStack(alignment: .bottom) {
                    // Scrollable content area - fills available space
                    ScrollViewReader { scrollProxy in
                        ScrollView {
                            VStack(spacing: 24) {
                                // Mode-specific header with inline toggle
                                HStack(alignment: .center) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(modeTitle)
                                            .font(.title2.weight(.semibold))
                                            .foregroundColor(.tidexTextPrimary)

                                        Text(modeSubtitle)
                                            .font(.subheadline)
                                            .foregroundColor(.tidexTextSecondary)
                                    }

                                    Spacer()

                                    ShiftModeToggle(mode: $viewModel.mode)
                                }

                                switch viewModel.mode {
                                case .single:
                                    SingleShiftContent(viewModel: viewModel, scrollProxy: scrollProxy)
                                case .recurring:
                                    RecurringShiftContent(viewModel: viewModel, scrollProxy: scrollProxy)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 24)
                            // Add bottom padding to account for fixed bottom controls
                            .padding(.bottom, 200)
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .onTapGesture {
                            hideKeyboard()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Fixed bottom area with liquid glass background
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

                        // Month picker and add button in one row
                        // Matches Dashboard month picker: height 56, cornerRadius 30, padding 16
                        HStack(spacing: 4) {
                            AnimatedMonthHeader(
                                monthName: viewModel.displayMonthName,
                                year: viewModel.displayYear,
                                phase: transitionPhase,
                                isCurrentMonth: viewModel.isCurrentMonth,
                                config: .compact,
                                onPrevious: {
                                    viewModel.goToPreviousMonth()
                                },
                                onNext: {
                                    viewModel.goToNextMonth()
                                },
                                onReturnToCurrent: {
                                    viewModel.goToCurrentMonth()
                                },
                                isLoading: viewModel.isLoading,
                                backToTodayText: localization.string("dashboard.backToToday")
                            )

                            // Compact add button - 48pt to be concentric with 56pt pill (4pt padding each side)
                            CompactAddButton(viewModel: viewModel)
                        }
                        .padding(.leading, 8)
                        .padding(.trailing, 4)
                        .frame(height: 56)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 30))
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
            },
            principalContent: {
                EmptyView()
            }
        )
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

    var body: some View {
        VStack(spacing: 24) {
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
            RepeatIntervalPicker(interval: $viewModel.repeatInterval)

            DurationPicker(endCondition: $viewModel.endCondition)

            Divider()
                .background(Color.tidexBorder)

            WeekdayChipBar(
                selectedDays: viewModel.selectedDays,
                onRemove: { weekday in
                    viewModel.removeAnchor(weekday: weekday)
                }
            )

            RecurringCalendarView(viewModel: viewModel)

            TimeRangePicker(
                startTime: $viewModel.startTime,
                endTime: $viewModel.endTime,
                scrollProxy: scrollProxy,
                scrollId: "recurringTimePicker"
            )
        }
    }
}

// MARK: - Compact Add Button

private struct CompactAddButton: View {
    @ObservedObject var viewModel: AddShiftViewModel

    private var canSubmit: Bool {
        switch viewModel.mode {
        case .single:
            return viewModel.canSubmitSingle
        case .recurring:
            return viewModel.canSubmitRecurring
        }
    }

    /// Badge text showing count or status
    private var badgeText: String? {
        switch viewModel.mode {
        case .single:
            let count = viewModel.selectedDates.count
            return count > 0 ? "\(count)" : nil
        case .recurring:
            let count = viewModel.selectedDays.count
            return count > 0 ? "\(count)" : nil
        }
    }

    var body: some View {
        Button(action: handleSubmit) {
            ZStack(alignment: .topTrailing) {
                if viewModel.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .frame(width: 48, height: 48)
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .semibold))
                        .frame(width: 48, height: 48)
                }

                // Badge showing count
                if let badge = badgeText, !viewModel.isLoading {
                    Text(badge)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Color.tidexBlue)
                        .clipShape(Circle())
                        .offset(x: 4, y: -4)
                }
            }
        }
        .foregroundColor(canSubmit ? .white : .tidexTextMuted)
        .background(canSubmit ? Color.tidexBlue : Color.tidexSurfaceSecondary)
        .clipShape(Circle())
        .disabled(!canSubmit || viewModel.isLoading)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: canSubmit)
    }

    private func handleSubmit() {
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        switch viewModel.mode {
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
