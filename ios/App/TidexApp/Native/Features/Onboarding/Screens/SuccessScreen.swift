import SwiftUI
import UIKit

/// Screen 6: Success/Ready
/// Confirms setup complete, builds excitement, transitions to app
struct SuccessScreen: View {
    let onComplete: () -> Void

    @Environment(\.localization) private var localization
    @State private var checkmarkScale: CGFloat = 0.0
    @State private var checkmarkOpacity: Double = 0.0
    @State private var contentVisible = false

    var body: some View {
        ZStack {
            // Background
            Color.tidexBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Animated checkmark
                checkmarkAnimation

                Spacer()
                    .frame(height: 32)

                // Header and content
                VStack(spacing: 12) {
                    Text(localization.string("onboarding.success.title"))
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.tidexTextPrimary)
                        .multilineTextAlignment(.center)

                    Text(localization.string("onboarding.success.subtitle"))
                        .font(.system(size: 17))
                        .foregroundColor(.tidexTextSecondary)
                        .multilineTextAlignment(.center)

                    Spacer()
                        .frame(height: 8)

                    // Reassurance line
                    Text(localization.string("onboarding.success.reassurance"))
                        .font(.system(size: 14))
                        .foregroundColor(.tidexTextMuted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }
                .padding(.horizontal, 32)
                .opacity(contentVisible ? 1 : 0)
                .offset(y: contentVisible ? 0 : 20)

                Spacer()

                // Go to Dashboard button
                OnboardingButton(
                    title: localization.string("onboarding.success.button"),
                    action: {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        onComplete()
                    }
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
                .opacity(contentVisible ? 1 : 0)
            }
        }
        .onAppear {
            startAnimations()
        }
    }

    // MARK: - Checkmark Animation

    @ViewBuilder
    private var checkmarkAnimation: some View {
        ZStack {
            // Background circle
            Circle()
                .fill(Color.tidexSuccess.opacity(0.15))
                .frame(width: 120, height: 120)
                .scaleEffect(checkmarkScale)

            // Checkmark icon
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.tidexSuccess)
                .scaleEffect(checkmarkScale)
                .opacity(checkmarkOpacity)
        }
    }

    // MARK: - Animation Sequence

    private func startAnimations() {
        // Checkmark draw and scale animation
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6).delay(0.1)) {
            checkmarkScale = 1.1
            checkmarkOpacity = 1.0
        }

        // Settle to normal scale
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8).delay(0.4)) {
            checkmarkScale = 1.0
        }

        // Show content
        withAnimation(.easeOut(duration: 0.3).delay(0.5)) {
            contentVisible = true
        }

        // Success haptic
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}

#Preview {
    SuccessScreen {
        print("Completed!")
    }
    .environment(\.localization, LocalizationManager.shared)
}
