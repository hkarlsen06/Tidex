import SwiftUI

/// Animated text where each digit rolls/scrolls into place.
/// Matches the AnimateNumber React component behavior exactly.
///
/// Usage:
/// ```swift
/// CurrencyCountUpText(amount: 24650)
///     .font(.system(size: 48, weight: .bold))
/// ```
struct CountUpText: View {
  let targetValue: Double
  let duration: Double
  let format: (Double) -> String
  let animateOnAppear: Bool
  let animateChanges: Bool

  init(
    targetValue: Double,
    duration: Double = 1.0,
    animateOnAppear: Bool = true,
    animateChanges: Bool = true,
    format: @escaping (Double) -> String = { String(format: "%.0f", $0) }
  ) {
    self.targetValue = targetValue
    self.duration = duration
    self.animateOnAppear = animateOnAppear
    self.animateChanges = animateChanges
    self.format = format
  }

  private var formattedText: String {
    format(targetValue)
  }

  var body: some View {
    HStack(spacing: 0) {
      ForEach(Array(formattedText.enumerated()), id: \.offset) { index, character in
        if character.isNumber, let digit = Int(String(character)) {
          RollingDigit(
            digit: digit,
            duration: duration,
            animateOnAppear: animateOnAppear,
            animateChanges: animateChanges
          )
        } else {
          // Non-digit characters (currency symbols, separators, spaces)
          Text(String(character))
            .monospacedDigit()  // Ensures consistent spacing
        }
      }
    }
    // Keep character order stable in RTL so number + currency stays in string order.
    .environment(\.layoutDirection, .leftToRight)
    .monospacedDigit()  // Apply tabular figures for consistent digit widths
    .accessibilityLabel(formattedText)
  }
}

/// Single digit that rolls to the target digit using TimelineView for smooth animation
private struct RollingDigit: View {
  let digit: Int
  let duration: Double
  let animateOnAppear: Bool
  let animateChanges: Bool

  /// Animation start time
  @State private var animationStart: Date?
  /// Starting digit for current animation
  @State private var fromDigit: CGFloat = 0
  /// Target digit for current animation
  @State private var toDigit: CGFloat = 0
  /// Whether we've completed initial setup
  @State private var didSetup = false

  /// All digits 0-9 for the rolling column
  private let digits = Array(0...9)

  var body: some View {
    // Hidden "0" to establish the frame size (with monospaced digits for consistent width)
    Text("0")
      .monospacedDigit()
      .hidden()
      .overlay {
        TimelineView(.animation(paused: animationStart == nil)) { timeline in
          GeometryReader { geometry in
            let progress = calculateProgress(at: timeline.date)
            let currentDigit = fromDigit + (toDigit - fromDigit) * progress

            VStack(spacing: 0) {
              ForEach(digits, id: \.self) { d in
                Text("\(d)")
                  .monospacedDigit()
                  .frame(height: geometry.size.height)
              }
            }
            .offset(y: -currentDigit * geometry.size.height)
          }
        }
        .clipped()
      }
      .onAppear {
        guard !didSetup else { return }
        didSetup = true

        if animateOnAppear {
          fromDigit = 0
          toDigit = CGFloat(digit)
          // Small delay to let app settle
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            animationStart = Date()
          }
        } else {
          fromDigit = CGFloat(digit)
          toDigit = CGFloat(digit)
        }
      }
      .onChange(of: digit) { _, newValue in
        if animateChanges {
          fromDigit = toDigit
          toDigit = CGFloat(newValue)
          animationStart = Date()
        } else {
          fromDigit = CGFloat(newValue)
          toDigit = CGFloat(newValue)
          animationStart = nil
        }
      }
  }

  /// Calculate eased progress with critically damped spring (normalized to reach 1.0)
  private func calculateProgress(at date: Date) -> CGFloat {
    guard let start = animationStart else { return 1 }

    let elapsed = date.timeIntervalSince(start)
    let rawProgress = min(elapsed / duration, 1.0)

    // Critically damped spring, normalized to reach exactly 1.0 at end
    let omega: CGFloat = 6.0
    let t = rawProgress * omega
    let springRaw = 1 - (1 + t) * exp(-t)
    // Normalize: at t=omega, spring reaches ~0.9826 for omega=6
    let finalValue: CGFloat = 1 - (1 + omega) * exp(-omega)
    let eased = springRaw / finalValue

    // Stop the timeline when complete
    if rawProgress >= 1.0 {
      DispatchQueue.main.async {
        animationStart = nil
      }
    }

    return eased
  }
}

