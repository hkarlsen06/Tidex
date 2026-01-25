import SwiftUI
import UIKit

/// Screen for setting up user profile (name) during onboarding
/// Shown for users who don't have a name set (e.g., Apple Sign-In users)
struct ProfileSetupScreen: View {
    @Bindable var data: OnboardingData
    let onContinue: () -> Void

    @Environment(\.localization) private var localization
    @FocusState private var isNameFieldFocused: Bool

    /// Whether the continue button should be enabled
    private var canContinue: Bool {
        !data.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            // Background
            Color.tidexBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer()
                            .frame(height: 60)

                        // Waving hand icon
                        ZStack {
                            Circle()
                                .fill(Color.tidexBlue.opacity(0.1))
                                .frame(width: 100, height: 100)

                            Text("\u{1F44B}")
                                .font(.system(size: 48))
                        }
                        .padding(.bottom, 32)

                        // Header
                        VStack(spacing: 12) {
                            Text(localization.string("onboarding.profile.title"))
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(.tidexTextPrimary)
                                .multilineTextAlignment(.center)

                            Text(localization.string("onboarding.profile.subtitle"))
                                .font(.system(size: 17))
                                .foregroundColor(.tidexTextSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 32)
                        .adaptiveContentWidth()

                        Spacer()
                            .frame(height: 40)

                        // Name input field
                        VStack(alignment: .leading, spacing: 8) {
                            Text(localization.string("onboarding.profile.nameLabel"))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.tidexTextSecondary)

                            TextField(
                                localization.string("onboarding.profile.namePlaceholder"),
                                text: $data.displayName
                            )
                            .font(.system(size: 17))
                            .foregroundColor(.tidexTextPrimary)
                            .padding(16)
                            .background(Color.tidexSurfaceSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(isNameFieldFocused ? Color.tidexBlue : Color.tidexBorder, lineWidth: isNameFieldFocused ? 2 : 1)
                            )
                            .focused($isNameFieldFocused)
                            .textContentType(.name)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .onSubmit {
                                if canContinue {
                                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                                    onContinue()
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                        .adaptiveContentWidth()

                        // Bottom padding to account for fixed button
                        Spacer()
                            .frame(height: 120)
                    }
                }
                .scrollDismissesKeyboard(.interactively)

                // Fixed continue button at bottom
                VStack(spacing: 0) {
                    // Gradient fade
                    LinearGradient(
                        colors: [Color.tidexBackground.opacity(0), Color.tidexBackground],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 24)

                    OnboardingButton(
                        title: localization.string("common.continue"),
                        isEnabled: canContinue,
                        action: {
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            onContinue()
                        }
                    )
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                    .adaptiveContentWidth()
                    .background(Color.tidexBackground)
                }
            }
        }
        .onAppear {
            // Focus the name field when the screen appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isNameFieldFocused = true
            }
        }
    }
}

#Preview {
    ProfileSetupScreen(data: OnboardingData(), onContinue: {})
        .environment(\.localization, LocalizationManager.shared)
}
