import SwiftUI
import UIKit

/// Read-only calendar view for shared shifts
/// Matches the visual style of ShiftsCalendarView but without selection/editing features
struct SharedShiftsCalendarView: View {
    let shifts: [ShiftWithComputations]
    let year: Int
    let month: Int  // 1-12
    let currency: String
    let showEarnings: Bool

    /// Dates to highlight from notification deeplink (e.g., friend's updated shifts)
    var highlightDates: Set<String> = []

    /// Shift IDs to highlight from notification deeplink (more precise than dates)
    var highlightShiftIds: Set<String> = []

    /// Whether superimpose mode is active (shows user's shifts instead of friend's)
    var isSuperimposing: Bool = false

    /// User's own shift hours by date (for superimpose feature)
    var userHoursByDate: [String: HoursData]?

    /// Callback when a shift is tapped (for showing details)
    var onShiftTapped: ((ShiftWithComputations) -> Void)?

    @State private var viewMode: CalendarViewMode = CalendarViewMode.load()

    /// Purple/violet color for deep link highlight (matches ShiftsCalendarView)
    private static let deepLinkHighlightColor = Color(red: 0.545, green: 0.361, blue: 0.965)

    private let calendar = Calendar.current

    // MARK: - Computed Data

    /// Earnings by ISO date string
    private var earningsByDate: [String: Double] {
        var result: [String: Double] = [:]
        for shift in shifts {
            let net = shift.taxEnabled ? shift.netPay : shift.grossPay
            result[shift.shiftDate, default: 0] += net
        }
        return result
    }

    /// Hours by ISO date string
    private var hoursByDate: [String: HoursData] {
        var shiftsByDateDict: [String: [ShiftWithComputations]] = [:]
        for shift in shifts {
            shiftsByDateDict[shift.shiftDate, default: []].append(shift)
        }

        var result: [String: HoursData] = [:]
        for (date, shiftsOnDate) in shiftsByDateDict {
            let sorted = shiftsOnDate.sorted { $0.startTime < $1.startTime }
            let earliestStart = sorted.first?.startTime ?? ""
            let latestEnd = sorted.map(\.endTime).max() ?? ""

            let crossesMidnight = shiftsOnDate.contains { shift in
                let startMinutes = CalendarGridHelper.timeToMinutes(shift.startTime)
                let endMinutes = CalendarGridHelper.timeToMinutes(shift.endTime)
                return endMinutes <= startMinutes
            }

            result[date] = HoursData(
                start: CalendarGridHelper.formatTime(earliestStart),
                end: CalendarGridHelper.formatTime(latestEnd),
                crossesMidnight: crossesMidnight
            )
        }
        return result
    }

    /// Shifts grouped by ISO date string
    private var shiftsByDate: [String: [ShiftWithComputations]] {
        var result: [String: [ShiftWithComputations]] = [:]
        for shift in shifts {
            result[shift.shiftDate, default: []].append(shift)
        }
        return result
    }

    /// Monthly totals (net and gross)
    private var monthlyTotals: (net: Double, gross: Double) {
        let gross = shifts.reduce(0) { $0 + $1.grossPay }
        let net = shifts.reduce(0) {
            $0 + ($1.taxEnabled ? $1.netPay : $1.grossPay)
        }
        return (net: net, gross: gross)
    }

    /// Whether tax is enabled for any shift
    private var hasTaxEnabled: Bool {
        shifts.contains { $0.taxEnabled }
    }

