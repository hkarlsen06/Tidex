import SwiftUI
import UIKit

/// Multi-select calendar for choosing shift dates
/// Supports tap to toggle date selection
struct ShiftCalendarView: View {
    @ObservedObject var viewModel: AddShiftViewModel
    @Environment(\.localization) private var localization

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 16) {
            // Month navigation header
            MonthNavigationHeader(
                month: viewModel.displayMonth,
                onPrevious: { navigateToPreviousMonth() },
                onNext: { navigateToNextMonth() }
            )

            // Weekday headers
            WeekdayHeaderRow()

            // Calendar grid
            CalendarGridView(
                days: daysInMonth(),
                viewModel: viewModel
            )
        }
    }

    // MARK: - Navigation

    private func navigateToPreviousMonth() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            viewModel.displayMonth = calendar.date(byAdding: .month, value: -1, to: viewModel.displayMonth) ?? viewModel.displayMonth
        }
        viewModel.reloadShiftsForDisplayedMonth()
    }

    private func navigateToNextMonth() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            viewModel.displayMonth = calendar.date(byAdding: .month, value: 1, to: viewModel.displayMonth) ?? viewModel.displayMonth
        }
        viewModel.reloadShiftsForDisplayedMonth()
    }

    // MARK: - Calendar Helpers

    struct DayInfo: Hashable {
        let id: Int
        let dayNumber: Int
        let dateISO: String?
    }

    private func daysInMonth() -> [DayInfo] {
        var days: [DayInfo] = []

        // Get first day of month
        let components = calendar.dateComponents([.year, .month], from: viewModel.displayMonth)
        guard let firstOfMonth = calendar.date(from: components) else { return days }

        // Get weekday of first day (1 = Sunday, 7 = Saturday)
        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)

        // Convert to Monday-start (0 = Monday, 6 = Sunday)
        let startOffset = (firstWeekday + 5) % 7

        // Add empty cells for days before first of month
        for i in 0..<startOffset {
            days.append(DayInfo(id: -i - 1, dayNumber: 0, dateISO: nil))
        }

        // Get number of days in month
        guard let range = calendar.range(of: .day, in: .month, for: firstOfMonth) else { return days }

        // Add cells for each day
        for day in range {
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth) else { continue }
            let dateISO = date.toISODateString()
            days.append(DayInfo(id: day, dayNumber: day, dateISO: dateISO))
        }

        return days
    }

    private func isToday(_ dateISO: String) -> Bool {
        let today = Date().toISODateString()
        return dateISO == today
    }
}

// MARK: - Month Navigation Header

struct MonthNavigationHeader: View {
    let month: Date
    let onPrevious: () -> Void
    let onNext: () -> Void

    @Environment(\.localization) private var localization

    private var monthYearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        formatter.locale = Locale(identifier: localization.currentLocale.localeIdentifier)
        return formatter.string(from: month).capitalized
    }

    var body: some View {
        HStack {
            Button(action: onPrevious) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.tidexBlue)
                    .frame(width: 44, height: 44)
            }

            Spacer()

            Text(monthYearString)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.tidexTextPrimary)

            Spacer()

            Button(action: onNext) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.tidexBlue)
                    .frame(width: 44, height: 44)
            }
        }
    }
}

// MARK: - Weekday Header Row

struct WeekdayHeaderRow: View {
    @Environment(\.localization) private var localization

    // Get localized weekday symbols (Monday-first order)
    private var weekdays: [String] {
        var calendar = Calendar.current
        calendar.locale = Locale(identifier: localization.currentLocale.localeIdentifier)
        // veryShortWeekdaySymbols is Sunday-first, reorder to Monday-first
        let symbols = calendar.veryShortWeekdaySymbols
        return Array(symbols[1...]) + [symbols[0]]
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(weekdays.indices, id: \.self) { index in
                Text(weekdays[index])
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.tidexTextMuted)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Calendar Grid View

private struct CalendarGridView: View {
    let days: [ShiftCalendarView.DayInfo]
    @ObservedObject var viewModel: AddShiftViewModel

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(days, id: \.self) { dateInfo in
                if let dateISO = dateInfo.dateISO {
                    CalendarDayCell(
                        dateISO: dateISO,
                        dayNumber: dateInfo.dayNumber,
                        isSelected: viewModel.selectedDates.contains(dateISO),
                        hasExistingShift: viewModel.existingShiftDates.contains(dateISO),
                        hasConflict: viewModel.conflictDates.contains(dateISO),
                        isToday: isToday(dateISO)
                    )
                    .onTapGesture {
                        viewModel.toggleDate(dateISO)
                    }
                } else {
                    // Empty cell for padding
                    Color.clear
                        .frame(height: 44)
                }
            }
        }
    }

    private func isToday(_ dateISO: String) -> Bool {
        let today = Date().toISODateString()
        return dateISO == today
    }
}

// MARK: - Calendar Day Cell

struct CalendarDayCell: View {
    let dateISO: String
    let dayNumber: Int
    let isSelected: Bool
    let hasExistingShift: Bool
    let hasConflict: Bool
    let isToday: Bool

    var body: some View {
        ZStack {
            // Background - squircle shape
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(backgroundColor)
                .frame(width: 40, height: 40)

            // Today indicator ring
            if isToday && !isSelected {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.tidexBlue, lineWidth: 2)
                    .frame(width: 40, height: 40)
            }

            VStack(spacing: 2) {
                Text("\(dayNumber)")
                    .font(.system(size: 16, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(textColor)

                // Existing shift indicator dot
                if hasExistingShift && !isSelected {
                    Circle()
                        .fill(hasConflict ? Color.tidexWarning : Color.tidexTextMuted)
                        .frame(width: 4, height: 4)
                }
            }
        }
        .frame(height: 44)
        .contentShape(Rectangle())
    }

    private var backgroundColor: Color {
        if isSelected {
            return hasConflict ? Color.tidexWarning : Color.tidexBlue
        }
        return Color.clear
    }

    private var textColor: Color {
        if isSelected {
            return .white
        }
        if hasConflict {
            return .tidexWarning
        }
        return .tidexTextPrimary
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        ShiftCalendarView(viewModel: AddShiftViewModel())
            .padding()
    }
    .background(Color.tidexBackground)
    .environment(\.localization, LocalizationManager.shared)
}
