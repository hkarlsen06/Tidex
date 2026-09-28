import SwiftUI

/// Card displaying a featured shift
/// - For current month: shows next upcoming shift with countdown
/// - For other months: shows best shift (highest earnings)
/// Design matches ShiftCard from the Next.js app
struct FeaturedShiftCard: View {  // swiftlint:disable:this explicit_acl explicit_top_level_acl file_types_order line_length type_body_length
  enum SurfaceStyle {  // swiftlint:disable:this explicit_acl
    case standard
    case example
    case flat
  }

  let shift: ShiftWithComputations  // swiftlint:disable:this explicit_acl
  let isToday: Bool  // swiftlint:disable:this explicit_acl
  let isBestShift: Bool  // true = showing best shift, false = showing next shift // swiftlint:disable:this explicit_acl
  let countdownText: String?  // Countdown text shown below the amount // swiftlint:disable:this explicit_acl
  /// Progress through the shift (0-100), shows a subtle progress bar when provided (for active shifts)
  var progress: Double?  // swiftlint:disable:this explicit_acl
  /// Remaining seconds in the final countdown window for active shifts.
  var finalCountdownSeconds: Int?  // swiftlint:disable:this explicit_acl
  /// When true, the end time is rendered as a skeleton placeholder.
  var showTimeRangeEndSkeleton: Bool = false  // swiftlint:disable:this explicit_acl
  /// When true, shows a "+" prefix and uses blue color for the amount (used in celebration overlay)
  var showIncreaseHighlight: Bool = false  // swiftlint:disable:this explicit_acl
  /// Whether the countdown/status badge should be shown below the amount.
  var showFooter: Bool = true  // swiftlint:disable:this explicit_acl
  var surfaceStyle: SurfaceStyle = .standard  // swiftlint:disable:this explicit_acl

  init(  // swiftlint:disable:this explicit_acl type_contents_order
    shift: ShiftWithComputations,
    isToday: Bool,
    isBestShift: Bool,
    countdownText: String?,
    progress: Double? = nil,
    finalCountdownSeconds: Int? = nil,
    showTimeRangeEndSkeleton: Bool = false,
    showIncreaseHighlight: Bool = false,
    showFooter: Bool = true,
    surfaceStyle: SurfaceStyle = .standard
  ) {
    self.shift = shift
    self.isToday = isToday
    self.isBestShift = isBestShift
    self.countdownText = countdownText
    self.progress = progress
    self.finalCountdownSeconds = finalCountdownSeconds
    self.showTimeRangeEndSkeleton = showTimeRangeEndSkeleton
    self.showIncreaseHighlight = showIncreaseHighlight
    self.showFooter = showFooter
    self.surfaceStyle = surfaceStyle
  }

  @Environment(\.layoutDirection) private var layoutDirection  // swiftlint:disable:this explicit_type_interface
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize  // swiftlint:disable:this explicit_type_interface

  /// Animated progress value for smooth entrance animation
  @State private var animatedProgress: Double = 0
  @State private var previousDisplayAmount: Double?
  @State private var previousHasTrailingBottomContent: Bool?  // swiftlint:disable:this discouraged_optional_boolean

  // MARK: - Computed Properties

  private var dateParts: ShiftCardDateParts {
    ShiftCardFormatter.dateParts(for: shift.shiftDate)
  }

  private func hasProgress(_ value: Double?) -> Bool {  // swiftlint:disable:this type_contents_order
    guard let value else { return false }  // swiftlint:disable:this conditional_returns_on_newline
    return value >= 0 && value <= 100
  }

  /// Footer label shown below the card - "Best shift" or countdown text.
  private func footerText(countdown: String?) -> String? {  // swiftlint:disable:this type_contents_order
    isBestShift ? String(localized: .dashboardBestShift) : countdown
  }

  /// Badge color status for the featured shift countdown.
  private func countdownStatus(progress: Double?, at now: Date) -> ShiftPreviewStatus {  // swiftlint:disable:this line_length type_contents_order
    if hasProgress(progress) {
      return .active
    }

    if Date.hasShiftEnded(
      shiftDate: shift.shiftDate,
      startTime: shift.startTime,
      endTime: shift.endTime,
      referenceDate: now
    ) {
      return .past
    }

    return .upcoming
  }

  private var isRTL: Bool {
    layoutDirection == .rightToLeft
  }

  private var hasTrailingBottomContent: Bool {
    showFooter && footerText(countdown: countdownText) != nil
  }

  private var displayAmount: Double {
    shift.taxEnabled ? shift.netPay : shift.grossPay
  }

  private var timeRangeText: String {
    ShiftCardFormatter.localizedTimeRange(
      start: shift.startTime,
      end: shift.endTime,
      locale: Locale.appLocale
    )
  }

  private var startTimeText: String {
    ShiftCardFormatter.localizedTime(shift.startTime, locale: Locale.appLocale)
  }

