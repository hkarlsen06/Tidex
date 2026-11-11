import SwiftUI

/// Pre-auth onboarding: the welcome page, then the Add screen demo. Each page draws its own
/// header and buttons, so a page change moves them with the page.
struct OnboardingView: View {
  /// Gets the demo shift when the user saved one, nil when they skipped.
  let onNavigateToSignup: (PreAuthDemoShift?) -> Void
  var onNavigateToLogin: () -> Void = {}

  private enum Page {
    case welcome
    case demo

    var funnelStep: String {
      switch self {
      case .welcome: "welcome"
      case .demo: "add_shift_simulator"
      }
    }
  }

  /// Set when the user leaves for sign-up. The pages fade out before the hand-off.
  private struct Exit: Equatable {
    let shift: PreAuthDemoShift?
  }

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var page = Page.welcome
  @State private var exit: Exit?
  @State private var currency: String =
    OnboardingCurrencyCarryoverStore.readValidPreferredCurrency()
    ?? OnboardingCurrencyResolver.detectDefaultCurrency()

  var body: some View {
    ZStack {
      Color.tidexBackground
        .ignoresSafeArea()

      switch page {
      case .welcome:
        WelcomeScreen(
          currency: Binding(get: { currency }, set: setCurrency),
          onContinue: { show(.demo) },
          onLogin: onNavigateToLogin
        )
        .transition(MotionTokens.mirroredMoveTransition(edge: .leading, reduceMotion: reduceMotion))

      case .demo:
        PreAuthAddShiftSimulatorScreen(
          initialCurrency: currency,
          onCurrencyChanged: setCurrency,
          onSave: { shift in
            OnboardingFunnelRecorder.shared.recordPreAuth("demo_shift_added")
            leave(with: shift)
          },
          onSkip: {
            OnboardingFunnelRecorder.shared.recordPreAuth("demo_skipped")
            OnboardingFirstShiftCarryoverStore.clear()
            leave(with: nil)
          },
          onBack: { show(.welcome) }
        )
        .transition(MotionTokens.mirroredMoveTransition(edge: .trailing, reduceMotion: reduceMotion))
      }
    }
    .opacity(exit == nil ? 1 : 0)
    .motionAnimation(.emphasis, value: exit, reduceMotion: reduceMotion)
    .allowsHitTesting(exit == nil)
    .task(id: exit) {
      guard let exit else { return }
      do { try await Task.sleep(for: .seconds(0.32)) } catch { return }
      onNavigateToSignup(exit.shift)
    }
    .onAppear {
      OnboardingCurrencyCarryoverStore.writePreferredCurrency(currency)
      OnboardingFunnelRecorder.shared.recordPreAuth(page.funnelStep)
    }
    .onChange(of: page) { _, newPage in
      OnboardingFunnelRecorder.shared.recordPreAuth(newPage.funnelStep)
    }
  }

  private func show(_ newPage: Page) {
    MotionTokens.animate(.pageTransition, reduceMotion: reduceMotion) {
      page = newPage
    }
  }

  private func setCurrency(_ newCurrency: String) {
    guard newCurrency != currency else { return }
    currency = newCurrency
    OnboardingCurrencyCarryoverStore.writePreferredCurrency(newCurrency)
  }

  private func leave(with shift: PreAuthDemoShift?) {
    guard exit == nil else { return }
    guard !reduceMotion else {
      onNavigateToSignup(shift)
      return
    }
    exit = Exit(shift: shift)
  }
}

#Preview {
  OnboardingView(onNavigateToSignup: { _ in })
}
