import SwiftUI

/// Read-only calendar view for shared shifts
/// Shows shift times or earnings per day, similar to the main Shifts calendar
struct SharedShiftsCalendarView: View {
    let shifts: [ShiftWithComputations]
    let year: Int
    let month: Int  // 1-12
    let currency: String
    let showEarnings: Bool

    @Environment(\.localization) private var localization
    @State private var viewMode: CalendarViewMode = .hours

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

    /// Monthly totals (net and gross)
    private var monthlyTotals: (net: Double, gross: Double) {
        let gross = shifts.reduce(0) { $0 + $1.grossPay }
        let net = shifts.reduce(0) {
            $0 + ($1.taxEnabled ? $1.netPay : $1.grossPay)
        }
        return (net: net, gross: gross)
    }

    /// Month name
    private var monthName: String {
        let formatter = DateFormatter()
        let isNorwegian = localization.currentLocale == .norwegian
        formatter.locale = Locale(identifier: isNorwegian ? "nb_NO" : "en_US")
        formatter.dateFormat = "LLLL"

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1

        if let date = calendar.date(from: components) {
            return formatter.string(from: date).capitalized
        }
        return ""
    }

    /// Days in the month
    private var daysInMonth: Int {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1

        guard let date = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: date) else {
            return 30
        }
        return range.count
    }

    /// First weekday of month (0 = Sunday, 1 = Monday, etc.)
    private var firstWeekday: Int {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1

        guard let date = calendar.date(from: components) else { return 0 }

        let weekday = calendar.component(.weekday, from: date)
        // Convert to Monday-based (0 = Monday, 6 = Sunday)
        return (weekday + 5) % 7
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header with totals
            headerRow
                .padding(.bottom, 12)

            // Weekday headers
            weekdayHeaderRow
                .padding(.bottom, 8)

            // Calendar grid
            calendarGrid
                .padding(.bottom, 12)

            // View mode toggle
            if showEarnings {
                viewModeToggle
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

            // Total earnings (if showing earnings)
            if showEarnings {
                Text(CurrencyConfig.format(monthlyTotals.net, currency: currency))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.tidexTextPrimary)
            }
        }
    }

    // MARK: - Weekday Headers

    private var weekdayHeaderRow: some View {
        HStack(spacing: 4) {
            ForEach(weekdayNames, id: \.self) { name in
                Text(name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.tidexTextMuted)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var weekdayNames: [String] {
        let formatter = DateFormatter()
        let isNorwegian = localization.currentLocale == .norwegian
        formatter.locale = Locale(identifier: isNorwegian ? "nb_NO" : "en_US")
        let symbols = formatter.shortWeekdaySymbols!
        // Reorder to start with Monday
        return Array(symbols[1...]) + [symbols[0]]
    }

    // MARK: - Calendar Grid

    private var calendarGrid: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            // Empty cells for days before first of month
            ForEach(0..<firstWeekday, id: \.self) { _ in
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
            }

            // Day cells
            ForEach(1...daysInMonth, id: \.self) { day in
                dayCell(day: day)
            }
        }
    }

    private func dayCell(day: Int) -> some View {
        let dateISO = String(format: "%04d-%02d-%02d", year, month, day)
        let earnings = earningsByDate[dateISO]
        let hoursData = hoursByDate[dateISO]
        let hasShift = earnings != nil || hoursData != nil
        let isToday = dateISO == todayISO()

        return ZStack {
            // Background
            RoundedRectangle(cornerRadius: 10)
                .fill(hasShift ? Color.tidexSurfacePrimary : Color.clear)

            // Content
            VStack(spacing: 2) {
                // Day number
                Text("\(day)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isToday ? .tidexBlue : .tidexTextPrimary)

                // Shift data
                if hasShift {
                    if viewMode == .money && showEarnings, let amount = earnings {
                        Text(formatCompactCurrency(amount))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.tidexTextSecondary)
                            .lineLimit(1)
                    } else if let hours = hoursData {
                        VStack(spacing: 0) {
                            Text(hours.start)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.tidexTextSecondary)
                            Text(hours.end)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.tidexTextMuted)
                        }
                    }
                }
            }
            .padding(4)

            // Today indicator
            if isToday {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.tidexBlue, lineWidth: 2)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: - View Mode Toggle

    private var viewModeToggle: some View {
        HStack {
            Spacer()

            Picker("", selection: $viewMode) {
                Image(systemName: "clock")
                    .tag(CalendarViewMode.hours)
                Image(systemName: "banknote")
                    .tag(CalendarViewMode.money)
            }
            .pickerStyle(.segmented)
            .frame(width: 100)

            Spacer()
        }
        .padding(.top, 8)
    }

    // MARK: - Helpers

    private func formatTime(_ time: String) -> String {
        String(time.prefix(5))
    }

    private func timeToMinutes(_ time: String) -> Int {
        let components = time.split(separator: ":").compactMap { Int($0) }
        guard components.count >= 2 else { return 0 }
        return components[0] * 60 + components[1]
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
