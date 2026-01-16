import SwiftUI
import UIKit

/// Animated text that counts up from 0 to a target value on first appear.
/// After initial animation, updates instantly to track value changes.
/// Includes proper VoiceOver handling.
///
/// Usage:
/// ```swift
/// // Basic usage with custom format
/// CountUpText(targetValue: 1234, format: { "\($0, specifier: "%.0f") pts" })
///
/// // Currency convenience wrapper
/// CurrencyCountUpText(amount: 24650)
///     .font(.system(size: 48, weight: .bold))
/// ```
struct CountUpText: View {
    let targetValue: Double
    let duration: Double
    let format: (Double) -> String

    @State private var displayedValue: Double = 0
    @State private var hasCompletedInitialAnimation: Bool = false
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
            .contentTransition(.numericText())
            .accessibilityLabel(format(targetValue))
            .onAppear {
                startInitialAnimation()
            }
            .onChange(of: targetValue) { _, newValue in
                if hasCompletedInitialAnimation {
                    // After initial animation, just track the value directly
                    withAnimation(.easeOut(duration: 0.15)) {
                        displayedValue = newValue
                    }
                }
            }
    }

    private func startInitialAnimation() {
        let startTime = Date()
        let currentAnimationId = animationId

        // Count up from 0 to target on first appear
        Timer.scheduledTimer(withTimeInterval: 1/60, repeats: true) { timer in
            guard currentAnimationId == animationId else {
                timer.invalidate()
                return
            }

            let elapsed = Date().timeIntervalSince(startTime)
            let progress = min(elapsed / duration, 1.0)

            // Ease-out curve
            let easedProgress = 1 - pow(1 - progress, 3)

            displayedValue = targetValue * easedProgress

            if progress >= 1.0 {
                timer.invalidate()
                displayedValue = targetValue
                hasCompletedInitialAnimation = true

                // Announce final value for VoiceOver
                UIAccessibility.post(
                    notification: .announcement,
                    argument: format(targetValue)
                )
            }
        }
    }
}

/// Currency-formatted count-up text with locale-aware formatting
/// Norwegian locale: "24 380 kr"
/// English locale: "$24,380"
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
            format: { Self.formatCurrency($0, locale: localization.currentLocale) }
        )
    }

    /// Format currency based on locale
    /// Norwegian: number + " kr" (e.g., "24 380 kr")
    /// English: "$" + number (e.g., "$24,380")
    static func formatCurrency(_ value: Double, locale: LocalizationManager.AppLocale) -> String {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 0

        switch locale {
        case .norwegian:
            formatter.numberStyle = .decimal
            formatter.locale = Locale(identifier: "nb_NO")
            let number = formatter.string(from: NSNumber(value: value)) ?? "0"
            return "\(number) kr"
        case .english:
            formatter.numberStyle = .currency
            formatter.currencyCode = "USD"
            formatter.currencySymbol = "$"
            formatter.locale = Locale(identifier: "en_US")
            return formatter.string(from: NSNumber(value: value)) ?? "$0"
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
