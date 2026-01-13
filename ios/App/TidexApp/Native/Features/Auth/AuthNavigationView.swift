import SwiftUI

/// Navigation container for all authentication screens
/// Handles routing between login, signup, and reset password flows
struct AuthNavigationView: View {
    @State private var currentScreen: AuthScreen = .login

    enum AuthScreen {
        case login
        case signup
        case resetPassword
    }

    var body: some View {
        ZStack {
            // Background
            Color.tidexDarkBackground
                .ignoresSafeArea()

            // Current screen with transition
            Group {
                switch currentScreen {
                case .login:
                    LoginView(
                        onNavigateToSignup: { navigateTo(.signup) },
                        onNavigateToResetPassword: { navigateTo(.resetPassword) }
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))

                case .signup:
                    SignupView(
                        onNavigateToLogin: { navigateTo(.login) }
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))

                case .resetPassword:
                    ResetPasswordView(
                        onNavigateToLogin: { navigateTo(.login) }
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: currentScreen)
    }

    private func navigateTo(_ screen: AuthScreen) {
        currentScreen = screen
    }
}

#Preview {
    AuthNavigationView()
        .environment(\.localization, LocalizationManager.shared)
}
