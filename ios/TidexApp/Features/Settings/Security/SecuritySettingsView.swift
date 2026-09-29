import CoreImage.CIFilterBuiltins
import SwiftUI

/// Security settings view
/// Password, connected accounts, passkeys and two-factor authentication
struct SecuritySettingsView: View {  // swiftlint:disable:this explicit_acl explicit_top_level_acl type_body_length
  @Environment(\.dismiss) private var dismiss
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var viewModel = SecuritySettingsViewModel()
  /// Connected account waiting for the user to confirm the disconnect
  @State private var pendingDisconnect: ConnectedAccount?
  /// Provider whose row started the running connect or disconnect request
  @State private var busyProviderId: String?

  private struct ConnectedAccount: Identifiable {
    let id: String
    let title: String
  }

  var body: some View {
    Form {
      Group {
        if let error = viewModel.errorMessage {
          ErrorBanner(message: error, onDismiss: { viewModel.clearMessages() })
        }

        if viewModel.isOfflineLimited {
          Section {
            Label {
              Text(.securityOfflineManageUnavailable)
                .foregroundColor(.tidexTextSecondary)
            } icon: {
              Image(systemName: "wifi.slash")
                .foregroundColor(.tidexTextMuted)
            }
            .font(.tidexFootnote)
          }
        }

        passwordSection
        connectedAccountsSection
        passkeysSection
        mfaSection
      }
      .listRowBackground(Color.tidexSurfacePrimary)
    }
    .tidexListBackground()
    .navigationTitle(String(localized: .securityTitle))
    .navigationBarTitleDisplayMode(.inline)
    .task {
      await viewModel.loadSecurityInfo()
    }
    .sheet(isPresented: $viewModel.showPasswordForm) {
      passwordFormSheet
    }
    .sheet(isPresented: $viewModel.showMFAEnrollment) {
      mfaEnrollmentSheet
    }
    .confirmationDialog(
      pendingDisconnect?.title ?? "",
      isPresented: Binding(
        get: { pendingDisconnect != nil },
        set: { isPresented in
          if !isPresented {
            pendingDisconnect = nil
          }
        }
      ),
      titleVisibility: .visible,
      presenting: pendingDisconnect
    ) { account in
      Button(String(localized: .securityConnectionsDisconnect), role: .destructive) {
        busyProviderId = account.id
        Task {
          await viewModel.disconnectProvider(account.id)
        }
      }
      Button(String(localized: .commonCancel), role: .cancel) {}
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

  // MARK: - Shared Rows

  /// An icon with a title and a secondary line, used by every row on this screen.
  private func detailLabel(icon: String, title: String, detail: String) -> some View {
    Label {
      VStack(alignment: .leading, spacing: Spacing.micro) {
        Text(title)
          .font(.tidexBodyMedium)
          .foregroundColor(.tidexTextPrimary)

        Text(detail)
          .font(.tidexFootnote)
          .foregroundColor(.tidexTextSecondary)
      }
    } icon: {
      Image(systemName: icon)
        .foregroundColor(.tidexBlueText)
    }
  }

  private var disclosureChevron: some View {
    Image(systemName: "chevron.forward")
      .font(.tidexCaptionRegular)
      .foregroundColor(.tidexTextMuted)
      .accessibilityHidden(true)
  }

  /// Text and the trailing control share a line at normal sizes and stack at accessibility sizes.
  private var rowLayout: AnyLayout {
    dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xs))
      : AnyLayout(HStackLayout(spacing: Spacing.sm))
  }

