import SwiftUI

/// MFA verification screen
/// Displays a 6-digit code input for TOTP verification
struct MFAVerifyView: View {
    @StateObject private var viewModel: MFAVerifyViewModel
    @Environment(\.localization) private var localization

    init(factor: AuthService.MFAFactor, coordinator: AppCoordinator) {
        _viewModel = StateObject(wrappedValue: MFAVerifyViewModel(
            factor: factor,
            coordinator: coordinator
        ))
    }

    var body: some View {
        ZStack {
            // Background - adapts to system appearance
            Color.tidexBackground
                .ignoresSafeArea()

            // Content - constrained for iPad
            ScrollView {
                VStack(spacing: 24) {
                    // Header with logo
                    headerView
                        .padding(.top, 40)

                    // Main card - constrained width for iPad
                    TidexCard {
                        VStack(spacing: 20) {
                            // Card header
                            cardHeader

                            // Error banner
                            if let error = viewModel.errorMessage {
                                ErrorBanner(
                                    message: error,
                                    onDismiss: { viewModel.errorMessage = nil }
                                )
                            }

                            // Code input
                            codeInputSection

                            // Verify button
                            PrimaryButton(
                                title: localization.string("mfa.submitButton"),
                                action: {
                                    Task { await viewModel.verifyCode() }
                                },
                                isLoading: viewModel.isLoading
                            )
                            .disabled(viewModel.code.count != 6)

                            // Back to login
                            backButton
                        }
                        .padding(24)
                    }
                    .adaptiveFormWidth()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .loading(viewModel.isLoading)
        .onAppear {
            Task { await viewModel.createChallenge() }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(spacing: 12) {
            // Lock icon for MFA
            ZStack {
                Circle()
                    .fill(Color.tidexBlue.opacity(0.1))
                    .frame(width: 80, height: 80)

                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.tidexBlue)
            }

            Text("Tidex")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.tidexTextPrimary)
        }
    }

    // MARK: - Card Header

    private var cardHeader: some View {
        VStack(spacing: 8) {
            Text(localization.string("mfa.title"))
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.tidexTextPrimary)

            Text(localization.string("mfa.subtitle"))
                .font(.system(size: 14))
                .foregroundColor(.tidexTextSecondary)
                .multilineTextAlignment(.center)

            // Show factor name if available
            if let factorName = viewModel.factor.friendlyName {
                Text(factorName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.tidexTextMuted)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.tidexSurfaceSecondary)
                    .cornerRadius(6)
            }
        }
    }

    // MARK: - Code Input

    private var codeInputSection: some View {
        VStack(spacing: 12) {
            Text(localization.string("mfa.codeLabel"))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.tidexTextSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Use OTPInputField for consistent, fast input
            OTPInputField(
                code: $viewModel.code,
                error: nil,
                onComplete: {
                    Task { await viewModel.verifyCode() }
                },
                autoFocus: true
            )
        }
    }

    // MARK: - Back Button

    private var backButton: some View {
        Button(action: {
            Task { await viewModel.signOutAndReturn() }
        }) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 14))

                Text(localization.string("mfa.backToLogin"))
                    .font(.system(size: 14, weight: .medium))
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
        .environment(\.localization, LocalizationManager.shared)
}
