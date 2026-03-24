import SwiftUI

/// Navigation container for all authentication screens
/// Handles routing between login, signup, and reset password flows
struct AuthNavigationView: View {
  let initialScreen: AuthScreen

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var currentScreen: AuthScreen
  @StateObject private var loginViewModel = LoginViewModel()
  @StateObject private var signupViewModel = SignupViewModel()

  enum AuthScreen {
    case login
    case signup
    case resetPassword
  }

  init(initialScreen: AuthScreen = .login) {
    self.initialScreen = initialScreen
    self._currentScreen = State(initialValue: initialScreen)
  }

  var body: some View {
    ZStack {
      // Background - adapts to system appearance
      Color.tidexBackground
        .ignoresSafeArea()

      // Current screen with transition
      Group {
        switch currentScreen {
        case .login:
          LoginView(
            viewModel: loginViewModel,
            onNavigateToSignup: { navigateToSignup() },
            onNavigateToResetPassword: { navigateTo(.resetPassword) }
          )
          .transition(
            MotionTokens.mirroredMoveTransition(edge: .leading, reduceMotion: reduceMotion))

        case .signup:
          SignupView(
            viewModel: signupViewModel,
            onNavigateToLogin: { navigateToLoginFromSignup() }
          )
          .transition(
            MotionTokens.mirroredMoveTransition(edge: .trailing, reduceMotion: reduceMotion))

        case .resetPassword:
          ResetPasswordView(
            onNavigateToLogin: { navigateTo(.login) }
          )
          .transition(
            MotionTokens.mirroredMoveTransition(edge: .trailing, reduceMotion: reduceMotion))
        }
      }
    }
    .motionAnimation(.navigationPush, value: currentScreen, reduceMotion: reduceMotion)
  }

  private func navigateTo(_ screen: AuthScreen) {
    currentScreen = screen
  }

  private func navigateToSignup() {
    signupViewModel.applyLoginPrefill(
      emailOrPhone: loginViewModel.emailOrPhone,
      password: loginViewModel.password
    )
    navigateTo(.signup)
  }

  private func navigateToLoginFromSignup() {
    loginViewModel.applySignupPrefill(
      emailOrPhone: signupViewModel.emailOrPhone,
      password: signupViewModel.password
    )
    navigateTo(.login)
  }
}

#Preview {
  AuthNavigationView()
}
