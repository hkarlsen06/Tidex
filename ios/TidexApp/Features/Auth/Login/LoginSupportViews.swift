import SwiftUI

/// Banner shown on the login screen when the entered account does not exist yet.
struct AccountCreationPromptCard: View {
  let message: String
  let onDismiss: () -> Void
  let onCreateAccount: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.md) {
      HStack(alignment: .top, spacing: Spacing.sm) {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundColor(.tidexError)
          .font(.tidexBody)
          .accessibilityHidden(true)

        Text(message)
          .font(.tidexSubheadline)
          .foregroundColor(.tidexTextPrimary)
          .multilineTextAlignment(.leading)

        Spacer()

        Button(action: {
          onDismiss()
        }) {
          Image(systemName: "xmark")
            .foregroundColor(.tidexTextMuted)
            .font(.tidexCaptionStrong)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(.commonDismiss))
      }

      PrimaryButton(
        title: String(localized: .loginCreateAccount),
        action: {
          onCreateAccount()
        }
      )
    }
    .padding(Spacing.md)
    .background(Color.tidexError.opacity(0.15))
    .overlay(
      RoundedRectangle(cornerRadius: CornerRadius.md)
        .stroke(Color.tidexError.opacity(0.3), lineWidth: 1)
    )
    .cornerRadius(CornerRadius.md)
    .announcesToVoiceOver(message)
  }
}

/// "Create account" and "Forgot password" links under the login form.
struct LoginFooterLinks: View {
  let onCreateAccount: () -> Void
  let onForgotPassword: () -> Void
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    let layout =
      dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(spacing: Spacing.xs))
      : AnyLayout(HStackLayout(spacing: 0))

    return layout {
      footerLink(title: Text(.loginCreateAccount)) {
        onCreateAccount()
      }
      .accessibilityIdentifier("login.create-account")

      if !dynamicTypeSize.isAccessibilitySize {
        Rectangle()
          .fill(Color.tidexSeparator)
          .frame(width: 1, height: 18)
      }

      footerLink(title: Text(.loginForgotPassword)) {
        onForgotPassword()
      }
      .accessibilityIdentifier("login.forgot-password")
    }
    .frame(maxWidth: .infinity)
  }

  private func footerLink(title: Text, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      title
        .font(.tidexLabelStrong)
        .foregroundColor(.tidexBlueText)
        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
        .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.86)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? Spacing.xs : 0)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}
