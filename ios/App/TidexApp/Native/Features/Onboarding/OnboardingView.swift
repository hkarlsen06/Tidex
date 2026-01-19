import SwiftUI

/// Pre-auth onboarding flow container (Screens 1-4)
/// Shows value proposition before requiring authentication
struct OnboardingView: View {
    let onComplete: () -> Void
    let onNavigateToSignup: () -> Void
    let onNavigateToLogin: () -> Void

    @Environment(\.localization) private var localization
    @State private var currentPage = 0
    @State private var hourlyRate: Double = 0  // Set on appear based on locale
    @State private var hasInitializedRate = false

    private let totalPages = 4

    /// Default hourly rate based on locale
    /// Norwegian: 200 kr/hour, English: $25/hour
    private var defaultHourlyRate: Double {
        localization.currentLocale == .norwegian ? 200 : 25
    }

    var body: some View {
        ZStack {
            // Background
            Color.tidexBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Page content - takes full height, skip button overlaid
                TabView(selection: $currentPage) {
                    WelcomeScreen()
                        .tag(0)

                    SamplePaycheckScreen(hourlyRate: $hourlyRate)
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

                // Bottom controls area - constrained for iPad
                VStack(spacing: 16) {
                    // Hourly rate slider (only on page 2)
                    if currentPage == 1 {
                        OnboardingRateSlider(value: $hourlyRate)
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }

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
                    }
                }
                .padding(.horizontal, 24)
                .adaptiveContentWidth()
                .padding(.bottom, 32)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: currentPage)
            }

            // Skip button overlaid at top-right (only on first page)
            VStack {
                HStack {
                    Spacer()
                    if currentPage == 0 {
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                currentPage = totalPages - 1
                            }
                        } label: {
                            Text(localization.string("onboarding.skip"))
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.tidexTextSecondary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                        }
                        .glassEffect(.regular.interactive(), in: .capsule)
                        .padding(.trailing, 24)
                        .padding(.top, 16)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }
                Spacer()
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: currentPage)
        }
        .onAppear {
            // Initialize hourly rate based on locale (only once)
            if !hasInitializedRate {
                hourlyRate = defaultHourlyRate
                hasInitializedRate = true
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
