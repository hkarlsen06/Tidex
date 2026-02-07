import SwiftUI

/// MFA verification screen with native iOS styling
/// Displays a 6-digit code input for TOTP verification
struct MFAVerifyView: View {
  @StateObject private var viewModel: MFAVerifyViewModel

  init(factor: AuthService.MFAFactor, coordinator: AppCoordinator) {
    _viewModel = StateObject(
      wrappedValue: MFAVerifyViewModel(
        factor: factor,
        coordinator: coordinator
      ))
  }

  var body: some View {
    VStack(spacing: 0) {
      Spacer()

      // Header section
      headerSection
        .padding(.bottom, Spacing.xl)

      // Main content
      VStack(spacing: Spacing.lg) {
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
      .padding(.horizontal, Spacing.lg)

      Spacer()
    }
    .background(Color.tidexBackground)
    .loadingWithSuccess(viewModel.isLoading, isSuccess: viewModel.isVerificationComplete)
    .onTapGesture {
      UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    .onAppear {
      Task { await viewModel.createChallenge() }
    }
  }

  // MARK: - Header Section

  private var headerSection: some View {
    VStack(spacing: Spacing.md) {
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
    VStack(spacing: Spacing.xs) {
      Text(.mfaTitle)
        .font(.tidexTitle)
        .foregroundColor(.tidexTextPrimary)

      Text(.mfaSubtitle)
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextSecondary)
        .multilineTextAlignment(.center)

      // Show factor name if available
      if let factorName = viewModel.factor.friendlyName {
        Text(factorName)
          .font(.tidexFootnoteMedium)
          .foregroundColor(.tidexTextMuted)
          .padding(.horizontal, Spacing.sm)
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
      HStack(spacing: Spacing.xxs) {
        Image(systemName: "chevron.left")
          .font(.tidexCaption)
        Text(.mfaBackToLogin)
          .font(.tidexSubheadline)
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
