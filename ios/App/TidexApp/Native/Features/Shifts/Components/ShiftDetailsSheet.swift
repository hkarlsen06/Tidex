import SwiftUI

/// Sheet view displaying detailed information about a shift
/// Shows date, time, hours, earnings breakdown, and actions
struct ShiftDetailsSheet: View {
    let shift: ShiftWithComputations
    let onDelete: (() -> Void)?

    @Environment(\.localization) private var localization
    @Environment(\.userCurrency) private var currency
    @Environment(\.dismiss) private var dismiss

    // MARK: - Computed Properties

    private var isVirtualShift: Bool {
        shift.isVirtual
    }

    private var formattedDate: String {
        guard let date = Date.fromISODateString(shift.shiftDate) else {
            return shift.shiftDate
        }

        let formatter = DateFormatter()
        let isNorwegian = localization.currentLocale == .norwegian
        formatter.locale = Locale(identifier: isNorwegian ? "nb_NO" : "en_US")
        formatter.dateFormat = "EEEE, d. MMMM yyyy"
        return formatter.string(from: date).capitalized
    }

    private var formattedTimeRange: String {
        "\(formatTime(shift.startTime)) – \(formatTime(shift.endTime))"
    }

    private var formattedHours: String {
        let hoursLabel = localization.currentLocale == .norwegian ? "timer" : "hours"
        if shift.paidHours == floor(shift.paidHours) {
            return String(format: "%.0f %@", shift.paidHours, hoursLabel)
        }
        return String(format: "%.1f %@", shift.paidHours, hoursLabel)
    }

    private var showTaxBreakdown: Bool {
        shift.taxEnabled && shift.taxAmount > 0
    }

    /// Whether this shift has supplement pay to show breakdown
    private var hasSupplementBreakdown: Bool {
        shift.computed.supplementPay > 0 && !supplementSegments.isEmpty
    }

    /// Check if shift has custom supplements
    private var hasCustomSupplements: Bool {
        if let custom = shift.shift.custom_supplements,
           !custom.rules.isEmpty {
            return true
        }
        return false
    }

    /// Base wage rate per hour (for showing in supplement rows)
    private var baseWageRate: Double {
        guard shift.computed.paidHours > 0 else { return 0 }
        return shift.computed.basePay / shift.computed.paidHours
    }

