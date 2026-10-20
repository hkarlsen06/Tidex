import SwiftUI

/// Security settings view
/// Password and connected accounts
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
    (viewModel.hasGoogleConnected && !viewModel.canDisconnectGoogle)
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

  // MARK: - Password Form Sheet

  private var passwordInstructions: String {
    viewModel.hasPassword
      ? String(localized: .securityPasswordChangeInstructions)
      : String(localized: .securityPasswordSetInstructions)
  }

  private var passwordFieldsSection: some View {
    Section {
      if viewModel.hasPassword {
        SecureField(
          String(localized: .securityPasswordCurrentPasswordLabel),
          text: $viewModel.currentPassword
        )
        .textContentType(.password)
      }

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
      && (!viewModel.hasPassword || !viewModel.currentPassword.isEmpty)
  }
}

// MARK: - Preview

#Preview {
  NavigationStack {
    SecuritySettingsView()
  }
}
