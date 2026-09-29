import SwiftUI

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
      Haptics.play(.medium)
      action()
    } label: {
      Text(title)
        .font(.tidexHeadline)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xs)
        .frame(minHeight: 54)
        .foregroundColor(style == .primary ? .tidexTextOnBrand : .tidexBlueText)
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

extension View {
  /// Keeps the layout unchanged when it fits and lets it scroll when large text makes it overflow.
  /// The content is at least as tall as the available space, so spacers still fill the page.
  func scrollsOnOverflow(alignment: Alignment = .center) -> some View {
    GeometryReader { proxy in
      ScrollView {
        frame(minHeight: proxy.size.height, alignment: alignment)
      }
      .scrollBounceBehavior(.basedOnSize)
    }
  }
}
