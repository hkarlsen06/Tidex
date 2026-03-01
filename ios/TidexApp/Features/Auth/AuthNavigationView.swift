import SwiftUI

/// Navigation container for all authentication screens
/// Handles routing between login, signup, and reset password flows
struct AuthNavigationView: View {
  let initialScreen: AuthScreen

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var currentScreen: AuthScreen

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
            onNavigateToSignup: { navigateTo(.signup) },
            onNavigateToResetPassword: { navigateTo(.resetPassword) }
          )
          .transition(
            MotionTokens.mirroredMoveTransition(edge: .leading, reduceMotion: reduceMotion))

        case .signup:
          SignupView(
            onNavigateToLogin: { navigateTo(.login) }
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
}

#Preview {
  AuthNavigationView()
}
