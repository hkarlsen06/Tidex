import SwiftUI
import UIKit

/// Multi-select calendar for choosing shift dates in AddShift
/// Uses the same visual style as ShiftsCalendarView but adapted for date selection
/// Supports tap to toggle date selection with existing shift and conflict indicators
struct AddShiftCalendarView: View {
    @ObservedObject var viewModel: AddShiftViewModel
    @Environment(\.localization) private var localization

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        VStack(spacing: 0) {
            // Weekday headers
            weekdayHeaderRow
                .padding(.bottom, 8)

            // Calendar grid
            calendarGrid
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

        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(days, id: \.id) { dayInfo in
                AddShiftCalendarDayCell(
                    dayInfo: dayInfo,
                    isToday: dayInfo.dateISO == todayISO(),
                    isSelected: dayInfo.dateISO.map { viewModel.selectedDates.contains($0) } ?? false,
                    hasExistingShift: dayInfo.dateISO.map { viewModel.existingShiftDates.contains($0) } ?? false,
                    hasConflict: dayInfo.dateISO.map { viewModel.conflictDates.contains($0) } ?? false,
                    existingEarnings: dayInfo.dateISO.flatMap { viewModel.existingShiftEarnings[$0] },
                    previewEarnings: dayInfo.dateISO.flatMap { viewModel.previewEarnings[$0] }
                )
                .onTapGesture {
                    if let dateISO = dayInfo.dateISO, !dayInfo.isOutsideMonth {
                        viewModel.toggleDate(dateISO)
                    }
                }
            }
        }
    }

    // MARK: - Calendar Helpers

    struct DayInfo: Identifiable {
        let id: Int
        let dayNumber: Int
        let dateISO: String?
        let weekNumber: Int?  // ISO week number (only on Mondays)
        let isOutsideMonth: Bool
    }

    private func daysInMonth() -> [DayInfo] {
        var days: [DayInfo] = []

        // Get first day of month from viewModel's displayMonth
        let components = calendar.dateComponents([.year, .month], from: viewModel.displayMonth)
        guard let firstOfMonth = calendar.date(from: components) else { return days }

        // Get weekday of first day (1 = Sunday, 7 = Saturday)
        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)

        // Convert to Monday-start (0 = Monday, 6 = Sunday)
        let startOffset = (firstWeekday + 5) % 7

        // Get number of days in month
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

// MARK: - Day Cell

private struct AddShiftCalendarDayCell: View {
    let dayInfo: AddShiftCalendarView.DayInfo
    let isToday: Bool
    let isSelected: Bool
    let hasExistingShift: Bool
    let hasConflict: Bool
    let existingEarnings: Double?
    let previewEarnings: Double?

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

                if isSelected, let earnings = previewEarnings {
                    // Preview earnings for selected dates (blue)
                    Text(formatCompactCurrency(earnings))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(hasConflict ? .tidexWarning : .tidexBlue)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.bottom, 6)
                } else if isSelected {
                    // Selected but no preview earnings yet (need times)
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(hasConflict ? .tidexWarning : .tidexBlue)
                        .padding(.bottom, 8)
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
        if isSelected {
            return hasConflict ? Color.tidexWarning.opacity(0.15) : Color.tidexBlue.opacity(0.15)
        }
        if isToday && !dayInfo.isOutsideMonth {
            return Color.tidexBlue.opacity(0.2)
        }
        return Color.tidexSurfacePrimary
    }

    private var borderColor: Color {
        if isSelected {
            return hasConflict ? Color.tidexWarning : Color.tidexBlue
        }
        return Color.clear
    }

    private var borderWidth: CGFloat {
        if isSelected {
            return 2
        }
        return 0
    }

    private var dayNumberColor: Color {
        if hasConflict && isSelected {
            return .tidexWarning
        }
        if isToday && !dayInfo.isOutsideMonth {
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

// MARK: - Preview

#Preview {
    ScrollView {
        AddShiftCalendarView(viewModel: AddShiftViewModel())
            .padding()
    }
    .background(Color.tidexBackground)
    .environment(\.localization, LocalizationManager.shared)
}
