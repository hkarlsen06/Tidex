import SwiftUI

/// Card displaying current month's total earnings
/// Design matches OfflineTotalCard from the Capacitor app
///
/// When there are future/planned shifts:
/// - Main display shows projected total (all shifts)
/// - Subtitle shows "earned to date" (completed shifts only)
struct TotalCard: View {
  let gross: Double  // Projected total (all shifts)
  let net: Double?  // Projected net (all shifts)
  let completedGross: Double  // Earned to date (completed shifts)
  let completedNet: Double?  // Earned net (completed shifts)
  let shiftCount: Int  // Total shift count
  let plannedCount: Int  // Future/planned shift count
  let percentageChange: Double?
  let taxEnabled: Bool
  /// When true, shows skeleton state with shimmer animation (for loading)
  var isLoading: Bool = false

  @Environment(\.userCurrency) private var currency

  /// Tracks whether the launch count-up animation has already played this session.
  /// Static so it persists across view recreations but resets on app restart.
  private static var hasPlayedLaunchAnimation = false

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

  private var formattedPercentage: String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .percent
    formatter.locale = Locale.appLocale
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 0
    let value = displayPercentage / 100
    return formatter.string(from: NSNumber(value: value)) ?? "\(Int(displayPercentage))%"
  }

  /// Whether to show a dash instead of percentage (nil or zero means no meaningful comparison)
  private var showPercentageDash: Bool {
    percentageChange == nil || percentageChange == 0
  }

  // MARK: - Subtitle Text

  /// Subtitle type for determining which content to show
  private enum SubtitleType {
    case earnedToDate(Double)
    case beforeTax(Double)
    case plannedCount(Int)
    case shiftCount(Int)
    case none
  }

  /// Determine which subtitle to show
  /// Logic matches Next.js TotalCard exactly:
  /// 1. If showing dashes (loading/zero) → no subtitle (skeleton shown instead)
  /// 2. If has future shifts AND has real earned amount → show "[earned] hittil/to date"
  /// 3. If no future with real earnings, but tax enabled with different gross → show "[gross] før skatt/before tax"
  /// 4. If has future shifts but no real earnings yet → show "[count] vakter planlagt/shifts planned"
  /// 5. Otherwise if has any shifts → show "[count] vakter/shifts"
  private var subtitleType: SubtitleType {
    // Don't show subtitle when showing placeholder - skeleton shown instead
    if showDashes { return .none }

    // Check if we have real earnings to date (not zero)
    let hasRealEarned = hasFutureShifts && earnedToDateValue > 0

    // When there are future shifts AND real earnings, show "earned to date" amount
    if hasRealEarned {
      return .earnedToDate(earnedToDateValue)
    }

    // Show gross before tax when tax is enabled (only when NOT showing earned to date)
    let hasGross = !hasFutureShifts && taxEnabled && gross > 0 && gross != mainDisplayValue
    if hasGross {
      return .beforeTax(gross)
    }

    // When there are future/planned shifts but no real earnings yet, show planned count
    let showPlanned = hasFutureShifts && !hasRealEarned && plannedCount > 0
    if showPlanned {
      return .plannedCount(plannedCount)
    }

    // Show total shift count as fallback
    if shiftCount > 0 {
      return .shiftCount(shiftCount)
    }

    return .none
  }

  // MARK: - Body

  var body: some View {
    VStack(spacing: 4) {
      // Percentage change indicator (top) - fixed height for consistent card size
      percentageIndicator
        .frame(height: 22)  // Match the 18pt font line height

      // Main total display (large centered) - fixed height for consistency
      mainAmountDisplay
        .frame(height: 88)  // Match the 88pt font line height

      // Subtitle row - fixed height for consistent card size
      subtitleContent
        .frame(height: 24)  // Fixed height for subtitle area
    }
    .frame(maxWidth: .infinity)
    .padding(.horizontal, 24)
    .padding(.top, 20)
    .padding(.bottom, 16)
    .background(
      RoundedRectangle(cornerRadius: 24)
        .fill(Color.tidexSurfacePrimary)
    )
    .tidexCardShadow()
    .shimmer(isActive: isLoading)
  }

  // MARK: - Subviews

  @ViewBuilder
  private var percentageIndicator: some View {
    if showPercentageDash {
      // Skeleton placeholder bar matching other empty states
      RoundedRectangle(cornerRadius: 4)
        .fill(Color.tidexTextMuted.opacity(0.3))
        .frame(width: 48, height: 14)
    } else {
      HStack(spacing: 4) {
        Image(systemName: isPositive ? "arrow.up" : "arrow.down")
          .font(.system(size: 16, weight: .semibold))
          .contentTransition(.symbolEffect(.replace))
        Text(formattedPercentage)
          .font(.system(size: 18, weight: .semibold))
          .contentTransition(.numericText(value: displayPercentage))
      }
      .foregroundColor(isPositive ? .tidexBlue : .tidexTextSecondary)
      .animation(.spring(duration: 0.8, bounce: 0), value: displayPercentage)
      .animation(.spring(duration: 0.8, bounce: 0), value: isPositive)
    }
  }

  @ViewBuilder
  private var subtitleContent: some View {
    switch subtitleType {
    case .earnedToDate(let amount):
      HStack(spacing: 4) {
        CurrencyCountUpText(
          amount: amount,
          duration: 0.8,
          animateOnAppear: true,
          animateChanges: true
        )
        Text(String(localized: .dashboardEarnedToDate))
      }
      .font(.system(size: 18, weight: .regular))
      .foregroundColor(.tidexTextSecondary)

    case .beforeTax(let amount):
      HStack(spacing: 4) {
        CurrencyCountUpText(
          amount: amount,
          duration: 0.8,
          animateOnAppear: true,
          animateChanges: true
        )
        Text(String(localized: .dashboardBeforeTax))
      }
      .font(.system(size: 18, weight: .regular))
      .foregroundColor(.tidexTextSecondary)

    case .plannedCount(let count):
      let plannedLabel =
        count == 1
        ? String(localized: .dashboardShiftPlanned)
        : String(localized: .dashboardShiftsPlanned)
      Text("\(count) \(plannedLabel)")
        .font(.system(size: 18, weight: .regular))
        .foregroundColor(.tidexTextSecondary)
        .contentTransition(.numericText(value: Double(count)))
        .animation(.spring(duration: 0.8, bounce: 0), value: count)

    case .shiftCount(let count):
      let shiftsLabel =
        count == 1
        ? String(localized: .dashboardShift)
        : String(localized: .dashboardShifts)
      Text("\(count) \(shiftsLabel)")
        .font(.system(size: 18, weight: .regular))
        .foregroundColor(.tidexTextSecondary)
        .contentTransition(.numericText(value: Double(count)))
        .animation(.spring(duration: 0.8, bounce: 0), value: count)

    case .none:
      if showDashes {
        // Skeleton placeholder line
        RoundedRectangle(cornerRadius: 6)
          .fill(Color.tidexTextMuted.opacity(0.3))
          .frame(width: 120, height: 16)
      } else {
        // Empty spacer to maintain height
        Color.clear
      }
    }
  }

  @ViewBuilder
  private var mainAmountDisplay: some View {
    if showDashes {
      // Skeleton placeholder line matching the height of the large text
      RoundedRectangle(cornerRadius: 12)
        .fill(Color.tidexBlue.opacity(0.3))
        .frame(width: 200, height: 56)
    } else {
      // Animate count-up on app launch AND on month changes
      let shouldAnimateOnAppear = !Self.hasPlayedLaunchAnimation
      CountUpText(
        targetValue: mainDisplayValue,
        duration: 0.8,
        animateOnAppear: shouldAnimateOnAppear,
        animateChanges: true,
        format: { CurrencyConfig.format($0, currency: currency) }
      )
      .font(.system(size: 88, weight: .bold))
      .foregroundColor(.tidexBlue)
      .minimumScaleFactor(0.4)
      .lineLimit(1)
      .onAppear {
        // Mark animation as played once we show the actual amount
        Self.hasPlayedLaunchAnimation = true
      }
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
}
