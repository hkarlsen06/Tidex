import SwiftUI

/// Calendar for selecting anchor dates in recurring shift mode
/// Uses the same visual style as ShiftsCalendarView with rectangular cells and week numbers
/// Allows one anchor per weekday (max 7 anchors)
/// Note: Month navigation is handled by AnimatedMonthHeader in AddShiftView
struct RecurringCalendarView: View {
    @ObservedObject var viewModel: AddShiftViewModel
    let onReset: (() -> Void)?

    init(viewModel: AddShiftViewModel, onReset: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self.onReset = onReset
    }
    
    var body: some View {
        VStack(spacing: 0) {
            CalendarHeaderRow(
                monthName: monthName,
                year: viewModel.displayYear,
                selectionCount: viewModel.selectedDays.count >= 2 ? viewModel.selectedDays.count : nil,
                phase: transitionPhase,
                totals: headerTotals,
                trailingAccessory: resetButton
            )

            // Weekday headers
            CalendarWeekdayHeader()
                .padding(.bottom, 8)

            // Calendar grid
            calendarGrid

            // Instructions
            if viewModel.selectedDays.isEmpty {
                CalendarInstructions()
                    .padding(.top, 16)
            }
        }
    }

    private var monthName: String {
        CalendarGridHelper.monthName(
            from: viewModel.displayMonth,
            locale: Locale.appLocale
        )
    }

    private var transitionPhase: MonthTransitionPhase {
        MonthTransitionPhase(
            year: viewModel.displayYear,
            month: viewModel.displayMonthNumber,
            direction: viewModel.navigationDirection
        )
    }

    private var headerTotals: CalendarHeaderTotals {
        let monthTotals = monthlyTotals
        let selectedTotals = selectedAnchorTotals
        let displayTotals = selectedTotals ?? monthTotals

        let primaryAmount = displayTotals.gross > 0
            ? (displayTotals.hasTaxEnabled ? displayTotals.net : displayTotals.gross)
            : nil
        let secondaryAmount = (displayTotals.hasTaxEnabled && displayTotals.gross > 0)
            ? displayTotals.gross
            : nil

        return CalendarHeaderTotals(
            primary: primaryAmount,
            secondary: secondaryAmount
        )
    }

