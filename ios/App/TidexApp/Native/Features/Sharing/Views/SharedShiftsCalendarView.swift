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

    // Haptic feedback
    private let toggleHaptic = UIImpactFeedbackGenerator(style: .light)

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

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
        var shiftsByDate: [String: [ShiftWithComputations]] = [:]
        for shift in shifts {
            shiftsByDate[shift.shiftDate, default: []].append(shift)
        }

        var result: [String: HoursData] = [:]
        for (date, shiftsOnDate) in shiftsByDate {
            let sorted = shiftsOnDate.sorted { $0.startTime < $1.startTime }
            let earliestStart = sorted.first?.startTime ?? ""
            let latestEnd = sorted.map(\.endTime).max() ?? ""

            // Check if any shift crosses midnight
            let crossesMidnight = shiftsOnDate.contains { shift in
                let startMinutes = timeToMinutes(shift.startTime)
                let endMinutes = timeToMinutes(shift.endTime)
                return endMinutes <= startMinutes
            }

            result[date] = HoursData(
                start: formatTime(earliestStart),
                end: formatTime(latestEnd),
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
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        formatter.locale = Locale(identifier: localization.currentLocale.localeIdentifier)

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1

        if let date = calendar.date(from: components) {
            return formatter.string(from: date).capitalized
        }
        return ""
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header: Month name + Year and Total
            headerRow

            // Weekday headers
            weekdayHeaderRow
                .padding(.bottom, 8)

            // Calendar grid
            calendarGrid
                .padding(.bottom, 12)

            // View mode toggle (hours/money)
            if showEarnings {
                actionBar
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
            Text(displayTotals.gross == 0 ? "—" : formatCurrency(displayAmount))
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.tidexTextPrimary)

            if showTax && displayTotals.gross > 0 {
                Text(formatCurrency(displayTotals.gross))
                    .font(.system(size: 13))
                    .foregroundColor(.tidexTextMuted)
            }
        }
    }

    // MARK: - Weekday Headers

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

    private var calendarGrid: some View {
        let days = daysInMonth()

        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(days, id: \.id) { dayInfo in
                let shiftsOnDay = dayInfo.dateISO.flatMap { shiftsByDate[$0] } ?? []

                SharedCalendarDayCell(
                    dayInfo: dayInfo,
                    viewMode: showEarnings ? viewMode : .hours,
                    earnings: dayInfo.dateISO.flatMap { earningsByDate[$0] },
                    hours: dayInfo.dateISO.flatMap { hoursByDate[$0] },
                    isToday: dayInfo.dateISO == todayISO(),
                    hasShifts: !shiftsOnDay.isEmpty
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

    // MARK: - Action Bar (View Mode Toggle)

    private var actionBar: some View {
        HStack(spacing: 0) {
            // Hours button
            Button {
                guard viewMode != .hours else { return }
                toggleHaptic.impactOccurred()
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    viewMode = .hours
                    viewMode.save()
                }
            } label: {
                HStack(spacing: 6) {
                    Text("--:--")
                    Image(systemName: "clock")
                        .font(.system(size: 14, weight: .medium))
                }
                .font(.system(size: 14, weight: viewMode == .hours ? .semibold : .regular))
                .foregroundColor(viewMode == .hours ? .tidexTextPrimary : .tidexTextMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
                .background(
                    Group {
                        if viewMode == .hours {
                            Capsule()
                                .fill(.clear)
                                .glassEffect(.regular.interactive())
                        }
                    }
                )
            }
            .buttonStyle(.plain)

            // Money button
            Button {
                guard viewMode != .money else { return }
                toggleHaptic.impactOccurred()
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    viewMode = .money
                    viewMode.save()
                }
            } label: {
                Text("---- \(currency)")
                    .font(.system(size: 14, weight: viewMode == .money ? .semibold : .regular))
                    .foregroundColor(viewMode == .money ? .tidexTextPrimary : .tidexTextMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                    .background(
                        Group {
                            if viewMode == .money {
                                Capsule()
                                    .fill(.clear)
                                    .glassEffect(.regular.interactive())
                            }
                        }
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(4)
        .background(Capsule().fill(Color.tidexSurfaceSecondary))
        .onAppear {
            toggleHaptic.prepare()
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

        // Get first day of month
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
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

    // MARK: - Formatting

    private func formatCurrency(_ amount: Double) -> String {
        CurrencyConfig.format(amount, currency: currency)
    }

    private func formatTime(_ time: String) -> String {
        // Remove seconds and leading zero (e.g., "08:30:00" -> "8:30")
        let hhmm = String(time.prefix(5))
        return hhmm.hasPrefix("0") ? String(hhmm.dropFirst()) : hhmm
    }

    private func timeToMinutes(_ time: String) -> Int {
        let parts = time.split(separator: ":")
        guard parts.count >= 2,
              let hours = Int(parts[0]),
              let minutes = Int(parts[1]) else { return 0 }
        return hours * 60 + minutes
    }
}

// MARK: - Shared Calendar Day Cell

/// Individual day cell for the shared shifts calendar
/// Matches the visual style of ShiftsCalendarDayCell
private struct SharedCalendarDayCell: View {
    let dayInfo: SharedShiftsCalendarView.DayInfo
    let viewMode: CalendarViewMode
    let earnings: Double?
    let hours: HoursData?
    let isToday: Bool
    let hasShifts: Bool

    private var hasShift: Bool {
        earnings != nil || hours != nil
    }

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

            // Content (centered - hours or earnings)
            if viewMode == .money, let amount = earnings {
                Text(formatCompactCurrency(amount))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.tidexTextPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.top, 8)
            } else if viewMode == .hours, let hoursData = hours {
                VStack(spacing: 1) {
                    Text(hoursData.start)
                        .font(.system(size: 14, weight: .bold))
                    Text(hoursData.end + (hoursData.crossesMidnight ? "*" : ""))
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundColor(.tidexTextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1 / 1.3, contentMode: .fill)
        .clipped()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColor)
        )
        .opacity(dayInfo.isOutsideMonth ? 0.4 : 1.0)
    }

    private var backgroundColor: Color {
        if isToday {
            return Color.tidexBlue.opacity(0.2)
        }
        return Color.tidexSurfacePrimary
    }

    private var dayNumberColor: Color {
        if isToday {
            return .tidexBlue
        }
        if hasShift {
            return .white
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