/// Currency-formatted rolling text using the user's selected currency
/// Uses SwiftUI's built-in content transition for smooth digit animations
struct CurrencyCountUpText: View {
  let amount: Double
  let duration: Double
  let animateOnAppear: Bool
  let animateChanges: Bool
  /// Optional starting value to animate FROM (useful when view may be recreated)
  let animateFrom: Double?

  @Environment(\.userCurrency) private var currency

  /// Track the displayed amount for animation
  @State private var displayedAmount: Double?
  /// Track if this is the initial appear
  @State private var hasAppeared = false

  init(
    amount: Double,
    duration: Double = 1.0,
    animateOnAppear: Bool = true,
    animateChanges: Bool = true,
    animateFrom: Double? = nil
  ) {
    self.amount = amount
    self.duration = duration
    self.animateOnAppear = animateOnAppear
    self.animateChanges = animateChanges
    self.animateFrom = animateFrom
  }

  private var formattedText: String {
    CurrencyConfig.format(displayedAmount ?? amount, currency: currency)
  }

  private func formattedText(for amount: Double) -> String {
    CurrencyConfig.format(amount, currency: currency)
  }

  var body: some View {
    Text(formattedText)
      .contentTransition(.numericText(value: displayedAmount ?? amount))
      .accessibilityLabel(CurrencyConfig.format(amount, currency: currency))
      .onAppear {
        if !hasAppeared {
          hasAppeared = true
          // Use animateFrom if provided (for recreated views), otherwise 0 or immediate
          let startValue = animateFrom ?? (animateOnAppear ? 0 : amount)
          if animateOnAppear || animateFrom != nil {
            displayedAmount = startValue
            // Only animate if we're not already at the target
            if startValue != amount {
              withAnimation(.spring(duration: duration, bounce: 0).delay(0.05)) {
                displayedAmount = amount
              }
            }
          } else {
            displayedAmount = amount
          }
        }
      }
      .onChange(of: amount) { _, newValue in
        guard formattedText(for: displayedAmount ?? amount) != formattedText(for: newValue) else {
          var transaction = Transaction()
          transaction.animation = nil
          withTransaction(transaction) {
            displayedAmount = newValue
          }
          return
        }

        if animateChanges {
          withAnimation(.spring(duration: duration, bounce: 0)) {
            displayedAmount = newValue
          }
        } else {
          displayedAmount = newValue
        }
      }
  }
}

// MARK: - Previews

#Preview("Currency") {
  VStack(spacing: Spacing.lg) {
    CurrencyCountUpText(amount: 24650)
      .font(.system(size: 48, weight: .bold))
      .foregroundColor(.tidexBlue)

    CurrencyCountUpText(amount: 31200)
      .font(.system(size: 48, weight: .bold))
      .foregroundColor(.tidexSuccess)
  }
  .padding()
  .background(Color.tidexBackground)
}

#Preview("Custom Format") {
  VStack(spacing: Spacing.lg) {
    CountUpText(targetValue: 142.5, format: { String(format: "%.1f timer", $0) })
      .font(.system(size: 32, weight: .semibold))
      .foregroundColor(.tidexTextPrimary)

    CountUpText(targetValue: 28, format: { String(format: "%.0f vakter", $0) })
      .font(.system(size: 32, weight: .semibold))
      .foregroundColor(.tidexTextPrimary)
  }
  .padding()
  .background(Color.tidexBackground)
}

#Preview("Large Number") {
  CurrencyCountUpText(amount: 156789)
    .font(.system(size: 72, weight: .bold))
    .foregroundColor(.tidexBlue)
    .padding()
    .background(Color.tidexBackground)
}

#Preview("Value Changes") {
  struct ValueChangePreview: View {
    @State private var amount: Double = 1234

    var body: some View {
      VStack(spacing: Spacing.lg) {
        CurrencyCountUpText(amount: amount)
          .font(.system(size: 48, weight: .bold))
          .foregroundColor(.tidexBlue)

        HStack(spacing: Spacing.md) {
          Button("-500") { amount = max(0, amount - 500) }
          Button("+500") { amount += 500 }
          Button("Random") { amount = Double.random(in: 1000...50000) }
        }
        .buttonStyle(.bordered)
      }
      .padding()
      .background(Color.tidexBackground)
    }
  }

  return ValueChangePreview()
}
