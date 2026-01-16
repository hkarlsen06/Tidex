import SwiftUI

/// Pre-auth onboarding flow container (Screens 1-4)
/// Shows value proposition before requiring authentication
struct OnboardingView: View {
    let onComplete: () -> Void
    let onNavigateToSignup: () -> Void
    let onNavigateToLogin: () -> Void

    @Environment(\.localization) private var localization
    @State private var currentPage = 0

    private let totalPages = 4

    var body: some View {
        ZStack {
            // Background
            Color.tidexBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Skip button (top-right)
                HStack {
                    Spacer()
                    if currentPage < totalPages - 1 {
                        Button {
                            // Skip to Get Started screen
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                currentPage = totalPages - 1
                            }
                        } label: {
                            Text(localization.string("onboarding.skip"))
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.tidexTextMuted)
                        }
                        .padding(.trailing, 24)
                        .padding(.top, 16)
                    }
                }
                .frame(height: 50)

                // Page content
                TabView(selection: $currentPage) {
                    WelcomeScreen()
                        .tag(0)

                    SamplePaycheckScreen()
                        .tag(1)

                    HowItWorksScreen()
                        .tag(2)

                    GetStartedScreen(
                        onCreateAccount: {
                            onComplete()
                            onNavigateToSignup()
                        },
                        onLogin: {
                            onComplete()
                            onNavigateToLogin()
                        }
                    )
                    .tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: currentPage)

                // Page indicator and continue button
                VStack(spacing: 20) {
                    PageIndicator(totalPages: totalPages, currentPage: currentPage)

                    if currentPage < totalPages - 1 {
                        OnboardingButton(
                            title: localization.string("common.continue"),
                            action: {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    currentPage += 1
                                }
                            }
                        )
                        .padding(.horizontal, 24)
                    }
                }
                .padding(.bottom, 32)
            }
        }
    }
}

#Preview {
    OnboardingView(
        onComplete: {},
        onNavigateToSignup: {},
        onNavigateToLogin: {}
    )
    .environment(\.localization, LocalizationManager.shared)
}
