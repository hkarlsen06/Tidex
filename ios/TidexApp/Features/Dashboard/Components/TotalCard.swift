import SwiftUI

/// Card displaying current month's total earnings
/// A quiet earnings headline with a stable month-over-month comparison.
///
/// When there are future/planned shifts:
/// - Main display shows projected total (all shifts)
/// - Subtitle shows "earned to date" (completed shifts only)
struct TotalCard: View {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  let gross: Double  // Projected total (all shifts) // swiftlint:disable:this explicit_acl type_contents_order
  let net: Double?  // Projected net (all shifts) // swiftlint:disable:this explicit_acl type_contents_order
  let completedGross: Double  // Earned to date (completed shifts) // swiftlint:disable:this explicit_acl line_length type_contents_order
  let completedNet: Double?  // Earned net (completed shifts) // swiftlint:disable:this explicit_acl type_contents_order
  let shiftCount: Int  // Total shift count // swiftlint:disable:this explicit_acl type_contents_order
  let plannedCount: Int  // Future/planned shift count // swiftlint:disable:this explicit_acl type_contents_order
  let percentageChange: Double?  // swiftlint:disable:this explicit_acl type_contents_order
  let taxEnabled: Bool  // swiftlint:disable:this explicit_acl type_contents_order
  var isElevated: Bool = true  // swiftlint:disable:this explicit_acl type_contents_order
  /// When true, shows skeleton state with shimmer animation (for loading)
  var isLoading: Bool = false  // swiftlint:disable:this explicit_acl type_contents_order

  @Environment(\.userCurrency) private var currency  // swiftlint:disable:this explicit_type_interface line_length type_contents_order
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize  // swiftlint:disable:this explicit_type_interface line_length type_contents_order
  @Environment(\.accessibilityReduceMotion) private var reduceMotion  // swiftlint:disable:this explicit_type_interface line_length type_contents_order

  /// Animated fraction for the month-over-month comparison bar.
  @State private var animatedComparisonProgressFraction: Double = 0  // swiftlint:disable:this type_contents_order
  private let amountAnimationDuration: Double = 0.8  // swiftlint:disable:this type_contents_order
  private let comparisonFillAnimationDuration: Double = 0.52  // swiftlint:disable:this type_contents_order

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

  private var usesFixedTypographyFrames: Bool {  // swiftlint:disable:this type_contents_order
    !dynamicTypeSize.isAccessibilitySize
  }

  private var renderedComparisonProgressFraction: Double {  // swiftlint:disable:this type_contents_order
    isLoading ? 0 : Self.comparisonProgressFraction(for: percentageChange)
  }

  private var comparisonPercentText: String {  // swiftlint:disable:this type_contents_order
    Self.comparisonPercentText(for: isLoading ? nil : percentageChange)
  }

  private var isAtOrAbovePreviousMonth: Bool {  // swiftlint:disable:this type_contents_order
    !isLoading && percentageChange.map { $0 >= 0 } == true
  }

  static func comparisonProgressFraction(for percentageChange: Double?) -> Double {
    guard let percentageChange else { return 0 }
    if percentageChange.isInfinite { return 1 }
    return min(max(1 + percentageChange / 100, 0), 1)
  }

  static func comparisonPercentText(for percentageChange: Double?) -> String {
    guard let percentageChange else { return "---%" }
    if percentageChange.isInfinite { return "∞" }
    let rounded = Int(percentageChange.rounded())  // swiftlint:disable:this explicit_type_interface
    return "\(rounded > 0 ? "+" : "")\(rounded)%"
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
      mainAmountDisplay
        .frame(height: usesFixedTypographyFrames ? 88 : nil)  // swiftlint:disable:this no_magic_numbers

      comparisonProgressBar

      subtitleContent
        .frame(height: usesFixedTypographyFrames ? 24 : nil)  // swiftlint:disable:this no_magic_numbers
    }
    .frame(maxWidth: .infinity)
    .padding(.horizontal, isElevated ? Spacing.lg : 0)
    .padding(.top, Spacing.mlg)
    .padding(.bottom, Spacing.md)
    .tidexRowSurface(
      cornerRadius: CornerRadius.card,
      fillColor: isElevated ? .tidexSurfacePrimary : .clear,
      shadowLevel: isElevated ? .card : nil
    )
    .shimmer(isActive: isLoading)
    .onChange(of: renderedComparisonProgressFraction) { _, newValue in
      animateComparisonProgress(to: newValue)
    }
    .onAppear {
      animateComparisonProgress(to: renderedComparisonProgressFraction)
    }
  }

  // MARK: - Subviews

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

  private var comparisonProgressBar: some View {
    HStack(spacing: Spacing.sm) {
      GeometryReader { geometry in
        ZStack(alignment: .leading) {
          Capsule()
            .fill(Color.tidexSurfaceSecondary)
          Capsule()
            .fill(isAtOrAbovePreviousMonth ? Color.tidexBlue : Color.tidexTextMuted)
            .frame(width: geometry.size.width * animatedComparisonProgressFraction)
        }
      }
      .frame(height: 6)  // swiftlint:disable:this no_magic_numbers

      Text(comparisonPercentText)
        .font(.tidexLabel)
        .monospacedDigit()
        .foregroundColor(.tidexTextSecondary)
        .lineLimit(1)
        .minimumScaleFactor(0.7)  // swiftlint:disable:this no_magic_numbers
        .frame(width: usesFixedTypographyFrames ? 64 : nil, alignment: .trailing)  // swiftlint:disable:this no_magic_numbers line_length
        .fixedSize(horizontal: !usesFixedTypographyFrames, vertical: false)
    }
    .frame(height: usesFixedTypographyFrames ? 18 : nil)  // swiftlint:disable:this no_magic_numbers
    .padding(.top, -Spacing.xxs)
    .padding(.bottom, Spacing.xs)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(.statsFromPreviousMonth))
    .accessibilityValue(Text(verbatim: comparisonPercentText))
  }

  @ViewBuilder
  private var mainAmountDisplay: some View {
    if showDashes {
      // Skeleton placeholder line matching the height of the large text
      RoundedRectangle(cornerRadius: CornerRadius.lg)
        .fill(Color.tidexTextMuted.opacity(0.2))  // swiftlint:disable:this no_magic_numbers
        .frame(width: 200, height: 56)  // swiftlint:disable:this no_magic_numbers
    } else {
      CurrencyCountUpText(
        amount: mainDisplayValue,
        duration: amountAnimationDuration,
        animateOnAppear: false,
        animateChanges: true
      )
      .font(usesFixedTypographyFrames ? .tidexHeroAmount : .tidexAmountDisplay)
      .foregroundColor(.tidexTextPrimary)
      .minimumScaleFactor(0.4)  // swiftlint:disable:this no_magic_numbers
      .lineLimit(1)
    }
  }

  private func subtitleAmountRow(amount: Double, label: String) -> some View {
    let layout =
      dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(spacing: Spacing.xxs))
      : AnyLayout(HStackLayout(spacing: Spacing.xxs))

    return layout {
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

  private func animateComparisonProgress(to newValue: Double) {
    withAnimation(reduceMotion ? nil : .easeOut(duration: comparisonFillAnimationDuration)) {
      animatedComparisonProgressFraction = newValue
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
      taxEnabled: true
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
      taxEnabled: true
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
      taxEnabled: false
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
  .padding(.horizontal, Spacing.lg)
  .background(Color.tidexBackground)
}
