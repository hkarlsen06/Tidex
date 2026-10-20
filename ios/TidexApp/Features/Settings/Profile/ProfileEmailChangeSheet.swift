import SwiftUI

/// Sheet that asks for a new email address, then for the code Clerk emailed to it.
struct ProfileEmailChangeSheet: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Bindable var viewModel: ProfileSettingsViewModel

  var body: some View {
    NavigationStack {
      Group {
        if viewModel.awaitingEmailCode {
          emailCodeForm
        } else {
          emailChangeForm
        }
      }
      .navigationTitle(String(localized: .profileEmailChangeTitle))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(String(localized: .commonCancel)) {
            viewModel.resetEmailChangeState()
          }
        }
      }
    }
    .presentationDetents([.medium, .large])
  }

  private var emailChangeForm: some View {
    Form {
      Group {
        Section {
          currentEmailRow
        }

        Section {
          TextField(
            String(localized: .profileEmailChangeNewEmailPlaceholder),
            text: $viewModel.newEmail
          )
          .keyboardType(.emailAddress)
          .textContentType(.emailAddress)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
        } header: {
          Text(.profileEmailChangeNewEmailLabel)
        } footer: {
          if let error = viewModel.errorMessage {
            Text(error)
              .foregroundColor(.tidexError)
              .announcesToVoiceOver(error)
          } else {
            Text(.profileEmailChangeCodeInstructions)
          }
        }

        Section {
          emailChangeSendButton
        }
      }
      .listRowBackground(Color.tidexSurfacePrimary)
    }
    .tidexListBackground()
  }

  private var currentEmailRow: some View {
    LabeledContent(String(localized: .profileEmailChangeCurrentEmailLabel)) {
      Text(viewModel.email)
        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
        .truncationMode(.middle)
    }
  }

  private var emailChangeSendButton: some View {
    Button {
      Task {
        await viewModel.initiateEmailChange()
      }
    } label: {
      HStack(spacing: Spacing.xs) {
        if viewModel.isChangingEmail {
          ProgressView()
            .controlSize(.small)
        }

        Text(
          viewModel.isChangingEmail
            ? String(localized: .profileEmailChangeSending)
            : String(localized: .profileEmailChangeSendConfirmation)
        )
        .font(.tidexBodyMedium)
      }
      .frame(maxWidth: .infinity)
    }
    .disabled(viewModel.newEmail.isEmpty || viewModel.isChangingEmail)
  }

  private var emailCodeForm: some View {
    Form {
      Group {
        Section {
          TextField(
            String(localized: .profileEmailChangeCodePlaceholder),
            text: $viewModel.emailCode
          )
          .keyboardType(.numberPad)
          .textContentType(.oneTimeCode)
        } header: {
          Text(String(localized: .otpSubtitle(viewModel.newEmail)))
        } footer: {
          if let error = viewModel.errorMessage {
            Text(error)
              .foregroundColor(.tidexError)
              .announcesToVoiceOver(error)
          }
        }

        Section {
          Button {
            Task {
              await viewModel.confirmEmailChange()
            }
          } label: {
            HStack(spacing: Spacing.xs) {
              if viewModel.isChangingEmail {
                ProgressView()
                  .controlSize(.small)
              }

              Text(.otpSubmitButton)
                .font(.tidexBodyMedium)
            }
            .frame(maxWidth: .infinity)
          }
          .disabled(viewModel.emailCode.isEmpty || viewModel.isChangingEmail)
        }
      }
      .listRowBackground(Color.tidexSurfacePrimary)
    }
    .tidexListBackground()
  }
}
