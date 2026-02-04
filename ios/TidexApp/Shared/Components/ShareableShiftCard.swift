import SwiftUI

/// A shareable view that mirrors the ShiftDetailsSheet content
/// Renders the shift details exactly as shown in the modal for sharing as a PNG
struct ShareableShiftCard: View {
    let shift: ShiftWithComputations
    let currency: String
    let includeEarnings: Bool
    @Environment(\.layoutDirection) private var layoutDirection

    // MARK: - Computed Properties

    private var formattedDate: String {
        guard let date = Date.fromISODateString(shift.shiftDate) else {
            return shift.shiftDate
        }
        let formatter = DateFormatter()
        formatter.locale = Locale.appLocale
        formatter.dateFormat = "EEEE, d. MMMM yyyy"
        return formatter.string(from: date).capitalized
    }

    private var formattedTimeRange: String {
        ShiftCardFormatter.localizedTimeRange(
            start: shift.startTime,
            end: shift.endTime,
            locale: Locale.appLocale,
            isRTL: layoutDirection == .rightToLeft,
            separator: " – "
        )
    }

    private var formattedHours: String {
        let hoursLabel = String(localized: .commonHours)
        let formatter = FormatterCache.numberFormatter(includeDecimals: true, locale: Locale.appLocale)
        let hoursValue = formatter.string(from: NSNumber(value: shift.paidHours)) ?? String(format: "%.2f", shift.paidHours)
        return "\(hoursValue) \(hoursLabel)"
    }

    private var showTaxBreakdown: Bool {
        shift.taxEnabled && shift.taxAmount > 0
    }

    private var hasSupplementBreakdown: Bool {
        shift.computed.supplementPay > 0 && !supplementSegments.isEmpty
    }

    private var hasCustomSupplements: Bool {
        if let custom = shift.shift.custom_supplements,
           !custom.rules.isEmpty {
            return true
        }
        return false
    }

    private var baseWageRate: Double {
        guard shift.computed.paidHours > 0 else { return 0 }
        return shift.computed.basePay / shift.computed.paidHours
    }

