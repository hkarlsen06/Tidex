// swiftlint:disable:next blanket_disable_command
// swiftlint:disable line_length superfluous_disable_command
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable explicit_acl explicit_top_level_acl explicit_type_interface file_types_order
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable implicit_optional_initialization multiline_arguments_brackets no_magic_numbers shorthand_optional_binding
import SwiftUI

/// Full-screen loading overlay with smooth animations
/// Used during async operations like login
struct LoadingOverlay: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var message: String?
  var isSuccess: Bool = false

  var body: some View {
    ZStack {
      // Light dim: enough to show the screen is busy and to block taps, without hiding what's behind.
      Color.black.opacity(0.25)
        .ignoresSafeArea()

      VStack(spacing: Spacing.sm) {
        statusIcon

        if let message {
          Text(message)
            .font(.tidexSubheadline)
            .foregroundStyle(Color.tidexTextPrimary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .padding(Spacing.lg)
      .frame(minWidth: 112, maxWidth: 240)
      .background(
        Color.tidexSurfacePrimary,
        in: RoundedRectangle(cornerRadius: CornerRadius.xxl, style: .continuous)
      )
      .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isSuccess)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(message.map { Text($0) } ?? Text(isSuccess ? .commonDone : .commonLoading))
    }
    .accessibilityAddTraits(.isModal)
    .onChange(of: isSuccess) { _, newValue in
      if newValue {
        AccessibilityNotification.Announcement(String(localized: .commonDone)).post()
      }
    }
  }

  /// Fixed-size slot so the card doesn't jump when the spinner turns into a checkmark.
  private var statusIcon: some View {
    ZStack {
      if isSuccess {
        Image(systemName: "checkmark.circle.fill")
          .font(.largeTitle)
          .foregroundStyle(Color.tidexSuccess)
          .accessibilityHidden(true)
          .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
      } else {
        ProgressView()
          .controlSize(.large)
          .tint(.tidexTextSecondary)
      }
    }
    .frame(width: 44, height: 44)
  }
}

/// View modifier for applying loading overlay with smooth transitions
struct LoadingModifier: ViewModifier {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  let isLoading: Bool
  var isSuccess: Bool = false
  var message: String?

  private var showOverlay: Bool {
    isLoading || isSuccess
  }

  func body(content: Content) -> some View {
    ZStack {
      content

      if showOverlay {
        LoadingOverlay(message: message, isSuccess: isSuccess)
          .transition(
            .opacity
              .combined(with: reduceMotion ? .identity : .scale(scale: 0.95))
          )
      }
    }
    .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: showOverlay)
    .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isSuccess)
  }
}

extension View {
  /// Apply a loading overlay to the view with smooth transitions
  func loading(_ isLoading: Bool, message: String? = nil) -> some View {
    modifier(LoadingModifier(isLoading: isLoading, message: message))
  }

  /// Apply a loading overlay that transitions to a success state
  func loadingWithSuccess(_ isLoading: Bool, isSuccess: Bool, message: String? = nil) -> some View {
    modifier(LoadingModifier(isLoading: isLoading, isSuccess: isSuccess, message: message))
  }
}

#Preview {
  ZStack {
    Color.tidexBackground.ignoresSafeArea()

    Text("Content behind overlay")
      .foregroundColor(.tidexTextPrimary)
  }
  .loading(true, message: "Logging in...")
}

#Preview("Success") {
  ZStack {
    Color.tidexBackground.ignoresSafeArea()
  }
  .loadingWithSuccess(false, isSuccess: true)
}
