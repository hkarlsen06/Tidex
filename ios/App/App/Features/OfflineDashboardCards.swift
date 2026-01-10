import SwiftUI

// MARK: - Payroll Card

/// Card showing previous month's earnings being paid this month - matches NextPayrollCard.tsx
struct OfflinePayrollCard: View {
    let payrollDay: Int
    let payrollMonth: Date
    let netAmount: Double
    let grossAmount: Double
    let taxAmount: Double
    let hasTax: Bool
    let hasPayout: Bool
    let locale: String
    let currencySymbol: String
    let showPreviousPayroll: Bool

    // MARK: - Localized Strings

    private var nextPayrollLabel: String {
        locale == "no" ? "Neste utbetaling" : "Next payout"
    }

    private var previousPayrollLabel: String {
        locale == "no" ? "Forrige utbetaling" : "Previous payout"
    }

    private var payrollLabel: String {
        locale == "no" ? "Utbetaling" : "Payout"
    }

    private var todayLabel: String {
        locale == "no" ? "I dag" : "Today"
    }

    // MARK: - Date Formatting

    private var payrollDate: Date {
        // Calculate the actual payroll date for the month
        var components = Calendar.current.dateComponents([.year, .month], from: payrollMonth)
        components.day = min(payrollDay, daysInMonth)
        return Calendar.current.date(from: components) ?? payrollMonth
    }

    private var daysInMonth: Int {
        let range = Calendar.current.range(of: .day, in: .month, for: payrollMonth)
        return range?.count ?? 28
    }

    private var dayNumber: Int {
        Calendar.current.component(.day, from: payrollDate)
    }

