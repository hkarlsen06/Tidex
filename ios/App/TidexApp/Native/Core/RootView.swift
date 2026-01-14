import SwiftUI

/// Root view that manages the app's navigation based on authentication state
/// Handles transitions between: Loading -> Login -> MFA -> Dashboard
struct RootView: View {
    // Note: Using @ObservedObject for singletons as @StateObject is meant for owned instances
    @ObservedObject private var coordinator = AppCoordinator.shared
    @ObservedObject private var localization = LocalizationManager.shared

    var body: some View {
        ZStack {
            // Background - prevents white flash during transitions
            Color.tidexDarkBackground
                .ignoresSafeArea()

            // Content based on app state
            Group {
                switch coordinator.appState {
                case .loading:
                    LoadingView()

                case .unauthenticated:
                    AuthNavigationView()
                        .transition(.opacity)

                case .mfaRequired:
                    if let factor = coordinator.pendingMFAFactor {
                        MFAVerifyView(factor: factor, coordinator: coordinator)
                            .transition(.opacity)
                    } else {
                        // Fallback - shouldn't happen
                        AuthNavigationView()
                    }

                case .authenticated:
                    MainTabView()
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: coordinator.appState)
        .environmentObject(coordinator)
        .environment(\.localization, localization)
        .preferredColorScheme(.dark)
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
        Color.tidexDarkBackground.ignoresSafeArea()
        LoadingView()
    }
}
