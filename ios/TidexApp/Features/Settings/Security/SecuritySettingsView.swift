import SwiftUI
import CoreImage.CIFilterBuiltins

/// Security settings view
/// Displays password management, connected accounts, and MFA settings
struct SecuritySettingsView: View {
        @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = SecuritySettingsViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                headerSection

                // Error/Success messages
                if let error = viewModel.errorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(.tidexError)
                        Text(error)
                            .font(.system(size: 14))
                            .foregroundColor(.tidexError)
                        Spacer()
                        Button {
                            viewModel.clearMessages()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.tidexError)
                        }
                    }
                    .padding(12)
                    .background(Color.tidexError.opacity(0.1))
                    .cornerRadius(8)
                }

                if let success = viewModel.successMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.tidexSuccess)
                        Text(success)
                            .font(.system(size: 14))
                            .foregroundColor(.tidexSuccess)
                        Spacer()
                        Button {
                            viewModel.clearMessages()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.tidexSuccess)
                        }
                    }
                    .padding(12)
                    .background(Color.tidexSuccess.opacity(0.1))
                    .cornerRadius(8)
                }

                // Biometric lock section (only show if available)
                if viewModel.isBiometricAvailable {
                    biometricLockSection
                }

                // Password section
                passwordSection

                // Connected accounts section
                connectedAccountsSection

                // MFA section
                mfaSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
        }
        .background(Color.tidexBackground)
        .navigationTitle(String(localized: .securityTitle))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.tidexBackground, for: .navigationBar)
        .task {
            await viewModel.loadSecurityInfo()
        }
        .sheet(isPresented: $viewModel.showPasswordForm) {
            passwordFormSheet
        }
        .sheet(isPresented: $viewModel.showMFAEnrollment) {
            mfaEnrollmentSheet
        }
        .sheet(isPresented: $viewModel.showPhoneLinkingSheet) {
            phoneLinkingSheet
        }
        .alert(String(localized: .securityMfaUnenrollDialogTitle), isPresented: $viewModel.showUnenrollConfirmation) {
            Button(String(localized: .commonCancel), role: .cancel) {
                viewModel.factorToUnenroll = nil
            }
            Button(String(localized: .securityMfaUnenrollDialogConfirm), role: .destructive) {
                if let factor = viewModel.factorToUnenroll {
                    Task {
                        await viewModel.unenrollMFA(factor)
                    }
                }
            }
        } message: {
            Text(.securityMfaUnenrollDialogDescription)
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(.securityTitle)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.tidexTextPrimary)

            Text(.securitySubtitle)
                .font(.subheadline)
                .foregroundColor(.tidexTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Biometric Lock Section

    private var biometricLockSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            VStack(alignment: .leading, spacing: 4) {
                Text(.securityBiometricSectionTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.tidexTextMuted)
                    .textCase(.uppercase)

                Text(.securityBiometricSectionSubtitle)
                    .font(.system(size: 13))
                    .foregroundColor(.tidexTextSecondary)
            }

            // Biometric toggle card
            VStack(spacing: 0) {
                HStack(spacing: Spacing.sm) {
                    // Icon
                    Image(systemName: viewModel.biometricIconName)
                        .font(.system(size: 20))
                        .foregroundColor(.tidexBlue)
                        .frame(width: 32, height: 32)

                    // Content
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: .securityBiometricTitle(viewModel.biometricTypeName)))
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.tidexTextPrimary)

                        Text(viewModel.isBiometricLockEnabled
                             ? String(localized: .securityBiometricEnabled)
                             : String(localized: .securityBiometricDisabled))
                            .font(.system(size: 13))
                            .foregroundColor(.tidexTextSecondary)
                    }

                    Spacer()

                    // Toggle
                    if viewModel.isTogglingBiometric {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .tidexBlue))
                            .scaleEffect(0.8)
                    } else {
                        Toggle("", isOn: Binding(
                            get: { viewModel.isBiometricLockEnabled },
                            set: { _ in
                                Task {
                                    await viewModel.toggleBiometricLock()
                                }
                            }
                        ))
                        .labelsHidden()
                        .tint(.tidexBlue)
                    }
                }
                .padding(16)
            }
            .background(Color.tidexSurfacePrimary)
            .cornerRadius(12)
            .tidexCardShadow(cornerRadius: 12)
        }
    }

    // MARK: - Password Section

    private var passwordSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            Text(.securityPasswordSectionTitle)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.tidexTextMuted)
                .textCase(.uppercase)

            // Password card
            VStack(spacing: 0) {
                HStack(spacing: Spacing.sm) {
                    // Icon
                    Image(systemName: "lock.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.tidexBlue)
                        .frame(width: 32, height: 32)

                    // Content
                    VStack(alignment: .leading, spacing: 2) {
                        Text(.securityPasswordTitle)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.tidexTextPrimary)

                        Text(viewModel.hasPassword
                             ? String(localized: .securityPasswordHasPassword)
                             : String(localized: .securityPasswordNoPassword))
                            .font(.system(size: 13))
                            .foregroundColor(.tidexTextSecondary)
                    }

                    Spacer()

                    // Button
                    Button {
                        viewModel.showPasswordForm = true
                    } label: {
                        Text(viewModel.hasPassword
                             ? String(localized: .securityPasswordChange)
                             : String(localized: .securityPasswordSet))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(viewModel.hasPassword ? .tidexBlue : .white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(viewModel.hasPassword ? Color.tidexBlue.opacity(0.1) : Color.tidexBlue)
                            .cornerRadius(8)
                    }
                }
                .padding(16)
            }
            .background(Color.tidexSurfacePrimary)
            .cornerRadius(12)
            .tidexCardShadow(cornerRadius: 12)
        }
    }

    // MARK: - Connected Accounts Section

    private var connectedAccountsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            VStack(alignment: .leading, spacing: 4) {
                Text(.securityConnectionsSectionTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.tidexTextMuted)
                    .textCase(.uppercase)

                Text(.securityConnectionsSectionSubtitle)
                    .font(.system(size: 13))
                    .foregroundColor(.tidexTextSecondary)
            }

            // Connection cards
            VStack(spacing: 2) {
                // Phone connection
                connectionRow(
                    icon: "phone.fill",
                    title: String(localized: .securityConnectionsPhoneTitle),
                    isConnected: viewModel.hasPhoneConnected,
                    connectedText: formatPhoneForDisplay(viewModel.phoneNumber) ?? String(localized: .securityConnectionsPhoneConnected),
                    notConnectedText: String(localized: .securityConnectionsPhoneNotConnected),
                    canDisconnect: viewModel.canUnlinkPhone,
                    onConnect: {
                        viewModel.showPhoneLinkingSheet = true
                    },
                    onDisconnect: {
                        Task { await viewModel.disconnectProvider("phone") }
                    },
                    connectDisabled: false
                )

                Divider()
                    .background(Color.tidexBorder)
                    .padding(.horizontal, 16)

                // Google connection
                connectionRow(
                    icon: "g.circle.fill",
                    title: String(localized: .securityConnectionsGoogleTitle),
                    isConnected: viewModel.hasGoogleConnected,
                    connectedText: String(localized: .securityConnectionsGoogleConnected),
                    notConnectedText: String(localized: .securityConnectionsGoogleNotConnected),
                    canDisconnect: viewModel.canDisconnectGoogle,
                    onConnect: {
                        Task { await viewModel.connectGoogle() }
                    },
                    onDisconnect: {
                        Task { await viewModel.disconnectProvider("google") }
                    },
                    connectDisabled: false
                )

                Divider()
                    .background(Color.tidexBorder)
                    .padding(.horizontal, 16)

                // Apple connection
                connectionRow(
                    icon: "apple.logo",
                    title: String(localized: .securityConnectionsAppleTitle),
                    isConnected: viewModel.hasAppleConnected,
                    connectedText: String(localized: .securityConnectionsAppleConnected),
                    notConnectedText: String(localized: .securityConnectionsAppleNotConnected),
                    canDisconnect: viewModel.canDisconnectApple,
                    onConnect: {
                        Task { await viewModel.connectApple() }
                    },
                    onDisconnect: {
                        Task { await viewModel.disconnectProvider("apple") }
                    },
                    connectDisabled: false
                )
            }
            .background(Color.tidexSurfacePrimary)
            .cornerRadius(12)
            .tidexCardShadow(cornerRadius: 12)
        }
    }

    @ViewBuilder
    // swiftlint:disable:next function_parameter_count
    private func connectionRow(
        icon: String,
        title: String,
        isConnected: Bool,
        connectedText: String,
        notConnectedText: String,
        canDisconnect: Bool,
        onConnect: @escaping () -> Void,
        onDisconnect: @escaping () -> Void,
        connectDisabled: Bool = false
    ) -> some View {
        HStack(spacing: Spacing.sm) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(.tidexBlue)
                .frame(width: 32, height: 32)

            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.tidexTextPrimary)

                Text(isConnected ? connectedText : notConnectedText)
                    .font(.system(size: 13))
                    .foregroundColor(.tidexTextSecondary)

                if isConnected && !canDisconnect {
                    Text(.securityConnectionsAddOtherMethod)
                        .font(.system(size: 11))
                        .foregroundColor(.tidexTextMuted)
                }
            }

            Spacer()

            // Action button
            if isConnected {
                if canDisconnect {
                    // Disconnect button
                    Button(action: onDisconnect) {
                        if viewModel.isConnectingProvider {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .tidexError))
                                .scaleEffect(0.8)
                        } else {
                            Text(.securityConnectionsDisconnect)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.tidexError)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.tidexError.opacity(0.1))
                                .cornerRadius(6)
                        }
                    }
                    .disabled(viewModel.isConnectingProvider)
                } else {
                    // Connected indicator
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.tidexSuccess)

                        Text(.securityConnectionsConnected)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.tidexSuccess)
                    }
                }
            } else if !connectDisabled {
                Button(action: onConnect) {
                    if viewModel.isConnectingProvider {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .tidexBlue))
                            .scaleEffect(0.8)
                    } else {
                        Text(.securityConnectionsConnect)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.tidexBlue)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.tidexBlue.opacity(0.1))
                            .cornerRadius(6)
                    }
                }
                .disabled(viewModel.isConnectingProvider)
            }
        }
        .padding(16)
    }

    // MARK: - MFA Section

    private var mfaSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            VStack(alignment: .leading, spacing: 4) {
                Text(.securityMfaSectionTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.tidexTextMuted)
                    .textCase(.uppercase)

                Text(.securityMfaSectionSubtitle)
                    .font(.system(size: 13))
                    .foregroundColor(.tidexTextSecondary)
            }

            // MFA card
            VStack(spacing: 0) {
                // Enrolled factors
                if viewModel.mfaFactors.isEmpty {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "shield.slash")
                            .font(.system(size: 20))
                            .foregroundColor(.tidexTextMuted)
                            .frame(width: 32, height: 32)

                        Text(.securityMfaNoFactors)
                            .font(.system(size: 14))
                            .foregroundColor(.tidexTextSecondary)

                        Spacer()
                    }
                    .padding(16)
                } else {
                    ForEach(viewModel.mfaFactors) { factor in
                        mfaFactorRow(factor)

                        if factor.id != viewModel.mfaFactors.last?.id {
                            Divider()
                                .background(Color.tidexBorder)
                                .padding(.horizontal, 16)
                        }
                    }
                }

                Divider()
                    .background(Color.tidexBorder)

                // Add factor button
                Button {
                    Task {
                        await viewModel.startMFAEnrollment()
                    }
                } label: {
                    HStack(spacing: 8) {
                        if viewModel.isEnrollingMFA {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .tidexBlue))
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 18))
                        }

                        Text(.securityMfaAddFactor)
                            .font(.system(size: 15, weight: .medium))
                    }
                    .foregroundColor(.tidexBlue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.sm)
                }
                .disabled(viewModel.isEnrollingMFA)
            }
            .background(Color.tidexSurfacePrimary)
            .cornerRadius(12)
            .tidexCardShadow(cornerRadius: 12)

            // Success/Error messages
            if let success = viewModel.successMessage {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.tidexSuccess)
                    Text(success)
                        .font(.system(size: 13))
                        .foregroundColor(.tidexSuccess)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.tidexSuccess.opacity(0.1))
                .cornerRadius(8)
            }

            if let error = viewModel.errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.tidexError)
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundColor(.tidexError)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.tidexError.opacity(0.1))
                .cornerRadius(8)
            }
        }
    }

    @ViewBuilder
    private func mfaFactorRow(_ factor: SecuritySettingsViewModel.MFAFactor) -> some View {
        HStack(spacing: Spacing.sm) {
            // Icon
            Image(systemName: "iphone")
                .font(.system(size: 20))
                .foregroundColor(.tidexBlue)
                .frame(width: 32, height: 32)

            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(factor.displayName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.tidexTextPrimary)

                Text(String(localized: .securityMfaAddedOn(factor.formattedDate)))
                    .font(.system(size: 12))
                    .foregroundColor(.tidexTextMuted)
            }

            Spacer()

            // Delete button
            Button {
                viewModel.factorToUnenroll = factor
                viewModel.showUnenrollConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 16))
                    .foregroundColor(.tidexError)
                    .padding(8)
            }
            .disabled(viewModel.isUnenrollingMFA)
        }
        .padding(16)
    }

    // MARK: - Password Form Sheet

    private var passwordFormSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Instructions
                    Text(viewModel.hasPassword
                         ? String(localized: .securityPasswordChangeInstructions)
                         : viewModel.hasPhoneConnected
                         ? String(localized: .securityPasswordSetWithPhoneInstructions)
                         : String(localized: .securityPasswordSetInstructions))
                        .font(.system(size: 14))
                        .foregroundColor(.tidexTextSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Phone OTP section (for phone-only users without password)
                    if !viewModel.hasPassword && viewModel.hasPhoneConnected {
                        phoneOtpSection
                    }

                    // Password fields (show after OTP sent for phone users, or immediately for others)
                    if viewModel.hasPassword || !viewModel.hasPhoneConnected || viewModel.otpSent {
                        passwordFieldsSection
                    }

                    // Error message
                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundColor(.tidexError)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Success message
                    if let success = viewModel.successMessage {
                        Text(success)
                            .font(.system(size: 13))
                            .foregroundColor(.tidexSuccess)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Submit button
                    if viewModel.hasPassword || !viewModel.hasPhoneConnected || viewModel.otpSent {
                        Button {
                            Task {
                                await viewModel.setPassword()
                            }
                        } label: {
                            HStack {
                                if viewModel.isSettingPassword {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)
                                }
                                Text(viewModel.isSettingPassword
                                     ? String(localized: .securityPasswordSetting)
                                     : viewModel.hasPassword
                                     ? String(localized: .securityPasswordUpdate)
                                     : String(localized: .securityPasswordSet))
                            }
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.sm)
                            .background(canSubmitPassword ? Color.tidexBlue : Color.tidexBlue.opacity(0.5))
                            .cornerRadius(10)
                        }
                        .disabled(!canSubmitPassword || viewModel.isSettingPassword)
                    }
                }
                .padding(24)
            }
            .background(Color.tidexBackground)
            .navigationTitle(viewModel.hasPassword
                             ? String(localized: .securityPasswordChangeTitle)
                             : String(localized: .securityPasswordSetTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: .commonCancel)) {
                        viewModel.resetPasswordForm()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var phoneOtpSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !viewModel.otpSent {
                // Request OTP button
                Button {
                    Task {
                        await viewModel.requestPasswordOTP()
                    }
                } label: {
                    HStack {
                        if viewModel.isSettingPassword {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        }
                        Text(viewModel.isSettingPassword
                             ? String(localized: .securityPasswordSendingCode)
                             : String(localized: .securityPasswordRequestCode))
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.sm)
                    .background(Color.tidexBlue)
                    .cornerRadius(10)
                }
                .disabled(viewModel.isSettingPassword)
            } else {
                // OTP input
                VStack(alignment: .leading, spacing: 6) {
                    Text(.securityPasswordOtpLabel)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.tidexTextSecondary)

                    TextField("123456", text: $viewModel.phoneOtp)
                        .font(.system(size: 16))
                        .foregroundColor(.tidexTextPrimary)
                        .keyboardType(.numberPad)
                        .padding(.horizontal, 12)
                        .padding(.vertical, Spacing.sm)
                        .background(Color.tidexSurfaceSecondary)
                        .cornerRadius(8)
                        .onChange(of: viewModel.phoneOtp) { _, newValue in
                            // Limit to 6 digits
                            let filtered = newValue.filter { $0.isNumber }
                            if filtered.count > 6 {
                                viewModel.phoneOtp = String(filtered.prefix(6))
                            } else if filtered != newValue {
                                viewModel.phoneOtp = filtered
                            }
                        }
                }
            }
        }
    }

    private var passwordFieldsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // New password
            VStack(alignment: .leading, spacing: 6) {
                Text(viewModel.hasPassword
                     ? String(localized: .securityPasswordNewPasswordLabel)
                     : String(localized: .securityPasswordPasswordLabel))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.tidexTextSecondary)

                SecureField(String(localized: .securityPasswordPasswordPlaceholder), text: $viewModel.newPassword)
                    .font(.system(size: 16))
                    .foregroundColor(.tidexTextPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, Spacing.sm)
                    .background(Color.tidexSurfaceSecondary)
                    .cornerRadius(8)
            }

            // Confirm password
            VStack(alignment: .leading, spacing: 6) {
                Text(.securityPasswordConfirmPasswordLabel)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.tidexTextSecondary)

                SecureField(String(localized: .securityPasswordPasswordPlaceholder), text: $viewModel.confirmPassword)
                    .font(.system(size: 16))
                    .foregroundColor(.tidexTextPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, Spacing.sm)
                    .background(Color.tidexSurfaceSecondary)
                    .cornerRadius(8)
            }

            // Password hint
            Text(.securityPasswordHint)
                .font(.system(size: 12))
                .foregroundColor(.tidexTextMuted)
        }
    }

    private var canSubmitPassword: Bool {
        let hasPassword = !viewModel.newPassword.isEmpty && !viewModel.confirmPassword.isEmpty
        let hasOtp = !viewModel.hasPassword && viewModel.hasPhoneConnected ? !viewModel.phoneOtp.isEmpty : true
        return hasPassword && hasOtp
    }

    // MARK: - MFA Enrollment Sheet

    private var mfaEnrollmentSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // QR Code - Generated natively from TOTP URI
                    if let totpUri = viewModel.mfaTotpUri {
                        qrCodeSection(totpUri)
                    }

                    // Manual entry secret
                    if let secret = viewModel.mfaSecret {
                        manualEntrySection(secret)
                    }

                    // Verification code input
                    verificationCodeSection

                    // Error message
                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundColor(.tidexError)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Buttons
                    VStack(spacing: 12) {
                        Button {
                            Task {
                                await viewModel.verifyMFAEnrollment()
                            }
                        } label: {
                            HStack {
                                if viewModel.isVerifyingMFA {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)
                                }
                                Text(viewModel.isVerifyingMFA
                                     ? String(localized: .securityMfaVerifying)
                                     : String(localized: .securityMfaVerify))
                            }
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.sm)
                            .background(viewModel.mfaVerifyCode.count == 6 ? Color.tidexBlue : Color.tidexBlue.opacity(0.5))
                            .cornerRadius(10)
                        }
                        .disabled(viewModel.mfaVerifyCode.count != 6 || viewModel.isVerifyingMFA)

                        // Open in app button
                        if let uri = viewModel.mfaTotpUri, let url = URL(string: uri) {
                            Button {
                                UIApplication.shared.open(url)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.up.right.square")
                                    Text(.securityMfaOpenInApp)
                                }
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.tidexBlue)
                            }
                        }
                    }
                }
                .padding(24)
            }
            .background(Color.tidexBackground)
            .navigationTitle(String(localized: .securityMfaEnrollTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: .commonCancel)) {
                        Task {
                            await viewModel.cancelMFAEnrollment()
                        }
                    }
                }
            }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder
    private func qrCodeSection(_ totpUri: String) -> some View {
        VStack(spacing: 12) {
            Text(.securityMfaScanQR)
                .font(.system(size: 14))
                .foregroundColor(.tidexTextSecondary)
                .multilineTextAlignment(.center)

            // QR Code - Generated natively from otpauth:// URI
            if let qrImage = generateQRCode(from: totpUri) {
                Image(uiImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white)
                            .padding(-8)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                // Fallback if QR generation fails
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white)
                        .frame(width: 200, height: 200)

                    VStack(spacing: 8) {
                        Image(systemName: "qrcode")
                            .font(.system(size: 60))
                            .foregroundColor(.tidexTextMuted)

                        Text(.securityMfaUseSecretBelow)
                            .font(.system(size: 12))
                            .foregroundColor(.tidexTextMuted)
                            .multilineTextAlignment(.center)
                    }
                }
            }
        }
    }

    /// Generate QR code from a string using CoreImage
    private func generateQRCode(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()

        guard let data = string.data(using: .utf8) else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel") // High error correction

        guard let outputImage = filter.outputImage else { return nil }

        // Scale up the QR code for better quality
        let scale = 10.0
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    @ViewBuilder
    private func manualEntrySection(_ secret: String) -> some View {
        VStack(spacing: 8) {
            Text(.securityMfaManualEntry)
                .font(.system(size: 13))
                .foregroundColor(.tidexTextSecondary)

            // Secret code with copy button
            HStack {
                Text(secret)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.tidexTextPrimary)
                    .lineLimit(1)

                Spacer()

                Button {
                    UIPasteboard.general.string = secret
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 14))
                        .foregroundColor(.tidexBlue)
                }
            }
            .padding(12)
            .background(Color.tidexSurfaceSecondary)
            .cornerRadius(8)
        }
    }

    private var verificationCodeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(.securityMfaVerifyLabel)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.tidexTextSecondary)

            // 6-digit code input using OTPInputField style
            TextField("000000", text: $viewModel.mfaVerifyCode)
                .font(.system(size: 24, weight: .semibold, design: .monospaced))
                .foregroundColor(.tidexTextPrimary)
                .multilineTextAlignment(.center)
                .keyboardType(.numberPad)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.tidexSurfaceSecondary)
                .cornerRadius(8)
                .onChange(of: viewModel.mfaVerifyCode) { _, newValue in
                    // Limit to 6 digits
                    let filtered = newValue.filter { $0.isNumber }
                    if filtered.count > 6 {
                        viewModel.mfaVerifyCode = String(filtered.prefix(6))
                    } else if filtered != newValue {
                        viewModel.mfaVerifyCode = filtered
                    }
                }
        }
    }

    // MARK: - Phone Linking Sheet

    private var phoneLinkingSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Instructions
                    Text(viewModel.phoneLinkStep == .input
                         ? String(localized: .securityPhoneLinkingInstructionEnter)
                         : String(localized: .securityPhoneLinkingInstructionVerify))
                        .font(.system(size: 14))
                        .foregroundColor(.tidexTextSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if viewModel.phoneLinkStep == .input {
                        phoneLinkInputSection
                    } else {
                        phoneLinkOtpSection
                    }

                    // Error message
                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundColor(.tidexError)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Success message
                    if let success = viewModel.successMessage {
                        Text(success)
                            .font(.system(size: 13))
                            .foregroundColor(.tidexSuccess)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Action button
                    Button {
                        Task {
                            if viewModel.phoneLinkStep == .input {
                                await viewModel.connectPhone()
                            } else {
                                await viewModel.verifyPhoneLinkOTP()
                            }
                        }
                    } label: {
                        HStack {
                            if viewModel.isLinkingPhone {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            }
                            Text(viewModel.isLinkingPhone
                                 ? (viewModel.phoneLinkStep == .input
                                    ? String(localized: .securityPhoneLinkingSending)
                                    : String(localized: .securityPhoneLinkingVerifying))
                                 : (viewModel.phoneLinkStep == .input
                                    ? String(localized: .securityPhoneLinkingSendCode)
                                    : String(localized: .securityPhoneLinkingVerify)))
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.sm)
                        .background(canSubmitPhoneLinking ? Color.tidexBlue : Color.tidexBlue.opacity(0.5))
                        .cornerRadius(10)
                    }
                    .disabled(!canSubmitPhoneLinking || viewModel.isLinkingPhone)
                }
                .padding(24)
            }
            .background(Color.tidexBackground)
            .navigationTitle(String(localized: .securityPhoneLinkingTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: .commonCancel)) {
                        viewModel.resetPhoneLinkingForm()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var phoneLinkInputSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(.securityPhoneLinkingPhoneLabel)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.tidexTextSecondary)

            HStack(spacing: 8) {
                // Country code indicator
                Text("+47")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.tidexTextPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, Spacing.sm)
                    .background(Color.tidexSurfaceSecondary)
                    .cornerRadius(8)

                TextField("12345678", text: $viewModel.phoneLinkInput)
                    .font(.system(size: 16))
                    .foregroundColor(.tidexTextPrimary)
                    .keyboardType(.numberPad)
                    .padding(.horizontal, 12)
                    .padding(.vertical, Spacing.sm)
                    .background(Color.tidexSurfaceSecondary)
                    .cornerRadius(8)
                    .onChange(of: viewModel.phoneLinkInput) { _, newValue in
                        // Limit to 8 digits (Norwegian phone numbers)
                        let filtered = newValue.filter { $0.isNumber }
                        if filtered.count > 8 {
                            viewModel.phoneLinkInput = String(filtered.prefix(8))
                        } else if filtered != newValue {
                            viewModel.phoneLinkInput = filtered
                        }
                    }
            }

            Text(.securityPhoneLinkingPhoneHint)
                .font(.system(size: 12))
                .foregroundColor(.tidexTextMuted)
        }
    }

    private var phoneLinkOtpSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Show the phone number that code was sent to
            HStack(spacing: 8) {
                Image(systemName: "phone.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.tidexBlue)
                Text(formatPhoneForDisplay(viewModel.phoneLinkInput) ?? "+47 \(viewModel.phoneLinkInput)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.tidexTextPrimary)

                Spacer()

                Button {
                    viewModel.phoneLinkStep = .input
                    viewModel.phoneLinkOtp = ""
                    viewModel.errorMessage = nil
                } label: {
                    Text(.securityPhoneLinkingChangeNumber)
                        .font(.system(size: 13))
                        .foregroundColor(.tidexBlue)
                }
            }
            .padding(12)
            .background(Color.tidexSurfaceSecondary)
            .cornerRadius(8)

            // OTP input
            VStack(alignment: .leading, spacing: 6) {
                Text(.securityPhoneLinkingOtpLabel)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.tidexTextSecondary)

                TextField("123456", text: $viewModel.phoneLinkOtp)
                    .font(.system(size: 24, weight: .semibold, design: .monospaced))
                    .foregroundColor(.tidexTextPrimary)
                    .multilineTextAlignment(.center)
                    .keyboardType(.numberPad)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.tidexSurfaceSecondary)
                    .cornerRadius(8)
                    .onChange(of: viewModel.phoneLinkOtp) { _, newValue in
                        // Limit to 6 digits
                        let filtered = newValue.filter { $0.isNumber }
                        if filtered.count > 6 {
                            viewModel.phoneLinkOtp = String(filtered.prefix(6))
                        } else if filtered != newValue {
                            viewModel.phoneLinkOtp = filtered
                        }
                    }
            }
        }
    }

    private var canSubmitPhoneLinking: Bool {
        if viewModel.phoneLinkStep == .input {
            return viewModel.phoneLinkInput.count == 8
        } else {
            return viewModel.phoneLinkOtp.count == 6
        }
    }

    /// Format a phone number for display (Norwegian: nnn nn nnn)
    private func formatPhoneForDisplay(_ phone: String?) -> String? {
        guard let phone = phone else { return nil }

        // Remove any non-digit characters and country code
        var digits = phone.filter { $0.isNumber }

        // Remove Norwegian country code if present
        if digits.hasPrefix("47") && digits.count > 8 {
            digits = String(digits.dropFirst(2))
        }

        // Format as "nnn nn nnn" for 8-digit Norwegian numbers
        guard digits.count == 8 else { return phone }

        let part1 = digits.prefix(3)
        let part2 = digits.dropFirst(3).prefix(2)
        let part3 = digits.dropFirst(5)

        return "+47 \(part1) \(part2) \(part3)"
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        SecuritySettingsView()
    }
}