    private var monthName: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: locale == "no" ? "nb_NO" : "en_US")
        formatter.dateFormat = "MMMM"
        return formatter.string(from: payrollDate).lowercased()
    }

    private var isPayrollToday: Bool {
        Calendar.current.isDateInToday(payrollDate)
    }

    private var displayLabel: String {
        // Check if the selected month is the current month
        let now = Date()
        let isCurrentMonth = Calendar.current.isDate(payrollMonth, equalTo: now, toGranularity: .month)

        if isCurrentMonth {
            return showPreviousPayroll ? previousPayrollLabel : nextPayrollLabel
        }
        return payrollLabel
    }

    // MARK: - Body

    var body: some View {
        HStack(alignment: hasTax && taxAmount > 0 ? .top : .center, spacing: 16) {
            // Left side: date and label
            VStack(alignment: .leading, spacing: 4) {
                // Date display
                if isPayrollToday {
                    HStack(spacing: 8) {
                        Text(todayLabel)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(tidexTextPrimary)
                        Image(systemName: "party.popper.fill")
                            .font(.system(size: 15))
                            .foregroundColor(tidexBlue)
                    }
                } else {
                    Text(locale == "no" ? "\(dayNumber). \(monthName)" : "\(monthName.capitalized) \(dayNumber)")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(tidexTextPrimary)
                }

                // Label with calendar icon
                HStack(spacing: 4) {
                    calendarIcon
                        .foregroundColor(tidexTextMuted)
                    Text(displayLabel)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(tidexTextPrimary)
                }
            }

            Spacer()

            // Right side: amount and breakdown
            if hasPayout {
                VStack(alignment: .trailing, spacing: 2) {
                    // Net amount
                    Text(OfflineShiftStorage.formatCurrency(netAmount, symbol: currencySymbol))
                        .font(.system(size: 22, weight: .semibold))
                        .tracking(-0.5)
                        .foregroundColor(tidexTextPrimary)

                    // Breakdown (gross - tax)
                    if hasTax && taxAmount > 0 {
                        HStack(spacing: 4) {
                            Text(OfflineShiftStorage.formatCurrency(grossAmount, symbol: currencySymbol))
                            Text("−")
                            Text(OfflineShiftStorage.formatCurrency(taxAmount, symbol: currencySymbol))
                        }
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(tidexTextMuted)
                    }
                }
            } else {
                // No payout placeholder
                VStack(alignment: .trailing, spacing: 2) {
                    Text(currencySymbol == "kr" ? "—— kr" : "\(currencySymbol)——")
                        .font(.system(size: 22, weight: .semibold))
                        .tracking(-0.5)
                        .foregroundColor(tidexTextMuted)
                    Text("——")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(tidexTextMuted)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(tidexSurfacePrimary)
        )
    }

    // MARK: - Calendar Icon

    private var calendarIcon: some View {
        Image(systemName: "calendar")
            .font(.system(size: 14, weight: .regular))
    }
}

// MARK: - Total Card

/// Card showing current month's total earnings - matches TotalCard.tsx
struct OfflineTotalCard: View {
    let total: Double
    let percentageChange: Double?
    let projectedTotal: Double?
    let grossBeforeTax: Double?
    let shiftCount: Int
    let plannedShiftsCount: Int?
    let hasTax: Bool
    let locale: String
    let currencySymbol: String

    // MARK: - Localized Strings

    private var earnedToDateLabel: String {
        locale == "no" ? "Opptjent hittil" : "Earned to date"
    }

    private var beforeTaxLabel: String {
        locale == "no" ? "før skatt" : "before tax"
    }

    private var shiftsPlannedLabel: String {
        if let count = plannedShiftsCount {
            if count == 1 {
                return locale == "no" ? "vakt planlagt" : "shift planned"
            }
            return locale == "no" ? "vakter planlagt" : "shifts planned"
        }
        return ""
    }

    private var shiftsLabel: String {
        if shiftCount == 1 {
            return locale == "no" ? "vakt" : "shift"
        }
        return locale == "no" ? "vakter" : "shifts"
    }

    // MARK: - Computed Display Values

    private var mainDisplayValue: Double {
        // Show projected total if available and different from current total
        if let projected = projectedTotal, projected != total && projected > 0 {
            return projected
        }
        return total
    }

    private var showDashes: Bool {
        return mainDisplayValue == 0
    }

    private var subtitleText: String? {
        if showDashes { return "— — —" }

        let hasFuture = projectedTotal != nil && projectedTotal != total && projectedTotal! > 0
        let hasRealEarned = hasFuture && total > 0
        let showGross = !hasFuture && grossBeforeTax != nil && grossBeforeTax! > 0 && grossBeforeTax != total
        let showPlanned = !showDashes && hasFuture && !hasRealEarned && plannedShiftsCount != nil && plannedShiftsCount! > 0
        let showCount = !showDashes && !hasRealEarned && !showGross && !showPlanned && shiftCount > 0

        if hasRealEarned {
            return "\(OfflineShiftStorage.formatCurrency(total, symbol: currencySymbol)) \(earnedToDateLabel)"
        } else if showGross {
            return "\(OfflineShiftStorage.formatCurrency(grossBeforeTax!, symbol: currencySymbol)) \(beforeTaxLabel)"
        } else if showPlanned {
            return "\(plannedShiftsCount!) \(shiftsPlannedLabel)"
        } else if showCount {
            return "\(shiftCount) \(shiftsLabel)"
        }
        return nil
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 4) {
            // Percentage change indicator (top)
            percentageIndicator

            // Main total display (large centered)
            mainAmountDisplay

            // Subtitle row
            if let subtitle = subtitleText {
                Text(subtitle)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundColor(tidexTextSecondary)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(tidexSurfacePrimary)
        )
    }

    // MARK: - Subviews

    @ViewBuilder
    private var percentageIndicator: some View {
        let hasChange = percentageChange != nil && percentageChange != 0
        let isPositive = (percentageChange ?? 0) >= 0
        let displayPercentage = abs(percentageChange ?? 0)

        HStack(spacing: 4) {
            if hasChange {
                Image(systemName: isPositive ? "arrow.up" : "arrow.down")
                    .font(.system(size: 14, weight: .semibold))
            }
            Text(String(format: "%.0f%%", displayPercentage))
                .font(.system(size: 17, weight: .semibold))
        }
        .foregroundColor(hasChange ? (isPositive ? tidexBlue : tidexTextSecondary) : tidexTextMuted)
    }

    @ViewBuilder
    private var mainAmountDisplay: some View {
        if showDashes {
            Text("— — —")
                .font(.system(size: 48, weight: .bold))
                .foregroundColor(tidexBlue)
        } else {
            Text(OfflineShiftStorage.formatCurrency(mainDisplayValue, symbol: currencySymbol))
                .font(.system(size: 48, weight: .bold))
                .foregroundColor(tidexBlue)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
    }
}

// MARK: - Featured Shift Card

/// Card showing the next upcoming shift - matches ShiftCard.tsx
struct OfflineFeaturedShiftCard: View {
    let shift: StoredShift
    let locale: String
    let hasTax: Bool
    let isToday: Bool

    // MARK: - Computed Properties

    private var hours: Double {
        OfflineShiftStorage.calculateHours(start: shift.startTime, end: shift.endTime)
    }

    private var netEarnings: Double {
        OfflineShiftStorage.calculateNetEarnings(
            gross: shift.totalGrossEstimate,
            taxRate: hasTax ? shift.taxRate : 0
        )
    }

    private var taxAmount: Double {
        hasTax ? shift.totalGrossEstimate * (shift.taxRate ?? 0) : 0
    }

    private var showBreakdown: Bool {
        hasTax && taxAmount > 0
    }

    // Format hours like "8.5 t" or "8.5 h"
    private var formattedHours: String {
        let hoursLabel = locale == "no" ? "t" : "h"
        if hours == floor(hours) {
            return String(format: "%.0f %@", hours, hoursLabel)
        }
        return String(format: "%.1f %@", hours, hoursLabel)
    }

    // MARK: - Date Formatting

    private var dateParts: (dayName: String, dayNumber: String, monthName: String) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: locale == "no" ? "nb_NO" : "en_US")

        // Parse the shift date
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: shift.shiftDate) else {
            return ("", "", "")
        }

        // Get day name (full)
        formatter.dateFormat = "EEEE"
        let dayName = formatter.string(from: date).capitalized

        // Get day number
        formatter.dateFormat = "d"
        let dayNumber = formatter.string(from: date)

        // Get month name (short)
        formatter.dateFormat = "MMM"
        let monthName = formatter.string(from: date).lowercased()

        return (dayName, dayNumber, monthName)
    }

    // MARK: - Body

    var body: some View {
        HStack(alignment: showBreakdown ? .top : .center, spacing: 16) {
            // Left side: date and time info
            VStack(alignment: .leading, spacing: 4) {
                // Day name and date
                HStack(spacing: 4) {
                    Text(dateParts.dayName)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(tidexTextPrimary)
                    Text("·")
                        .foregroundColor(tidexTextMuted)
                    Text("\(dateParts.dayNumber) \(dateParts.monthName)")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(tidexTextMuted)
                }

                // Time range and hours
                HStack(spacing: 8) {
                    // Time with clock icon
                    HStack(spacing: 4) {
                        clockIcon
                            .foregroundColor(tidexTextMuted)
                        Text("\(shift.startTime)–\(shift.endTime)")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(tidexTextPrimary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }

                    // Arrow and hours combined
                    Text("→ \(formattedHours)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(tidexTextMuted)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }

            Spacer()

            // Right side: earnings
            VStack(alignment: .trailing, spacing: 2) {
                // Net/gross amount
                Text(OfflineShiftStorage.formatCurrency(hasTax ? netEarnings : shift.totalGrossEstimate, symbol: shift.currencySymbol ?? "kr"))
                    .font(.system(size: 22, weight: .semibold))
                    .tracking(-0.5)
                    .foregroundColor(tidexTextPrimary)

                // Breakdown (gross - tax) when tax enabled
                if showBreakdown {
                    HStack(spacing: 4) {
                        Text(OfflineShiftStorage.formatCurrency(shift.totalGrossEstimate, symbol: shift.currencySymbol ?? "kr"))
                        Text("−")
                        Text(OfflineShiftStorage.formatCurrency(taxAmount, symbol: shift.currencySymbol ?? "kr"))
                    }
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(tidexTextMuted)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(tidexSurfacePrimary)
        )
        .overlay(
            // Today indicator ring
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(tidexBlue, lineWidth: isToday ? 2 : 0)
        )
    }

    // MARK: - Clock Icon

    private var clockIcon: some View {
        Image(systemName: "clock")
            .font(.system(size: 13, weight: .regular))
    }
}

// MARK: - Compact Shift Row

/// Compact shift row for the upcoming shifts list - styled to match ShiftCard.tsx
struct OfflineShiftRow: View {
    let shift: StoredShift
    let locale: String
    let hasTax: Bool

    // MARK: - Computed Properties

    private var netEarnings: Double {
        OfflineShiftStorage.calculateNetEarnings(
            gross: shift.totalGrossEstimate,
            taxRate: hasTax ? shift.taxRate : 0
        )
    }

    private var displayAmount: Double {
        hasTax ? netEarnings : shift.totalGrossEstimate
    }

    // MARK: - Date Formatting

    private var dateParts: (dayName: String, dayNumber: String, monthName: String) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: locale == "no" ? "nb_NO" : "en_US")

        // Parse the shift date
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: shift.shiftDate) else {
            return ("", "", "")
        }

        // Get day name (abbreviated)
        formatter.dateFormat = "EEE"
        let dayName = formatter.string(from: date).capitalized

        // Get day number
        formatter.dateFormat = "d"
        let dayNumber = formatter.string(from: date)

        // Get month name (short)
        formatter.dateFormat = "MMM"
        let monthName = formatter.string(from: date).lowercased()

        return (dayName, dayNumber, monthName)
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 12) {
            // Left: Date (abbreviated day name + day + month)
            Text("\(dateParts.dayName) \(dateParts.dayNumber) \(dateParts.monthName)")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(tidexTextPrimary)
                .frame(minWidth: 80, alignment: .leading)

            // Middle: Time range
            Text("\(shift.startTime)–\(shift.endTime)")
                .font(.system(size: 14, weight: .regular))
                .monospacedDigit()
                .foregroundColor(tidexTextSecondary)

            Spacer()

            // Right: Earnings
            Text(OfflineShiftStorage.formatCurrency(displayAmount, symbol: shift.currencySymbol ?? "kr"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(tidexTextPrimary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Previews

#if DEBUG
struct OfflineDashboardCards_Previews: PreviewProvider {
    static var sampleShift: StoredShift {
        StoredShift(
            shiftId: "1",
            shiftDate: "2025-01-10",
            startTime: "12:00",
            endTime: "20:30",
            hourlyWage: 180,
            supplementRatePerHour: 20,
            totalGrossEstimate: 1700,
            locale: "no",
            currencySymbol: "kr",
            taxRate: 0.22
        )
    }

    static var previews: some View {
        ZStack {
            tidexDarkBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    OfflinePayrollCard(
                        payrollDay: 15,
                        payrollMonth: Date(),
                        netAmount: 12500,
                        grossAmount: 15800,
                        taxAmount: 3300,
                        hasTax: true,
                        hasPayout: true,
                        locale: "no",
                        currencySymbol: "kr",
                        showPreviousPayroll: false
                    )

                    OfflineTotalCard(
                        total: 12500,
                        percentageChange: 15,
                        projectedTotal: 16851,
                        grossBeforeTax: nil,
                        shiftCount: 8,
                        plannedShiftsCount: 3,
                        hasTax: true,
                        locale: "no",
                        currencySymbol: "kr"
                    )

                    OfflineFeaturedShiftCard(
                        shift: sampleShift,
                        locale: "no",
                        hasTax: true,
                        isToday: false
                    )

                    // Shift row in list
                    VStack(spacing: 0) {
                        OfflineShiftRow(
                            shift: sampleShift,
                            locale: "no",
                            hasTax: true
                        )
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 24)
                            .fill(tidexSurfacePrimary)
                    )
                }
                .padding(.horizontal, 24)
            }
        }
        .previewDisplayName("Norwegian - With Tax")

        ZStack {
            tidexDarkBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    OfflinePayrollCard(
                        payrollDay: 25,
                        payrollMonth: Date(),
                        netAmount: 0,
                        grossAmount: 0,
                        taxAmount: 0,
                        hasTax: false,
                        hasPayout: false,
                        locale: "en",
                        currencySymbol: "kr",
                        showPreviousPayroll: false
                    )

                    OfflineTotalCard(
                        total: 0,
                        percentageChange: 0,
                        projectedTotal: nil,
                        grossBeforeTax: nil,
                        shiftCount: 0,
                        plannedShiftsCount: nil,
                        hasTax: false,
                        locale: "en",
                        currencySymbol: "kr"
                    )

                    OfflineFeaturedShiftCard(
                        shift: sampleShift,
                        locale: "en",
                        hasTax: false,
                        isToday: true
                    )
                }
                .padding(.horizontal, 24)
            }
        }
        .previewDisplayName("English - Today Shift")
    }
}
#endif