  private var shouldShowLiveEndTimeIndicator: Bool {
    hasProgress(progress) && !showTimeRangeEndSkeleton
  }

  private var cardShape: RoundedRectangle {
    RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous)
  }

  private var usesFixedCardHeight: Bool {
    !dynamicTypeSize.isAccessibilitySize
  }

  // MARK: - Body

  var body: some View {  // swiftlint:disable:this explicit_acl
    let displayedProgress = progress  // swiftlint:disable:this explicit_type_interface
    let displayedFooterText = footerText(countdown: countdownText)  // swiftlint:disable:this explicit_type_interface
    let status = countdownStatus(progress: displayedProgress, at: Date())  // swiftlint:disable:this explicit_type_interface line_length

    VStack(spacing: Spacing.sm) {  // swiftlint:disable:this closure_body_length
      // Main card content
      ShiftCardContentLayout(centerTrailing: !hasTrailingBottomContent) {
        // Row 1: Day name and date
        HStack(spacing: Spacing.xxs) {
          Text(dateParts.weekday)
            .font(.tidexBodyMedium)
            .foregroundColor(.tidexTextPrimary)
          Text("·")
            .foregroundColor(.tidexTextMuted)
          Text(dateParts.dayMonth)
            .font(.tidexBodyMedium)
            .foregroundColor(.tidexTextMuted)
            .contentTransition(.numericText())
        }
        .animation(.spring(duration: 0.8, bounce: 0), value: dateParts.dayMonth)  // swiftlint:disable:this line_length no_magic_numbers
      } leadingBottom: {
        // Row 2: Time range
        timeRangeLabel
      } trailingTop: {
        // Net/gross amount
        HStack(spacing: Spacing.xxxs) {
          if showIncreaseHighlight {
            Text("+")
              .font(.tidexTitle)
              .foregroundColor(.tidexBlue)
          }
          CurrencyCountUpText(
            amount: displayAmount,
            duration: 0.8,  // swiftlint:disable:this no_magic_numbers
            animateOnAppear: false,
            animateChanges: true,
            animateFrom: ShiftCardAmountAnimationFallback.animateFrom(
              previousAmount: previousDisplayAmount,
              previousHasTrailingBottomContent: previousHasTrailingBottomContent,
              currentHasTrailingBottomContent: hasTrailingBottomContent
            )
          )
          .font(.tidexTitle)
          .foregroundColor(showIncreaseHighlight ? .tidexBlue : .tidexTextPrimary)
        }
      } trailingBottom: {
        if showFooter, let text = displayedFooterText {
          if isBestShift {
            HStack(spacing: Spacing.xxxs) {
              Image(systemName: "star.fill")  // swiftlint:disable:this accessibility_label_for_image
              Text(text)
            }
            .font(.tidexLabel)
            .foregroundColor(.tidexTextSecondary)
          } else {
            ShiftCountdownBadge(
              text: text,
              status: status,
              finalCountdownSeconds: finalCountdownSeconds
            )
          }
        }
      }
      .padding(.horizontal, surfaceStyle == .flat ? 0 : Spacing.mlg)
      .padding(.vertical, ShiftCardMetrics.verticalPadding)
      .frame(minHeight: usesFixedCardHeight ? ShiftCardMetrics.regularCardMinHeight : nil)
      .background(cardFillColor)
      .overlay(alignment: .leading) {
        // Progress bar overlay - fills from left based on progress (for active shifts)
        // Uses Rectangle instead of RoundedRectangle so small widths don't overflow
        // The clipShape on the parent handles the rounded corners
        if hasProgress(displayedProgress) {
          GeometryReader { geometry in
            if surfaceStyle == .flat {
              Rectangle()
                .fill(Color.tidexBlue)
                .frame(
                  width: geometry.size.width * (animatedProgress / 100),
                  height: 3  // swiftlint:disable:this no_magic_numbers
                )
                .frame(maxHeight: .infinity, alignment: .bottom)
            } else {
              Rectangle()
                .fill(Color.tidexBlue.opacity(0.1))  // swiftlint:disable:this no_magic_numbers
                .frame(width: geometry.size.width * (animatedProgress / 100))
            }
          }
        }
      }
      .overlay {
        cardShape
          .strokeBorder(cardBorderColor, style: cardBorderStyle)
      }
      .clipShape(cardShape)
      .onChange(of: displayedProgress) { _, newValue in
        // Animate to new progress value
        withAnimation(.linear(duration: 1.0)) {
          animatedProgress = newValue ?? 0
        }
      }
      .onChange(of: displayAmount) { _, newValue in
        previousDisplayAmount = newValue
      }
      .onChange(of: hasTrailingBottomContent) { _, newValue in
        previousHasTrailingBottomContent = newValue
      }
      .onAppear {
        previousDisplayAmount = displayAmount
        previousHasTrailingBottomContent = hasTrailingBottomContent

        // Animate from 0 to current progress on appear (matches CSS animation)
        if hasProgress(displayedProgress) {
          withAnimation(.linear(duration: 1.0)) {
            animatedProgress = displayedProgress ?? 0
          }
        }
      }

    }
  }

  // MARK: - Formatting

  private var timeRangeLabel: some View {
    HStack(spacing: Spacing.xxs) {
      if isRTL {
        timeRangeContent
        clockIcon
      } else {
        clockIcon
        timeRangeContent
      }
    }
  }

  @ViewBuilder
  private var timeRangeContent: some View {
    if showTimeRangeEndSkeleton {
      timeRangeSkeletonLabel
    } else {
      timeRangeTextLabel
    }
  }

  private var timeRangeTextLabel: some View {
    HStack(alignment: .firstTextBaseline, spacing: 0) {
      Text(timeRangeText)
      if shouldShowLiveEndTimeIndicator {
        LiveTypingDots()
          .padding(.leading, 1)
      }
    }
    .font(.tidexSubheadline)
    .foregroundColor(.tidexTextPrimary)
    .lineLimit(1)
    .fixedSize(horizontal: true, vertical: false)
    .environment(\.layoutDirection, .leftToRight)
  }

  private var timeRangeSkeletonLabel: some View {
    HStack(spacing: Spacing.xxxs) {
      Text(startTimeText)
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextPrimary)
      Text(verbatim: "-")
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextMuted)
      RoundedRectangle(cornerRadius: CornerRadius.xxs)
        .fill(Color.tidexTextMuted.opacity(0.22))  // swiftlint:disable:this no_magic_numbers
        .frame(width: 38, height: 12)  // swiftlint:disable:this no_magic_numbers
    }
    .lineLimit(1)
    .fixedSize(horizontal: true, vertical: false)
    .environment(\.layoutDirection, .leftToRight)
  }

  private var clockIcon: some View {
    Image(systemName: "clock")  // swiftlint:disable:this accessibility_label_for_image
      .font(.tidexSubheadline)
      .foregroundColor(.tidexTextMuted)
  }

  private var cardBorderColor: Color {
    switch surfaceStyle {
    case .standard:
      .clear

    case .example:
      .tidexBorder

    case .flat:
      .clear
    }
  }

  private var cardFillColor: Color {
    surfaceStyle == .standard ? .tidexSurfacePrimary : .clear
  }

  private var cardBorderStyle: StrokeStyle {
    switch surfaceStyle {
    case .standard:
      StrokeStyle(lineWidth: 0)

    case .example:
      StrokeStyle(lineWidth: 1.5, dash: [7, 5])  // swiftlint:disable:this no_magic_numbers

    case .flat:
      StrokeStyle(lineWidth: 0)
    }
  }
}

