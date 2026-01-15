import SwiftUI

/// Main login screen view
/// Supports email/password, phone/OTP, Google, and Apple sign-in
struct LoginView: View {
    @StateObject private var viewModel = LoginViewModel()
    @Environment(\.localization) private var localization

    // Navigation callbacks
    var onNavigateToSignup: (() -> Void)?
    var onNavigateToResetPassword: (() -> Void)?

    // Animation state
    @State private var headerAppeared = false
    @State private var cardAppeared = false
    @State private var footerAppeared = false

    var body: some View {
        ZStack {
            // Background
            Color.tidexDarkBackground
                .ignoresSafeArea()

            // Content
            ScrollView {
                VStack(spacing: 24) {
                    // Header with logo
                    headerView
                        .padding(.top, 40)
                        .opacity(headerAppeared ? 1 : 0)
                        .offset(y: headerAppeared ? 0 : -20)

                    // Main card
                    TidexCard {
                        VStack(spacing: 20) {
                            // Card header
                            cardHeader

                            // Error/Success banners
                            if let error = viewModel.errorMessage {
                                ErrorBanner(
                                    message: error,
                                    onDismiss: { viewModel.errorMessage = nil }
                                )
                            }

                            if let success = viewModel.successMessage {
                                SuccessBanner(
                                    message: success,
                                    onDismiss: { viewModel.successMessage = nil }
                                )
                            }

                            // Step content
                            switch viewModel.currentStep {
                            case .input:
                                inputStepContent
                            case .otp:
                                PhoneOTPForm(viewModel: viewModel)
                            }
                        }
                        .padding(24)
                    }
                    .opacity(cardAppeared ? 1 : 0)
                    .offset(y: cardAppeared ? 0 : 30)
                    .scaleEffect(cardAppeared ? 1 : 0.95)

                    // Footer
                    if viewModel.currentStep == .input {
                        footerView
                            .opacity(footerAppeared ? 1 : 0)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .loading(viewModel.isLoading)
        .onAppear {
            // Fast staggered entrance animations - feel snappy
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                headerAppeared = true
            }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8).delay(0.05)) {
                cardAppeared = true
            }
            withAnimation(.easeOut(duration: 0.25).delay(0.1)) {
                footerAppeared = true
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(spacing: 12) {
            // Logo
            LogoWatermark(opacity: 1.0)
                .frame(width: 60, height: 60)

            Text("Tidex")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.tidexTextPrimary)
        }
    }

    // MARK: - Card Header

    private var cardHeader: some View {
        VStack(spacing: 8) {
            Text(localization.string("login.title"))
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.tidexTextPrimary)

            Text(localization.string("login.subtitle"))
                .font(.system(size: 14))
                .foregroundColor(.tidexTextSecondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Input Step Content

    @ViewBuilder
    private var inputStepContent: some View {
        // OAuth buttons
        OAuthButtonsView(
            onGoogleTap: { Task { await viewModel.signInWithGoogle() } },
            onAppleTap: { Task { await viewModel.signInWithApple() } },
            isLoading: viewModel.isLoading
        )

        // Divider
        dividerView

        // Email/phone form
        if viewModel.showEmailForm {
            EmailPasswordForm(
                viewModel: viewModel,
                onForgotPassword: onNavigateToResetPassword
            )
        } else {
            OutlineButton(
                title: localization.string("login.emailOrPhoneReveal"),
                action: { viewModel.showEmailForm = true },
                icon: "envelope"
            )
        }
    }

    // MARK: - Divider

    private var dividerView: some View {
        HStack(spacing: 16) {
            Rectangle()
                .fill(Color.tidexBorderSubtle)
                .frame(height: 1)

            Text(localization.string("login.separator"))
                .font(.system(size: 14))
                .foregroundColor(.tidexTextMuted)

            Rectangle()
                .fill(Color.tidexBorderSubtle)
                .frame(height: 1)
        }
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack(spacing: 4) {
            Text(localization.string("login.noAccount"))
                .font(.system(size: 14))
                .foregroundColor(.tidexTextSecondary)

            Button(action: {
                onNavigateToSignup?()
            }) {
                Text(localization.string("login.createAccount"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.tidexBlue)
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    LoginView()
        .environment(\.localization, LocalizationManager.shared)
}