  private func addRow(title: String, isLoading: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Label {
        Text(title)
          .foregroundColor(.tidexBlueText)
      } icon: {
        if isLoading {
          ProgressView()
            .controlSize(.small)
        } else {
          Image(systemName: "plus.circle.fill")
            .foregroundColor(.tidexBlueText)
        }
      }
    }
  }

  private func emptyRow(_ text: String) -> some View {
    Text(text)
      .font(.tidexSubheadline)
      .foregroundColor(.tidexTextMuted)
  }

  // MARK: - Password Section

  private var passwordSection: some View {
    Section {
      Button {
        viewModel.showPasswordForm = true
      } label: {
        rowLayout {
          detailLabel(
            icon: "lock.fill",
            title: String(localized: .securityPasswordTitle),
            detail: viewModel.hasPassword
              ? String(localized: .securityPasswordHasPassword)
              : String(localized: .securityPasswordNoPassword)
          )

          if !dynamicTypeSize.isAccessibilitySize {
            Spacer(minLength: Spacing.sm)
          }

          if !viewModel.hasPassword {
            Text(.securityPasswordSet)
              .font(.tidexLabel)
              .foregroundColor(.tidexBlueText)
          }

          disclosureChevron
        }
        .contentShape(Rectangle())
      }
      .disabled(viewModel.isOfflineLimited)
    }
  }

  // MARK: - Connected Accounts Section

  private var connectedAccountsSection: some View {
    Section {
      phoneConnectionRow

      googleConnectionRow

      appleConnectionRow
    } header: {
      Text(String(localized: .securityConnectionsSectionTitle))
    } footer: {
      VStack(alignment: .leading, spacing: Spacing.xxs) {
        Text(.securityConnectionsSectionSubtitle)

        if hasLockedConnection {
          Text(.securityConnectionsAddOtherMethod)
        }
      }
    }
  }

  // New numbers cannot be linked without SMS, but existing ones can still be removed.
  @ViewBuilder
  private var phoneConnectionRow: some View {
    if viewModel.hasPhoneConnected {
      connectionRow(
        id: "phone",
        icon: "phone.fill",
        title: String(localized: .securityConnectionsPhoneTitle),
        isConnected: true,
        connectedText: formatPhoneForDisplay(viewModel.phoneNumber)
          ?? String(localized: .securityConnectionsPhoneConnected),
        notConnectedText: "",
        canDisconnect: viewModel.canUnlinkPhone
      )
    }
  }

  private var googleConnectionRow: some View {
    connectionRow(
      id: "google",
      icon: "g.circle.fill",
      title: String(localized: .securityConnectionsGoogleTitle),
      isConnected: viewModel.hasGoogleConnected,
      connectedText: String(localized: .securityConnectionsGoogleConnected),
      notConnectedText: String(localized: .securityConnectionsGoogleNotConnected),
      canDisconnect: viewModel.canDisconnectGoogle
    ) {
      Task { await viewModel.connectGoogle() }
    }
  }

  private var appleConnectionRow: some View {
    connectionRow(
      id: "apple",
      icon: "apple.logo",
      title: String(localized: .securityConnectionsAppleTitle),
      isConnected: viewModel.hasAppleConnected,
      connectedText: String(localized: .securityConnectionsAppleConnected),
      notConnectedText: String(localized: .securityConnectionsAppleNotConnected),
      canDisconnect: viewModel.canDisconnectApple
    ) {
      Task { await viewModel.connectApple() }
    }
  }

  /// True when a connected account is the last way in and so cannot be removed.
  private var hasLockedConnection: Bool {
    (viewModel.hasPhoneConnected && !viewModel.canUnlinkPhone)
      || (viewModel.hasGoogleConnected && !viewModel.canDisconnectGoogle)
      || (viewModel.hasAppleConnected && !viewModel.canDisconnectApple)
  }

  /// Tapping connects an account, or asks to disconnect a connected one.
  /// The last remaining sign-in method is shown without an action.
  @ViewBuilder
  private func connectionRow(  // swiftlint:disable:this function_parameter_count function_body_length
    id: String,
    icon: String,
    title: String,
    isConnected: Bool,
    connectedText: String,
    notConnectedText: String,
    canDisconnect: Bool,
    onConnect: (() -> Void)? = nil
  ) -> some View {
    let isBusy = viewModel.isConnectingProvider && busyProviderId == id
    let content = rowLayout {
      detailLabel(
        icon: icon,
        title: title,
        detail: isConnected ? connectedText : notConnectedText
      )

      if !dynamicTypeSize.isAccessibilitySize {
        Spacer(minLength: Spacing.sm)
      }

      if isBusy {
        ProgressView()
          .controlSize(.small)
      } else if isConnected {
        Image(systemName: "checkmark.circle.fill")
          .foregroundColor(.tidexSuccess)
          .accessibilityHidden(true)
      } else {
        Text(.securityConnectionsConnect)
          .font(.tidexLabel)
          .foregroundColor(.tidexBlueText)
      }
    }
    .contentShape(Rectangle())

    if isConnected, !canDisconnect {
      content
        .accessibilityElement(children: .combine)
    } else {
      Button {
        if isConnected {
          pendingDisconnect = ConnectedAccount(id: id, title: title)
        } else {
          busyProviderId = id
          onConnect?()
        }
      } label: {
        content
      }
      .disabled(viewModel.isConnectingProvider || viewModel.isOfflineLimited)
      .accessibilityHint(isConnected ? Text(.settingsAccessibilityDisconnectHint) : Text(verbatim: ""))
    }
  }

  // MARK: - Passkeys Section

  private var passkeysSection: some View {
    Section {
      if viewModel.passkeys.isEmpty {
        emptyRow(String(localized: .securityPasskeysNoPasskeys))
      } else {
        ForEach(viewModel.passkeys) { passkey in
          passkeyRow(passkey)
        }
      }

      addRow(
        title: viewModel.isRegisteringPasskey
          ? String(localized: .securityPasskeysAdding)
          : String(localized: .securityPasskeysAdd),
        isLoading: viewModel.isRegisteringPasskey
      ) {
        Task {
          await viewModel.registerPasskey()
        }
      }
      .disabled(viewModel.isRegisteringPasskey || viewModel.isOfflineLimited)
    } header: {
      Text(String(localized: .securityPasskeysSectionTitle))
    } footer: {
      Text(.securityPasskeysSectionSubtitle)
    }
  }

  private func passkeyRow(_ passkey: PasskeyAuthService.Passkey) -> some View {
    rowLayout {
      detailLabel(
        icon: "person.badge.key.fill",
        title: passkey.displayName,
        detail: String(localized: .securityMfaAddedOn(passkey.formattedCreatedAt))
      )

      if !dynamicTypeSize.isAccessibilitySize {
        Spacer(minLength: Spacing.sm)
      }

      if viewModel.isRenamingPasskey, viewModel.passkeyToRename?.id == passkey.id {
        ProgressView()
          .controlSize(.small)
      }
    }
    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
      passkeyActions(passkey)
    }
    .contextMenu {
      passkeyActions(passkey)
    }
  }

  @ViewBuilder
  private func passkeyActions(_ passkey: PasskeyAuthService.Passkey) -> some View {
    let isBusy =
      viewModel.isRenamingPasskey || viewModel.isDeletingPasskey || viewModel.isOfflineLimited

    SwipeDeleteButton(title: String(localized: .securityPasskeysDeleteDialogConfirm)) {
      viewModel.passkeyToDelete = passkey
      viewModel.showDeletePasskeyConfirmation = true
    }
    .disabled(isBusy)

    Button {
      viewModel.startRenamingPasskey(passkey)
    } label: {
      Label(String(localized: .commonRename), systemImage: "pencil")
    }
    .tint(.tidexBlue)
    .disabled(isBusy)
  }

  // MARK: - MFA Section

  private var mfaSection: some View {
    Section {
      if viewModel.mfaFactors.isEmpty {
        emptyRow(String(localized: .securityMfaNoFactors))
      } else {
        ForEach(viewModel.mfaFactors) { factor in
          mfaFactorRow(factor)
        }
      }

      addRow(
        title: String(localized: .securityMfaAddFactor),
        isLoading: viewModel.isEnrollingMFA
      ) {
        Task {
          await viewModel.startMFAEnrollment()
        }
      }
      .disabled(viewModel.isEnrollingMFA || viewModel.isOfflineLimited)
    } header: {
      Text(String(localized: .securityMfaSectionTitle))
    } footer: {
      Text(.securityMfaSectionSubtitle)
    }
  }

  private func mfaFactorRow(_ factor: SecuritySettingsViewModel.MFAFactor) -> some View {
    detailLabel(
      icon: "iphone",
      title: factor.displayName,
      detail: String(localized: .securityMfaAddedOn(factor.formattedDate))
    )
    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
      mfaFactorActions(factor)
    }
    .contextMenu {
      mfaFactorActions(factor)
    }
  }

  private func mfaFactorActions(_ factor: SecuritySettingsViewModel.MFAFactor) -> some View {
    SwipeDeleteButton(title: String(localized: .securityMfaUnenrollDialogConfirm)) {
      viewModel.factorToUnenroll = factor
      viewModel.showUnenrollConfirmation = true
    }
    .disabled(viewModel.isUnenrollingMFA || viewModel.isOfflineLimited)
  }

  // MARK: - Sheet Helpers

  /// Full-width action row at the bottom of a sheet form.
  private func sheetActionSection(
    title: String,
    isLoading: Bool,
    isEnabled: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Section {
      Button(action: action) {
        HStack(spacing: Spacing.xs) {
          if isLoading {
            ProgressView()
              .controlSize(.small)
          }

          Text(title)
            .font(.tidexBodyMedium)
        }
        .frame(maxWidth: .infinity)
      }
      .disabled(!isEnabled || isLoading)
    }
  }

  /// Footer text that switches to the current error when there is one.
  @ViewBuilder
  private func sheetFooter(_ text: String) -> some View {
    if let error = viewModel.errorMessage {
      Text(error)
        .foregroundColor(.tidexError)
        .announcesToVoiceOver(error)
    } else {
      Text(text)
    }
  }

  /// A centered numeric code field that keeps at most `maxLength` digits.
  private func codeField(_ placeholder: String, text: Binding<String>, maxLength: Int) -> some View
  {
    TextField(placeholder, text: text)
      .accessibilityLabel(Text(.settingsAccessibilityVerificationCode))
      .font(.tidexMonoTitle)
      .multilineTextAlignment(.center)
      .keyboardType(.numberPad)
      .textContentType(.oneTimeCode)
      .onChange(of: text.wrappedValue) { _, newValue in
        let filtered = String(newValue.filter(\.isNumber).prefix(maxLength))
        if filtered != newValue {
          text.wrappedValue = filtered
        }
      }
  }

  // MARK: - Password Form Sheet

  private var passwordInstructions: String {
    viewModel.hasPassword
      ? String(localized: .securityPasswordChangeInstructions)
      : String(localized: .securityPasswordSetInstructions)
  }

  private var passwordFieldsSection: some View {
    Section {
      SecureField(
        viewModel.hasPassword
          ? String(localized: .securityPasswordNewPasswordLabel)
          : String(localized: .securityPasswordPasswordLabel),
        text: $viewModel.newPassword
      )
      .textContentType(.newPassword)

      SecureField(
        String(localized: .securityPasswordConfirmPasswordLabel),
        text: $viewModel.confirmPassword
      )
      .textContentType(.newPassword)
    } footer: {
      sheetFooter("\(passwordInstructions) \(String(localized: .securityPasswordHint))")
    }
  }

  private var passwordForm: some View {
    Form {
      Group {
        passwordFieldsSection

        sheetActionSection(
          title: viewModel.isSettingPassword
            ? String(localized: .securityPasswordSetting)
            : viewModel.hasPassword
              ? String(localized: .securityPasswordUpdate)
              : String(localized: .securityPasswordSet),
          isLoading: viewModel.isSettingPassword,
          isEnabled: canSubmitPassword
        ) {
          Task {
            await viewModel.setPassword()
          }
        }
      }
      .listRowBackground(Color.tidexSurfacePrimary)
    }
  }

  private var passwordFormSheet: some View {
    NavigationStack {
      passwordForm
        .tidexListBackground()
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

  private var canSubmitPassword: Bool {
    !viewModel.newPassword.isEmpty && !viewModel.confirmPassword.isEmpty
  }

  // MARK: - MFA Enrollment Sheet

  private var mfaEnrollmentForm: some View {
    Form {
      Group {
        if let totpUri = viewModel.mfaTotpUri {
          qrCodeSection(totpUri)
        }

        if let secret = viewModel.mfaSecret {
          mfaManualEntrySection(secret)
        }

        Section {
          codeField("000000", text: $viewModel.mfaVerifyCode, maxLength: 6)
        } footer: {
          sheetFooter(String(localized: .securityMfaVerifyLabel))
        }

        sheetActionSection(
          title: viewModel.isVerifyingMFA
            ? String(localized: .securityMfaVerifying)
            : String(localized: .securityMfaVerify),
          isLoading: viewModel.isVerifyingMFA,
          isEnabled: viewModel.mfaVerifyCode.count == 6
        ) {
          Task {
            await viewModel.verifyMFAEnrollment()
          }
        }
      }
      .listRowBackground(Color.tidexSurfacePrimary)
    }
  }

  private func mfaManualEntrySection(_ secret: String) -> some View {
    Section {
      HStack(spacing: Spacing.sm) {
        Text(secret)
          .font(.tidexMonoCaptionRegular)
          .foregroundColor(.tidexTextPrimary)
          .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
          .truncationMode(.middle)
          .textSelection(.enabled)
          .speechSpellsOutCharacters()

        Spacer(minLength: Spacing.sm)

        Button {
          UIPasteboard.general.string = secret
          AccessibilityNotification.Announcement(String(localized: .settingsAccessibilityCopied)).post()
        } label: {
          Label(String(localized: .commonCopy), systemImage: "doc.on.doc")
            .labelStyle(.iconOnly)
        }
        .buttonStyle(.borderless)
      }
    } header: {
      Text(.securityMfaManualEntry)
    }
  }

  private var mfaEnrollmentSheet: some View {
    NavigationStack {
      mfaEnrollmentForm
        .tidexListBackground()
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

  private func qrCodeImage(_ totpUri: String) -> some View {
    Group {
      if let qrImage = generateQRCode(from: totpUri) {
        Image(uiImage: qrImage)
          .interpolation(.none)
          .resizable()
          .scaledToFit()
          .accessibilityHidden(true)
      } else {
        VStack(spacing: Spacing.xs) {
          Image(systemName: "qrcode")
            .font(.system(size: 60))
            .foregroundColor(.tidexLightTextPrimary)
            .accessibilityHidden(true)

          Text(.securityMfaUseSecretBelow)
            .font(.tidexCaptionRegular)
            .foregroundColor(.tidexLightTextPrimary)
            .multilineTextAlignment(.center)
        }
      }
    }
  }

  private func qrCodeSection(_ totpUri: String) -> some View {
    Section {
      qrCodeImage(totpUri)
        .frame(width: 184)
        .frame(minHeight: 184)
        .padding(Spacing.xs)
        // QR scanners need dark modules on a light background in both appearances.
        .background(Color.white, in: RoundedRectangle(cornerRadius: CornerRadius.lg))
        .frame(maxWidth: .infinity)

      if let url = URL(string: totpUri) {
        Button {
          UIApplication.shared.open(url)
        } label: {
          Label(String(localized: .securityMfaOpenInApp), systemImage: "arrow.up.right.square")
            .frame(maxWidth: .infinity)
        }
      }
    } footer: {
      Text(.securityMfaScanQR)
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

  /// Format a phone number for display (Norwegian: nnn nn nnn)
  private func formatPhoneForDisplay(_ phone: String?) -> String? {
    guard let phone else { return nil }  // swiftlint:disable:this conditional_returns_on_newline
    // swiftlint:disable:this conditional_returns_on_newline
    // Remove any non-digit characters and country code
    var digits = phone.filter(\.isNumber)  // swiftlint:disable:this explicit_type_interface
    // swiftlint:disable:this explicit_type_interface
    // Remove Norwegian country code if present
    if digits.hasPrefix("47"), digits.count > 8 {  // swiftlint:disable:this no_magic_numbers
      digits = String(digits.dropFirst(2))  // swiftlint:disable:this no_magic_numbers
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
}  // swiftlint:disable:this file_length
