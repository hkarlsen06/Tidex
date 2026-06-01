import SwiftUI

/// Error banner for displaying error messages
/// Appears at the top of forms when there's an error
/// Supports optional retry and dismiss actions
struct ErrorBanner: View {
  let message: String
  var onRetry: (() -> Void)? = nil
  var onDismiss: (() -> Void)? = nil

  var body: some View {
    HStack(alignment: .top, spacing: Spacing.sm) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundColor(.tidexError)
        .font(.tidexBody)

      Text(message)
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextPrimary)
        .multilineTextAlignment(.leading)

      Spacer()

      if let onRetry = onRetry {
        Button(action: onRetry) {
          Text(.commonRetry)
            .font(.tidexLabel)
            .foregroundColor(.tidexBlue)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }

      if let onDismiss = onDismiss {
        Button(action: onDismiss) {
          Image(systemName: "xmark")
            .foregroundColor(.tidexTextMuted)
            .font(.tidexCaptionStrong)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(.screenshotShareDismiss))
      }
    }
    .padding(Spacing.md)
    .background(Color.tidexError.opacity(0.15))
    .overlay(
      RoundedRectangle(cornerRadius: CornerRadius.md)
        .stroke(Color.tidexError.opacity(0.3), lineWidth: 1)
    )
    .cornerRadius(CornerRadius.md)
  }
}

/// Success banner for displaying success messages
struct SuccessBanner: View {
  enum Style {
    case inline
    case toast
  }

  let message: String
  var style: Style = .inline
  var actionTitle: LocalizedStringResource? = nil
  var onAction: (() -> Void)? = nil
  var onDismiss: (() -> Void)? = nil

  private var backgroundColor: Color {
    switch style {
    case .inline:
      return Color.tidexSuccess.opacity(0.15)
    case .toast:
      return .tidexSurfacePrimary
    }
  }

  private var borderColor: Color {
    switch style {
    case .inline:
      return Color.tidexSuccess.opacity(0.3)
    case .toast:
      return .tidexBorder
    }
  }

  private var cornerRadius: CGFloat {
    switch style {
    case .inline:
      return CornerRadius.md
    case .toast:
      return CornerRadius.xxxl
    }
  }

  private var isToast: Bool {
    style == .toast
  }

  var body: some View {
    HStack(alignment: isToast ? .center : .top, spacing: isToast ? Spacing.xs : Spacing.sm) {
      Image(systemName: "checkmark.circle.fill")
        .foregroundColor(.tidexSuccess)
        .font(isToast ? .tidexLabelStrong : .tidexBody)

      Text(message)
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextPrimary)
        .multilineTextAlignment(.leading)
        .lineLimit(isToast ? 1 : nil)
        .truncationMode(.tail)
        .layoutPriority(1)

      Spacer()

      if let actionTitle, let onAction {
        Button(action: onAction) {
          Text(actionTitle)
            .font(isToast ? .tidexFootnoteStrong : .tidexLabel)
            .foregroundColor(.tidexBlue)
            .lineLimit(1)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
      }

      if let onDismiss = onDismiss {
        Button(action: onDismiss) {
          Image(systemName: "xmark")
            .foregroundColor(.tidexTextMuted)
            .font(isToast ? .tidexMicro : .tidexCaptionStrong)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel(Text(.screenshotShareDismiss))
      }
    }
    .padding(.horizontal, isToast ? Spacing.sm : Spacing.md)
    .padding(.vertical, isToast ? Spacing.xs : Spacing.md)
    .background(backgroundColor)
    .overlay(
      RoundedRectangle(cornerRadius: cornerRadius)
        .stroke(borderColor, lineWidth: 1)
    )
    .cornerRadius(cornerRadius)
    .shadow(color: style == .toast ? Color.black.opacity(0.12) : .clear, radius: 10, y: 3)
  }
}

#Preview {
  VStack(spacing: Spacing.md) {
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
