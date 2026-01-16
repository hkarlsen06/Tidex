import SwiftUI
import UIKit

/// Animated text that counts up from 0 to a target value
/// Includes proper VoiceOver handling to prevent stuttering
struct CountUpText: View {
    let targetValue: Double
    let duration: Double
    let format: (Double) -> String

    @State private var displayedValue: Double = 0
    @State private var isAnimating: Bool = true
    @State private var animationId = UUID()

    init(
        targetValue: Double,
        duration: Double = 0.8,
        format: @escaping (Double) -> String = { String(format: "%.0f", $0) }
    ) {
        self.targetValue = targetValue
        self.duration = duration
        self.format = format
    }

    var body: some View {
        Text(format(displayedValue))
            .accessibilityHidden(isAnimating)
            .onAppear {
                startAnimation()
            }
            .onChange(of: targetValue) { _, newValue in
                // Restart animation with new target
                animationId = UUID()
                displayedValue = 0
                isAnimating = true
                startAnimation()
            }
            .onChange(of: isAnimating) { _, newValue in
                if !newValue {
                    // Animation completed - announce final value
                    UIAccessibility.post(
                        notification: .announcement,
                        argument: format(targetValue)
                    )
                }
            }
    }

    private func startAnimation() {
        let startTime = Date()
        let currentAnimationId = animationId

        // Use DisplayLink timing for smooth animation
        Timer.scheduledTimer(withTimeInterval: 1/60, repeats: true) { timer in
            // Check if animation was cancelled
            guard currentAnimationId == animationId else {
                timer.invalidate()
                return
            }

            let elapsed = Date().timeIntervalSince(startTime)
            let progress = min(elapsed / duration, 1.0)

            // Ease-out curve
            let easedProgress = 1 - pow(1 - progress, 3)

            withAnimation(.linear(duration: 0.016)) {
                displayedValue = targetValue * easedProgress
            }

            if progress >= 1.0 {
                timer.invalidate()
                displayedValue = targetValue
                isAnimating = false
            }
        }
    }
}

/// Currency-formatted count-up text
struct CurrencyCountUpText: View {
    let amount: Double
    let duration: Double

    @Environment(\.localization) private var localization

    init(amount: Double, duration: Double = 0.8) {
        self.amount = amount
        self.duration = duration
    }

    var body: some View {
        CountUpText(
            targetValue: amount,
            duration: duration,
            format: formatCurrency
        )
    }

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "NOK"
        formatter.currencySymbol = "kr "
        formatter.maximumFractionDigits = 0
        formatter.locale = Locale(identifier: "nb_NO")
        return formatter.string(from: NSNumber(value: value)) ?? "kr 0"
    }
}

#Preview {
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
