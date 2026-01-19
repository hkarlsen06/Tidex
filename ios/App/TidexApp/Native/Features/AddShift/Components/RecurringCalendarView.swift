import SwiftUI

/// Calendar for selecting anchor dates in recurring shift mode
/// Uses the same visual style as ShiftsCalendarView with rectangular cells and week numbers
/// Allows one anchor per weekday (max 7 anchors)
/// Note: Month navigation is handled by AnimatedMonthHeader in AddShiftView
struct RecurringCalendarView: View {
    @ObservedObject var viewModel: AddShiftViewModel
    @Environment(\.localization) private var localization

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 0) {
            // Weekday headers
            weekdayHeaderRow
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

    // MARK: - Weekday Header Row

    private var weekdayHeaderRow: some View {
        HStack(spacing: 0) {
            ForEach(weekdaySymbols.indices, id: \.self) { index in
                Text(weekdaySymbols[index])
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.tidexTextMuted)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var weekdaySymbols: [String] {
        let isNorwegian = localization.currentLocale == .norwegian
        if isNorwegian {
            return ["MA", "TI", "ON", "TO", "FR", "LØ", "SØ"]
        } else {
            return ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]
        }
    }

    // MARK: - Calendar Grid

    @ViewBuilder
    private var calendarGrid: some View {
        let days = daysInMonth()
        let projectedDatesSet = Set(viewModel.projectedRecurringDates)

        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(days, id: \.id) { dayInfo in
                let isAnchor = dayInfo.dateISO.map { isAnchorDate($0) } ?? false
                let isProjected = dayInfo.dateISO.map { projectedDatesSet.contains($0) } ?? false

                RecurringCalendarDayCell(
                    dayInfo: dayInfo,
                    isAnchor: isAnchor,
                    isProjected: isProjected,
                    hasConflict: dayInfo.dateISO.map { viewModel.conflictDates.contains($0) } ?? false,
                    hasExistingShift: dayInfo.dateISO.map { viewModel.existingShiftDates.contains($0) } ?? false,
                    isToday: dayInfo.dateISO == todayISO(),
                    existingEarnings: dayInfo.dateISO.flatMap { viewModel.existingShiftEarnings[$0] },
                    // Only show earnings for anchor dates - projected dates show a dot
                    anchorEarnings: isAnchor ? dayInfo.dateISO.flatMap { viewModel.earningsForRecurringDate($0) } : nil
                )
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

    struct DayInfo: Identifiable {
        let id: Int
        let dayNumber: Int
        let dateISO: String?
        let weekNumber: Int?  // ISO week number (only on Mondays)
        let isOutsideMonth: Bool
    }

    private func daysInMonth() -> [DayInfo] {
        var days: [DayInfo] = []

        let components = calendar.dateComponents([.year, .month], from: viewModel.displayMonth)
        guard let firstOfMonth = calendar.date(from: components) else { return days }

        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)
        let startOffset = (firstWeekday + 5) % 7

        guard let range = calendar.range(of: .day, in: .month, for: firstOfMonth) else { return days }

        // Get last day of previous month for "outside days"
        let previousMonth = calendar.date(byAdding: .month, value: -1, to: firstOfMonth)!
        let daysInPreviousMonth = calendar.range(of: .day, in: .month, for: previousMonth)!.count

        // Add days from previous month (outside days)
        for i in 0..<startOffset {
            let day = daysInPreviousMonth - startOffset + i + 1
            let date = calendar.date(byAdding: .day, value: i - startOffset, to: firstOfMonth)!
            let dateISO = date.toISODateString()
            let weekNum = calendar.component(.weekday, from: date) == 2 ? getIsoWeek(from: date) : nil

            days.append(DayInfo(
                id: -1000 + i,
                dayNumber: day,
                dateISO: dateISO,
                weekNumber: weekNum,
                isOutsideMonth: true
            ))
        }

        // Add cells for each day in current month
        for day in range {
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth) else { continue }
            let dateISO = date.toISODateString()
            let isMonday = calendar.component(.weekday, from: date) == 2
            let weekNum = isMonday ? getIsoWeek(from: date) : nil

            days.append(DayInfo(
                id: day,
                dayNumber: day,
                dateISO: dateISO,
                weekNumber: weekNum,
                isOutsideMonth: false
            ))
        }

        // Add days from next month to fill the last row
        let totalDays = days.count
        let remainder = totalDays % 7
        if remainder > 0 {
            let daysToAdd = 7 - remainder
            for i in 0..<daysToAdd {
                let date = calendar.date(byAdding: .day, value: range.count + i, to: firstOfMonth)!
                let dateISO = date.toISODateString()
                let weekNum = calendar.component(.weekday, from: date) == 2 ? getIsoWeek(from: date) : nil

                days.append(DayInfo(
                    id: 1000 + i,
                    dayNumber: i + 1,
                    dateISO: dateISO,
                    weekNumber: weekNum,
                    isOutsideMonth: true
                ))
            }
        }

        return days
    }

    private func getIsoWeek(from date: Date) -> Int {
        var isoCalendar = Calendar(identifier: .iso8601)
        isoCalendar.firstWeekday = 2  // Monday
        isoCalendar.minimumDaysInFirstWeek = 4
        return isoCalendar.component(.weekOfYear, from: date)
    }
}

// MARK: - Recurring Calendar Day Cell

private struct RecurringCalendarDayCell: View {
    let dayInfo: RecurringCalendarView.DayInfo
    let isAnchor: Bool
    let isProjected: Bool
    let hasConflict: Bool
    let hasExistingShift: Bool
    let isToday: Bool
    let existingEarnings: Double?
    let anchorEarnings: Double?  // Only set for anchor dates

    var body: some View {
        ZStack {
            // Week number (top-left corner, only on Mondays)
            if let weekNum = dayInfo.weekNumber {
                VStack {
                    HStack {
                        Text("\(weekNum)")
                            .font(.system(size: 9))
                            .foregroundColor(.tidexTextMuted)
                            .padding(.leading, 6)
                            .padding(.top, 4)
                        Spacer()
                    }
                    Spacer()
                }
            }

            // Day number (top-right corner)
            VStack {
                HStack {
                    Spacer()
                    Text("\(dayInfo.dayNumber)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(dayNumberColor)
                        .padding(.trailing, 4)
                        .padding(.top, 3)
                }
                Spacer()
            }

            // Content: earnings display or indicator
            VStack {
                Spacer()

                if isAnchor {
                    // Anchor date: show earnings if available, otherwise star icon
                    if let earnings = anchorEarnings {
                        Text(formatCompactCurrency(earnings))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .padding(.bottom, 6)
                    } else {
                        Image(systemName: "star.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.bottom, 8)
                    }
                } else if isProjected {
                    // Projected dates: simple dot indicator (no earnings computation)
                    Circle()
                        .fill(hasConflict ? Color.tidexWarning : Color.tidexBlue)
                        .frame(width: 8, height: 8)
                        .padding(.bottom, 10)
                } else if let earnings = existingEarnings, !dayInfo.isOutsideMonth {
                    // Existing shift earnings (grey)
                    Text(formatCompactCurrency(earnings))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.tidexTextMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.bottom, 6)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1 / 1.3, contentMode: .fill)
        .clipped()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColor)
        )
        .overlay(
            // Selection/today indicator ring
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(borderColor, lineWidth: borderWidth)
        )
        .opacity(dayInfo.isOutsideMonth ? 0.4 : 1.0)
        .contentShape(Rectangle())
    }

    private var backgroundColor: Color {
        if isAnchor {
            return .tidexBlue
        }
        if isProjected {
            return hasConflict ? Color.tidexWarning.opacity(0.15) : Color.tidexBlue.opacity(0.15)
        }
        return Color.tidexSurfacePrimary
    }

    private var borderColor: Color {
        if isAnchor {
            return .tidexBlue
        }
        if isProjected {
            return hasConflict ? Color.tidexWarning : Color.tidexBlue
        }
        if isToday && !dayInfo.isOutsideMonth {
            return Color.tidexBlue
        }
        return Color.clear
    }

    private var borderWidth: CGFloat {
        if isAnchor || isProjected || (isToday && !dayInfo.isOutsideMonth) {
            return 2
        }
        return 0
    }

    private var dayNumberColor: Color {
        if isAnchor {
            return .white
        }
        if isProjected {
            return hasConflict ? .tidexWarning : .tidexBlue
        }
        if hasExistingShift && !dayInfo.isOutsideMonth {
            return .tidexBlue
        }
        return .tidexTextPrimary
    }

    private func formatCompactCurrency(_ amount: Double) -> String {
        // Compact format without currency symbol for calendar cells
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.groupingSeparator = " "
        return formatter.string(from: NSNumber(value: amount)) ?? "\(Int(amount))"
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