    private var resetButton: AnyView? {
        guard viewModel.hasContent, let onReset else { return nil }
        return AnyView(
            Button(action: onReset) {
                Image(systemName: "arrow.counterclockwise.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.tidexBlue)
            }
            .buttonStyle(.plain)
        )
    }

    private var monthlyTotals: (net: Double, gross: Double, hasTaxEnabled: Bool) {
        viewModel.existingShiftEarnings.values.reduce(
            into: (net: 0.0, gross: 0.0, hasTaxEnabled: false)
        ) { partial, earnings in
            partial.net += earnings.net
            partial.gross += earnings.gross
            partial.hasTaxEnabled = partial.hasTaxEnabled || earnings.hasTaxEnabled
        }
    }

    private var selectedAnchorTotals: (net: Double, gross: Double, hasTaxEnabled: Bool)? {
        guard !viewModel.selectedDays.isEmpty else { return nil }

        let anchorEarnings = viewModel.selectedDays.values.compactMap { anchorDateISO in
            viewModel.earningsForRecurringDate(anchorDateISO)
        }
        guard !anchorEarnings.isEmpty else { return nil }

        return anchorEarnings.reduce(
            into: (net: 0.0, gross: 0.0, hasTaxEnabled: false)
        ) { partial, earnings in
            partial.net += earnings.net
            partial.gross += earnings.gross
            partial.hasTaxEnabled = partial.hasTaxEnabled || earnings.hasTaxEnabled
        }
    }

    // MARK: - Calendar Grid

    @ViewBuilder
    private var calendarGrid: some View {
        let days = CalendarGridHelper.daysInMonth(for: viewModel.displayMonth)
        let projectedDatesSet = Set(viewModel.projectedRecurringDates)

        LazyVGrid(columns: CalendarGridHelper.columns, spacing: 4) {
            ForEach(days, id: \.id) { dayInfo in
                let isAnchor = dayInfo.dateISO.map { isAnchorDate($0) } ?? false
                let isProjected = dayInfo.dateISO.map { projectedDatesSet.contains($0) } ?? false
                let hasConflict = dayInfo.dateISO.map { viewModel.conflictDates.contains($0) } ?? false
                let hasExistingShift = dayInfo.dateISO.map { viewModel.existingShiftDates.contains($0) } ?? false
                let isToday = dayInfo.dateISO == todayISO()
                let existingEarnings = dayInfo.dateISO.flatMap { viewModel.existingShiftEarnings[$0] }
                let anchorEarnings = isAnchor ? dayInfo.dateISO.flatMap { viewModel.earningsForRecurringDate($0) } : nil

                CalendarDayCell(
                    dayInfo: dayInfo,
                    style: cellStyle(
                        isAnchor: isAnchor,
                        isProjected: isProjected,
                        hasConflict: hasConflict,
                        hasExistingShift: hasExistingShift,
                        isToday: isToday,
                        isOutsideMonth: dayInfo.isOutsideMonth
                    ),
                    content: cellContent(
                        isAnchor: isAnchor,
                        isProjected: isProjected,
                        hasConflict: hasConflict,
                        anchorEarnings: anchorEarnings,
                        existingEarnings: existingEarnings,
                        isOutsideMonth: dayInfo.isOutsideMonth
                    )
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    if let dateISO = dayInfo.dateISO, !dayInfo.isOutsideMonth {
                        viewModel.toggleAnchorDate(dateISO)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func isAnchorDate(_ dateISO: String) -> Bool {
        viewModel.selectedDays.values.contains(dateISO)
    }

    // MARK: - Cell Styling

    private func cellStyle(
        isAnchor: Bool,
        isProjected: Bool,
        hasConflict: Bool,
        hasExistingShift: Bool,
        isToday: Bool,
        isOutsideMonth: Bool
    ) -> CalendarCellStyle {
        if isAnchor {
            return CalendarCellStyle(
                backgroundColor: .tidexBlue,
                borderColor: .tidexBlue,
                borderWidth: 2,
                dayNumberColor: .white
            )
        }
        if isProjected {
            return CalendarCellStyle(
                backgroundColor: hasConflict ? Color.tidexWarning.opacity(0.15) : Color.tidexBlue.opacity(0.15),
                borderColor: hasConflict ? .tidexWarning : .tidexBlue,
                borderWidth: 2,
                dayNumberColor: hasConflict ? .tidexWarning : .tidexBlue
            )
        }
        if isToday && !isOutsideMonth {
            return CalendarCellStyle(
                backgroundColor: .tidexSurfacePrimary,
                borderColor: .tidexBlue,
                borderWidth: 2,
                dayNumberColor: .tidexBlue
            )
        }
        if hasExistingShift && !isOutsideMonth {
            return CalendarCellStyle(
                backgroundColor: .tidexSurfacePrimary,
                borderColor: .clear,
                borderWidth: 0,
                dayNumberColor: .tidexBlue
            )
        }
        return .default
    }

    private func cellContent(
        isAnchor: Bool,
        isProjected: Bool,
        hasConflict: Bool,
        anchorEarnings: CalendarEarningsData?,
        existingEarnings: CalendarEarningsData?,
        isOutsideMonth: Bool
    ) -> CalendarCellContent {
        if isAnchor {
            // Anchor date: show earnings if available, otherwise star icon
            if let earnings = anchorEarnings {
                return .earningsBreakdown(
                    earnings,
                    color: .white,
                    beforeTaxColor: .white.opacity(0.75)
                )
            } else {
                return .starIcon(color: .white)
            }
        }

        if isProjected {
            // Projected dates: simple dot indicator
            return .dot(color: hasConflict ? .tidexWarning : .tidexBlue)
        }

        if let earnings = existingEarnings, !isOutsideMonth {
            // Existing shift earnings (grey)
            return .earningsBreakdown(
                earnings,
                color: .tidexTextMuted,
                beforeTaxColor: .tidexTextMuted
            )
        }

        return .empty
    }
}

// MARK: - Calendar Instructions

private struct CalendarInstructions: View {
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 24))
                .foregroundColor(.tidexTextMuted)

            Text(.addShiftTapToSetAnchors)
                .font(.system(size: 14))
                .foregroundColor(.tidexTextSecondary)
                .multilineTextAlignment(.center)

            Text(.addShiftOneAnchorPerWeekday)
                .font(.system(size: 12))
                .foregroundColor(.tidexTextMuted)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color.tidexSurfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        RecurringCalendarView(viewModel: AddShiftViewModel())
            .padding()
    }
    .background(Color.tidexBackground)
}
