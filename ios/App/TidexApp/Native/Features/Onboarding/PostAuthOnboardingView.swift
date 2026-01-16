import SwiftUI
import Supabase

/// Post-auth onboarding flow container (Screens 5-6)
/// Shows personalization and success after authentication
struct PostAuthOnboardingView: View {
    let onComplete: () -> Void
    let userId: String

    @Environment(\.localization) private var localization
    @State private var currentScreen: PostAuthScreen = .personalization

    enum PostAuthScreen {
        case personalization
        case success
    }

    var body: some View {
        ZStack {
            // Background
            Color.tidexBackground
                .ignoresSafeArea()

            // Current screen with transition
            Group {
                switch currentScreen {
                case .personalization:
                    PersonalizationScreen(
                        onComplete: { wage, payrollDay in
                            savePersonalization(wage: wage, payrollDay: payrollDay)
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                currentScreen = .success
                            }
                        }
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))

                case .success:
                    SuccessScreen(onComplete: onComplete)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .opacity
                        ))
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: currentScreen)
    }

    // MARK: - Save Personalization

    private func savePersonalization(wage: Double, payrollDay: Int) {
        // Save to UserDefaults for immediate use (will sync with full settings flow later)
        UserDefaults.standard.set(wage, forKey: "onboarding_hourly_wage")
        UserDefaults.standard.set(payrollDay, forKey: "onboarding_payroll_day")

        // Try to update settings repository if user has synced settings
        Task { @MainActor in
            do {
                _ = try await SettingsRepository.shared.updateSettings(
                    for: userId,
                    payrollDay: payrollDay
                )
            } catch {
                // Silently fail - will be set up properly in full settings flow
                print("[PostAuthOnboarding] Could not update settings: \(error)")
            }

            // Mark onboarding as finished in Supabase user metadata
            await markOnboardingFinishedInMetadata()
        }
    }

    // MARK: - Update User Metadata

    /// Updates the user's Supabase metadata to mark onboarding as finished
    /// This ensures the flag persists across devices/reinstalls
    private func markOnboardingFinishedInMetadata() async {
        do {
            _ = try await supabase.auth.update(
                user: UserAttributes(
                    data: ["finishedOnboarding": .bool(true)]
                )
            )
            print("[PostAuthOnboarding] Successfully marked finishedOnboarding in user metadata")
        } catch {
            // Non-critical error - local AppStorage will still work
            print("[PostAuthOnboarding] Could not update user metadata: \(error)")
        }
    }
}

#Preview {
    PostAuthOnboardingView(
        onComplete: {},
        userId: "test-user-id"
    )
    .environment(\.localization, LocalizationManager.shared)
}
