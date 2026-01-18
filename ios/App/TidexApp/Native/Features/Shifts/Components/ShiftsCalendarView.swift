import SwiftUI

// MARK: - Calendar View Mode

/// Mode for displaying data in calendar cells
enum CalendarViewMode: String, CaseIterable {
    case hours
    case money

    /// UserDefaults key for persisting view mode
    static let userDefaultsKey = "shifts_calendar_view_mode"

    /// Save the current mode to UserDefaults
    func save() {
        UserDefaults.standard.set(rawValue, forKey: Self.userDefaultsKey)
    }

    /// Load saved mode from UserDefaults (defaults to hours)
    static func load() -> CalendarViewMode {
        guard let rawValue = UserDefaults.standard.string(forKey: userDefaultsKey),
              let mode = CalendarViewMode(rawValue: rawValue) else {
            return .hours
        }
        return mode
    }
}

// MARK: - Hours Data for Calendar Cell

/// Time range data for a single day
struct HoursData: Equatable {
    let start: String
    let end: String
    let crossesMidnight: Bool
}

// MARK: - Shifts Calendar View

/// Full-featured calendar for the Shifts tab
/// Shows shift times or earnings per day, ISO week numbers, and monthly totals
struct ShiftsCalendarView: View {
    let shifts: [ShiftWithComputations]
    let month: Date
    let year: Int
    let monthNumber: Int  // 1-12
    let currency: String
    let showEarnings: Bool
    var onDayTapped: ((String, [ShiftWithComputations]) -> Void)?

    @Environment(\.localization) private var localization
    @State private var viewMode: CalendarViewMode = CalendarViewMode.load()

    // Haptic feedback for interactions
    private let selectionHaptic = UISelectionFeedbackGenerator()
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
            // Sort by start time
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
        let filteredShifts = shifts.filter { shift in
            guard let date = Date.fromISODateString(shift.shiftDate) else { return false }
            let components = calendar.dateComponents([.year, .month], from: date)
            return components.year == year && components.month == monthNumber
        }

        let gross = filteredShifts.reduce(0) { $0 + $1.grossPay }
        let net = filteredShifts.reduce(0) {
            $0 + ($1.taxEnabled ? $1.netPay : $1.grossPay)
        }
        return (net: net, gross: gross)
    }

    /// Whether tax is enabled for any shift
    private var hasTaxEnabled: Bool {
        shifts.contains { $0.taxEnabled }
    }

    /// Shifts grouped by ISO date string
    private var shiftsByDate: [String: [ShiftWithComputations]] {
        var result: [String: [ShiftWithComputations]] = [:]
        for shift in shifts {
            result[shift.shiftDate, default: []].append(shift)
        }
        return result
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

            // View mode toggle
            viewModeToggle
        }
    }

    // MARK: - Header Row

    private var headerRow: some View {
        HStack {
            // Month name + Year (year in muted color)
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
                VStack(alignment: .trailing, spacing: 2) {
                    // Primary: net (or gross if no tax)
                    let displayAmount = hasTaxEnabled ? monthlyTotals.net : monthlyTotals.gross
                    Text(monthlyTotals.gross == 0 ? "—" : formatCurrency(displayAmount))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.tidexTextPrimary)

                    // Secondary: gross (only if tax enabled)
                    if hasTaxEnabled && monthlyTotals.gross > 0 {
                        Text(formatCurrency(monthlyTotals.gross))
                            .font(.system(size: 13))
                            .foregroundColor(.tidexTextMuted)
                    }
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 12)
    }

    // MARK: - Month Name

    private var monthName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        formatter.locale = Locale(identifier: localization.currentLocale.localeIdentifier)
        return formatter.string(from: month).capitalized
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

    private var calendarGrid: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(daysInMonth(), id: \.id) { dayInfo in
                let shiftsOnDay = dayInfo.dateISO.flatMap { shiftsByDate[$0] } ?? []

                ShiftsCalendarDayCell(
                    dayInfo: dayInfo,
                    viewMode: showEarnings ? viewMode : .hours,
                    earnings: dayInfo.dateISO.flatMap { earningsByDate[$0] },
                    hours: dayInfo.dateISO.flatMap { hoursByDate[$0] },
                    isToday: dayInfo.dateISO == todayISO(),
                    hasShifts: !shiftsOnDay.isEmpty
                )
                .onTapGesture {
                    guard let dateISO = dayInfo.dateISO,
                          !dayInfo.isOutsideMonth,
                          !shiftsOnDay.isEmpty,
                          onDayTapped != nil else { return }

                    selectionHaptic.selectionChanged()
                    onDayTapped?(dateISO, shiftsOnDay)
                }
            }
        }
        .onAppear {
            selectionHaptic.prepare()
        }
    }

    // MARK: - View Mode Toggle

    private var viewModeToggle: some View {
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
                .background(
                    Group {
                        if viewMode == .hours {
                            if #available(iOS 26.0, *) {
                                // Liquid glass pill on iOS 26+
                                Capsule()
                                    .fill(.clear)
                                    .glassEffect(.regular.interactive())
                            } else {
                                // Fallback for older iOS
                                Capsule()
                                    .fill(Color.tidexSurfacePrimary)
                                    .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                            }
                        }
                    }
                )
            }
            .buttonStyle(.plain)

            // Money button (only if showing earnings)
            if showEarnings {
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
                        .background(
                            Group {
                                if viewMode == .money {
                                    if #available(iOS 26.0, *) {
                                        // Liquid glass pill on iOS 26+
                                        Capsule()
                                            .fill(.clear)
                                            .glassEffect(.regular.interactive())
                                    } else {
                                        // Fallback for older iOS
                                        Capsule()
                                            .fill(Color.tidexSurfacePrimary)
                                            .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                                    }
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            Capsule()
                .fill(Color.tidexSurfaceSecondary)
        )
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
        components.month = monthNumber
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

// MARK: - Shifts Calendar Day Cell

private struct ShiftsCalendarDayCell: View {
    let dayInfo: ShiftsCalendarView.DayInfo
    let viewMode: CalendarViewMode
    let earnings: Double?
    let hours: HoursData?
    let isToday: Bool
    let hasShifts: Bool

    private var hasShift: Bool {
        earnings != nil || hours != nil
    }

    /// Whether this cell is tappable (has shifts and is in current month)
    private var isTappable: Bool {
        hasShifts && !dayInfo.isOutsideMonth
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
                .fill(Color.tidexSurfacePrimary)
        )
        .overlay(
            // Today indicator ring
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.tidexBlue, lineWidth: isToday ? 2 : 0)
        )
        .opacity(dayInfo.isOutsideMonth ? 0.4 : 1.0)
    }

    private var dayNumberColor: Color {
        if hasShift {
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
        ShiftsCalendarView(
            shifts: [],
            month: Date(),
            year: 2025,
            monthNumber: 1,
            currency: "kr",
            showEarnings: true
        )
        .padding()
    }
    .background(Color.tidexBackground)
    .environment(\.localization, LocalizationManager.shared)
}
