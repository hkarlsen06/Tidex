import SwiftUI

/// Error banner for displaying error messages
/// Appears at the top of forms when there's an error
/// Supports optional retry and dismiss actions
struct ErrorBanner: View {
  let message: String
  var onRetry: (() -> Void)? = nil
  var onDismiss: (() -> Void)? = nil

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundColor(.tidexError)
        .font(.system(size: 16))

      Text(message)
        .font(.system(size: 14))
        .foregroundColor(.tidexTextPrimary)
        .multilineTextAlignment(.leading)

      Spacer()

      if let onRetry = onRetry {
        Button(action: onRetry) {
          Text(.commonRetry)
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.tidexBlue)
        }
        .buttonStyle(.plain)
      }

      if let onDismiss = onDismiss {
        Button(action: onDismiss) {
          Image(systemName: "xmark")
            .foregroundColor(.tidexTextMuted)
            .font(.system(size: 12, weight: .semibold))
        }
        .buttonStyle(.plain)
      }
    }
    .padding(16)
    .background(Color.tidexError.opacity(0.15))
    .overlay(
      RoundedRectangle(cornerRadius: 10)
        .stroke(Color.tidexError.opacity(0.3), lineWidth: 1)
    )
    .cornerRadius(10)
  }
}

/// Success banner for displaying success messages
struct SuccessBanner: View {
  let message: String
  var onDismiss: (() -> Void)? = nil

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: "checkmark.circle.fill")
        .foregroundColor(.tidexSuccess)
        .font(.system(size: 16))

      Text(message)
        .font(.system(size: 14))
        .foregroundColor(.tidexTextPrimary)
        .multilineTextAlignment(.leading)

      Spacer()

      if let onDismiss = onDismiss {
        Button(action: onDismiss) {
          Image(systemName: "xmark")
            .foregroundColor(.tidexTextMuted)
            .font(.system(size: 12, weight: .semibold))
        }
        .buttonStyle(.plain)
      }
    }
    .padding(16)
    .background(Color.tidexSuccess.opacity(0.15))
    .overlay(
      RoundedRectangle(cornerRadius: 10)
        .stroke(Color.tidexSuccess.opacity(0.3), lineWidth: 1)
    )
    .cornerRadius(10)
  }
}

#Preview {
  VStack(spacing: 16) {
    ErrorBanner(
      message: "Invalid email or password. Please try again.",
      onRetry: {},
      onDismiss: {}
    )

    ErrorBanner(
      message: "Connection failed. Check your network.",
      onRetry: {}
    )

    ErrorBanner(
      message: "Simple error without actions."
    )

    SuccessBanner(
      message: "A verification code has been sent to your phone.",
      onDismiss: {}
    )
  }
  .padding()
  .background(Color.tidexBackground)
}
