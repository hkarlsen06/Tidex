import SwiftUI

/// MFA verification screen with native iOS styling
/// Displays a 6-digit code input for TOTP verification
struct MFAVerifyView: View {
    @StateObject private var viewModel: MFAVerifyViewModel
    
    init(factor: AuthService.MFAFactor, coordinator: AppCoordinator) {
        _viewModel = StateObject(wrappedValue: MFAVerifyViewModel(
            factor: factor,
            coordinator: coordinator
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Header section
            headerSection
                .padding(.bottom, 32)

            // Main content
            VStack(spacing: 24) {
                // Error banner
                if let error = viewModel.errorMessage {
                    ErrorBanner(
                        message: error,
                        onDismiss: { viewModel.errorMessage = nil }
                    )
                }

                // Instructions
                instructionsSection

                // OTP input
                OTPInputField(
                    code: $viewModel.code,
                    error: nil,
                    onComplete: {
                        Task { await viewModel.verifyCode() }
                    },
                    autoFocus: true
                )

                // Verify button
                PrimaryButton(
                    title: String(localized: .mfaSubmitButton),
                    action: {
                        Task { await viewModel.verifyCode() }
                    },
                    isLoading: viewModel.isLoading,
                    isDisabled: viewModel.code.count < 6
                )

                // Back to login
                backButton
            }
            .padding(.horizontal, 24)

            Spacer()
        }
        .background(Color.tidexBackground)
        .loadingWithSuccess(viewModel.isLoading, isSuccess: viewModel.isVerificationComplete)
        .onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .onAppear {
            Task { await viewModel.createChallenge() }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 16) {
            // Lock icon for MFA
            ZStack {
                Circle()
                    .fill(Color.tidexBlue.opacity(0.1))
                    .frame(width: 80, height: 80)

                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.tidexBlue)
            }

            // Title
            Text("Tidex")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.tidexTextPrimary)
        }
    }

    // MARK: - Instructions Section

    private var instructionsSection: some View {
        VStack(spacing: 8) {
            Text(.mfaTitle)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.tidexTextPrimary)

            Text(.mfaSubtitle)
                .font(.system(size: 15))
                .foregroundColor(.tidexTextSecondary)
                .multilineTextAlignment(.center)

            // Show factor name if available
            if let factorName = viewModel.factor.friendlyName {
                Text(factorName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.tidexTextMuted)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.tidexSurfaceSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    // MARK: - Back Button

    private var backButton: some View {
        Button(action: {
            Task { await viewModel.signOutAndReturn() }
        }) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .medium))
                Text(.mfaBackToLogin)
                    .font(.system(size: 15))
            }
            .foregroundColor(.tidexTextSecondary)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    let factor = AuthService.MFAFactor(
        id: "test-factor",
        type: "totp",
        friendlyName: "Authenticator",
        status: "verified"
    )

    return MFAVerifyView(factor: factor, coordinator: AppCoordinator.shared)
}
