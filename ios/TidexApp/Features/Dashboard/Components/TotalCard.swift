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
  let monthlyGoal: Double?  // Optional monthly goal used for thin progress bar under total
  /// When true, shows skeleton state with shimmer animation (for loading)
  var isLoading: Bool = false

  @Environment(\.userCurrency) private var currency
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// Animated fraction for the monthly goal progress bar.
  @State private var animatedGoalProgressFraction: Double = 0
  /// Second-pass overlay progress (0...1) that sweeps gradient over the filled blue bar.
  @State private var goalReachedOverlayProgress: Double = 0
  /// Pending delayed task for activating reached-goal visuals.
  @State private var goalVisualTask: Task<Void, Never>?

  private let amountAnimationDuration: Double = 0.8
  private let goalFillAnimationDuration: Double = 0.52
  private let goalReachedSweepDuration: Double = 0.4

  private struct GlitterSpeck: Identifiable {
    let id: Int
    let x: CGFloat
    let y: CGFloat
    let size: CGFloat
    let opacity: Double
  }

  // Deterministic sparkle texture so the bar feels premium, not noisy.
  private static let glitterSpecks: [GlitterSpeck] = [
    .init(id: 0, x: 0.07, y: 0.32, size: 1.6, opacity: 0.55),
    .init(id: 1, x: 0.13, y: 0.66, size: 1.2, opacity: 0.42),
    .init(id: 2, x: 0.21, y: 0.45, size: 1.4, opacity: 0.50),
    .init(id: 3, x: 0.30, y: 0.22, size: 1.8, opacity: 0.62),
    .init(id: 4, x: 0.37, y: 0.70, size: 1.1, opacity: 0.40),
    .init(id: 5, x: 0.46, y: 0.38, size: 1.5, opacity: 0.56),
    .init(id: 6, x: 0.54, y: 0.60, size: 1.3, opacity: 0.47),
    .init(id: 7, x: 0.63, y: 0.30, size: 1.7, opacity: 0.60),
    .init(id: 8, x: 0.72, y: 0.68, size: 1.2, opacity: 0.44),
    .init(id: 9, x: 0.81, y: 0.41, size: 1.6, opacity: 0.58),
    .init(id: 10, x: 0.90, y: 0.24, size: 1.4, opacity: 0.52),
    .init(id: 11, x: 0.95, y: 0.62, size: 1.1, opacity: 0.38),
  ]

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

  private var usesFixedTypographyFrames: Bool {
    !dynamicTypeSize.isAccessibilitySize
  }

  private var goalTarget: Double? {
    guard let monthlyGoal, monthlyGoal > 0 else { return nil }
    return monthlyGoal
  }

  private var showGoalProgressBar: Bool {
    isLoading || goalTarget != nil
  }

  /// Raw progress fraction for monthly goal (can exceed 1.0 when over target).
  private var rawGoalProgressFraction: Double {
    guard let goalTarget else { return 0 }
    return max(mainDisplayValue / goalTarget, 0)
  }

  /// Progress fraction used for bar fill (0.0-1.0), clamped to the track.
  private var goalProgressFraction: Double {
    min(rawGoalProgressFraction, 1)
  }

  /// Rendered fraction for the progress bar.
  /// Keep loading state visually empty, then animate to the real value on load completion.
  private var renderedGoalProgressFraction: Double {
    isLoading ? 0 : goalProgressFraction
  }

  private var goalProgressPercentText: String {
    let percent = Int((rawGoalProgressFraction * 100).rounded())
    return "\(percent)%"
  }

  private var isGoalReachedOrExceeded: Bool {
    !isLoading && rawGoalProgressFraction >= 1
  }

  private var showGoalReachedOverlay: Bool {
    goalReachedOverlayProgress > 0
  }

  private var goalReachedOverlayStyle: AnyShapeStyle {
    AnyShapeStyle(
      LinearGradient(
        colors: [
          .tidexBrandPrimary,
          .tidexBlue,
          .tidexBlue.opacity(0.82),
        ],
        startPoint: .leading,
        endPoint: .trailing
      )
    )
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
    VStack(spacing: Spacing.xxs) {
      // Use fixed heights for standard text sizes, but allow expansion for accessibility sizes.
      percentageIndicator
        .frame(height: usesFixedTypographyFrames ? 22 : nil)

      mainAmountDisplay
        .frame(height: usesFixedTypographyFrames ? 88 : nil)

      goalProgressBar

      subtitleContent
        .frame(height: usesFixedTypographyFrames ? 24 : nil)
    }
    .frame(maxWidth: .infinity)
    .padding(.horizontal, Spacing.lg)
    .padding(.top, Spacing.mlg)
    .padding(.bottom, Spacing.md)
    .background(
      RoundedRectangle(cornerRadius: CornerRadius.card)
        .fill(Color.tidexSurfacePrimary)
    )
    .tidexCardShadow()
    .shimmer(isActive: isLoading)
    .onChange(of: renderedGoalProgressFraction) { _, newValue in
      animateGoalProgress(to: newValue)
      syncGoalReachedVisualsAfterProgressAnimation(for: newValue)
    }
    .onAppear {
      animateGoalProgress(to: renderedGoalProgressFraction)
      syncGoalReachedVisualsAfterProgressAnimation(for: renderedGoalProgressFraction)
    }
    .onDisappear {
      goalVisualTask?.cancel()
    }
  }

  // MARK: - Subviews

  @ViewBuilder
  private var percentageIndicator: some View {
    if showPercentageDash {
      // Skeleton placeholder bar matching other empty states
      RoundedRectangle(cornerRadius: CornerRadius.xxs)
        .fill(Color.tidexTextMuted.opacity(0.3))
        .frame(width: 48, height: 14)
    } else {
      HStack(spacing: Spacing.xxs) {
        Image(systemName: isPositive ? "arrow.up" : "arrow.down")
          .font(.tidexButton)
          .contentTransition(.symbolEffect(.replace))
        Text(formattedPercentage)
          .font(.tidexHeadline)
          .contentTransition(.numericText(value: displayPercentage))
      }
      .foregroundColor(isPositive ? .tidexBlue : .tidexTextSecondary)
      .animation(.spring(duration: amountAnimationDuration, bounce: 0), value: displayPercentage)
      .animation(.spring(duration: amountAnimationDuration, bounce: 0), value: isPositive)
    }
  }

  @ViewBuilder
  private var subtitleContent: some View {
    switch subtitleType {
    case .earnedToDate(let amount):
      subtitleAmountRow(amount: amount, label: String(localized: .dashboardEarnedToDate))

    case .beforeTax(let amount):
      subtitleAmountRow(amount: amount, label: String(localized: .dashboardBeforeTax))

    case .plannedCount(let count):
      let plannedLabel =
        count == 1
        ? String(localized: .dashboardShiftPlanned)
        : String(localized: .dashboardShiftsPlanned)
      animatedCountLabel(count: count, label: plannedLabel)

    case .shiftCount(let count):
      let shiftsLabel =
        count == 1
        ? String(localized: .dashboardShift)
        : String(localized: .dashboardShifts)
      animatedCountLabel(count: count, label: shiftsLabel)

    case .none:
      if showDashes {
        // Skeleton placeholder line
        RoundedRectangle(cornerRadius: CornerRadius.xs)
          .fill(Color.tidexTextMuted.opacity(0.3))
          .frame(width: 120, height: 16)
      } else {
        // Empty spacer to maintain height
        Color.clear
      }
    }
  }

  @ViewBuilder
  private var goalProgressBar: some View {
    if showGoalProgressBar {
      HStack(spacing: Spacing.xs) {
        GeometryReader { geometry in
          ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: CornerRadius.xs)
              .fill(Color.tidexSurfaceSecondary)
              .frame(height: 8)

            RoundedRectangle(cornerRadius: CornerRadius.xs)
              .fill(Color.tidexBlue)
              .frame(
                width: geometry.size.width * animatedGoalProgressFraction,
                height: 8
              )

            RoundedRectangle(cornerRadius: CornerRadius.xs)
              .fill(goalReachedOverlayStyle)
              .frame(
                width: geometry.size.width
                  * animatedGoalProgressFraction
                  * goalReachedOverlayProgress,
                height: 8
              )
              .shadow(
                color: showGoalReachedOverlay ? Color.tidexBlue.opacity(0.4) : .clear,
                radius: 8,
                x: 0,
                y: 0
              )
              .shadow(
                color: showGoalReachedOverlay ? Color.tidexBlue.opacity(0.28) : .clear,
                radius: 14,
                x: 0,
                y: 0
              )
              .overlay {
                if showGoalReachedOverlay {
                  RoundedRectangle(cornerRadius: CornerRadius.xs)
                    .stroke(Color.white.opacity(0.28), lineWidth: 0.8)
                }
              }
              .overlay {
                if showGoalReachedOverlay {
                  goalGlitterOverlay
                }
              }
          }
        }
        .frame(height: 8)

        ZStack(alignment: .trailing) {
          // Always present — anchors both the width and height to the real font metrics.
          Text("999%")
            .font(.tidexLabel)
            .monospacedDigit()
            .hidden()

          if showDashes {
            RoundedRectangle(cornerRadius: CornerRadius.xxs)
              .fill(Color.tidexTextMuted.opacity(0.3))
              .frame(width: 46, height: 14)
          } else {
            Text(goalProgressPercentText)
              .font(.tidexLabel)
              .monospacedDigit()
              .lineLimit(1)
              .foregroundColor(.tidexBlue)
              .shadow(
                color: showGoalReachedOverlay ? Color.tidexBlue.opacity(0.35) : .clear,
                radius: 6,
                x: 0,
                y: 0
              )
          }
        }
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(1)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      // Make the amount feel anchored to the bar, then restore breathing room
      // before the subtitle row.
      .padding(.top, -Spacing.xxs)
      .padding(.bottom, Spacing.xs)
    }
  }

  private var goalGlitterOverlay: some View {
    TimelineView(.animation(minimumInterval: reduceMotion ? 0.35 : 1.0 / 24.0)) { context in
      let time = context.date.timeIntervalSinceReferenceDate
      GeometryReader { geometry in
        ZStack {
          ForEach(Self.glitterSpecks) { speck in
            glitterSpeckView(speck, time: time, size: geometry.size)
          }
          glitterSheenOverlay
        }
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xs))
      }
    }
  }

  @ViewBuilder
  private func glitterSpeckView(_ speck: GlitterSpeck, time: TimeInterval, size: CGSize)
    -> some View
  {
    let xRatio = glitterXRatio(for: speck, time: time)
    let yRatio = glitterYRatio(for: speck, time: time)
    let opacity = speck.opacity * glitterTwinkle(for: speck, time: time)

    Circle()
      .fill(Color.white.opacity(opacity))
      .frame(width: speck.size, height: speck.size)
      .position(
        x: size.width * xRatio,
        y: size.height * yRatio
      )
  }

  private var glitterSheenOverlay: some View {
    LinearGradient(
      colors: [
        Color.white.opacity(0.20),
        Color.clear,
        Color.white.opacity(0.10),
      ],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
  }

  private func glitterXRatio(for speck: GlitterSpeck, time: TimeInterval) -> CGFloat {
    guard !reduceMotion else { return speck.x }
    let frequency = 0.9 + Double(speck.id % 4) * 0.16
    let phase = Double(speck.id)
    let drift = CGFloat(sin(time * frequency + phase) * 0.018)
    return clamp(speck.x + drift, lower: 0.02, upper: 0.98)
  }

  private func glitterYRatio(for speck: GlitterSpeck, time: TimeInterval) -> CGFloat {
    guard !reduceMotion else { return speck.y }
    let frequency = 1.1 + Double(speck.id % 3) * 0.2
    let phase = Double(speck.id) * 0.6
    let drift = CGFloat(cos(time * frequency + phase) * 0.11)
    return clamp(speck.y + drift, lower: 0.12, upper: 0.88)
  }

  private func glitterTwinkle(for speck: GlitterSpeck, time: TimeInterval) -> Double {
    guard !reduceMotion else { return 1.0 }
    let frequency = 2.4 + Double(speck.id % 5) * 0.35
    let phase = Double(speck.id)
    let normalizedSine = (sin(time * frequency + phase) + 1) / 2
    return 0.78 + (normalizedSine * 0.22)
  }

  private func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
    min(upper, max(lower, value))
  }

  @ViewBuilder
  private var mainAmountDisplay: some View {
    if showDashes {
      // Skeleton placeholder line matching the height of the large text
      RoundedRectangle(cornerRadius: CornerRadius.lg)
        .fill(Color.tidexBlue.opacity(0.3))
        .frame(width: 200, height: 56)
    } else {
      CurrencyCountUpText(
        amount: mainDisplayValue,
        duration: amountAnimationDuration,
        animateOnAppear: false,
        animateChanges: true
      )
      .font(.tidexHeroAmount)
      .foregroundColor(.tidexBlue)
      .minimumScaleFactor(0.4)
      .lineLimit(1)
    }
  }

  private func subtitleAmountRow(amount: Double, label: String) -> some View {
    HStack(spacing: Spacing.xxs) {
      CurrencyCountUpText(
        amount: amount,
        duration: amountAnimationDuration,
        animateOnAppear: false,
        animateChanges: true
      )
      Text(label)
    }
    .font(.tidexBody)
    .foregroundColor(.tidexTextSecondary)
  }

  private func animatedCountLabel(count: Int, label: String) -> some View {
    Text("\(count) \(label)")
      .font(.tidexBody)
      .foregroundColor(.tidexTextSecondary)
      .contentTransition(.numericText(value: Double(count)))
      .animation(.spring(duration: amountAnimationDuration, bounce: 0), value: count)
  }

  // MARK: - Formatting

  private func animateGoalProgress(to newValue: Double) {
    withAnimation(.spring(duration: goalFillAnimationDuration, bounce: 0.06)) {
      animatedGoalProgressFraction = newValue
    }
  }

  /// Keep the fill blue while it animates, then sweep a gradient overlay from left to right once full.
  private func syncGoalReachedVisualsAfterProgressAnimation(for renderedProgress: Double) {
    goalVisualTask?.cancel()

    guard isGoalReachedOrExceeded && renderedProgress >= 1 else {
      withAnimation(.easeOut(duration: 0.2)) {
        goalReachedOverlayProgress = 0
      }
      return
    }

    goalReachedOverlayProgress = 0
    goalVisualTask = Task { @MainActor in
      let delay = UInt64(goalFillAnimationDuration * 1_000_000_000)
      try? await Task.sleep(nanoseconds: delay)
      guard !Task.isCancelled, isGoalReachedOrExceeded else { return }

      withAnimation(.easeOut(duration: goalReachedSweepDuration)) {
        goalReachedOverlayProgress = 1
      }
    }
  }

}

#Preview {
  VStack(spacing: Spacing.sm) {
    // Case 1: Has future shifts AND real earned amount → "7 500 kr hittil"
    TotalCard(
      gross: 15000,
      net: 12500,
      completedGross: 9000,
      completedNet: 7500,
      shiftCount: 8,
      plannedCount: 3,
      percentageChange: 15,
      taxEnabled: true,
      monthlyGoal: 20000
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
      taxEnabled: true,
      monthlyGoal: 15000
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
      taxEnabled: false,
      monthlyGoal: 15000
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
      taxEnabled: false,
      monthlyGoal: 15000
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
      taxEnabled: false,
      monthlyGoal: nil
    )
  }
  .padding(.horizontal, Spacing.lg)
  .background(Color.tidexBackground)
}
