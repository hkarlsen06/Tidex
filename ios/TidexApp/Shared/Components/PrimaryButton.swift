// swiftlint:disable:next blanket_disable_command
// swiftlint:disable line_length superfluous_disable_command
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable explicit_acl explicit_top_level_acl explicit_type_interface file_types_order
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable no_empty_block no_magic_numbers
import SwiftUI
import UIKit

/// Primary action button with Tidex brand styling
/// Used for main CTAs like "Log in", "Sign up", etc.
struct PrimaryButton: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  let title: String
  let action: () -> Void
  var isLoading: Bool = false
  var isDisabled: Bool = false

  var body: some View {
    Button {
      UIImpactFeedbackGenerator(style: .medium).impactOccurred()
      action()
    } label: {
      HStack(spacing: Spacing.xs) {
        if isLoading {
          ProgressView()
            .progressViewStyle(CircularProgressViewStyle(tint: .tidexTextOnBrand))
            .scaleEffect(0.8)
        }

        Text(title)
          .font(.tidexButton)
      }
      .frame(maxWidth: .infinity)
      .frame(height: Spacing.buttonHeight)
      .background(
        isDisabled
          ? Color.tidexBrandPrimary.opacity(0.5)
          : Color.tidexBrandPrimary
      )
      .foregroundColor(.tidexTextOnBrand)
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.pill, style: .continuous))
    }
    .buttonStyle(SnappyPrimaryButtonStyle(reduceMotion: reduceMotion))
    .disabled(isDisabled || isLoading)
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: isLoading)
  }
}

/// Snappy button style with scale and opacity feedback
private struct SnappyPrimaryButtonStyle: ButtonStyle {
  let reduceMotion: Bool

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(reduceMotion ? 1.0 : (configuration.isPressed ? 0.97 : 1.0))
      .opacity(configuration.isPressed ? 0.9 : 1.0)
      .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: configuration.isPressed)
  }
}

/// Loading button that shows a spinner while loading
struct LoadingButton: View {
  let title: String
  let isLoading: Bool
  let action: () -> Void

  var body: some View {
    PrimaryButton(
      title: title,
      action: action,
      isLoading: isLoading
    )
  }
}

#Preview {
  VStack(spacing: Spacing.md) {
    PrimaryButton(title: "Log in", action: {})

    PrimaryButton(title: "Loading...", action: {}, isLoading: true)

    PrimaryButton(title: "Disabled", action: {}, isDisabled: true)
  }
  .padding()
  .background(Color.tidexBackground)
}
