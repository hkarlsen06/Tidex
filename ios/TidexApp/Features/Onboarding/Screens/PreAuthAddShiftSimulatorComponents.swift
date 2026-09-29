import SwiftUI
import UIKit

struct OnboardingHintShimmerText: View {
  let text: String
  let trigger: Int

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var shimmerStartDate: Date?
  @State private var isShimmerActive = false
  @State private var cycleToken = 0
  @ScaledMetric(relativeTo: .footnote) private var basePointSize: CGFloat = 13

  private let shimmerDuration = PreAuthSimulatorAnimationTiming.hintSweepDuration
  private let shimmerCleanupDelay = PreAuthSimulatorAnimationTiming.hintCleanupDelay

  var body: some View {
    Group {
      if isShimmerActive {
        TimelineView(.animation) { context in
          shimmerText(styledText(at: context.date))
        }
      } else {
        shimmerText(staticText)
      }
    }
    .onChange(of: trigger) { _, _ in
      runShimmerCycle()
    }
    .onDisappear {
      cycleToken += 1
      isShimmerActive = false
      shimmerStartDate = nil
    }
  }

  private var staticText: AttributedString {
    var attributed = AttributedString(text)
    attributed.font = .system(size: basePointSize, weight: .regular, design: .default)
    attributed.foregroundColor = .tidexTextMuted
    return attributed
  }

  private func shimmerText(_ attributed: AttributedString) -> some View {
    Text(attributed)
      .multilineTextAlignment(.center)
      .lineLimit(3)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .center)
  }

  private func styledText(at currentDate: Date) -> AttributedString {
    var attributed = AttributedString(text)
    let characterCount = max(text.count, 1)

    guard
      isShimmerActive,
      let shimmerStartDate
    else {
      attributed.font = .system(size: basePointSize, weight: .regular, design: .default)
      attributed.foregroundColor = .tidexTextMuted
      return attributed
    }

    let elapsed = max(currentDate.timeIntervalSince(shimmerStartDate), 0)
    let progress = CGFloat(min(elapsed / shimmerDuration, 1))
    let radius = max(CGFloat(characterCount) * 0.24, 4)
    let startCenter = -radius
    let endCenter = CGFloat(max(characterCount - 1, 1)) + radius
    let center = startCenter + ((endCenter - startCenter) * progress)

    var charIndex = 0
    var stringIndex = text.startIndex

    while stringIndex < text.endIndex {
      let nextIndex = text.index(after: stringIndex)
      let charRange = stringIndex..<nextIndex
      if let attributedRange = Range(charRange, in: attributed) {
        let distance = abs(CGFloat(charIndex) - center)
        let intensity = max(0, 1 - (distance / radius))
        let weight: Font.Weight =
          intensity > 0.6 ? .bold : (intensity > 0.25 ? .semibold : .regular)
        let size = basePointSize * (1 + (0.09 * intensity))
        let color: Color = intensity > 0.08 ? .tidexBlueText : .tidexTextMuted

        attributed[attributedRange].font = .system(size: size, weight: weight, design: .default)
        attributed[attributedRange].foregroundColor = color
      }
      stringIndex = nextIndex
      charIndex += 1
    }

    return attributed
  }

  private func runShimmerCycle() {
    // The per-frame font sweep is motion, so Reduce Motion keeps the static hint.
    guard !reduceMotion else { return }
    cycleToken += 1
    let token = cycleToken
    shimmerStartDate = Date()
    isShimmerActive = true

    DispatchQueue.main.asyncAfter(deadline: .now() + shimmerDuration + shimmerCleanupDelay) {
      guard token == cycleToken else { return }
      isShimmerActive = false
      shimmerStartDate = nil
    }
  }
}

enum PreAuthSimulatorAnimationTiming {
  static let hintSweepDuration: TimeInterval = 1.28
  static let hintCleanupDelay: TimeInterval = 0.08
  static let totalsIndicatorStartDelay: TimeInterval = hintSweepDuration + hintCleanupDelay
}

enum PreAuthSimulatorFocusStage {
  case calendar
  case times
  case totals
  case add
}

extension View {
  @ViewBuilder
  func simulatorFocusStyle(isFocused: Bool) -> some View {
    // Sections that are not in focus lose color, not opacity or sharpness, so their text stays readable.
    saturation(isFocused ? 1 : 0.45)
  }
}

/// Blue focus indicator under totals: dot -> line to the right -> dot again from the left.
struct TotalsFocusSweepIndicator: View {
  let isActive: Bool
  let reduceMotion: Bool
  let trackWidth: CGFloat

  @State private var cycleToken = 0
  @State private var hasPlayedCurrentActivation = false
  @State private var leadingProgress: CGFloat = 0
  @State private var trailingProgress: CGFloat = 0
  @State private var indicatorOpacity: CGFloat = 0

