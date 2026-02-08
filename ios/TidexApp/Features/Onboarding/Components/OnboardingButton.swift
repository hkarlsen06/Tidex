import SwiftUI
import UIKit

/// Full-width CTA button for onboarding screens
/// Matches PrimaryButton styling with gradient option
struct OnboardingButton: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  let title: String
  var isEnabled: Bool = true
  let action: () -> Void
  var style: ButtonStyle = .primary

  enum ButtonStyle {
    case primary  // Brand gradient/solid fill
    case secondary  // Text link style
  }

  var body: some View {
    Button {
      UIImpactFeedbackGenerator(style: .medium).impactOccurred()
      action()
    } label: {
      Text(title)
        .font(.tidexHeadline)
        .frame(maxWidth: .infinity)
        .frame(height: 54)
        .foregroundColor(style == .primary ? .white : .tidexBlue)
        .background(
          Group {
            if style == .primary {
              isEnabled ? Color.tidexBrandPrimary : Color.tidexBrandPrimary.opacity(0.5)
            } else {
              Color.clear
            }
          }
        )
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous))
    }
    .buttonStyle(SnappyOnboardingButtonStyle(reduceMotion: reduceMotion))
    .disabled(!isEnabled)
  }
}

/// Snappy button style with scale and opacity feedback
private struct SnappyOnboardingButtonStyle: ButtonStyle {
  let reduceMotion: Bool

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(reduceMotion ? 1.0 : (configuration.isPressed ? 0.97 : 1.0))
      .opacity(configuration.isPressed ? 0.9 : 1.0)
      .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: configuration.isPressed)
  }
}

#Preview {
  VStack(spacing: Spacing.md) {
    OnboardingButton(title: "Create Account", action: {})

    OnboardingButton(title: "Already have an account? Log in", action: {}, style: .secondary)
  }
  .padding(.horizontal, Spacing.lg)
  .frame(maxHeight: .infinity)
  .background(Color.tidexBackground)
}
