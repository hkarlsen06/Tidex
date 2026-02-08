import SwiftUI

/// Full-screen loading overlay with smooth animations
/// Used during async operations like login
struct LoadingOverlay: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var message: String? = nil
  var isSuccess: Bool = false

  var body: some View {
    ZStack {
      Color.black.opacity(0.4)
        .ignoresSafeArea()

      VStack(spacing: Spacing.md) {
        if isSuccess {
          Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 44))
            .foregroundColor(.tidexSuccess)
            .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
        } else {
          ProgressView()
            .progressViewStyle(CircularProgressViewStyle(tint: .white))
            .scaleEffect(1.5)
        }

        if let message = message {
          Text(message)
            .font(.tidexSubheadline)
            .foregroundColor(.tidexTextPrimary)
        }
      }
      .padding(Spacing.xl)
      .background(Color.tidexSurfacePrimary.opacity(0.95))
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xxl, style: .continuous))
      .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isSuccess)
      .accessibilityElement(children: .combine)
      .accessibilityLabel(
        message ?? String(localized: isSuccess ? "common.done" : "common.loading"))
    }
  }
}

/// View modifier for applying loading overlay with smooth transitions
struct LoadingModifier: ViewModifier {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  let isLoading: Bool
  var isSuccess: Bool = false
  var message: String? = nil

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
