import SwiftUI

/// Email/phone and password input form
struct EmailPasswordForm: View {
    @ObservedObject var viewModel: LoginViewModel
    var onForgotPassword: (() -> Void)?

    @Environment(\.localization) private var localization

    var body: some View {
        VStack(spacing: 16) {
            // Email/Phone field
            TidexTextField(
                label: localization.string("login.emailOrPhoneLabel"),
                placeholder: localization.string("login.emailOrPhonePlaceholder"),
                text: $viewModel.emailOrPhone,
                error: viewModel.fieldErrors.emailOrPhone,
                keyboardType: .emailAddress,
                textContentType: .emailAddress,
                autocapitalization: .never,
                autocorrection: false
            )

            // Password field (always shown for email, optional for phone)
            if viewModel.inputType == .email || !viewModel.password.isEmpty {
                SecureTextField(
                    label: localization.string("login.passwordLabel"),
                    placeholder: localization.string("login.passwordPlaceholder"),
                    text: $viewModel.password,
                    error: viewModel.fieldErrors.password,
                    onSubmit: {
                        Task { await viewModel.signIn() }
                    }
                )
            }

            // Forgot password link
            if viewModel.inputType == .email || !viewModel.password.isEmpty {
                HStack {
                    Spacer()
                    Button(action: {
                        onForgotPassword?()
                    }) {
                        Text(localization.string("login.forgotPassword"))
                            .font(.system(size: 14))
                            .foregroundColor(.tidexBlue)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Phone hint - show password is optional
            if viewModel.inputType == .phone && viewModel.password.isEmpty {
                Text("Leave password empty to receive an SMS code")
                    .font(.system(size: 12))
                    .foregroundColor(.tidexTextMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Submit button
            PrimaryButton(
                title: localization.string("login.submitButton"),
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
        .background(Color.tidexDarkBackground)
}
