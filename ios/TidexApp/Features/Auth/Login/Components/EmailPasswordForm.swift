import SwiftUI

/// Email/phone and password input form
internal struct EmailPasswordForm: View {
  @ObservedObject internal var viewModel: LoginViewModel
  internal var onForgotPassword: (() -> Void)?

  internal var body: some View {
    VStack(spacing: Spacing.md) {
      identityField
      passwordField

      // Forgot password link (only for email login)
      if viewModel.inputType == .email {
        forgotPasswordLink
      }

      // Phone hint - password is optional for OTP flow
      if viewModel.inputType == .phone {
        Text(.loginPhonePasswordHint)
          .font(.tidexCaptionRegular)
          .foregroundColor(.tidexTextMuted)
          .frame(maxWidth: .infinity, alignment: .leading)
      }

      // Submit button
      PrimaryButton(
        title: String(localized: .loginSubmitButton),
        action: {
          Task { await viewModel.signIn() }
        },
        isLoading: viewModel.isLoading
      )
    }
  }

  private var identityField: some View {
    TidexTextField(
      label: String(localized: .loginEmailOrPhoneLabel),
      placeholder: String(localized: .loginEmailOrPhonePlaceholder),
      text: $viewModel.emailOrPhone,
      error: viewModel.fieldErrors.emailOrPhone,
      keyboardType: .emailAddress,
      textContentType: .emailAddress,
      autocapitalization: .never,
      autocorrection: false
    )
  }

  private var passwordField: some View {
    SecureTextField(
      label: viewModel.inputType == .phone
        ? String(localized: .loginPasswordOptionalLabel)
        : String(localized: .loginPasswordLabel),
      placeholder: String(localized: .loginPasswordPlaceholder),
      text: $viewModel.password,
      error: viewModel.fieldErrors.password,
      onSubmit: {
        Task { await viewModel.signIn() }
      }
    )
  }

  private var forgotPasswordLink: some View {
    HStack {
      Spacer()
      Button(action: {
        onForgotPassword?()
      }) {
        Text(.loginForgotPassword)
          .font(.tidexSubheadline)
          .foregroundColor(.tidexBlue)
      }
      .buttonStyle(.plain)
    }
  }
}

#Preview {
  EmailPasswordForm(viewModel: LoginViewModel())
    .padding()
    .background(Color.tidexBackground)
}
