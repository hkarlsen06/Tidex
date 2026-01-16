import SwiftUI
import UIKit

/// Multi-select calendar for choosing shift dates
/// Supports tap to toggle and drag-based multi-selection
struct ShiftCalendarView: View {
    @ObservedObject var viewModel: AddShiftViewModel
    @Environment(\.localization) private var localization

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private let calendar = Calendar.current

    // State for drag selection
    @State private var isDragSelecting = false
    @State private var dragSelectedDates: Set<String> = []
    @GestureState private var dragLocation: CGPoint = .zero

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

            // Calendar grid with drag selection
            CalendarGridView(
                days: daysInMonth(),
                viewModel: viewModel,
                isDragSelecting: $isDragSelecting,
                dragSelectedDates: $dragSelectedDates
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

// MARK: - Calendar Grid View (handles drag selection)

private struct CalendarGridView: View {
    let days: [ShiftCalendarView.DayInfo]
    @ObservedObject var viewModel: AddShiftViewModel
    @Binding var isDragSelecting: Bool
    @Binding var dragSelectedDates: Set<String>

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    // Store cell frames for hit testing
    @State private var cellFrames: [String: CGRect] = [:]
    // Track the start date and current end date for range selection
    @State private var dragStartDate: String?
    @State private var lastEndDate: String?

    var body: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(days, id: \.self) { dateInfo in
                if let dateISO = dateInfo.dateISO {
                    CalendarDayCell(
                        dateISO: dateISO,
                        dayNumber: dateInfo.dayNumber,
                        isSelected: viewModel.selectedDates.contains(dateISO) || dragSelectedDates.contains(dateISO),
                        isDragHighlighted: dragSelectedDates.contains(dateISO),
                        hasExistingShift: viewModel.existingShiftDates.contains(dateISO),
                        hasConflict: viewModel.conflictDates.contains(dateISO),
                        isToday: isToday(dateISO)
                    )
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: CellFramePreferenceKey.self,
                                value: [dateISO: geo.frame(in: .named("calendarGrid"))]
                            )
                        }
                    )
                    .onTapGesture {
                        if !isDragSelecting {
                            viewModel.toggleDate(dateISO)
                        }
                    }
                } else {
                    // Empty cell for padding
                    Color.clear
                        .frame(height: 44)
                }
            }
        }
        .coordinateSpace(name: "calendarGrid")
        .onPreferenceChange(CellFramePreferenceKey.self) { frames in
            cellFrames = frames
        }
        .gesture(
            LongPressGesture(minimumDuration: 0.2)
                .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("calendarGrid")))
                .onChanged { value in
                    switch value {
                    case .second(true, let drag):
                        if let drag = drag {
                            let location = drag.location
                            let currentDate = dateAtLocation(location)

                            // Long press triggered + drag started
                            if !isDragSelecting {
                                // Start drag selection mode
                                isDragSelecting = true
                                dragStartDate = currentDate
                                lastEndDate = nil
                                dragSelectedDates.removeAll()

                                // Add start date
                                if let startDate = currentDate {
                                    dragSelectedDates.insert(startDate)
                                }

                                // Haptic feedback for starting selection
                                let generator = UIImpactFeedbackGenerator(style: .medium)
                                generator.impactOccurred()
                            } else if let startDate = dragStartDate, let endDate = currentDate {
                                // Update range selection - select all dates from start to current
                                if endDate != lastEndDate {
                                    let newDates = datesInRange(from: startDate, to: endDate)
                                    dragSelectedDates = newDates

                                    // Light haptic when range changes
                                    let generator = UIImpactFeedbackGenerator(style: .light)
                                    generator.impactOccurred()

                                    lastEndDate = endDate
                                }
                            }
                        }

                    default:
                        break
                    }
                }
                .onEnded { _ in
                    // Commit drag selection to viewModel
                    if isDragSelecting {
                        for dateISO in dragSelectedDates {
                            if !viewModel.selectedDates.contains(dateISO) {
                                viewModel.selectedDates.insert(dateISO)
                            }
                        }
                        dragSelectedDates.removeAll()
                        dragStartDate = nil
                        lastEndDate = nil
                        isDragSelecting = false

                        // Success haptic
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.success)
                    }
                }
        )
    }

    private func isToday(_ dateISO: String) -> Bool {
        let today = Date().toISODateString()
        return dateISO == today
    }

    private func dateAtLocation(_ location: CGPoint) -> String? {
        for (dateISO, frame) in cellFrames {
            if frame.contains(location) {
                return dateISO
            }
        }
        return nil
    }

    /// Generate all dates in a range (inclusive)
    private func datesInRange(from startISO: String, to endISO: String) -> Set<String> {
        guard let startDate = Date.fromISODateString(startISO),
              let endDate = Date.fromISODateString(endISO) else {
            return []
        }

        var dates = Set<String>()
        let calendar = Calendar.current

        // Ensure we iterate from earlier to later date
        let (earlier, later) = startDate <= endDate ? (startDate, endDate) : (endDate, startDate)

        var current = earlier
        while current <= later {
            dates.insert(current.toISODateString())
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: current) else {
                break
            }
            current = nextDay
        }

        return dates
    }
}

// MARK: - Cell Frame Preference Key

private struct CellFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

// MARK: - Calendar Day Cell

struct CalendarDayCell: View {
    let dateISO: String
    let dayNumber: Int
    let isSelected: Bool
    let isDragHighlighted: Bool
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

            // Drag highlight indicator
            if isDragHighlighted {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.5), lineWidth: 2)
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
