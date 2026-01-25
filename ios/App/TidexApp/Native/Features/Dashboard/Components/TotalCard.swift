import SwiftUI

/// Card displaying current month's total earnings
/// Design matches OfflineTotalCard from the Capacitor app
///
/// When there are future/planned shifts:
/// - Main display shows projected total (all shifts)
/// - Subtitle shows "earned to date" (completed shifts only)
struct TotalCard: View {
    let gross: Double                  // Projected total (all shifts)
    let net: Double?                   // Projected net (all shifts)
    let completedGross: Double         // Earned to date (completed shifts)
    let completedNet: Double?          // Earned net (completed shifts)
    let shiftCount: Int                // Total shift count
    let plannedCount: Int              // Future/planned shift count
    let percentageChange: Double?
    let taxEnabled: Bool
    /// When true, shows skeleton state with shimmer animation (for loading)
    var isLoading: Bool = false

    @Environment(\.localization) private var localization
    @Environment(\.userCurrency) private var currency

    // MARK: - Computed Properties

    /// Main display value (projected total)
    private var mainDisplayValue: Double {
        taxEnabled ? (net ?? gross) : gross
    }

    /// Earned to date value (completed shifts only)
    private var earnedToDateValue: Double {
        taxEnabled ? (completedNet ?? completedGross) : completedGross
    }

    /// Whether there are future shifts (show projected vs earned)
    private var hasFutureShifts: Bool {
        plannedCount > 0 && mainDisplayValue != earnedToDateValue
    }

    private var showDashes: Bool {
        isLoading || mainDisplayValue == 0
    }

    private var hasChange: Bool {
        percentageChange != nil && percentageChange != 0
    }

    private var isPositive: Bool {
        (percentageChange ?? 0) >= 0
    }

    private var displayPercentage: Double {
        abs(percentageChange ?? 0)
    }

    /// Whether to show a dash instead of percentage (nil or zero means no meaningful comparison)
    private var showPercentageDash: Bool {
        percentageChange == nil || percentageChange == 0
    }

    // MARK: - Subtitle Text