private struct LiveTypingDots: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion  // swiftlint:disable:this explicit_type_interface
  @State private var activeDotIndex: Int?

  var body: some View {
    HStack(spacing: 2) {  // swiftlint:disable:this no_magic_numbers
      ForEach(0..<3, id: \.self) { index in  // swiftlint:disable:this no_magic_numbers
        let isActive = activeDotIndex == index  // swiftlint:disable:this explicit_type_interface
        Circle()
          .fill(Color.tidexTextMuted)
          .frame(width: 3, height: 3)  // swiftlint:disable:this no_magic_numbers
          .scaleEffect(reduceMotion ? 1.0 : (isActive ? 1.0 : 0.55))  // swiftlint:disable:this no_magic_numbers
          .opacity(reduceMotion ? 0.65 : (isActive ? 1.0 : 0.35))  // swiftlint:disable:this no_magic_numbers
          .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: activeDotIndex)  // swiftlint:disable:this line_length no_magic_numbers
      }
    }
    .frame(width: 14, alignment: .leading)  // swiftlint:disable:this no_magic_numbers
    .task {
      guard !reduceMotion else { return }  // swiftlint:disable:this conditional_returns_on_newline
      while !Task.isCancelled {
        for index in 0..<3 {  // swiftlint:disable:this no_magic_numbers
          activeDotIndex = index
          try? await Task.sleep(for: .milliseconds(170))  // swiftlint:disable:this no_magic_numbers
        }
        activeDotIndex = nil
        // Deliberate gap after each full wave to make the indicator feel less frantic.
        try? await Task.sleep(for: .milliseconds(520))  // swiftlint:disable:this no_magic_numbers
      }
    }
  }
}

// Preview disabled - requires full app context
// #Preview {
//     VStack(spacing: Spacing.md) {
//         FeaturedShiftCard(shift: mockShift, isToday: true, isBestShift: false)
//         FeaturedShiftCard(shift: mockShift, isToday: false, isBestShift: true)
//     }
// }
