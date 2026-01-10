import Foundation

// MARK: - Dashboard Data Model

/// Aggregated data for the offline dashboard view
struct OfflineDashboardData {
    // Payroll Card (previous month earnings being paid this month)
    let payrollDay: Int
    let payrollMonth: Date
    let previousMonthNet: Double
    let previousMonthGross: Double
    let previousMonthTax: Double
    let showPreviousPayroll: Bool
    let hasPayout: Bool

    // Total Card (current month)
    let currentMonthNet: Double
    let currentMonthGross: Double
    let currentMonthShiftCount: Int
    let percentageChange: Double?
    let projectedTotal: Double?
    let plannedShiftsCount: Int?

    // Next Shift + Upcoming List
    let nextShift: StoredShift?
    let upcomingShifts: [StoredShift]  // Excludes nextShift
    let nextShiftIsToday: Bool

    // Metadata
    let currencySymbol: String
    let locale: String
    let currentMonthName: String
    let hasTaxEnabled: Bool
    let hasData: Bool
}

// MARK: - Offline Shift Storage

/// Utility for reading cached shifts from App Group storage.
/// Used by the offline screen to display shifts when network is unavailable.
enum OfflineShiftStorage {
    private static let appGroupId = "group.no.tidex.app"
    private static let shiftsKey = "upcoming_shifts"

    /// Load cached shifts from App Group storage.
    /// Returns empty array if no shifts are cached or parsing fails.
    static func loadShifts() -> [StoredShift] {
        guard let userDefaults = UserDefaults(suiteName: appGroupId),
              let shiftsJson = userDefaults.string(forKey: shiftsKey),
              let data = shiftsJson.data(using: .utf8)
        else {
            print("[OfflineShiftStorage] No cached shifts found")
            return []
        }

        do {
            let shifts = try JSONDecoder().decode([StoredShift].self, from: data)
            print("[OfflineShiftStorage] Loaded \(shifts.count) cached shifts")
            return shifts
        } catch {
            print("[OfflineShiftStorage] Failed to decode shifts: \(error)")
            return []
        }
    }

    /// Get upcoming shifts (today and future), sorted by date
    static func getUpcomingShifts() -> [StoredShift] {
        let allShifts = loadShifts()
        let today = Calendar.current.startOfDay(for: Date())
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        return allShifts
            .filter { shift in
                guard let shiftDate = formatter.date(from: shift.shiftDate) else { return false }
                return shiftDate >= today
            }
            .sorted { a, b in
                guard let dateA = formatter.date(from: a.shiftDate),
                      let dateB = formatter.date(from: b.shiftDate)
                else { return false }
                return dateA < dateB
            }
    }

    /// Format a shift date string for display
    /// - Parameters:
    ///   - dateString: Date in YYYY-MM-DD format
    ///   - locale: "no" for Norwegian, "en" for English
    /// - Returns: Formatted date string (e.g., "I dag", "Tomorrow", "Mon 12.")
    static func formatShiftDate(_ dateString: String, locale: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let shiftDate = formatter.date(from: dateString) else { return dateString }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let shiftDay = calendar.startOfDay(for: shiftDate)

        // Today
        if calendar.isDate(shiftDay, inSameDayAs: today) {
            return locale == "no" ? "I dag" : "Today"
        }

        // Tomorrow
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
           calendar.isDate(shiftDay, inSameDayAs: tomorrow)
        {
            return locale == "no" ? "I morgen" : "Tomorrow"
        }

        // Weekday + day: "Man 12." or "Mon 12."
        let weekdayFormatter = DateFormatter()
        weekdayFormatter.locale = Locale(identifier: locale == "no" ? "nb_NO" : "en_US")
        weekdayFormatter.dateFormat = "EEE d."
        return weekdayFormatter.string(from: shiftDate).capitalized
    }

    /// Format currency value for display
    /// - Parameters:
    ///   - value: Amount to format
    ///   - symbol: Currency symbol (e.g., "kr", "$")
    /// - Returns: Formatted string (e.g., "1 234 kr")
    static func formatCurrency(_ value: Double, symbol: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        formatter.groupingSeparator = " "

        let formatted = formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
        return "\(formatted) \(symbol)"
    }

    /// Calculate net earnings from gross and tax rate
    static func calculateNetEarnings(gross: Double, taxRate: Double?) -> Double {
        let rate = taxRate ?? 0.0
        return gross * (1 - rate)
    }

    /// Get the detected locale from cached shifts, or default to "no"
    static func getLocale() -> String {
        let shifts = loadShifts()
        return shifts.first?.locale ?? "no"
    }

    // MARK: - Dashboard Calculations

    /// Calculate all dashboard data from cached shifts
    static func calculateDashboardData() -> OfflineDashboardData {
        let allShifts = loadShifts()
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)

        // Get current and previous month components
        let currentYear = calendar.component(.year, from: now)
        let currentMonth = calendar.component(.month, from: now)

        var prevMonthComponents = DateComponents()
        prevMonthComponents.year = currentYear
        prevMonthComponents.month = currentMonth - 1
        if prevMonthComponents.month! < 1 {
            prevMonthComponents.month = 12
            prevMonthComponents.year = currentYear - 1
        }

        // Get shifts for each month
        let previousMonthShifts = getShiftsForMonth(
            year: prevMonthComponents.year!,
            month: prevMonthComponents.month!,
            from: allShifts
        )
        let currentMonthShifts = getShiftsForMonth(
            year: currentYear,
            month: currentMonth,
            from: allShifts
        )