    /// Subtitle logic matches Next.js TotalCard exactly:
    /// 1. If showing dashes (loading/zero) → no subtitle (skeleton shown instead)
    /// 2. If has future shifts AND has real earned amount → show "[earned] hittil/to date"
    /// 3. If no future with real earnings, but tax enabled with different gross → show "[gross] før skatt/before tax"
    /// 4. If has future shifts but no real earnings yet → show "[count] vakter planlagt/shifts planned"
    /// 5. Otherwise if has any shifts → show "[count] vakter/shifts"
    private var subtitleText: String? {
        // Don't return text when showing placeholder - we'll show a skeleton line instead
        if showDashes { return nil }

        // Check if we have real earnings to date (not zero)
        let hasRealEarned = hasFutureShifts && earnedToDateValue > 0

        // When there are future shifts AND real earnings, show "earned to date" amount
        if hasRealEarned {
            return "\(formatCurrency(earnedToDateValue)) \(localization.string("dashboard.earnedToDate"))"
        }

        // Show gross before tax when tax is enabled (only when NOT showing earned to date)
        let hasGross = !hasFutureShifts && taxEnabled && gross > 0 && gross != mainDisplayValue
        if hasGross {
            return "\(formatCurrency(gross)) \(localization.string("dashboard.beforeTax"))"
        }

        // When there are future/planned shifts but no real earnings yet, show planned count
        let showPlanned = hasFutureShifts && !hasRealEarned && plannedCount > 0
        if showPlanned {
            let plannedLabel = plannedCount == 1
                ? localization.string("dashboard.shiftPlanned")
                : localization.string("dashboard.shiftsPlanned")
            return "\(plannedCount) \(plannedLabel)"
        }

        // Show total shift count as fallback
        if shiftCount > 0 {
            let shiftsLabel = shiftCount == 1
                ? localization.string("dashboard.shift")
                : localization.string("dashboard.shifts")
            return "\(shiftCount) \(shiftsLabel)"
        }

        return nil
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 4) {
            // Percentage change indicator (top)
            percentageIndicator

            // Main total display (large centered) - fixed height for consistency
            mainAmountDisplay
                .frame(height: 88) // Match the 88pt font line height

            // Subtitle row - fixed height for consistent card size
            Group {
                if showDashes {
                    // Skeleton placeholder line
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.tidexTextMuted.opacity(0.3))
                        .frame(width: 120, height: 16)
                } else if let subtitle = subtitleText {
                    Text(subtitle)
                        .font(.system(size: 18, weight: .regular))
                        .foregroundColor(.tidexTextSecondary)
                } else {
                    // Empty spacer to maintain height
                    Color.clear
                }
            }
            .frame(height: 24) // Fixed height for subtitle area
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.tidexSurfacePrimary)
        )
        .shimmer(isActive: isLoading)
    }

    // MARK: - Subviews

    @ViewBuilder
    private var percentageIndicator: some View {
        HStack(spacing: 4) {
            if hasChange {
                Image(systemName: isPositive ? "arrow.up" : "arrow.down")
                    .font(.system(size: 16, weight: .semibold))
            }
            if showPercentageDash {
                Text("—")
                    .font(.system(size: 18, weight: .semibold))
            } else {
                Text(String(format: "%.0f%%", displayPercentage))
                    .font(.system(size: 18, weight: .semibold))
            }
        }
        .foregroundColor(hasChange ? (isPositive ? .tidexBlue : .tidexTextSecondary) : .tidexTextMuted)
    }

    @ViewBuilder
    private var mainAmountDisplay: some View {
        if showDashes {
            // Skeleton placeholder line matching the height of the large text
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.tidexBlue.opacity(0.3))
                .frame(width: 200, height: 56)
        } else {
            Text(formatCurrency(mainDisplayValue))
                .font(.system(size: 88, weight: .bold))
                .foregroundColor(.tidexBlue)
                .minimumScaleFactor(0.4)
                .lineLimit(1)
        }
    }

    // MARK: - Formatting

    private func formatCurrency(_ amount: Double) -> String {
        CurrencyConfig.format(amount, currency: currency)
    }
}

#Preview {
    VStack(spacing: 12) {
        // Case 1: Has future shifts AND real earned amount → "7 500 kr hittil"
        TotalCard(
            gross: 15000,
            net: 12500,
            completedGross: 9000,
            completedNet: 7500,
            shiftCount: 8,
            plannedCount: 3,
            percentageChange: 15,
            taxEnabled: true
        )

        // Case 2: No future shifts, tax enabled → "12 000 kr før skatt"
        TotalCard(
            gross: 12000,
            net: 10000,
            completedGross: 12000,
            completedNet: 10000,
            shiftCount: 5,
            plannedCount: 0,
            percentageChange: -8,
            taxEnabled: true
        )

        // Case 3: No future shifts, no tax → "5 vakter"
        TotalCard(
            gross: 12000,
            net: nil,
            completedGross: 12000,
            completedNet: nil,
            shiftCount: 5,
            plannedCount: 0,
            percentageChange: -8,
            taxEnabled: false
        )

        // Case 4: Has future/planned shifts but NO real earnings yet → "3 vakter planlagt"
        TotalCard(
            gross: 5000,
            net: nil,
            completedGross: 0,
            completedNet: nil,
            shiftCount: 3,
            plannedCount: 3,
            percentageChange: nil,
            taxEnabled: false
        )

        // Case 5: Zero earnings (shows dashes with skeleton subtitle)
        TotalCard(
            gross: 0,
            net: nil,
            completedGross: 0,
            completedNet: nil,
            shiftCount: 0,
            plannedCount: 0,
            percentageChange: nil,
            taxEnabled: false
        )
    }
    .padding(.horizontal, 24)
    .background(Color.tidexBackground)
    .environment(\.localization, LocalizationManager.shared)
}
