import SwiftUI

/// Native offline dashboard displayed when network is unavailable.
/// Mirrors the web app's home screen with Payroll, Total, and Shift cards.
struct OfflineScreenView: View {
    let locale: String
    let onRetry: () -> Void

    @State private var dashboardData: OfflineDashboardData?
    @State private var showShiftsList = false
    @State private var allShifts: [StoredShift] = []

    // MARK: - Localized Strings

    private var offlineTitle: String {
        locale == "no" ? "Ingen tilkobling" : "No Connection"
    }

    private var offlineSubtitle: String {
        locale == "no"
            ? "Kobler til automatisk når online"
            : "Will reconnect when online"
    }

    private var retryButtonTitle: String {
        locale == "no" ? "Prøv igjen" : "Try Again"
    }

    private var noDataMessage: String {
        locale == "no"
            ? "Ingen data tilgjengelig"
            : "No data available"
    }

    /// Simple button label
    private var shiftsButtonLabel: String {
        locale == "no" ? "Se innlastede vakter" : "See loaded shifts"
    }

    /// Generate header for modal like "December's, January's and February's shifts"
    private var shiftsModalHeader: String {
        let months = getUniqueMonthNames(from: allShifts)
        guard !months.isEmpty else {
            return locale == "no" ? "Alle vakter" : "All shifts"
        }

        if months.count == 1 {
            let suffix = locale == "no" ? "s vakter" : "'s shifts"
            return "\(months[0])\(suffix)"
        } else if months.count == 2 {
            let andWord = locale == "no" ? " og " : " and "
            let suffix = locale == "no" ? "s vakter" : "'s shifts"
            return "\(months[0])\(andWord)\(months[1])\(suffix)"
        } else {
            // 3+ months: "December's, January's and February's shifts"
            let andWord = locale == "no" ? " og " : " and "
            let suffix = locale == "no" ? "s vakter" : "'s shifts"
            let allButLast = months.dropLast().map { "\($0)" }.joined(separator: ", ")
            let last = months.last!
            return "\(allButLast)\(andWord)\(last)\(suffix)"
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Dark background
            tidexDarkBackground
                .ignoresSafeArea()

            // Main content
            VStack(spacing: 0) {
                // Header with logo and offline indicator
                headerSection
                    .padding(.top, 16)

                // Centered dashboard content
                if let data = dashboardData, data.hasData {
                    // Status message centered between header and cards
                    Spacer()
                    statusSection
                    Spacer()

                    // Dashboard cards
                    dashboardCards(data)
                        .padding(.horizontal, 24)
                } else {
                    Spacer()
                    // Status message centered in empty state
                    statusSection
                        .padding(.bottom, 16)
                    // Empty state
                    emptyStateView
                }

                Spacer()

                // View shifts button (if we have shifts)
                if !allShifts.isEmpty {
                    viewShiftsButton
                        .padding(.horizontal, 24)
                        .padding(.bottom, 12)
                }

                // Fixed retry button at bottom
                retryButton
                    .padding(.horizontal, 24)
                    .padding(.bottom, 50)
            }
        }
        .onAppear {
            loadDashboardData()
        }
        .sheet(isPresented: $showShiftsList) {
            ShiftsListSheet(
                shifts: allShifts,
                locale: locale,
                hasTax: dashboardData?.hasTaxEnabled ?? false,
                headerTitle: shiftsModalHeader
            )
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack {
            // Logo and app name
            HStack(spacing: 8) {
                TidexLogoShape()
                    .fill(
                        LinearGradient(
                            colors: logoGradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 28, height: 28)

                Text("Tidex")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(tidexTextPrimary)
            }

            Spacer()

            // Offline indicator
            Image(systemName: "wifi.slash")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(tidexBlue)
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Status Section

    private var statusSection: some View {
        VStack(spacing: 4) {
            Text(offlineTitle)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(tidexTextPrimary)

            Text(offlineSubtitle)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(tidexTextMuted)
        }
    }

    // MARK: - Dashboard Cards

    @ViewBuilder
    private func dashboardCards(_ data: OfflineDashboardData) -> some View {
        VStack(spacing: 12) {
            // Payroll Card (previous month earnings)
            OfflinePayrollCard(
                payrollDay: data.payrollDay,
                payrollMonth: data.payrollMonth,
                netAmount: data.previousMonthNet,
                grossAmount: data.previousMonthGross,
                taxAmount: data.previousMonthTax,
                hasTax: data.hasTaxEnabled,
                hasPayout: data.hasPayout,
                locale: locale,
                currencySymbol: data.currencySymbol,
                showPreviousPayroll: data.showPreviousPayroll
            )

            // Total Card (current month)
            OfflineTotalCard(
                total: data.hasTaxEnabled ? data.currentMonthNet : data.currentMonthGross,
                percentageChange: data.percentageChange,
                projectedTotal: data.projectedTotal,
                grossBeforeTax: data.hasTaxEnabled ? data.currentMonthGross : nil,
                shiftCount: data.currentMonthShiftCount,
                plannedShiftsCount: data.plannedShiftsCount,
                hasTax: data.hasTaxEnabled,
                locale: locale,
                currencySymbol: data.currencySymbol
            )

            // Next Shift Card (featured)
            if let nextShift = data.nextShift {
                OfflineFeaturedShiftCard(
                    shift: nextShift,
                    locale: locale,
                    hasTax: data.hasTaxEnabled,
                    isToday: data.nextShiftIsToday
                )
            }
        }
    }

    // MARK: - View Shifts Button

    @ViewBuilder
    private var viewShiftsButton: some View {
        if #available(iOS 26.0, *) {
            Button(action: { showShiftsList = true }) {
                Label(shiftsButtonLabel, systemImage: "calendar")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
            }
            .glassEffect()
        } else {
            Button(action: { showShiftsList = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(tidexBlue)

                    Text(shiftsButtonLabel)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(tidexTextPrimary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(tidexTextMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(tidexSurfacePrimary)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(tidexTextMuted.opacity(0.2), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(tidexTextMuted.opacity(0.5))

            Text(noDataMessage)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(tidexTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Retry Button

    @ViewBuilder
    private var retryButton: some View {
        if #available(iOS 26.0, *) {
            Button(action: onRetry) {
                Label(retryButtonTitle, systemImage: "arrow.clockwise")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .contentShape(Rectangle())
            }
            .glassEffect(.regular.tint(tidexBlue).interactive())
        } else {
            Button(action: onRetry) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16, weight: .semibold))

                    Text(retryButtonTitle)
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(tidexBlue)
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Data Loading

    private func loadDashboardData() {
        allShifts = OfflineShiftStorage.loadShifts()
        dashboardData = OfflineShiftStorage.calculateDashboardData()
    }

    // MARK: - Helpers

    private func getUniqueMonthNames(from shifts: [StoredShift]) -> [String] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: locale == "no" ? "nb_NO" : "en_US")

        let monthFormatter = DateFormatter()
        monthFormatter.locale = Locale(identifier: locale == "no" ? "nb_NO" : "en_US")
        monthFormatter.dateFormat = "MMMM"

        var seenMonths: Set<String> = []
        var orderedMonths: [String] = []

        // Sort shifts by date first
        let sortedShifts = shifts.sorted { a, b in
            guard let dateA = formatter.date(from: a.shiftDate),
                  let dateB = formatter.date(from: b.shiftDate)
            else { return false }
            return dateA < dateB
        }

        for shift in sortedShifts {
            guard let date = formatter.date(from: shift.shiftDate) else { continue }
            let monthKey = monthFormatter.string(from: date)
            let capitalizedMonth = monthKey.capitalized

            if !seenMonths.contains(capitalizedMonth) {
                seenMonths.insert(capitalizedMonth)
                orderedMonths.append(capitalizedMonth)
            }
        }

        return orderedMonths
    }
}

// MARK: - Shifts List Sheet

struct ShiftsListSheet: View {
    let shifts: [StoredShift]
    let locale: String
    let hasTax: Bool
    let headerTitle: String

    @Environment(\.dismiss) private var dismiss

    private var closeLabel: String {
        locale == "no" ? "Lukk" : "Close"
    }

    /// Group shifts by month
    private var groupedShifts: [(month: String, shifts: [StoredShift])] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        let monthFormatter = DateFormatter()
        monthFormatter.locale = Locale(identifier: locale == "no" ? "nb_NO" : "en_US")
        monthFormatter.dateFormat = "MMMM yyyy"

        var groups: [String: [StoredShift]] = [:]
        var monthOrder: [String] = []

        // Sort shifts by date
        let sortedShifts = shifts.sorted { a, b in
            guard let dateA = formatter.date(from: a.shiftDate),
                  let dateB = formatter.date(from: b.shiftDate)
            else { return false }
            return dateA < dateB
        }

        for shift in sortedShifts {
            guard let date = formatter.date(from: shift.shiftDate) else { continue }
            let monthKey = monthFormatter.string(from: date).capitalized

            if groups[monthKey] == nil {
                groups[monthKey] = []
                monthOrder.append(monthKey)
            }
            groups[monthKey]?.append(shift)
        }

        return monthOrder.map { (month: $0, shifts: groups[$0] ?? []) }
    }

    var body: some View {
        NavigationView {
            ZStack {
                tidexDarkBackground
                    .ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: 24) {
                        ForEach(groupedShifts, id: \.month) { group in
                            VStack(alignment: .leading, spacing: 8) {
                                // Month header
                                Text(group.month)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(tidexTextMuted)
                                    .textCase(.uppercase)
                                    .tracking(1)

                                // Shifts in this month
                                VStack(spacing: 0) {
                                    ForEach(Array(group.shifts.enumerated()), id: \.element.shiftId) { index, shift in
                                        OfflineShiftRow(shift: shift, locale: locale, hasTax: hasTax)

                                        if index < group.shifts.count - 1 {
                                            Divider()
                                                .background(tidexTextMuted.opacity(0.2))
                                        }
                                    }
                                }
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(tidexSurfacePrimary)
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle(headerTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(closeLabel) {
                        dismiss()
                    }
                    .foregroundColor(tidexBlue)
                }
            }
            .toolbarBackground(tidexDarkBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Preview

#if DEBUG
struct OfflineScreenView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            OfflineScreenView(locale: "no", onRetry: {})
                .previewDisplayName("Norwegian")

            OfflineScreenView(locale: "en", onRetry: {})
                .previewDisplayName("English")
        }
    }
}
#endif
