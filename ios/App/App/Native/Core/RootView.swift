import SwiftUI

/// Root view that manages the app's navigation based on authentication state
/// Handles transitions between: Loading -> Login -> MFA -> Dashboard
struct RootView: View {
    @StateObject private var coordinator = AppCoordinator.shared
    @StateObject private var localization = LocalizationManager.shared

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
                    LoginView()
                        .transition(.opacity)

                case .mfaRequired:
                    if let factor = coordinator.pendingMFAFactor {
                        MFAVerifyView(factor: factor, coordinator: coordinator)
                            .transition(.opacity)
                    } else {
                        // Fallback - shouldn't happen
                        LoginView()
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
struct LoadingView: View {
    var body: some View {
        VStack(spacing: 24) {
            // Logo
            LogoWatermark(opacity: 1.0)
                .frame(width: 80, height: 80)

            // App name
            Text("Tidex")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.tidexTextPrimary)

            // Loading indicator
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .tidexBlue))
                .scaleEffect(1.2)

            Text("Loading...")
                .font(.system(size: 14))
                .foregroundColor(.tidexTextMuted)
        }
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
