import SwiftUI

/// Sheet that asks for a new email address and then confirms that the link was sent.
struct ProfileEmailChangeSheet: View {
  @Bindable var viewModel: ProfileSettingsViewModel

  var body: some View {
    NavigationStack {
      Group {
        if viewModel.emailChangeSent {
          emailChangeSentView
        } else {
          emailChangeForm
        }
      }
      .navigationTitle(String(localized: .profileEmailChangeTitle))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        if viewModel.emailChangeSent {
          ToolbarItem(placement: .confirmationAction) {
            Button(String(localized: .commonDone)) {
              viewModel.resetEmailChangeState()
            }
          }
        } else {
          ToolbarItem(placement: .cancellationAction) {
            Button(String(localized: .commonCancel)) {
              viewModel.resetEmailChangeState()
            }
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
          } else {
            Text(.profileEmailChangeInstructions)
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
        .lineLimit(1)
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

  private var emailChangeSentView: some View {
    ContentUnavailableView {
      Label(
        String(localized: .profileEmailChangeConfirmationSent),
        systemImage: "envelope.badge.fill"
      )
    } description: {
      Text(.profileEmailChangeConfirmationMessage)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.tidexBackground)
  }
}