    /// Supplement segments grouped by rate for display (same logic as ShiftDetailsSheet)
    private var supplementSegments: [ShareableSupplementSegment] {
        let original = shift.computed.originalWagePeriods
        let adjusted = shift.computed.wagePeriods

        var segments: [ShareableSupplementSegment] = []
        var i = 0

        while i < original.count {
            let period = original[i]
            guard period.supplementRate > 0 else {
                i += 1
                continue
            }

            let groupStart = period.fromMin
            var groupEnd = period.toMin
            let currentRate = period.supplementRate
            var j = i + 1

            while j < original.count && original[j].supplementRate == currentRate {
                groupEnd = original[j].toMin
                j += 1
            }

            var actualHours: Double = 0
            for adj in adjusted where adj.supplementRate == currentRate {
                let overlapStart = max(adj.fromMin, groupStart)
                let overlapEnd = min(adj.toMin, groupEnd)
                if overlapEnd > overlapStart {
                    actualHours += (overlapEnd - overlapStart) / 60.0
                }
            }

            if actualHours > 0 {
                segments.append(ShareableSupplementSegment(
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
        VStack(spacing: 24) {
            // Header with date
            headerSection

            // Time section
            timeSection

            // Earnings section (only if included)
            if includeEarnings {
                earningsSection
            }

            // Tidex branding centered
            HStack(spacing: 4) {
                LogoWatermark(opacity: 1.0)
                    .frame(width: 14, height: 14)
                Text("Tidex")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.tidexTextMuted)
            }
        }
        .padding(20)
        .frame(width: 360) // Fixed width for consistent sharing
        .background(Color.tidexBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 8) {
            Text(formattedDate)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.tidexTextPrimary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Time Section

    private var timeSection: some View {
        VStack(spacing: 16) {
            // Section header
            HStack {
                Image(systemName: "clock")
                    .foregroundColor(.tidexBlue)
                Text(.shiftsTimeSection)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.tidexTextSecondary)
                Spacer()
            }

            // Time details card
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(.shiftsTimeRange)
                        .font(.system(size: 13))
                        .foregroundColor(.tidexTextMuted)
                    Text(formattedTimeRange)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(.tidexTextPrimary)
                        .environment(\.layoutDirection, .leftToRight)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(.shiftsDuration)
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

    // MARK: - Earnings Section

    private var earningsSection: some View {
        VStack(spacing: 16) {
            // Section header
            HStack {
                Image(systemName: "creditcard")
                    .foregroundColor(.tidexBlue)
                Text(.shiftsEarningsSection)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.tidexTextSecondary)
                Spacer()
            }

            // Earnings card
            VStack(spacing: 12) {
                // Base Pay (only show when there are supplements)
                if hasSupplementBreakdown {
                    earningsRow(
                        label: String(localized: .shiftsBasePay),
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
                    label: String(localized: .shiftsGrossPay),
                    value: formatCurrency(shift.grossPay),
                    isHighlighted: !showTaxBreakdown && !hasSupplementBreakdown
                )

                if showTaxBreakdown {
                    Divider()

                    // Tax deduction
                    earningsRow(
                        label: String(localized: .shiftsTaxDeduction),
                        value: "−\(formatCurrency(shift.taxAmount))",
                        valueColor: .tidexError
                    )

                    Divider()

                    // Net (highlighted)
                    earningsRow(
                        label: String(localized: .shiftsNetPay),
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

    // MARK: - Supplement Breakdown

    @ViewBuilder
    private var supplementBreakdownSection: some View {
        VStack(spacing: 12) {
            // Total supplement header with optional "Customized" badge
            HStack {
                HStack(spacing: 8) {
                    Text(.shiftsTotalSupplement)
                        .font(.system(size: 15))
                        .foregroundColor(.tidexTextSecondary)

                    if hasCustomSupplements {
                        Text(.shiftsCustomized)
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

    @ViewBuilder
    private func supplementSegmentRow(_ segment: ShareableSupplementSegment) -> some View {
        VStack(spacing: 6) {
            // Time range and hours × rate
            HStack {
                Text(segmentTimeRange(segment))
                    .font(.system(size: 14))
                    .foregroundColor(.tidexTextPrimary)
                    .environment(\.layoutDirection, .leftToRight)

                Spacer()

                Text("\(formatHoursValue(segment.actualHours)) × \(formatCurrency(segment.rate))")
                    .font(.system(size: 14))
                    .foregroundColor(.tidexTextSecondary)
            }

            // Supplement label and amount
            HStack {
                Text(.shiftsSupplementLabel)
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

    // MARK: - Helper Views

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

    // MARK: - Formatting

    private func formatCurrency(_ amount: Double) -> String {
        CurrencyConfig.format(amount, currency: currency)
    }

    private func formatHoursValue(_ hours: Double) -> String {
        return String(format: "%.2f t", hours)
    }

    private func segmentTimeRange(_ segment: ShareableSupplementSegment) -> String {
        let range = segment.timeRange
        guard layoutDirection == .rightToLeft else { return range }
        let parts = range.components(separatedBy: " – ")
        if parts.count == 2 {
            return "\(parts[1]) – \(parts[0])"
        }
        return range
    }
}

// MARK: - Supplement Segment (for shareable view)

private struct ShareableSupplementSegment: Identifiable {
    let fromMin: Double
    let toMin: Double
    let rate: Double
    let actualHours: Double

    var id: String { "\(fromMin)-\(toMin)-\(rate)" }

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

    var timeRange: String {
        let from = formatTime(fromMin)
        let to = formatTime(toMin)
        let toDisplay = to == "23:59" ? "24:00" : to
        return "\(from) – \(toDisplay)"
    }

    var amount: Double {
        actualHours * rate
    }
}

// MARK: - Image Rendering Extension

extension ShareableShiftCard {
    /// Renders the view as a PNG image
    @MainActor
    func renderAsImage() -> UIImage? {
        let renderer = ImageRenderer(content: self)
        renderer.scale = 3.0 // High resolution for sharing
        return renderer.uiImage
    }
}
