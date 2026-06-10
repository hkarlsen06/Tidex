import SwiftUI

/// Card displaying current month's total earnings
/// Design matches OfflineTotalCard from the Capacitor app
///
/// When there are future/planned shifts:
/// - Main display shows projected total (all shifts)
/// - Subtitle shows "earned to date" (completed shifts only)
struct TotalCard: View {  // swiftlint:disable:this explicit_acl explicit_top_level_acl type_body_length
  let gross: Double  // Projected total (all shifts) // swiftlint:disable:this explicit_acl type_contents_order
  let net: Double?  // Projected net (all shifts) // swiftlint:disable:this explicit_acl type_contents_order
  let completedGross: Double  // Earned to date (completed shifts) // swiftlint:disable:this explicit_acl line_length type_contents_order
  let completedNet: Double?  // Earned net (completed shifts) // swiftlint:disable:this explicit_acl type_contents_order
  let shiftCount: Int  // Total shift count // swiftlint:disable:this explicit_acl type_contents_order
  let plannedCount: Int  // Future/planned shift count // swiftlint:disable:this explicit_acl type_contents_order
  let percentageChange: Double?  // swiftlint:disable:this explicit_acl type_contents_order
  let taxEnabled: Bool  // swiftlint:disable:this explicit_acl type_contents_order
  let monthlyGoal: Double?  // Optional monthly goal used for thin progress bar under total // swiftlint:disable:this explicit_acl line_length type_contents_order
  var percentageIncludesPayrollAdjustments: Bool = false  // swiftlint:disable:this explicit_acl type_contents_order
  /// When true, shows skeleton state with shimmer animation (for loading)
  var isLoading: Bool = false  // swiftlint:disable:this explicit_acl type_contents_order

  @Environment(\.userCurrency) private var currency  // swiftlint:disable:this explicit_type_interface line_length type_contents_order
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize  // swiftlint:disable:this explicit_type_interface line_length type_contents_order
  @Environment(\.accessibilityReduceMotion) private var reduceMotion  // swiftlint:disable:this explicit_type_interface line_length type_contents_order

  /// Animated fraction for the monthly goal progress bar.
  @State private var animatedGoalProgressFraction: Double = 0  // swiftlint:disable:this type_contents_order
  /// Second-pass overlay progress (0...1) that sweeps gradient over the filled blue bar.
  @State private var goalReachedOverlayProgress: Double = 0  // swiftlint:disable:this type_contents_order
  /// Pending delayed task for activating reached-goal visuals.
  @State private var goalVisualTask: Task<Void, Never>?  // swiftlint:disable:this type_contents_order

  private let amountAnimationDuration: Double = 0.8  // swiftlint:disable:this type_contents_order
  private let goalFillAnimationDuration: Double = 0.52  // swiftlint:disable:this type_contents_order
  private let goalReachedSweepDuration: Double = 0.4  // swiftlint:disable:this type_contents_order

  private struct GlitterSpeck: Identifiable {
    let id: Int
    let x: CGFloat
    let y: CGFloat
    let size: CGFloat
    let opacity: Double
  }

  // Deterministic sparkle texture so the bar feels premium, not noisy.
  private static let glitterSpecks: [GlitterSpeck] = [  // swiftlint:disable:this type_contents_order
    .init(id: 0, x: 0.07, y: 0.32, size: 1.6, opacity: 0.55),  // swiftlint:disable:this no_magic_numbers
    .init(id: 1, x: 0.13, y: 0.66, size: 1.2, opacity: 0.42),  // swiftlint:disable:this no_magic_numbers
    .init(id: 2, x: 0.21, y: 0.45, size: 1.4, opacity: 0.50),  // swiftlint:disable:this no_magic_numbers
    .init(id: 3, x: 0.30, y: 0.22, size: 1.8, opacity: 0.62),  // swiftlint:disable:this no_magic_numbers
    .init(id: 4, x: 0.37, y: 0.70, size: 1.1, opacity: 0.40),  // swiftlint:disable:this no_magic_numbers
    .init(id: 5, x: 0.46, y: 0.38, size: 1.5, opacity: 0.56),  // swiftlint:disable:this no_magic_numbers
    .init(id: 6, x: 0.54, y: 0.60, size: 1.3, opacity: 0.47),  // swiftlint:disable:this no_magic_numbers
    .init(id: 7, x: 0.63, y: 0.30, size: 1.7, opacity: 0.60),  // swiftlint:disable:this no_magic_numbers
    .init(id: 8, x: 0.72, y: 0.68, size: 1.2, opacity: 0.44),  // swiftlint:disable:this no_magic_numbers
    .init(id: 9, x: 0.81, y: 0.41, size: 1.6, opacity: 0.58),  // swiftlint:disable:this no_magic_numbers
    .init(id: 10, x: 0.90, y: 0.24, size: 1.4, opacity: 0.52),  // swiftlint:disable:this no_magic_numbers
    .init(id: 11, x: 0.95, y: 0.62, size: 1.1, opacity: 0.38),  // swiftlint:disable:this no_magic_numbers
  ]

