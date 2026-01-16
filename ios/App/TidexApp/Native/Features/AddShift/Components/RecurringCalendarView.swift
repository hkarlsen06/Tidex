import SwiftUI

/// Calendar for selecting anchor dates in recurring shift mode
/// Allows one anchor per weekday (max 7 anchors)
struct RecurringCalendarView: View {
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
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(daysInMonth(), id: \.self) { dateInfo in
                    if let dateISO = dateInfo.dateISO {
                        RecurringCalendarDayCell(
                            dateISO: dateISO,
                            dayNumber: dateInfo.dayNumber,
                            isAnchor: isAnchorDate(dateISO),
                            isProjected: viewModel.projectedRecurringDates.contains(dateISO),
                            hasConflict: viewModel.conflictDates.contains(dateISO),
                            hasExistingShift: viewModel.existingShiftDates.contains(dateISO),
                            isToday: isToday(dateISO),
                            onTap: { viewModel.toggleAnchorDate(dateISO) }
                        )
                    } else {
                        // Empty cell for padding
                        Color.clear
                            .frame(height: 44)
                    }
                }
            }

            // Instructions
            if viewModel.selectedDays.isEmpty {
                CalendarInstructions()
            }
        }
    }

    // MARK: - Navigation

    private func navigateToPreviousMonth() {
        let canNavigate = RecurringShiftProjector.canNavigateToPrevious(
            from: viewModel.displayMonth,
            selectedDays: viewModel.selectedDays
        )
        guard canNavigate else { return }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            viewModel.displayMonth = calendar.date(byAdding: .month, value: -1, to: viewModel.displayMonth) ?? viewModel.displayMonth
        }
        viewModel.reloadShiftsForDisplayedMonth()
    }

    private func navigateToNextMonth() {
        let canNavigate = RecurringShiftProjector.canNavigateToNext(
            from: viewModel.displayMonth,
            selectedDays: viewModel.selectedDays,
            endCondition: viewModel.endCondition
        )
        guard canNavigate else { return }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            viewModel.displayMonth = calendar.date(byAdding: .month, value: 1, to: viewModel.displayMonth) ?? viewModel.displayMonth
        }
        viewModel.reloadShiftsForDisplayedMonth()
    }

    // MARK: - Helpers

    private func isAnchorDate(_ dateISO: String) -> Bool {
        viewModel.selectedDays.values.contains(dateISO)
    }

    private struct DayInfo: Hashable {
        let id: Int
        let dayNumber: Int
        let dateISO: String?
    }

    private func daysInMonth() -> [DayInfo] {
        var days: [DayInfo] = []

        let components = calendar.dateComponents([.year, .month], from: viewModel.displayMonth)
        guard let firstOfMonth = calendar.date(from: components) else { return days }

        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)
        let startOffset = (firstWeekday + 5) % 7

        for i in 0..<startOffset {
            days.append(DayInfo(id: -i - 1, dayNumber: 0, dateISO: nil))
        }

        guard let range = calendar.range(of: .day, in: .month, for: firstOfMonth) else { return days }

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

// MARK: - Recurring Calendar Day Cell

struct RecurringCalendarDayCell: View {
    let dateISO: String
    let dayNumber: Int
    let isAnchor: Bool
    let isProjected: Bool
    let hasConflict: Bool
    let hasExistingShift: Bool
    let isToday: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Background
                Circle()
                    .fill(backgroundColor)
                    .frame(width: 40, height: 40)

                // Today indicator ring
                if isToday && !isAnchor && !isProjected {
                    Circle()
                        .strokeBorder(Color.tidexBlue, lineWidth: 2)
                        .frame(width: 40, height: 40)
                }

                // Anchor indicator (double ring)
                if isAnchor {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.5), lineWidth: 2)
                        .frame(width: 44, height: 44)
                }

                VStack(spacing: 2) {
                    Text("\(dayNumber)")
                        .font(.system(size: 16, weight: (isAnchor || isProjected) ? .semibold : .regular))
                        .foregroundColor(textColor)

                    // Existing shift indicator dot (only if not projected/anchor)
                    if hasExistingShift && !isAnchor && !isProjected {
                        Circle()
                            .fill(Color.tidexTextMuted)
                            .frame(width: 4, height: 4)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .frame(height: 44)
        .opacity(hasConflict && isProjected ? 0.5 : 1.0)
    }

    private var backgroundColor: Color {
        if isAnchor {
            return .tidexBlue
        }
        if isProjected {
            return hasConflict ? Color.tidexWarning.opacity(0.3) : Color.tidexBlue.opacity(0.2)
        }
        return .clear
    }

    private var textColor: Color {
        if isAnchor {
            return .white
        }
        if isProjected {
            return hasConflict ? .tidexWarning : .tidexBlue
        }
        if hasConflict {
            return .tidexWarning
        }
        return .tidexTextPrimary
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

            Text("Tap dates to set anchor days")
                .font(.system(size: 14))
                .foregroundColor(.tidexTextSecondary)
                .multilineTextAlignment(.center)

            Text("One anchor per weekday (max 7)")
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
