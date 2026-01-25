import SwiftUI

/// Calendar for selecting anchor dates in recurring shift mode
/// Uses the same visual style as ShiftsCalendarView with rectangular cells and week numbers
/// Allows one anchor per weekday (max 7 anchors)
/// Note: Month navigation is handled by AnimatedMonthHeader in AddShiftView
struct RecurringCalendarView: View {
    @ObservedObject var viewModel: AddShiftViewModel
    @Environment(\.localization) private var localization

    var body: some View {
        VStack(spacing: 0) {
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
        anchorEarnings: Double?,
        existingEarnings: Double?,
        isOutsideMonth: Bool
    ) -> CalendarCellContent {
        if isAnchor {
            // Anchor date: show earnings if available, otherwise star icon
            if let earnings = anchorEarnings {
                return .earnings(earnings, color: .white)
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
            return .earnings(earnings, color: .tidexTextMuted)
        }

        return .empty
    }
}

// MARK: - Calendar Instructions

private struct CalendarInstructions: View {
    @Environment(\.localization) private var localization

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 24))
                .foregroundColor(.tidexTextMuted)

            Text(localization.string("addShift.tapToSetAnchors"))
                .font(.system(size: 14))
                .foregroundColor(.tidexTextSecondary)
                .multilineTextAlignment(.center)

            Text(localization.string("addShift.oneAnchorPerWeekday"))
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
    .environment(\.localization, LocalizationManager.shared)
}
