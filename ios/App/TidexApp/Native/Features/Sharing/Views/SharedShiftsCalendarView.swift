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

    /// Callback when a shift is tapped (for showing details)
    var onShiftTapped: ((ShiftWithComputations) -> Void)?

    @Environment(\.localization) private var localization
    @State private var viewMode: CalendarViewMode = CalendarViewMode.load()

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
            locale: Locale(identifier: localization.currentLocale.localeIdentifier)
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

    // MARK: - Calendar Grid

    private var calendarGrid: some View {
        let days = CalendarGridHelper.daysInMonth(year: year, month: month)

        return LazyVGrid(columns: CalendarGridHelper.columns, spacing: 4) {
            ForEach(days, id: \.id) { dayInfo in
                let shiftsOnDay = dayInfo.dateISO.flatMap { shiftsByDate[$0] } ?? []
                let isToday = dayInfo.dateISO == todayISO()

                CalendarDayCell(
                    dayInfo: dayInfo,
                    style: isToday ? .today() : .default,
                    content: cellContent(for: dayInfo, hasShifts: !shiftsOnDay.isEmpty)
                )
                .onTapGesture {
                    // Only handle taps on days with shifts
                    if !dayInfo.isOutsideMonth, let dateISO = dayInfo.dateISO {
                        let shiftsForDay = shiftsByDate[dateISO] ?? []
                        if let firstShift = shiftsForDay.first {
                            onShiftTapped?(firstShift)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Cell Content

    private func cellContent(for dayInfo: CalendarDayInfo, hasShifts: Bool) -> CalendarCellContent {
        guard let dateISO = dayInfo.dateISO else { return .empty }

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
    .environment(\.localization, LocalizationManager.shared)
}