    /// Month name
    private var monthName: String {
        CalendarGridHelper.monthName(
            year: year,
            month: month,
            locale: Locale.appLocale
        )
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header: Month name + Year and Total
            headerRow

            // Weekday headers
            CalendarWeekdayHeader()
                .padding(.bottom, 8)

            // Calendar grid
            calendarGrid
                .padding(.bottom, 12)

            // View mode toggle (hours/money)
            if showEarnings {
                CalendarViewModeToggle(
                    viewMode: $viewMode,
                    currency: currency
                )
            }
        }
        .padding(.horizontal, 16)
        .overlay(alignment: .top) {
            // Superimpose legend (floats above header when active)
            if isSuperimposing {
                superimposeLegend
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.tidexSurfacePrimary)
                            .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
                    )
                    .offset(y: -44)
            }
        }
    }

    // MARK: - Header Row

    private var headerRow: some View {
        HStack {
            // Month name + Year
            HStack(spacing: 6) {
                Text(monthName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.tidexTextPrimary)

                Text(String(year))
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.tidexTextMuted)
            }

            Spacer()

            // Monthly total (if showing earnings)
            if showEarnings {
                earningsDisplay
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 12)
    }

    /// Earnings display - shows monthly totals
    @ViewBuilder
    private var earningsDisplay: some View {
        let displayTotals = monthlyTotals
        let showTax = hasTaxEnabled
        let displayAmount = showTax ? displayTotals.net : displayTotals.gross

        VStack(alignment: .trailing, spacing: 2) {
            Text(displayTotals.gross == 0 ? "—" : CurrencyConfig.format(displayAmount, currency: currency))
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.tidexTextPrimary)

            if showTax && displayTotals.gross > 0 {
                Text(CurrencyConfig.format(displayTotals.gross, currency: currency))
                    .font(.system(size: 13))
                    .foregroundColor(.tidexTextMuted)
            }
        }
    }

    // MARK: - Superimpose Legend

    /// Legend explaining the color coding when superimpose is active
    private var superimposeLegend: some View {
        HStack(spacing: 16) {
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.tidexBlue)
                    .frame(width: 8, height: 8)
                Text(.sharingSuperimposeLegendBlue)
                    .font(.system(size: 12))
                    .foregroundColor(.tidexTextMuted)
            }

            HStack(spacing: 4) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                Text(.sharingSuperimposeLegendGreen)
                    .font(.system(size: 12))
                    .foregroundColor(.tidexTextMuted)
            }
        }
        .padding(.horizontal, 12)
    }

    // MARK: - Calendar Grid

    private var calendarGrid: some View {
        let days = CalendarGridHelper.daysInMonth(year: year, month: month)

        return LazyVGrid(columns: CalendarGridHelper.columns, spacing: 4) {
            ForEach(days, id: \.id) { dayInfo in
                calendarDayView(for: dayInfo)
            }
        }
    }

    /// Build the view for a single calendar day
    /// Extracted to help Swift's type inference
    @ViewBuilder
    private func calendarDayView(for dayInfo: CalendarDayInfo) -> some View {
        let shiftsOnDay = dayInfo.dateISO.flatMap { shiftsByDate[$0] } ?? []
        let isToday = dayInfo.dateISO == todayISO()
        let isHighlighted = isDateHighlighted(dayInfo: dayInfo, shiftsOnDay: shiftsOnDay)

        // Show overlap indicator when superimposing and both user AND friend have shifts
        let friendHasShift = !shiftsOnDay.isEmpty
        let userHasShift = dayInfo.dateISO.flatMap { userHoursByDate?[$0] } != nil
        let showOverlap = isSuperimposing && friendHasShift && userHasShift

        CalendarDayCell(
            dayInfo: dayInfo,
            style: cellStyle(isToday: isToday, isHighlighted: isHighlighted),
            content: cellContent(for: dayInfo, hasShifts: friendHasShift),
            showOverlapIndicator: showOverlap
        )
        .onTapGesture {
            handleDayTap(dayInfo: dayInfo)
        }
    }

    /// Check if a date should be highlighted (from notification deeplink)
    private func isDateHighlighted(dayInfo: CalendarDayInfo, shiftsOnDay: [ShiftWithComputations]) -> Bool {
        // Check if any shift on this day matches a highlight shift ID (for added/updated)
        let matchesShiftId = !highlightShiftIds.isEmpty &&
            shiftsOnDay.contains(where: { highlightShiftIds.contains($0.id) })

        // Check date-based highlighting (for deleted shifts or legacy payloads)
        let matchesDate = dayInfo.dateISO.map { highlightDates.contains($0) } ?? false

        return matchesShiftId || matchesDate
    }

    /// Handle tap on a calendar day
    private func handleDayTap(dayInfo: CalendarDayInfo) {
        guard !dayInfo.isOutsideMonth, let dateISO = dayInfo.dateISO else { return }
        let shiftsForDay = shiftsByDate[dateISO] ?? []
        if let firstShift = shiftsForDay.first {
            onShiftTapped?(firstShift)
        }
    }

    // MARK: - Cell Styling

    private func cellStyle(isToday: Bool, isHighlighted: Bool) -> CalendarCellStyle {
        // Priority: highlighted > today > default
        if isHighlighted {
            return CalendarCellStyle(
                backgroundColor: Self.deepLinkHighlightColor.opacity(0.2),
                borderColor: Self.deepLinkHighlightColor,
                borderWidth: 2.5,
                dayNumberColor: .tidexTextPrimary
            )
        }
        if isToday {
            return .today()
        }
        return .default
    }

    // MARK: - Cell Content

    private func cellContent(for dayInfo: CalendarDayInfo, hasShifts: Bool) -> CalendarCellContent {
        guard let dateISO = dayInfo.dateISO else { return .empty }

        // When superimposing and user has a shift on this day
        if isSuperimposing, let userHours = userHoursByDate?[dateISO] {
            // Blue if both have shifts (overlap), green if only user has shift
            let color: Color = hasShifts ? .tidexBlue : .green
            return .hours(userHours, color: color)
        }

        // Otherwise show friend's shifts (normal behavior)
        let effectiveViewMode = showEarnings ? viewMode : .hours

        if effectiveViewMode == .money, let amount = earningsByDate[dateISO] {
            return .earnings(amount)
        } else if effectiveViewMode == .hours, let hoursData = hoursByDate[dateISO] {
            return .hours(hoursData)
        }

        return .empty
    }
}

// MARK: - Preview

#Preview {
    SharedShiftsCalendarView(
        shifts: [],
        year: 2025,
        month: 1,
        currency: "kr",
        showEarnings: true
    )
    .background(Color.tidexBackground)
}
