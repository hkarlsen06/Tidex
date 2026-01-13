import Foundation

/// Generates virtual shift occurrences from recurring patterns
/// Port of lib/recurring/utils.ts
struct RecurringShiftGenerator {

    // MARK: - Public API

    /// Check if a date is in phase with an anchor date given an interval
    /// - Parameters:
    ///   - dateISO: ISO date to check (YYYY-MM-DD)
    ///   - anchorISO: Anchor date (YYYY-MM-DD)
    ///   - interval: Repetition interval (0 = every week, 1 = every 2 weeks, etc.)
    /// - Returns: true if date is in phase with anchor
    ///
    /// Example:
    /// - isInPhase("2025-11-03", "2025-10-27", 0) → true (every week)
    /// - isInPhase("2025-11-03", "2025-10-27", 1) → true (every 2 weeks, 1 week apart)
    /// - isInPhase("2025-11-10", "2025-10-27", 1) → false (2 weeks apart, wrong phase)
    static func isInPhase(dateISO: String, anchorISO: String, interval: Int) -> Bool {
        // interval 0 means every week, always in phase
        if interval == 0 { return true }

        let daysDiff = Date.daysBetween(anchorISO, dateISO)
        let weeksDiff = daysDiff / 7

        // Check if week difference is divisible by (interval + 1)
        // interval 1 = every 2 weeks, interval 2 = every 3 weeks, etc.
        return weeksDiff % (interval + 1) == 0
    }

    /// Generate virtual shift occurrences for a specific month
    /// - Parameters:
    ///   - year: Target year
    ///   - month: Target month (1-12)
    ///   - recurring: Recurring shift pattern
    /// - Returns: Array of virtual shift occurrences in the target month
    static func generateVirtualShiftsForMonth(
        year: Int,
        month: Int,
        recurring: RecurringShiftRow
    ) -> [RecurringVirtualShift] {
        guard !recurring.selected_days.isEmpty else { return [] }

        let monthStartDate = Date.firstDayOfMonthDate(year: year, month: month)
        let monthEndDate = Date.lastDayOfMonthDate(year: year, month: month)
        let monthStartISO = Date.firstDayOfMonth(year: year, month: month)
        let monthEndISO = Date.lastDayOfMonth(year: year, month: month)

        var virtualShifts: [RecurringVirtualShift] = []
        let exclusionSet = Set(recurring.effectiveExclusions)

        let calendar = Calendar(identifier: .gregorian)

        // For each selected weekday anchor
        for (weekdayKey, anchorISO) in recurring.selected_days {
            guard let weekday = Int(weekdayKey) else { continue }

            // Find first occurrence of this weekday in target month
            var current = monthStartDate
            let currentWeekday = calendar.component(.weekday, from: current) - 1  // 0=Sun, 6=Sat

            let daysUntilTarget = (weekday - currentWeekday + 7) % 7
            current = calendar.date(byAdding: .day, value: daysUntilTarget, to: current) ?? current

            // Generate occurrences throughout the month
            while current <= monthEndDate {
                let currentISO = current.toISODateString(in: TimeZone(identifier: "UTC")!)

                // Check date range
                guard currentISO >= monthStartISO && currentISO <= monthEndISO else {
                    current = calendar.date(byAdding: .weekOfYear, value: 1, to: current) ?? current
                    continue
                }

                // Only generate forwards from anchor date
                guard currentISO >= anchorISO else {
                    current = calendar.date(byAdding: .weekOfYear, value: 1, to: current) ?? current
                    continue
                }

                // Check if in phase with anchor
                let inPhase = isInPhase(
                    dateISO: currentISO,
                    anchorISO: anchorISO,
                    interval: recurring.repeat_interval_weeks
                )

                // Check if within recurring shift window (end condition)
                let withinWindow = checkEndCondition(
                    currentDate: current,
                    currentISO: currentISO,
                    endCondition: recurring.end_condition,
                    selectedDays: recurring.selected_days
                )

                // Check if not excluded
                let notExcluded = !exclusionSet.contains(currentISO)

                if inPhase && withinWindow && notExcluded {
                    virtualShifts.append(RecurringVirtualShift(
                        date: currentISO,
                        weekday: weekday
                    ))
                }

                // Move to next week
                current = calendar.date(byAdding: .weekOfYear, value: 1, to: current) ?? current
            }
        }

        // Sort by date
        return virtualShifts.sorted { $0.date < $1.date }
    }

    // MARK: - Private Helpers

    /// Check if date is within the recurring shift's end condition window
    private static func checkEndCondition(
        currentDate: Date,
        currentISO: String,
        endCondition: EndCondition?,
        selectedDays: SelectedDays
    ) -> Bool {
        // No end condition = always valid (infinite recurrence)
        guard let endCondition = endCondition else {
            return true
        }

        // Find earliest anchor date for window calculation
        let anchorDates = selectedDays.values.sorted()
        guard let earliestAnchor = anchorDates.first,
              let anchorDate = Date.fromISODateStringUTC(earliestAnchor) else {
            return true
        }

        let calendar = Calendar(identifier: .gregorian)

        switch endCondition {
        case .months(let value):
            // End date is anchor + N months
            guard let endDate = calendar.date(byAdding: .month, value: value, to: anchorDate) else {
                return true
            }
            return currentDate <= endDate

        case .years(let value):
            // End date is anchor + N years
            guard let endDate = calendar.date(byAdding: .year, value: value, to: anchorDate) else {
                return true
            }
            return currentDate <= endDate

        case .endDate(let dateString):
            // Specific end date
            return currentISO <= dateString
        }
    }
}
