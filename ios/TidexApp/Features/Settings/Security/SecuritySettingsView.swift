import CoreImage.CIFilterBuiltins
import SwiftUI

/// Security settings view
/// Displays password management, connected accounts, and MFA settings
struct SecuritySettingsView: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var viewModel = SecuritySettingsViewModel()

  /// Whether AI data sharing is enabled (Wagey consent)
  @State private var aiDataSharingEnabled = WageyViewModel.shared.hasConsentedToAISharing
  /// Whether to show the consent view when re-enabling AI data sharing
  @State private var showAIConsentSheet = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Spacing.lg) {
        // Error message
        if let error = viewModel.errorMessage {
          HStack(spacing: Spacing.xs) {
            Image(systemName: "exclamationmark.circle.fill")
              .foregroundColor(.tidexError)
            Text(error)
              .font(.tidexSubheadline)
              .foregroundColor(.tidexError)
            Spacer()
            Button {
              viewModel.clearMessages()
            } label: {
              Image(systemName: "xmark")
                .font(.tidexCaptionStrong)
                .foregroundColor(.tidexError)
            }
          }
          .padding(Spacing.sm)
          .background(Color.tidexError.opacity(0.1))
          .cornerRadius(CornerRadius.sm)
        }

        // AI data sharing section
        aiDataSharingSection

        if viewModel.isOfflineLimited {
          Text(.securityOfflineManageUnavailable)
            .font(.tidexFootnote)
            .foregroundColor(.tidexTextMuted)
            .padding(.horizontal, Spacing.sm)
        }

        // Password section
        passwordSection

        // Connected accounts section
        connectedAccountsSection

        // Passkeys section
        passkeysSection

        // MFA section
        mfaSection
      }
      .padding(.horizontal, Spacing.md)
      .padding(.vertical, Spacing.lg)
    }
    .background(Color.tidexBackground)
    .navigationTitle(String(localized: .securityTitle))
    .navigationBarTitleDisplayMode(.inline)
    .onAppear {
      refreshAIDataSharingState()
    }
    .onChange(of: WageyViewModel.shared.hasConsentedToAISharing) { _, newValue in
      aiDataSharingEnabled = newValue
    }
    .task {
      await viewModel.loadSecurityInfo()
    }
    .sheet(isPresented: $showAIConsentSheet) {
      WageyConsentView(
        onAgree: {
          WageyViewModel.shared.grantAIConsent()
          refreshAIDataSharingState()
          showAIConsentSheet = false
        },
        onDecline: {
          aiDataSharingEnabled = false
          showAIConsentSheet = false
        }
      )
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
    .alert(
      String(localized: .securityMfaUnenrollDialogTitle),
      isPresented: $viewModel.showUnenrollConfirmation
    ) {
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
    .alert(
      String(localized: .securityPasskeysRenameDialogTitle),
      isPresented: $viewModel.showRenamePasskeyAlert
    ) {
      TextField(
        String(localized: .securityPasskeysRenameDialogPlaceholder),
        text: $viewModel.passkeyNameDraft
      )
      .textInputAutocapitalization(.words)

      Button(String(localized: .commonCancel), role: .cancel) {
        viewModel.cancelRenamingPasskey()
      }

      Button(String(localized: .commonSave)) {
        Task {
          await viewModel.renameSelectedPasskey()
        }
      }
      .disabled(!viewModel.canSavePasskeyName || viewModel.isOfflineLimited)
    }
    .alert(
      String(localized: .securityPasskeysDeleteDialogTitle),
      isPresented: $viewModel.showDeletePasskeyConfirmation
    ) {
      Button(String(localized: .commonCancel), role: .cancel) {
        viewModel.passkeyToDelete = nil
      }
      Button(String(localized: .securityPasskeysDeleteDialogConfirm), role: .destructive) {
        if let passkey = viewModel.passkeyToDelete {
          Task {
            await viewModel.deletePasskey(passkey)
          }
        }
      }
    } message: {
      Text(.securityPasskeysDeleteDialogDescription)
    }
  }

  @ViewBuilder
  private func settingsSection<Content: View>(
    title: String,
    footer: String? = nil,
    @ViewBuilder content: () -> Content
  ) -> some View {
    TidexSettingsSection(
      title: title,
      footer: {
        if let footer {
          Text(footer)
        }
      }
    ) {
      content()
    }
  }

  private var settingsDivider: some View {
    TidexSettingsDivider()
  }

  private func refreshAIDataSharingState() {
    let wageyViewModel = WageyViewModel.shared
    wageyViewModel.refreshEntryState()
    aiDataSharingEnabled = wageyViewModel.hasConsentedToAISharing
  }

  // MARK: - AI Data Sharing Section

  private var aiDataSharingSection: some View {
    settingsSection(
      title: String(localized: .settingsWageyAiDataSharing),
      footer: String(localized: .settingsWageyAiDataSharingDescription)
    ) {
      Toggle(
        isOn: Binding(
          get: { aiDataSharingEnabled },
          set: { newValue in
            if newValue {
              showAIConsentSheet = true
            } else {
              aiDataSharingEnabled = false
              WageyViewModel.shared.revokeAIConsent()
            }
          }
        )
      ) {
        HStack(spacing: Spacing.sm) {
          TidexSettingsIcon(systemName: "sparkles", foregroundColor: .tidexBlue, size: 29)

          Text(.settingsWageyAiDataSharing)
            .font(.tidexBodyMedium)
            .foregroundColor(.tidexTextPrimary)
        }
      }
      .tint(.tidexBlue)
    }
  }

  // MARK: - Password Section

  private var passwordSection: some View {
    settingsSection(title: String(localized: .securityPasswordSectionTitle)) {
      HStack(spacing: Spacing.sm) {
        // Icon
        TidexSettingsIcon(systemName: "lock.fill", foregroundColor: .tidexBlue, size: 29)

        // Content
        VStack(alignment: .leading, spacing: Spacing.micro) {
          Text(.securityPasswordTitle)
            .font(.tidexBodyMedium)
            .foregroundColor(.tidexTextPrimary)

          Text(
            viewModel.hasPassword
              ? String(localized: .securityPasswordHasPassword)
              : String(localized: .securityPasswordNoPassword)
          )
          .font(.tidexFootnote)
          .foregroundColor(.tidexTextSecondary)
        }

        Spacer()

        // Button
        Button {
          viewModel.showPasswordForm = true
        } label: {
          Text(
            viewModel.hasPassword
              ? String(localized: .securityPasswordChange)
              : String(localized: .securityPasswordSet)
          )
          .font(.tidexLabel)
          .foregroundColor(viewModel.hasPassword ? .tidexBlue : .tidexTextOnBrand)
          .padding(.horizontal, Spacing.md)
          .padding(.vertical, Spacing.xs)
          .background(viewModel.hasPassword ? Color.tidexBlue.opacity(0.1) : Color.tidexBlue)
          .cornerRadius(CornerRadius.sm)
        }
        .disabled(viewModel.isOfflineLimited)
        .opacity(viewModel.isOfflineLimited ? 0.55 : 1)
      }
    }
  }

  // MARK: - Connected Accounts Section

  private var connectedAccountsSection: some View {
    settingsSection(
      title: String(localized: .securityConnectionsSectionTitle),
      footer: String(localized: .securityConnectionsSectionSubtitle)
    ) {
      // Phone connection
      connectionRow(
        icon: "phone.fill",
        iconColor: .tidexBlue,
        title: String(localized: .securityConnectionsPhoneTitle),
        isConnected: viewModel.hasPhoneConnected,
        connectedText: formatPhoneForDisplay(viewModel.phoneNumber)
          ?? String(localized: .securityConnectionsPhoneConnected),
        notConnectedText: String(localized: .securityConnectionsPhoneNotConnected),
        canDisconnect: viewModel.canUnlinkPhone,
        onConnect: {
          viewModel.showPhoneLinkingSheet = true
        },
        onDisconnect: {
          Task { await viewModel.disconnectProvider("phone") }
        },
        connectDisabled: viewModel.isOfflineLimited
      )

      settingsDivider

      // Google connection
      connectionRow(
        icon: "g.circle.fill",
        iconColor: .tidexBlue,
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
        connectDisabled: viewModel.isOfflineLimited
      )

      settingsDivider

      // Apple connection
      connectionRow(
        icon: "apple.logo",
        iconColor: .tidexBlue,
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
        connectDisabled: viewModel.isOfflineLimited
      )
    }
  }

  @ViewBuilder
  // swiftlint:disable:next function_parameter_count
  private func connectionRow(
    icon: String,
    iconColor: Color,
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
      TidexSettingsIcon(systemName: icon, foregroundColor: iconColor, size: 29)

      // Content
      VStack(alignment: .leading, spacing: Spacing.micro) {
        Text(title)
          .font(.tidexBodyMedium)
          .foregroundColor(.tidexTextPrimary)

        Text(isConnected ? connectedText : notConnectedText)
          .font(.tidexFootnote)
          .foregroundColor(.tidexTextSecondary)

        if isConnected && !canDisconnect {
          Text(.securityConnectionsAddOtherMethod)
            .font(.tidexMicro)
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
                .font(.tidexLabel)
                .foregroundColor(.tidexError)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xxxs)
                .background(Color.tidexError.opacity(0.1))
                .cornerRadius(CornerRadius.xs)
            }
          }
          .disabled(viewModel.isConnectingProvider || viewModel.isOfflineLimited)
        } else {
          // Connected indicator
          HStack(spacing: Spacing.xxs) {
            Image(systemName: "checkmark.circle.fill")
              .font(.tidexSubheadline)
              .foregroundColor(.tidexSuccess)

            Text(.securityConnectionsConnected)
              .font(.tidexFootnoteMedium)
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
              .font(.tidexLabel)
              .foregroundColor(.tidexBlue)
              .padding(.horizontal, Spacing.sm)
              .padding(.vertical, Spacing.xxxs)
              .background(Color.tidexBlue.opacity(0.1))
              .cornerRadius(CornerRadius.xs)
          }
        }
        .disabled(viewModel.isConnectingProvider || viewModel.isOfflineLimited)
      }
    }
  }

  // MARK: - Passkeys Section

  private var passkeysSection: some View {
    settingsSection(
      title: String(localized: .securityPasskeysSectionTitle),
      footer: String(localized: .securityPasskeysSectionSubtitle)
    ) {
      if viewModel.passkeys.isEmpty {
        HStack(spacing: Spacing.sm) {
          TidexSettingsIcon(systemName: "key.slash", foregroundColor: .tidexBlue, size: 29)

          Text(.securityPasskeysNoPasskeys)
            .font(.tidexSubheadline)
            .foregroundColor(.tidexTextSecondary)

          Spacer()
        }

        settingsDivider
      } else {
        ForEach(viewModel.passkeys) { passkey in
          passkeyRow(passkey)
          settingsDivider
        }
      }

      Button {
        Task {
          await viewModel.registerPasskey()
        }
      } label: {
        HStack(spacing: Spacing.xs) {
          if viewModel.isRegisteringPasskey {
            ProgressView()
              .progressViewStyle(CircularProgressViewStyle(tint: .tidexBlue))
              .scaleEffect(0.8)
          } else {
            Image(systemName: "plus.circle.fill")
              .font(.tidexHeadline)
          }

          Text(
            viewModel.isRegisteringPasskey
              ? String(localized: .securityPasskeysAdding)
              : String(localized: .securityPasskeysAdd)
          )
          .font(.tidexLabel)
        }
        .foregroundColor(.tidexBlue)
        .frame(maxWidth: .infinity)
      }
      .disabled(viewModel.isRegisteringPasskey || viewModel.isOfflineLimited)
      .opacity(viewModel.isOfflineLimited ? 0.55 : 1)
    }
  }

  @ViewBuilder
  private func passkeyRow(_ passkey: PasskeyAuthService.Passkey) -> some View {
    HStack(spacing: Spacing.sm) {
      TidexSettingsIcon(systemName: "person.badge.key.fill", foregroundColor: .tidexBlue, size: 29)

      VStack(alignment: .leading, spacing: Spacing.micro) {
        Text(passkey.displayName)
          .font(.tidexLabel)
          .foregroundColor(.tidexTextPrimary)

        Text(String(localized: .securityMfaAddedOn(passkey.formattedCreatedAt)))
          .font(.tidexCaptionRegular)
          .foregroundColor(.tidexTextMuted)
      }

      Spacer()

      if viewModel.isRenamingPasskey && viewModel.passkeyToRename?.id == passkey.id {
        ProgressView()
          .progressViewStyle(CircularProgressViewStyle(tint: .tidexTextMuted))
          .scaleEffect(0.75)
          .padding(Spacing.xs)
      } else {
        Button {
          viewModel.startRenamingPasskey(passkey)
        } label: {
          Image(systemName: "pencil")
            .font(.tidexBody)
            .foregroundColor(.tidexTextPrimary)
            .padding(Spacing.xs)
        }
        .disabled(
          viewModel.isRenamingPasskey || viewModel.isDeletingPasskey || viewModel.isOfflineLimited
        )
        .opacity(viewModel.isOfflineLimited ? 0.55 : 1)
      }

      Button {
        viewModel.passkeyToDelete = passkey
        viewModel.showDeletePasskeyConfirmation = true
      } label: {
        Image(systemName: "trash")
          .font(.tidexBody)
          .foregroundColor(.tidexError)
          .padding(Spacing.xs)
      }
      .disabled(
        viewModel.isDeletingPasskey || viewModel.isRenamingPasskey || viewModel.isOfflineLimited
      )
      .opacity(viewModel.isOfflineLimited ? 0.55 : 1)
    }
  }

  // MARK: - MFA Section

  private var mfaSection: some View {
    settingsSection(
      title: String(localized: .securityMfaSectionTitle),
      footer: String(localized: .securityMfaSectionSubtitle)
    ) {
      // Enrolled factors
      if viewModel.mfaFactors.isEmpty {
        HStack(spacing: Spacing.sm) {
          TidexSettingsIcon(systemName: "shield.slash", foregroundColor: .tidexBlue, size: 29)

          Text(.securityMfaNoFactors)
            .font(.tidexSubheadline)
            .foregroundColor(.tidexTextSecondary)

          Spacer()
        }

        settingsDivider
      } else {
        ForEach(viewModel.mfaFactors) { factor in
          mfaFactorRow(factor)
          settingsDivider
        }
      }

      // Add factor button
      Button {
        Task {
          await viewModel.startMFAEnrollment()
        }
      } label: {
        HStack(spacing: Spacing.xs) {
          if viewModel.isEnrollingMFA {
            ProgressView()
              .progressViewStyle(CircularProgressViewStyle(tint: .tidexBlue))
              .scaleEffect(0.8)
          } else {
            Image(systemName: "plus.circle.fill")
              .font(.tidexHeadline)
          }

          Text(.securityMfaAddFactor)
            .font(.tidexLabel)
        }
        .foregroundColor(.tidexBlue)
        .frame(maxWidth: .infinity)
      }
      .disabled(viewModel.isEnrollingMFA || viewModel.isOfflineLimited)
      .opacity(viewModel.isOfflineLimited ? 0.55 : 1)
    }
  }

  @ViewBuilder
  private func mfaFactorRow(_ factor: SecuritySettingsViewModel.MFAFactor) -> some View {
    HStack(spacing: Spacing.sm) {
      // Icon
      TidexSettingsIcon(systemName: "iphone", foregroundColor: .tidexBlue, size: 29)

      // Content
      VStack(alignment: .leading, spacing: Spacing.micro) {
        Text(factor.displayName)
          .font(.tidexLabel)
          .foregroundColor(.tidexTextPrimary)

        Text(String(localized: .securityMfaAddedOn(factor.formattedDate)))
          .font(.tidexCaptionRegular)
          .foregroundColor(.tidexTextMuted)
      }

      Spacer()

      // Delete button
      Button {
        viewModel.factorToUnenroll = factor
        viewModel.showUnenrollConfirmation = true
      } label: {
        Image(systemName: "trash")
          .font(.tidexBody)
          .foregroundColor(.tidexError)
          .padding(Spacing.xs)
      }
      .disabled(viewModel.isUnenrollingMFA || viewModel.isOfflineLimited)
      .opacity(viewModel.isOfflineLimited ? 0.55 : 1)
    }
  }

  // MARK: - Password Form Sheet

  private var passwordFormSheet: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: Spacing.lg) {
          // Instructions
          Text(
            viewModel.hasPassword
              ? String(localized: .securityPasswordChangeInstructions)
              : viewModel.hasPhoneConnected
                ? String(localized: .securityPasswordSetWithPhoneInstructions)
                : String(localized: .securityPasswordSetInstructions)
          )
          .font(.tidexSubheadline)
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
              .font(.tidexFootnote)
              .foregroundColor(.tidexError)
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
                    .progressViewStyle(CircularProgressViewStyle(tint: .tidexTextOnBrand))
                    .scaleEffect(0.8)
                }
                Text(
                  viewModel.isSettingPassword
                    ? String(localized: .securityPasswordSetting)
                    : viewModel.hasPassword
                      ? String(localized: .securityPasswordUpdate)
                      : String(localized: .securityPasswordSet))
              }
              .font(.tidexButton)
              .foregroundColor(.tidexTextOnBrand)
              .frame(maxWidth: .infinity)
              .padding(.vertical, Spacing.sm)
              .background(canSubmitPassword ? Color.tidexBlue : Color.tidexBlue.opacity(0.5))
              .cornerRadius(CornerRadius.md)
            }
            .disabled(!canSubmitPassword || viewModel.isSettingPassword)
          }
        }
        .padding(Spacing.lg)
      }
      .background(Color.tidexBackground)
      .navigationTitle(
        viewModel.hasPassword
          ? String(localized: .securityPasswordChangeTitle)
          : String(localized: .securityPasswordSetTitle)
      )
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
    VStack(alignment: .leading, spacing: Spacing.sm) {
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
                .progressViewStyle(CircularProgressViewStyle(tint: .tidexTextOnBrand))
                .scaleEffect(0.8)
            }
            Text(
              viewModel.isSettingPassword
                ? String(localized: .securityPasswordSendingCode)
                : String(localized: .securityPasswordRequestCode))
          }
          .font(.tidexButton)
          .foregroundColor(.tidexTextOnBrand)
          .frame(maxWidth: .infinity)
          .padding(.vertical, Spacing.sm)
          .background(Color.tidexBlue)
          .cornerRadius(CornerRadius.md)
        }
        .disabled(viewModel.isSettingPassword)
      } else {
        // OTP input
        VStack(alignment: .leading, spacing: Spacing.xxxs) {
          Text(.securityPasswordOtpLabel)
            .font(.tidexFootnoteMedium)
            .foregroundColor(.tidexTextSecondary)

          TextField("123456", text: $viewModel.phoneOtp)
            .font(.tidexBody)
            .foregroundColor(.tidexTextPrimary)
            .keyboardType(.numberPad)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.sm)
            .background(Color.tidexSurfaceSecondary)
            .cornerRadius(CornerRadius.sm)
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
    VStack(alignment: .leading, spacing: Spacing.md) {
      // New password
      VStack(alignment: .leading, spacing: Spacing.xxxs) {
        Text(
          viewModel.hasPassword
            ? String(localized: .securityPasswordNewPasswordLabel)
            : String(localized: .securityPasswordPasswordLabel)
        )
        .font(.tidexFootnoteMedium)
        .foregroundColor(.tidexTextSecondary)

        SecureField(
          String(localized: .securityPasswordPasswordPlaceholder), text: $viewModel.newPassword
        )
        .font(.tidexBody)
        .foregroundColor(.tidexTextPrimary)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.sm)
        .background(Color.tidexSurfaceSecondary)
        .cornerRadius(CornerRadius.sm)
      }

      // Confirm password
      VStack(alignment: .leading, spacing: Spacing.xxxs) {
        Text(.securityPasswordConfirmPasswordLabel)
          .font(.tidexFootnoteMedium)
          .foregroundColor(.tidexTextSecondary)

        SecureField(
          String(localized: .securityPasswordPasswordPlaceholder), text: $viewModel.confirmPassword
        )
        .font(.tidexBody)
        .foregroundColor(.tidexTextPrimary)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.sm)
        .background(Color.tidexSurfaceSecondary)
        .cornerRadius(CornerRadius.sm)
      }

      // Password hint
      Text(.securityPasswordHint)
        .font(.tidexCaptionRegular)
        .foregroundColor(.tidexTextMuted)
    }
  }

  private var canSubmitPassword: Bool {
    let hasPassword = !viewModel.newPassword.isEmpty && !viewModel.confirmPassword.isEmpty
    let hasOtp =
      !viewModel.hasPassword && viewModel.hasPhoneConnected ? !viewModel.phoneOtp.isEmpty : true
    return hasPassword && hasOtp
  }

  // MARK: - MFA Enrollment Sheet

  private var mfaEnrollmentSheet: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: Spacing.lg) {
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
              .font(.tidexFootnote)
              .foregroundColor(.tidexError)
              .frame(maxWidth: .infinity, alignment: .leading)
          }

          // Buttons
          VStack(spacing: Spacing.sm) {
            Button {
              Task {
                await viewModel.verifyMFAEnrollment()
              }
            } label: {
              HStack {
                if viewModel.isVerifyingMFA {
                  ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .tidexTextOnBrand))
                    .scaleEffect(0.8)
                }
                Text(
                  viewModel.isVerifyingMFA
                    ? String(localized: .securityMfaVerifying)
                    : String(localized: .securityMfaVerify))
              }
              .font(.tidexButton)
              .foregroundColor(.tidexTextOnBrand)
              .frame(maxWidth: .infinity)
              .padding(.vertical, Spacing.sm)
              .background(
                viewModel.mfaVerifyCode.count == 6 ? Color.tidexBlue : Color.tidexBlue.opacity(0.5)
              )
              .cornerRadius(CornerRadius.md)
            }
            .disabled(viewModel.mfaVerifyCode.count != 6 || viewModel.isVerifyingMFA)

            // Open in app button
            if let uri = viewModel.mfaTotpUri, let url = URL(string: uri) {
              Button {
                UIApplication.shared.open(url)
              } label: {
                HStack(spacing: Spacing.xxxs) {
                  Image(systemName: "arrow.up.right.square")
                  Text(.securityMfaOpenInApp)
                }
                .font(.tidexLabel)
                .foregroundColor(.tidexBlue)
              }
            }
          }
        }
        .padding(Spacing.lg)
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
    VStack(spacing: Spacing.sm) {
      Text(.securityMfaScanQR)
        .font(.tidexSubheadline)
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
            RoundedRectangle(cornerRadius: CornerRadius.lg)
              .fill(Color.white)
              .padding(-Spacing.xs)
          )
          .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg))
      } else {
        // Fallback if QR generation fails
        ZStack {
          RoundedRectangle(cornerRadius: CornerRadius.lg)
            .fill(Color.white)
            .frame(width: 200, height: 200)

          VStack(spacing: Spacing.xs) {
            Image(systemName: "qrcode")
              .font(.system(size: 60))
              .foregroundColor(.tidexTextMuted)

            Text(.securityMfaUseSecretBelow)
              .font(.tidexCaptionRegular)
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
    filter.setValue("H", forKey: "inputCorrectionLevel")  // High error correction

    guard let outputImage = filter.outputImage else { return nil }

    // Scale up the QR code for better quality
    let scale = 10.0
    let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

    guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
      return nil
    }
    return UIImage(cgImage: cgImage)
  }

  @ViewBuilder
  private func manualEntrySection(_ secret: String) -> some View {
    VStack(spacing: Spacing.xs) {
      Text(.securityMfaManualEntry)
        .font(.tidexFootnote)
        .foregroundColor(.tidexTextSecondary)

      // Secret code with copy button
      HStack {
        Text(secret)
          .font(.tidexMonoCaptionRegular)
          .foregroundColor(.tidexTextPrimary)
          .lineLimit(1)

        Spacer()

        Button {
          UIPasteboard.general.string = secret
        } label: {
          Image(systemName: "doc.on.doc")
            .font(.tidexSubheadline)
            .foregroundColor(.tidexBlue)
        }
      }
      .padding(Spacing.sm)
      .background(Color.tidexSurfaceSecondary)
      .cornerRadius(CornerRadius.sm)
    }
  }

  private var verificationCodeSection: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      Text(.securityMfaVerifyLabel)
        .font(.tidexFootnoteMedium)
        .foregroundColor(.tidexTextSecondary)

      // 6-digit code input using OTPInputField style
      TextField("000000", text: $viewModel.mfaVerifyCode)
        .font(.tidexMonoTitle)
        .foregroundColor(.tidexTextPrimary)
        .multilineTextAlignment(.center)
        .keyboardType(.numberPad)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(Color.tidexSurfaceSecondary)
        .cornerRadius(CornerRadius.sm)
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
        VStack(spacing: Spacing.lg) {
          // Instructions
          Text(
            viewModel.phoneLinkStep == .input
              ? String(localized: .securityPhoneLinkingInstructionEnter)
              : String(localized: .securityPhoneLinkingInstructionVerify)
          )
          .font(.tidexSubheadline)
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
              .font(.tidexFootnote)
              .foregroundColor(.tidexError)
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
                  .progressViewStyle(CircularProgressViewStyle(tint: .tidexTextOnBrand))
                  .scaleEffect(0.8)
              }
              Text(
                viewModel.isLinkingPhone
                  ? (viewModel.phoneLinkStep == .input
                    ? String(localized: .securityPhoneLinkingSending)
                    : String(localized: .securityPhoneLinkingVerifying))
                  : (viewModel.phoneLinkStep == .input
                    ? String(localized: .securityPhoneLinkingSendCode)
                    : String(localized: .securityPhoneLinkingVerify)))
            }
            .font(.tidexButton)
            .foregroundColor(.tidexTextOnBrand)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
            .background(canSubmitPhoneLinking ? Color.tidexBlue : Color.tidexBlue.opacity(0.5))
            .cornerRadius(CornerRadius.md)
          }
          .disabled(!canSubmitPhoneLinking || viewModel.isLinkingPhone)
        }
        .padding(Spacing.lg)
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
    VStack(alignment: .leading, spacing: Spacing.xxxs) {
      Text(.securityPhoneLinkingPhoneLabel)
        .font(.tidexFootnoteMedium)
        .foregroundColor(.tidexTextSecondary)

      HStack(spacing: Spacing.xs) {
        // Country code indicator
        Text("+47")
          .font(.tidexBodyMedium)
          .foregroundColor(.tidexTextPrimary)
          .padding(.horizontal, Spacing.sm)
          .padding(.vertical, Spacing.sm)
          .background(Color.tidexSurfaceSecondary)
          .cornerRadius(CornerRadius.sm)

        TextField("12345678", text: $viewModel.phoneLinkInput)
          .font(.tidexBody)
          .foregroundColor(.tidexTextPrimary)
          .keyboardType(.numberPad)
          .padding(.horizontal, Spacing.sm)
          .padding(.vertical, Spacing.sm)
          .background(Color.tidexSurfaceSecondary)
          .cornerRadius(CornerRadius.sm)
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
        .font(.tidexCaptionRegular)
        .foregroundColor(.tidexTextMuted)
    }
  }

  private var phoneLinkOtpSection: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      // Show the phone number that code was sent to
      HStack(spacing: Spacing.xs) {
        Image(systemName: "phone.fill")
          .font(.tidexSubheadline)
          .foregroundColor(.tidexBlue)
        Text(formatPhoneForDisplay(viewModel.phoneLinkInput) ?? "+47 \(viewModel.phoneLinkInput)")
          .font(.tidexLabel)
          .foregroundColor(.tidexTextPrimary)

        Spacer()

        Button {
          viewModel.phoneLinkStep = .input
          viewModel.phoneLinkOtp = ""
          viewModel.errorMessage = nil
        } label: {
          Text(.securityPhoneLinkingChangeNumber)
            .font(.tidexFootnote)
            .foregroundColor(.tidexBlue)
        }
      }
      .padding(Spacing.sm)
      .background(Color.tidexSurfaceSecondary)
      .cornerRadius(CornerRadius.sm)

      // OTP input
      VStack(alignment: .leading, spacing: Spacing.xxxs) {
        Text(.securityPhoneLinkingOtpLabel)
          .font(.tidexFootnoteMedium)
          .foregroundColor(.tidexTextSecondary)

        TextField("123456", text: $viewModel.phoneLinkOtp)
          .font(.tidexMonoTitle)
          .foregroundColor(.tidexTextPrimary)
          .multilineTextAlignment(.center)
          .keyboardType(.numberPad)
          .padding(.horizontal, Spacing.md)
          .padding(.vertical, Spacing.sm)
          .background(Color.tidexSurfaceSecondary)
          .cornerRadius(CornerRadius.sm)
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
