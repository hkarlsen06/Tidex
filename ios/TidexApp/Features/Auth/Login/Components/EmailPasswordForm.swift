import SwiftUI

/// Email/phone and password input form
struct EmailPasswordForm: View {
  @ObservedObject var viewModel: LoginViewModel
  var onForgotPassword: (() -> Void)?

  var body: some View {
    VStack(spacing: Spacing.md) {
      // Email/Phone field
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

      // Password field (always visible for AutoFill, optional for phone login)
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

      // Forgot password link (only for email login)
      if viewModel.inputType == .email {
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
}

#Preview {
  EmailPasswordForm(viewModel: LoginViewModel())
    .padding()
    .background(Color.tidexBackground)
}
