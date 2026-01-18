import SwiftUI

/// Root view that manages the app's navigation based on authentication state
/// Handles transitions between: Loading -> Onboarding -> Login -> MFA -> Post-Auth Onboarding -> Dashboard
struct RootView: View {
    // Note: Using @ObservedObject for singletons as @StateObject is meant for owned instances
    @ObservedObject private var coordinator = AppCoordinator.shared
    @ObservedObject private var localization = LocalizationManager.shared

    // Onboarding state - explicit naming for two-phase onboarding
    @AppStorage("hasCompletedPreAuthOnboarding") private var hasCompletedPreAuthOnboarding = false
    @AppStorage("hasCompletedPostAuthOnboarding") private var hasCompletedPostAuthOnboarding = false

    // Navigation state for transitioning from onboarding to auth
    @State private var showAuthAfterOnboarding = false
    @State private var authDestination: AuthDestination = .login

    enum AuthDestination {
        case login
        case signup
    }

    var body: some View {
        ZStack {
            // Background - adapts to system appearance
            // Uses tidexBackground (adaptive) for main content areas
            Color.tidexBackground
                .ignoresSafeArea()

            // Content based on app state
            Group {
                switch coordinator.appState {
                case .loading:
                    LoadingView()

                case .unauthenticated:
                    if !hasCompletedPreAuthOnboarding && !showAuthAfterOnboarding {
                        // Show pre-auth onboarding (screens 1-4)
                        OnboardingView(
                            onComplete: {
                                hasCompletedPreAuthOnboarding = true
                            },
                            onNavigateToSignup: {
                                authDestination = .signup
                                showAuthAfterOnboarding = true
                            },
                            onNavigateToLogin: {
                                authDestination = .login
                                showAuthAfterOnboarding = true
                            }
                        )
                        .transition(.opacity)
                    } else {
                        // Show auth navigation with the selected destination
                        AuthNavigationView(initialScreen: authDestination == .signup ? .signup : .login)
                            .transition(.opacity)
                    }

                case .mfaRequired:
                    if let factor = coordinator.pendingMFAFactor {
                        MFAVerifyView(factor: factor, coordinator: coordinator)
                            .transition(.opacity)
                    } else {
                        // Fallback - shouldn't happen
                        AuthNavigationView()
                    }

                case .termsRequired:
                    AcceptTermsView(isUpdate: coordinator.isTermsUpdate, coordinator: coordinator)
                        .transition(.opacity)

                case .authenticated:
                    // Skip post-auth onboarding if already completed locally OR remotely (Supabase user metadata)
                    if !hasCompletedPostAuthOnboarding && !coordinator.hasFinishedOnboardingRemotely {
                        // Show post-auth onboarding (screens 5-6)
                        PostAuthOnboardingView(
                            onComplete: {
                                hasCompletedPostAuthOnboarding = true
                            },
                            userId: coordinator.userId ?? ""
                        )
                        .transition(.opacity)
                    } else {
                        MainTabView()
                            .transition(.opacity)
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: coordinator.appState)
        .animation(.easeInOut(duration: 0.3), value: hasCompletedPreAuthOnboarding)
        .animation(.easeInOut(duration: 0.3), value: hasCompletedPostAuthOnboarding)
        .environmentObject(coordinator)
        .environment(\.localization, localization)
    }
}

// MARK: - Loading View

/// Initial loading view shown while checking authentication state
/// Matches the splash screen exactly, with a spinner below the logo
struct LoadingView: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background - exact match for LaunchScreen.storyboard
                Color.tidexLaunchBackground

                // Logo centered in full screen (ignoring safe areas) - matches storyboard centerX/centerY
                Image("Splash")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 350, height: 350)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)

                // Spinner positioned below the logo
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .tidexBlue))
                    .scaleEffect(1.2)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2 + 220)
            }
        }
        .ignoresSafeArea()
    }
}

#Preview("Root View") {
    RootView()
}

#Preview("Loading View") {
    ZStack {
        Color.tidexBackground.ignoresSafeArea()
        LoadingView()
    }
}
