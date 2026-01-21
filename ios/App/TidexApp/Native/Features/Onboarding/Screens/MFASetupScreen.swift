import SwiftUI
import UIKit

/// Screen for optional MFA enrollment during onboarding
/// Shows benefits and offers setup or skip
struct MFASetupScreen: View {
    let onSetupMFA: () -> Void
    let onSkip: () -> Void
    var onBack: (() -> Void)? = nil

    @Environment(\.localization) private var localization

    var body: some View {
        ZStack {
            // Background
            Color.tidexBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Back button (if provided)
                if let onBack = onBack {
                    HStack {
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            onBack()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 16, weight: .semibold))
                                Text(localization.string("common.back"))
                                    .font(.system(size: 16))
                            }
                            .foregroundColor(.tidexBlue)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .adaptiveContentWidth()
                }

                Spacer()

                // Shield icon
                ZStack {
                    Circle()
                        .fill(Color.tidexBlue.opacity(0.1))
                        .frame(width: 120, height: 120)

                    Image(systemName: "shield.checkered")
                        .font(.system(size: 56))
                        .foregroundColor(.tidexBlue)
                }
                .padding(.bottom, 32)

                // Header
                VStack(spacing: 12) {
                    Text(localization.string("onboarding.mfa.title"))
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.tidexTextPrimary)
                        .multilineTextAlignment(.center)

                    Text(localization.string("onboarding.mfa.subtitle"))
                        .font(.system(size: 17))
                        .foregroundColor(.tidexTextSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)
                .adaptiveContentWidth()

                Spacer()
                    .frame(height: 32)

                // Benefits card
                benefitsCard
                    .padding(.horizontal, 24)
                    .adaptiveContentWidth()

                Spacer()

                // Bottom buttons
                VStack(spacing: 12) {
                    OnboardingButton(
                        title: localization.string("onboarding.mfa.setup"),
                        action: {
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            onSetupMFA()
                        }
                    )

                    Button(action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onSkip()
                    }) {
                        Text(localization.string("onboarding.mfa.skip"))
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.tidexTextSecondary)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
                .adaptiveContentWidth()
            }
        }
    }

    // MARK: - Benefits Card

    @ViewBuilder
    private var benefitsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            BenefitRow(
                icon: "lock.shield",
                title: localization.string("onboarding.mfa.benefit1.title"),
                description: localization.string("onboarding.mfa.benefit1.desc")
            )

            BenefitRow(
                icon: "key.horizontal",
                title: localization.string("onboarding.mfa.benefit2.title"),
                description: localization.string("onboarding.mfa.benefit2.desc")
            )

            BenefitRow(
                icon: "bolt.shield",
                title: localization.string("onboarding.mfa.benefit3.title"),
                description: localization.string("onboarding.mfa.benefit3.desc")
            )
        }
        .padding(20)
        .background(Color.tidexSurfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Benefit Row

private struct BenefitRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(.tidexBlue)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.tidexTextPrimary)

                Text(description)
                    .font(.system(size: 13))
                    .foregroundColor(.tidexTextSecondary)
            }
        }
    }
}

#Preview {
    MFASetupScreen(
        onSetupMFA: {},
        onSkip: {}
    )
    .environment(\.localization, LocalizationManager.shared)
}