  // MARK: - Computed Properties

  /// Main display value (projected total)
  private var mainDisplayValue: Double {  // swiftlint:disable:this type_contents_order
    taxEnabled ? (net ?? gross) : gross
  }

  /// Earned to date value (completed shifts only)
  private var earnedToDateValue: Double {  // swiftlint:disable:this type_contents_order
    taxEnabled ? (completedNet ?? completedGross) : completedGross
  }

  /// Whether there are future shifts (show projected vs earned)
  private var hasFutureShifts: Bool {  // swiftlint:disable:this type_contents_order
    plannedCount > 0 && mainDisplayValue != earnedToDateValue
  }

  private var showDashes: Bool {  // swiftlint:disable:this type_contents_order
    isLoading || mainDisplayValue == 0
  }

  private var isPositive: Bool {  // swiftlint:disable:this type_contents_order
    (percentageChange ?? 0) >= 0
  }

  private var displayPercentage: Double {  // swiftlint:disable:this type_contents_order
    abs(percentageChange ?? 0)
  }

  private var formattedPercentage: String {  // swiftlint:disable:this type_contents_order
    let value = displayPercentage / 100  // swiftlint:disable:this explicit_type_interface
    return value.formatted(.percent.precision(.fractionLength(0)).locale(Locale.appLocale))
  }

  /// Whether to show a dash instead of percentage (nil or zero means no meaningful comparison)
  private var showPercentageDash: Bool {  // swiftlint:disable:this type_contents_order
    percentageChange == nil || percentageChange == 0
  }

  private var usesFixedTypographyFrames: Bool {  // swiftlint:disable:this type_contents_order
    !dynamicTypeSize.isAccessibilitySize
  }

  private var goalTarget: Double? {  // swiftlint:disable:this type_contents_order
    guard let monthlyGoal, monthlyGoal > 0 else { return nil }  // swiftlint:disable:this conditional_returns_on_newline
    return monthlyGoal
  }

  private var showGoalProgressBar: Bool {  // swiftlint:disable:this type_contents_order
    isLoading || goalTarget != nil
  }

  /// Raw progress fraction for monthly goal (can exceed 1.0 when over target).
  private var rawGoalProgressFraction: Double {  // swiftlint:disable:this type_contents_order
    guard let goalTarget else { return 0 }  // swiftlint:disable:this conditional_returns_on_newline
    return max(mainDisplayValue / goalTarget, 0)
  }

  /// Progress fraction used for bar fill (0.0-1.0), clamped to the track.
  private var goalProgressFraction: Double {  // swiftlint:disable:this type_contents_order
    min(rawGoalProgressFraction, 1)
  }

  /// Rendered fraction for the progress bar.
  /// Keep loading state visually empty, then animate to the real value on load completion.
  private var renderedGoalProgressFraction: Double {  // swiftlint:disable:this type_contents_order
    isLoading ? 0 : goalProgressFraction
  }

  private var goalProgressPercentText: String {  // swiftlint:disable:this type_contents_order
    let percent = Int((rawGoalProgressFraction * 100).rounded())  // swiftlint:disable:this explicit_type_interface
    return "\(percent)%"
  }

  private var isGoalReachedOrExceeded: Bool {  // swiftlint:disable:this type_contents_order
    !isLoading && rawGoalProgressFraction >= 1
  }

  private var showGoalReachedOverlay: Bool {  // swiftlint:disable:this type_contents_order
    goalReachedOverlayProgress > 0
  }

