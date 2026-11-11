#if DEBUG
  import SwiftUI

  /// Welcome, the demo, then sign-up with the shift the demo saved, as RootView wires them.
  /// `startsAtSignup` opens sign-up with a fixed demo shift.
  struct DesignReviewPreAuthFlow: View {
    @State private var signupModel = SignupViewModel()
    /// Set on reaching sign-up. The inner value is the saved shift, nil after Skip.
    @State private var exit: PreAuthDemoShift??

    init(startsAtSignup: Bool) {
      _exit = State(
        initialValue: startsAtSignup
          ? .some(
            PreAuthDemoShift(
              dates: [
                "2026-11-13", "2026-11-14", "2026-11-20", "2026-11-21", "2026-11-27", "2026-11-28",
              ],
              startTime: "10:00", endTime: "18:00"))
          : nil)
    }

    var body: some View {
      if let exit {
        SignupView(viewModel: signupModel, currency: "kr", demoShift: exit)
      } else {
        OnboardingView(onNavigateToSignup: { exit = .some($0) }, onNavigateToLogin: {})
      }
    }
  }
#endif