        // Get upcoming shifts (today onwards)
        let upcomingAll = getUpcomingShifts()
        let nextShift = upcomingAll.first
        let remainingUpcoming = upcomingAll.count > 1 ? Array(upcomingAll.dropFirst()) : []

        // Check if next shift is today
        let nextShiftIsToday: Bool = {
            guard let next = nextShift else { return false }
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            guard let shiftDate = formatter.date(from: next.shiftDate) else { return false }
            return calendar.isDate(shiftDate, inSameDayAs: today)
        }()

        // Calculate totals
        let prevGross = sumEarnings(previousMonthShifts, net: false)
        let prevNet = sumEarnings(previousMonthShifts, net: true)
        let prevTax = prevGross - prevNet

        let currentGross = sumEarnings(currentMonthShifts, net: false)
        let currentNet = sumEarnings(currentMonthShifts, net: true)

        // Check if any shift has tax enabled
        let hasTax = allShifts.contains { ($0.taxRate ?? 0) > 0 }

        // Get metadata from first shift, or use defaults
        let locale = allShifts.first?.locale ?? "no"
        let currencySymbol = allShifts.first?.currencySymbol ?? "kr"
        let monthName = getMonthName(month: currentMonth, locale: locale)

        // Calculate payroll day (default to 15 if not stored - we could add this to StoredShift later)
        let payrollDay = 15

        // Check if payroll has passed this month
        var payrollDateComponents = calendar.dateComponents([.year, .month], from: now)
        payrollDateComponents.day = min(payrollDay, calendar.range(of: .day, in: .month, for: now)?.count ?? 28)
        let payrollDate = calendar.date(from: payrollDateComponents) ?? now
        let showPreviousPayroll = today > payrollDate

        // Calculate planned shifts (upcoming shifts this month)
        let plannedShiftsCount = upcomingAll.filter { shift in
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            guard let shiftDate = formatter.date(from: shift.shiftDate) else { return false }
            let shiftYear = calendar.component(.year, from: shiftDate)
            let shiftMonth = calendar.component(.month, from: shiftDate)
            return shiftYear == currentYear && shiftMonth == currentMonth
        }.count

        // Projected total = earned + upcoming in current month
        let displayTotal = hasTax ? currentNet : currentGross
        let projectedTotal: Double? = plannedShiftsCount > 0 ? displayTotal : nil

        // Calculate percentage change: compare current month to previous month
        // Use the same metric (net if tax enabled, gross otherwise)
        let currentDisplay = hasTax ? currentNet : currentGross
        let previousDisplay = hasTax ? prevNet : prevGross
        let percentageChange: Double? = {
            guard previousDisplay > 0 else { return nil }
            let change = ((currentDisplay - previousDisplay) / previousDisplay) * 100
            return change
        }()

        return OfflineDashboardData(
            payrollDay: payrollDay,
            payrollMonth: now,
            previousMonthNet: prevNet,
            previousMonthGross: prevGross,
            previousMonthTax: prevTax,
            showPreviousPayroll: showPreviousPayroll,
            hasPayout: prevGross > 0,
            currentMonthNet: currentNet,
            currentMonthGross: currentGross,
            currentMonthShiftCount: currentMonthShifts.count,
            percentageChange: percentageChange,
            projectedTotal: projectedTotal,
            plannedShiftsCount: plannedShiftsCount > 0 ? plannedShiftsCount : nil,
            nextShift: nextShift,
            upcomingShifts: remainingUpcoming,
            nextShiftIsToday: nextShiftIsToday,
            currencySymbol: currencySymbol,
            locale: locale,
            currentMonthName: monthName,
            hasTaxEnabled: hasTax,
            hasData: !allShifts.isEmpty
        )
    }

    /// Get shifts for a specific month
    static func getShiftsForMonth(year: Int, month: Int, from shifts: [StoredShift]) -> [StoredShift] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let calendar = Calendar.current

        return shifts.filter { shift in
            guard let shiftDate = formatter.date(from: shift.shiftDate) else { return false }
            let shiftYear = calendar.component(.year, from: shiftDate)
            let shiftMonth = calendar.component(.month, from: shiftDate)
            return shiftYear == year && shiftMonth == month
        }
    }

    /// Sum earnings for a list of shifts
    /// - Parameter net: If true, calculates net (after tax), otherwise gross
    static func sumEarnings(_ shifts: [StoredShift], net: Bool) -> Double {
        shifts.reduce(0) { total, shift in
            if net {
                return total + calculateNetEarnings(gross: shift.totalGrossEstimate, taxRate: shift.taxRate)
            } else {
                return total + shift.totalGrossEstimate
            }
        }
    }

    /// Get localized month name
    static func getMonthName(month: Int, locale: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: locale == "no" ? "nb_NO" : "en_US")

        // Create a date in the target month
        var components = DateComponents()
        components.year = 2024
        components.month = month
        components.day = 1
        guard let date = Calendar.current.date(from: components) else {
            return ""
        }

        formatter.dateFormat = "MMMM"
        return formatter.string(from: date).lowercased()
    }

    /// Calculate hours from time strings (HH:mm format), handling cross-midnight
    static func calculateHours(start: String, end: String) -> Double {
        let startParts = start.split(separator: ":").compactMap { Int($0) }
        let endParts = end.split(separator: ":").compactMap { Int($0) }

        guard startParts.count == 2, endParts.count == 2 else { return 0 }

        let startMinutes = startParts[0] * 60 + startParts[1]
        var endMinutes = endParts[0] * 60 + endParts[1]

        // Handle cross-midnight shifts
        if endMinutes <= startMinutes {
            endMinutes += 24 * 60
        }

        let totalMinutes = endMinutes - startMinutes
        return Double(totalMinutes) / 60.0
    }
}