  private var goalReachedOverlayStyle: AnyShapeStyle {  // swiftlint:disable:this type_contents_order
    AnyShapeStyle(
      LinearGradient(
        colors: [
          .tidexBrandPrimary,
          .tidexBlue,
          .tidexBlue.opacity(0.82),  // swiftlint:disable:this no_magic_numbers
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
    case none  // swiftlint:disable:this discouraged_none_name
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
    if showDashes { return .none }  // swiftlint:disable:this conditional_returns_on_newline

    // Check if we have real earnings to date (not zero)
    let hasRealEarned = hasFutureShifts && earnedToDateValue > 0  // swiftlint:disable:this explicit_type_interface

    // When there are future shifts AND real earnings, show "earned to date" amount
    if hasRealEarned {
      return .earnedToDate(earnedToDateValue)
    }

    // Show gross before tax when tax is enabled (only when NOT showing earned to date)
    let hasGross = !hasFutureShifts && taxEnabled && gross > 0 && gross != mainDisplayValue  // swiftlint:disable:this explicit_type_interface line_length
    if hasGross {
      return .beforeTax(gross)
    }

    // When there are future/planned shifts but no real earnings yet, show planned count
    let showPlanned = hasFutureShifts && !hasRealEarned && plannedCount > 0  // swiftlint:disable:this explicit_type_interface line_length
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

  var body: some View {  // swiftlint:disable:this explicit_acl
    VStack(spacing: Spacing.xxs) {
      // Use fixed heights for standard text sizes, but allow expansion for accessibility sizes.
      percentageIndicator
        .frame(height: usesFixedTypographyFrames ? 22 : nil)  // swiftlint:disable:this no_magic_numbers

      mainAmountDisplay
        .frame(height: usesFixedTypographyFrames ? 88 : nil)  // swiftlint:disable:this no_magic_numbers

      goalProgressBar

      subtitleContent
        .frame(height: usesFixedTypographyFrames ? 24 : nil)  // swiftlint:disable:this no_magic_numbers
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
        .fill(Color.tidexTextMuted.opacity(0.3))  // swiftlint:disable:this no_magic_numbers
        .frame(width: 48, height: 14)  // swiftlint:disable:this no_magic_numbers
    } else {
      HStack(spacing: Spacing.xxs) {
        Image(systemName: isPositive ? "arrow.up" : "arrow.down")
          .font(.tidexButton)
          .contentTransition(.symbolEffect(.replace))
        HStack(alignment: .firstTextBaseline, spacing: 1) {
          Text(formattedPercentage)
            .font(.tidexHeadline)
            .contentTransition(.numericText(value: displayPercentage))

          if percentageIncludesPayrollAdjustments {
            Text(verbatim: "*")
              .font(.tidexFootnote.weight(.semibold))
              .offset(y: -4)  // swiftlint:disable:this no_magic_numbers
              .accessibilityHidden(true)
          }
        }
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
      let plannedLabel =  // swiftlint:disable:this explicit_type_interface
        count == 1
        ? String(localized: .dashboardShiftPlanned)
        : String(localized: .dashboardShiftsPlanned)
      animatedCountLabel(count: count, label: plannedLabel)

    case .shiftCount(let count):
      let shiftsLabel =  // swiftlint:disable:this explicit_type_interface
        count == 1
        ? String(localized: .dashboardShift)
        : String(localized: .dashboardShifts)
      animatedCountLabel(count: count, label: shiftsLabel)

    case .none:
      if showDashes {
        // Skeleton placeholder line
        RoundedRectangle(cornerRadius: CornerRadius.xs)
          .fill(Color.tidexTextMuted.opacity(0.3))  // swiftlint:disable:this no_magic_numbers
          .frame(width: 120, height: 16)  // swiftlint:disable:this no_magic_numbers
      } else {
        // Empty spacer to maintain height
        Color.clear
      }
    }
  }

  @ViewBuilder
  private var goalProgressBar: some View {
    if showGoalProgressBar {
      HStack(spacing: Spacing.xs) {  // swiftlint:disable:this closure_body_length
        GeometryReader { geometry in  // swiftlint:disable:this closure_body_length
          ZStack(alignment: .leading) {  // swiftlint:disable:this closure_body_length
            RoundedRectangle(cornerRadius: CornerRadius.xs)
              .fill(Color.tidexSurfaceSecondary)
              .frame(height: 8)  // swiftlint:disable:this no_magic_numbers

            RoundedRectangle(cornerRadius: CornerRadius.xs)
              .fill(Color.tidexBlue)
              .frame(
                width: geometry.size.width * animatedGoalProgressFraction,
                height: 8  // swiftlint:disable:this no_magic_numbers
              )

            RoundedRectangle(cornerRadius: CornerRadius.xs)
              .fill(goalReachedOverlayStyle)
              .frame(
                width: geometry.size.width
                  * animatedGoalProgressFraction
                  * goalReachedOverlayProgress,
                height: 8  // swiftlint:disable:this no_magic_numbers
              )
              .shadow(
                color: showGoalReachedOverlay ? Color.tidexBlue.opacity(0.4) : .clear,  // swiftlint:disable:this line_length no_magic_numbers
                radius: 8,  // swiftlint:disable:this no_magic_numbers
                x: 0,
                y: 0
              )
              .shadow(
                color: showGoalReachedOverlay ? Color.tidexBlue.opacity(0.28) : .clear,  // swiftlint:disable:this line_length no_magic_numbers
                radius: 14,  // swiftlint:disable:this no_magic_numbers
                x: 0,
                y: 0
              )
              .overlay {
                if showGoalReachedOverlay {
                  RoundedRectangle(cornerRadius: CornerRadius.xs)
                    .stroke(Color.white.opacity(0.28), lineWidth: 0.8)  // swiftlint:disable:this no_magic_numbers
                }
              }
              .overlay {
                if showGoalReachedOverlay {
                  goalGlitterOverlay
                }
              }
          }
        }
        .frame(height: 8)  // swiftlint:disable:this no_magic_numbers

        ZStack(alignment: .trailing) {
          // Always present - anchors both the width and height to the real font metrics.
          Text(verbatim: "999%")
            .font(.tidexLabel)
            .monospacedDigit()
            .hidden()

          if showDashes {
            RoundedRectangle(cornerRadius: CornerRadius.xxs)
              .fill(Color.tidexTextMuted.opacity(0.3))  // swiftlint:disable:this no_magic_numbers
              .frame(width: 46, height: 14)  // swiftlint:disable:this no_magic_numbers
          } else {
            Text(goalProgressPercentText)
              .font(.tidexLabel)
              .monospacedDigit()
              .lineLimit(1)
              .foregroundColor(.tidexBlue)
              .shadow(
                color: showGoalReachedOverlay ? Color.tidexBlue.opacity(0.35) : .clear,  // swiftlint:disable:this line_length no_magic_numbers
                radius: 6,  // swiftlint:disable:this no_magic_numbers
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
    TimelineView(.animation(minimumInterval: reduceMotion ? 0.35 : 1.0 / 24.0)) { context in  // swiftlint:disable:this line_length no_magic_numbers
      let time = context.date.timeIntervalSinceReferenceDate  // swiftlint:disable:this explicit_type_interface
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
  private func glitterSpeckView(_ speck: GlitterSpeck, time: TimeInterval, size: CGSize)  // swiftlint:disable:this line_length type_contents_order
    -> some View
  {
    let xRatio = glitterXRatio(for: speck, time: time)  // swiftlint:disable:this explicit_type_interface
    let yRatio = glitterYRatio(for: speck, time: time)  // swiftlint:disable:this explicit_type_interface
    let opacity = speck.opacity * glitterTwinkle(for: speck, time: time)  // swiftlint:disable:this explicit_type_interface line_length

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
        Color.white.opacity(0.20),  // swiftlint:disable:this no_magic_numbers
        Color.clear,
        Color.white.opacity(0.10),  // swiftlint:disable:this no_magic_numbers
      ],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
  }

  private func glitterXRatio(for speck: GlitterSpeck, time: TimeInterval) -> CGFloat {  // swiftlint:disable:this line_length type_contents_order
    guard !reduceMotion else { return speck.x }  // swiftlint:disable:this conditional_returns_on_newline
    let frequency = 0.9 + Double(speck.id % 4) * 0.16  // swiftlint:disable:this explicit_type_interface no_magic_numbers
    let phase = Double(speck.id)  // swiftlint:disable:this explicit_type_interface
    let drift = CGFloat(sin(time * frequency + phase) * 0.018)  // swiftlint:disable:this explicit_type_interface line_length no_magic_numbers
    return clamp(speck.x + drift, lower: 0.02, upper: 0.98)  // swiftlint:disable:this no_magic_numbers
  }

  private func glitterYRatio(for speck: GlitterSpeck, time: TimeInterval) -> CGFloat {  // swiftlint:disable:this line_length type_contents_order
    guard !reduceMotion else { return speck.y }  // swiftlint:disable:this conditional_returns_on_newline
    let frequency = 1.1 + Double(speck.id % 3) * 0.2  // swiftlint:disable:this explicit_type_interface no_magic_numbers
    let phase = Double(speck.id) * 0.6  // swiftlint:disable:this explicit_type_interface no_magic_numbers
    let drift = CGFloat(cos(time * frequency + phase) * 0.11)  // swiftlint:disable:this explicit_type_interface line_length no_magic_numbers
    return clamp(speck.y + drift, lower: 0.12, upper: 0.88)  // swiftlint:disable:this no_magic_numbers
  }

  private func glitterTwinkle(for speck: GlitterSpeck, time: TimeInterval) -> Double {  // swiftlint:disable:this line_length type_contents_order
    guard !reduceMotion else { return 1.0 }  // swiftlint:disable:this conditional_returns_on_newline
    let frequency = 2.4 + Double(speck.id % 5) * 0.35  // swiftlint:disable:this explicit_type_interface no_magic_numbers
    let phase = Double(speck.id)  // swiftlint:disable:this explicit_type_interface
    let normalizedSine = (sin(time * frequency + phase) + 1) / 2  // swiftlint:disable:this explicit_type_interface line_length no_magic_numbers
    return 0.78 + (normalizedSine * 0.22)  // swiftlint:disable:this no_magic_numbers
  }

  private func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {  // swiftlint:disable:this line_length type_contents_order
    min(upper, max(lower, value))
  }

  @ViewBuilder
  private var mainAmountDisplay: some View {
    if showDashes {
      // Skeleton placeholder line matching the height of the large text
      RoundedRectangle(cornerRadius: CornerRadius.lg)
        .fill(Color.tidexBlue.opacity(0.3))  // swiftlint:disable:this no_magic_numbers
        .frame(width: 200, height: 56)  // swiftlint:disable:this no_magic_numbers
    } else {
      CurrencyCountUpText(
        amount: mainDisplayValue,
        duration: amountAnimationDuration,
        animateOnAppear: false,
        animateChanges: true
      )
      .font(.tidexHeroAmount)
      .foregroundColor(.tidexBlue)
      .minimumScaleFactor(0.4)  // swiftlint:disable:this no_magic_numbers
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
    withAnimation(.spring(duration: goalFillAnimationDuration, bounce: 0.06)) {  // swiftlint:disable:this line_length no_magic_numbers
      animatedGoalProgressFraction = newValue
    }
  }

  /// Keep the fill blue while it animates, then sweep a gradient overlay from left to right once full.
  private func syncGoalReachedVisualsAfterProgressAnimation(for renderedProgress: Double) {
    goalVisualTask?.cancel()

    guard isGoalReachedOrExceeded, renderedProgress >= 1 else {
      withAnimation(.easeOut(duration: 0.2)) {  // swiftlint:disable:this no_magic_numbers
        goalReachedOverlayProgress = 0
      }
      return
    }

    goalReachedOverlayProgress = 0
    goalVisualTask = Task { @MainActor in
      let delay = UInt64(goalFillAnimationDuration * 1_000_000_000)  // swiftlint:disable:this explicit_type_interface line_length no_magic_numbers
      try? await Task.sleep(nanoseconds: delay)
      guard !Task.isCancelled, isGoalReachedOrExceeded else { return }  // swiftlint:disable:this conditional_returns_on_newline line_length

      withAnimation(.easeOut(duration: goalReachedSweepDuration)) {
        goalReachedOverlayProgress = 1
      }
    }
  }

}

#Preview {  // swiftlint:disable:this closure_body_length
  VStack(spacing: Spacing.sm) {  // swiftlint:disable:this closure_body_length
    // Case 1: Has future shifts AND real earned amount → "7 500 kr hittil"
    TotalCard(
      gross: 15_000,
      net: 12_500,
      completedGross: 9_000,
      completedNet: 7_500,
      shiftCount: 8,
      plannedCount: 3,
      percentageChange: 15,
      taxEnabled: true,
      monthlyGoal: 20_000
    )

    // Case 2: No future shifts, tax enabled → "12 000 kr før skatt"
    TotalCard(
      gross: 12_000,
      net: 10_000,
      completedGross: 12_000,
      completedNet: 10_000,
      shiftCount: 5,
      plannedCount: 0,
      percentageChange: -8,
      taxEnabled: true,
      monthlyGoal: 15_000
    )

    // Case 3: No future shifts, no tax → "5 vakter"
    TotalCard(
      gross: 12_000,
      net: nil,
      completedGross: 12_000,
      completedNet: nil,
      shiftCount: 5,
      plannedCount: 0,
      percentageChange: -8,
      taxEnabled: false,
      monthlyGoal: 15_000
    )

    // Case 4: Has future/planned shifts but NO real earnings yet → "3 vakter planlagt"
    TotalCard(
      gross: 5_000,
      net: nil,
      completedGross: 0,
      completedNet: nil,
      shiftCount: 3,
      plannedCount: 3,
      percentageChange: nil,
      taxEnabled: false,
      monthlyGoal: 15_000
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
}  // swiftlint:disable:this file_length
