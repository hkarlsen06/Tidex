import SwiftUI
import UIKit

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
                        delay: Double(index) * 0.02,
                        animateOnAppear: animateOnAppear,
                        animateChanges: animateChanges
                    )
                } else {
                    // Non-digit characters (currency symbols, separators, spaces)
                    Text(String(character))
                }
            }
        }
        .accessibilityLabel(formattedText)
    }
}

/// Single digit that rolls to the target digit
/// Uses direct animation on offset for reliable value-change animations
private struct RollingDigit: View {
    let digit: Int
    let duration: Double
    let delay: Double
    let animateOnAppear: Bool
    let animateChanges: Bool

    /// Tracks the displayed digit for animation
    @State private var displayedDigit: Int?

    /// All digits 0-9 for the rolling column
    private let digits = Array(0...9)

    /// Mask fade height as percentage of digit height
    private let maskHeightRatio: CGFloat = 0.15

    var body: some View {
        // Hidden "0" to establish the frame size
        Text("0")
            .hidden()
            .overlay {
                GeometryReader { geometry in
                    let digitHeight = geometry.size.height

                    // The digit column with gradient mask
                    ZStack {
                        VStack(spacing: 0) {
                            ForEach(digits, id: \.self) { d in
                                Text("\(d)")
                                    .frame(height: digitHeight)
                            }
                        }
                        // Offset to show the displayed digit
                        .offset(y: -CGFloat(displayedDigit ?? 0) * digitHeight)
                    }
                    // Gradient mask for top/bottom fade (matches AnimateNumber's Mask)
                    .mask(
                        VStack(spacing: 0) {
                            // Top fade
                            LinearGradient(
                                colors: [.clear, .black],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: digitHeight * maskHeightRatio)

                            // Solid middle
                            Rectangle()
                                .fill(.black)

                            // Bottom fade
                            LinearGradient(
                                colors: [.black, .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: digitHeight * maskHeightRatio)
                        }
                    )
                }
                .clipped()
            }
            .onAppear {
                if animateOnAppear {
                    // Start at 0, then animate to target after delay
                    displayedDigit = 0
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05 + delay) {
                        withAnimation(.spring(duration: duration, bounce: 0)) {
                            displayedDigit = digit
                        }
                    }
                } else {
                    displayedDigit = digit
                }
            }
            .onChange(of: digit) { _, newValue in
                if animateChanges {
                    withAnimation(.spring(duration: duration, bounce: 0)) {
                        displayedDigit = newValue
                    }
                } else {
                    displayedDigit = newValue
                }
            }
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
    VStack(spacing: 24) {
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
    VStack(spacing: 24) {
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
            VStack(spacing: 24) {
                CurrencyCountUpText(amount: amount)
                    .font(.system(size: 48, weight: .bold))
                    .foregroundColor(.tidexBlue)

                HStack(spacing: 16) {
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