    /// Supplement segments grouped by rate for display
    /// Groups consecutive wage periods with the same supplement rate
    private var supplementSegments: [SupplementSegment] {
        let original = shift.computed.originalWagePeriods
        let adjusted = shift.computed.wagePeriods

        var segments: [SupplementSegment] = []
        var i = 0

        while i < original.count {
            let period = original[i]
            // Skip periods with no supplement
            guard period.supplementRate > 0 else {
                i += 1
                continue
            }

            // Find consecutive periods with same supplement rate
            let groupStart = period.fromMin
            var groupEnd = period.toMin
            let currentRate = period.supplementRate
            var j = i + 1

            while j < original.count && original[j].supplementRate == currentRate {
                groupEnd = original[j].toMin
                j += 1
            }

            // Calculate actual paid hours for this supplement rate group from adjusted periods
            var actualHours: Double = 0
            for adj in adjusted where adj.supplementRate == currentRate {
                let overlapStart = max(adj.fromMin, groupStart)
                let overlapEnd = min(adj.toMin, groupEnd)
                if overlapEnd > overlapStart {
                    actualHours += (overlapEnd - overlapStart) / 60.0
                }
            }

            if actualHours > 0 {
                segments.append(SupplementSegment(
                    fromMin: groupStart,
                    toMin: groupEnd,
                    rate: currentRate,
                    actualHours: actualHours
                ))
            }

            i = j
        }

        return segments
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header with date
                    headerSection

                    // Time and hours
                    timeSection

                    // Earnings breakdown
                    earningsSection

                    // Virtual shift indicator
                    if isVirtualShift {
                        virtualShiftBanner
                    }

                    // Delete button (for all shifts - virtual shifts get excluded)
                    if let onDelete = onDelete {
                        deleteButton(onDelete: onDelete, isVirtual: isVirtualShift)
                    }
                }
                .padding(20)
            }
            .background(Color.tidexBackground)
            .navigationTitle(localization.string("shifts.detailsTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(localization.string("common.done")) {
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.tidexBlue)
                }
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(spacing: 8) {
            // Large date display
            Text(formattedDate)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.tidexTextPrimary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var timeSection: some View {
        VStack(spacing: 16) {
            // Section header
            HStack {
                Image(systemName: "clock")
                    .foregroundColor(.tidexBlue)
                Text(localization.string("shifts.timeSection"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.tidexTextSecondary)
                Spacer()
            }

            // Time details card
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(localization.string("shifts.timeRange"))
                        .font(.system(size: 13))
                        .foregroundColor(.tidexTextMuted)
                    Text(formattedTimeRange)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(.tidexTextPrimary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(localization.string("shifts.duration"))
                        .font(.system(size: 13))
                        .foregroundColor(.tidexTextMuted)
                    Text(formattedHours)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(.tidexTextPrimary)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.tidexSurfacePrimary)
            )
        }
    }

    private var earningsSection: some View {
        VStack(spacing: 16) {
            // Section header
            HStack {
                Image(systemName: "creditcard")
                    .foregroundColor(.tidexBlue)
                Text(localization.string("shifts.earningsSection"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.tidexTextSecondary)
                Spacer()
            }

            // Earnings card
            VStack(spacing: 12) {
                // Base Pay (only show when there are supplements)
                if hasSupplementBreakdown {
                    earningsRow(
                        label: localization.string("shifts.basePay"),
                        value: formatCurrency(shift.computed.basePay)
                    )

                    Divider()
                }

                // Supplement breakdown section
                if hasSupplementBreakdown {
                    supplementBreakdownSection
                }

                // Gross
                earningsRow(
                    label: localization.string("shifts.grossPay"),
                    value: formatCurrency(shift.grossPay),
                    isHighlighted: !showTaxBreakdown && !hasSupplementBreakdown
                )

                if showTaxBreakdown {
                    Divider()

                    // Tax deduction
                    earningsRow(
                        label: localization.string("shifts.taxDeduction"),
                        value: "−\(formatCurrency(shift.taxAmount))",
                        valueColor: .tidexError
                    )

                    Divider()

                    // Net (highlighted)
                    earningsRow(
                        label: localization.string("shifts.netPay"),
                        value: formatCurrency(shift.netPay),
                        isHighlighted: true
                    )
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.tidexSurfacePrimary)
            )
        }
    }

    /// Supplement breakdown showing each time period with supplements
    @ViewBuilder
    private var supplementBreakdownSection: some View {
        VStack(spacing: 12) {
            // Total supplement header with optional "Customized" badge
            HStack {
                HStack(spacing: 8) {
                    Text(localization.string("shifts.totalSupplement"))
                        .font(.system(size: 15))
                        .foregroundColor(.tidexTextSecondary)

                    if hasCustomSupplements {
                        Text(localization.string("shifts.customized"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.tidexBlue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(Color.tidexBlue.opacity(0.15))
                            )
                    }
                }

                Spacer()

                Text(formatCurrency(shift.computed.supplementPay))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.tidexTextPrimary)
            }

            // Individual supplement segments
            ForEach(supplementSegments) { segment in
                supplementSegmentRow(segment)
            }

            Divider()
        }
    }

    /// A single supplement segment row showing time range, hours × rate, and amount
    @ViewBuilder
    private func supplementSegmentRow(_ segment: SupplementSegment) -> some View {
        VStack(spacing: 6) {
            // Time range and hours × rate
            HStack {
                Text(segment.timeRange)
                    .font(.system(size: 14))
                    .foregroundColor(.tidexTextPrimary)

                Spacer()

                Text("\(formatHoursValue(segment.actualHours)) × \(formatCurrency(segment.rate))")
                    .font(.system(size: 14))
                    .foregroundColor(.tidexTextSecondary)
            }

            // Supplement label and amount
            HStack {
                Text(localization.string("shifts.supplementLabel"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.tidexTextPrimary)

                Spacer()

                Text(formatCurrency(segment.amount))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.tidexTextPrimary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.tidexSurfaceSecondary.opacity(0.4))
        )
    }

    /// Format hours value (e.g., "2.5 t" or "2 t")
    private func formatHoursValue(_ hours: Double) -> String {
        if hours == floor(hours) {
            return String(format: "%.0f t", hours)
        }
        return String(format: "%.1f t", hours)
    }

    @ViewBuilder
    private func earningsRow(
        label: String,
        value: String,
        isHighlighted: Bool = false,
        valueColor: Color = .tidexTextPrimary
    ) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 15, weight: isHighlighted ? .medium : .regular))
                .foregroundColor(isHighlighted ? .tidexTextPrimary : .tidexTextSecondary)

            Spacer()

            Text(value)
                .font(.system(size: isHighlighted ? 20 : 15, weight: isHighlighted ? .semibold : .medium))
                .foregroundColor(valueColor)
        }
    }

    private var virtualShiftBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "repeat")
                .font(.system(size: 16))
                .foregroundColor(.tidexBlue)

            VStack(alignment: .leading, spacing: 2) {
                Text(localization.string("shifts.recurringShift"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.tidexTextPrimary)
                Text(localization.string("shifts.recurringShiftDescription"))
                    .font(.system(size: 13))
                    .foregroundColor(.tidexTextSecondary)
            }

            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.tidexBlue.opacity(0.1))
        )
    }

    @ViewBuilder
    private func deleteButton(onDelete: @escaping () -> Void, isVirtual: Bool) -> some View {
        Button(action: onDelete) {
            HStack(spacing: 8) {
                Image(systemName: isVirtual ? "minus.circle" : "trash")
                    .font(.system(size: 15, weight: .medium))
                Text(isVirtual
                    ? localization.string("shifts.excludeButton")
                    : localization.string("shifts.deleteButton"))
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.tidexError)
            .cornerRadius(12)
        }
        .padding(.top, 8)
    }

    // MARK: - Formatting

    private func formatTime(_ time: String) -> String {
        String(time.prefix(5))
    }

    private func formatCurrency(_ amount: Double) -> String {
        CurrencyConfig.format(amount, currency: currency)
    }
}