  private let dotDiameter: CGFloat = 7
  private let lineHeight: CGFloat = 5
  private let expandDuration: TimeInterval = 0.54
  private let collapseDuration: TimeInterval = 0.58
  private let fadeOutDuration: TimeInterval = 0.18
  private let startDelay = PreAuthSimulatorAnimationTiming.totalsIndicatorStartDelay

  var body: some View {
    let travel = trackWidth - dotDiameter
    let startX = travel * leadingProgress
    let endX = travel * trailingProgress
    let width = max(dotDiameter, (endX - startX) + dotDiameter)

    Capsule(style: .continuous)
      .fill(Color.tidexBlue)
      .frame(width: width, height: lineHeight)
      .offset(x: startX)
      .frame(width: trackWidth, height: dotDiameter, alignment: .leading)
      .opacity(indicatorOpacity)
      .allowsHitTesting(false)
      .accessibilityHidden(true)
      .onAppear {
        syncAnimationState()
      }
      .onChange(of: isActive) { _, _ in
        syncAnimationState()
      }
      .onDisappear {
        cycleToken += 1
      }
  }

  private func syncAnimationState() {
    cycleToken += 1
    let token = cycleToken

    if !isActive {
      withAnimation(.easeOut(duration: 0.2)) {
        leadingProgress = 0
        trailingProgress = 0
        indicatorOpacity = 0
      }
      hasPlayedCurrentActivation = false
      return
    }

    guard !hasPlayedCurrentActivation else { return }

    leadingProgress = 0
    trailingProgress = 0
    indicatorOpacity = 0

    hasPlayedCurrentActivation = true

    runSingleCycle(token: token)
  }

  private func runSingleCycle(token: Int) {
    guard token == cycleToken, isActive else { return }

    DispatchQueue.main.asyncAfter(deadline: .now() + startDelay) {
      guard token == cycleToken, isActive else { return }

      guard !reduceMotion else {
        indicatorOpacity = 1
        return
      }

      indicatorOpacity = 1
      withAnimation(.easeInOut(duration: expandDuration)) {
        trailingProgress = 1
      }

      DispatchQueue.main.asyncAfter(deadline: .now() + expandDuration) {
        guard token == cycleToken, isActive else { return }
        withAnimation(.easeInOut(duration: collapseDuration)) {
          leadingProgress = 1
        }
      }

      DispatchQueue.main.asyncAfter(deadline: .now() + expandDuration + collapseDuration) {
        guard token == cycleToken, isActive else { return }
        withAnimation(.easeOut(duration: fadeOutDuration)) {
          indicatorOpacity = 0
        }
      }
    }
  }
}

/// Compact earnings display used in the simulator toolbar.
struct PreAuthSimulatorToolbarTotals: View {
  let totals: CalendarHeaderTotals?
  let baselinePrimary: Double?
  let showDelta: Bool

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var lastDisplayedPrimary: Double = 0
  @State private var lastDisplayedSecondary: Double = 0

  var body: some View {
    Group {
      if let totals, let primary = totals.primary {
        VStack(alignment: .trailing, spacing: Spacing.micro) {
          animatedAmount(
            primary,
            lastDisplayed: lastDisplayedPrimary,
            onUpdate: { lastDisplayedPrimary = $0 }
          )
          .font(.tidexHeadline)
          .foregroundColor(.tidexTextPrimary)

          if let delta = deltaAmount {
            HStack(alignment: .center, spacing: Spacing.xxxs) {
              Image(systemName: "plus")
                .font(.caption2.weight(.bold))
                .accessibilityHidden(true)

              animatedAmount(
                delta,
                lastDisplayed: lastDisplayedSecondary,
                onUpdate: { lastDisplayedSecondary = $0 }
              )
              .font(.tidexFootnote)
            }
            .foregroundColor(.tidexBlueText)
            .transition(reduceMotion ? .opacity : .offset(y: -4).combined(with: .opacity))
          }
        }
        .accessibilityElement(children: .combine)
        .transition(reduceMotion ? .opacity : .offset(x: 6).combined(with: .opacity))
      }
    }
    .animation(
      reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.86), value: totals?.primary
    )
    .animation(
      reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.86), value: deltaAmount
    )
  }

  private var deltaAmount: Double? {
    guard showDelta, let currentPrimary = totals?.primary, let baselinePrimary else { return nil }
    let delta = max(currentPrimary - baselinePrimary, 0)
    return delta > 0 ? delta : nil
  }

  @ViewBuilder
  private func animatedAmount(
    _ amount: Double?,
    lastDisplayed: Double,
    onUpdate: @escaping (Double) -> Void
  ) -> some View {
    if let amount, amount > 0 {
      CurrencyCountUpText(
        amount: amount,
        animateOnAppear: false,
        animateFrom: lastDisplayed > 0 ? lastDisplayed : nil
      )
      .onChange(of: amount) { _, newValue in
        onUpdate(newValue)
      }
      .onAppear {
        if lastDisplayed == 0 {
          onUpdate(amount)
        }
      }
    }
  }
}