// MARK: - Supplement Segment

/// A grouped supplement segment for display
struct SupplementSegment: Identifiable {
    let fromMin: Double
    let toMin: Double
    let rate: Double
    let actualHours: Double

    var id: String { "\(fromMin)-\(toMin)-\(rate)" }

    /// Format minutes to display time (e.g., "21:00")
    func formatTime(_ minutes: Double) -> String {
        let dayOffset = Int(minutes / 1440)
        let remainder = Int(minutes) % 1440
        let normalizedMinutes = remainder < 0 ? remainder + 1440 : remainder
        let isFullDay = normalizedMinutes == 0 && Int(minutes) != 0
        let hours = isFullDay ? 24 : normalizedMinutes / 60
        let mins = isFullDay ? 0 : normalizedMinutes % 60
        let base = String(format: "%02d:%02d", hours, mins)
        if dayOffset > 0 {
            return "\(base) (+\(dayOffset))"
        } else if dayOffset < 0 {
            return "\(base) (\(dayOffset))"
        }
        return base
    }

    /// Formatted time range string
    var timeRange: String {
        let from = formatTime(fromMin)
        let to = formatTime(toMin)
        // Replace 23:59 with 24:00 for cleaner display
        let toDisplay = to == "23:59" ? "24:00" : to
        return "\(from) – \(toDisplay)"
    }

    /// Total supplement amount for this segment
    var amount: Double {
        actualHours * rate
    }
}

// MARK: - Preview

#Preview("With Supplements") {
    // Evening shift with supplements (17:00-23:00)
    // Supplement applies from 21:00-24:00 at 45 kr/hour
    let eveningSupplementPeriods = [
        // 17:00-21:00: 4 hours base only (1020 min to 1260 min)
        WagePeriod(fromMin: 1020, toMin: 1260, baseRate: 200, supplementRate: 0),
        // 21:00-23:00: 2 hours with supplement (1260 min to 1380 min)
        WagePeriod(fromMin: 1260, toMin: 1380, baseRate: 200, supplementRate: 45)
    ]

    return ShiftDetailsSheet(
        shift: ShiftWithComputations(
            shift: ShiftRow(
                id: "preview-1",
                user_id: "user-1",
                shift_date: "2025-01-17",
                start_time: "17:00",
                end_time: "23:00",
                custom_supplements: nil
            ),
            computed: ShiftComputed(
                id: "preview-1",
                durationHours: 6.0,
                paidHours: 5.5,
                basePay: 1100, // 5.5h × 200 kr
                supplementPay: 90, // 2h × 45 kr
                gross: 1190,
                wagePeriods: eveningSupplementPeriods,
                originalWagePeriods: eveningSupplementPeriods,
                breakAudit: BreakAudit(method: .proportional, thresholdHours: 5.0, deductedHours: 0.5, notes: [])
            ),
            taxEnabled: true,
            taxPercentage: 30
        ),
        onDelete: { print("Delete tapped") }
    )
}

#Preview("No Supplements") {
    ShiftDetailsSheet(
        shift: ShiftWithComputations(
            shift: ShiftRow(
                id: "preview-2",
                user_id: "user-1",
                shift_date: "2025-01-17",
                start_time: "08:00",
                end_time: "16:00",
                custom_supplements: nil
            ),
            computed: ShiftComputed(
                id: "preview-2",
                durationHours: 8.0,
                paidHours: 7.5,
                basePay: 1500,
                supplementPay: 0,
                gross: 1500,
                wagePeriods: [
                    WagePeriod(fromMin: 480, toMin: 960, baseRate: 200, supplementRate: 0)
                ],
                originalWagePeriods: [
                    WagePeriod(fromMin: 480, toMin: 960, baseRate: 200, supplementRate: 0)
                ],
                breakAudit: BreakAudit(method: .proportional, thresholdHours: 5.0, deductedHours: 0.5, notes: [])
            ),
            taxEnabled: false,
            taxPercentage: 0
        ),
        onDelete: { print("Delete tapped") }
    )
}
