import SwiftUI

/// Admin tab for impersonating users
///
/// Allows admins to search for a user and start an impersonation session
/// for debugging or support purposes.
struct ImpersonationTabView: View {
  @ObservedObject var viewModel: AdminSettingsViewModel
  @StateObject private var impersonationManager = ImpersonationManager.shared

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Spacing.md) {
        // Active impersonation banner
        if impersonationManager.isImpersonating {
          ActiveImpersonationCard(
            targetName: impersonationManager.impersonatedUserName ?? "Unknown",
            expiresAt: impersonationManager.expiresAt,
            onStop: { Task { await stopImpersonation() } }
          )
        }

        // Start new impersonation section
        if !impersonationManager.isImpersonating {
          StartImpersonationSection(viewModel: viewModel)
        }

        // Instructions
        InstructionsCard()
      }
      .padding(Spacing.md)
    }
  }

  private func stopImpersonation() async {
    do {
      try await impersonationManager.stopImpersonation()
      Haptics.play(.success)
    } catch {
      viewModel.errorMessage = error.localizedDescription
    }
  }
}

// MARK: - Active Impersonation Card

private struct ActiveImpersonationCard: View {
  let targetName: String
  let expiresAt: Date?
  let onStop: () -> Void

  @State private var isLoading = false

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      HStack {
        Image(systemName: "person.crop.circle.badge.exclamationmark")
          .font(.system(size: 20))
          .foregroundStyle(Color.tidexWarning)
        Text("Active Impersonation")
          .font(.tidexButton)
          .foregroundStyle(Color.tidexWarning)
      }

      VStack(alignment: .leading, spacing: Spacing.xxs) {
        Text("Impersonating: **\(targetName)**")
          .font(.tidexSubheadline)
          .foregroundStyle(Color.tidexTextPrimary)

        if let expiresAt {
          Text("Expires: \(expiresAt, style: .relative)")
            .font(.tidexFootnote)
            .foregroundStyle(Color.tidexTextSecondary)
        }
      }

      Button {
        isLoading = true
        onStop()
      } label: {
        HStack {
          if isLoading {
            ProgressView()
              .progressViewStyle(CircularProgressViewStyle(tint: .white))
          }
          Text(isLoading ? "Stopping..." : "Stop Impersonation")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.sm)
        .background(Color.tidexError)
        .foregroundStyle(.white)
        .cornerRadius(CornerRadius.sm)
      }
      .disabled(isLoading)
    }
    .padding(Spacing.md)
    .background(Color.tidexWarning.opacity(0.1))
    .cornerRadius(CornerRadius.lg)
    .overlay(
      RoundedRectangle(cornerRadius: CornerRadius.lg)
        .stroke(Color.tidexWarning.opacity(0.3), lineWidth: 1)
    )
  }
}

// MARK: - Start Impersonation Section

private struct StartImpersonationSection: View {
  @ObservedObject var viewModel: AdminSettingsViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.md) {
      Text("Impersonate User")
        .font(.headline)
        .foregroundStyle(Color.tidexTextPrimary)

      // User selection
      UserSelectionField(viewModel: viewModel)

      // Reason input
      ReasonInputField(viewModel: viewModel)

      // Start button
      StartButton(viewModel: viewModel)
    }
    .padding(Spacing.md)
    .background(Color.tidexSurfacePrimary)
    .cornerRadius(CornerRadius.lg)
    .tidexCardShadow(cornerRadius: CornerRadius.lg)
  }
}

// MARK: - User Selection Field

private struct UserSelectionField: View {
  @ObservedObject var viewModel: AdminSettingsViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      Text("Target User")
        .font(.subheadline)
        .foregroundStyle(Color.tidexTextMuted)

      if let selectedUser = viewModel.impersonationSelectedUser {
        // Show selected user
        SelectedUserChip(user: selectedUser) {
          viewModel.clearImpersonationUser()
        }
      } else {
        // Search field
        UserSearchField(viewModel: viewModel)

        // Search results
        if !viewModel.impersonationUserSearchResults.isEmpty {
          UserSearchResults(viewModel: viewModel)
        }
      }
    }
  }
}

// MARK: - Selected User Chip

private struct SelectedUserChip: View {
  let user: AdminUserItem
  let onClear: () -> Void

  var body: some View {
    HStack {
      VStack(alignment: .leading, spacing: Spacing.micro) {
        Text(user.displayName)
          .font(.tidexLabel)
          .foregroundStyle(Color.tidexTextPrimary)
        if let email = user.email, email != user.displayName {
          Text(email)
            .font(.tidexCaptionRegular)
            .foregroundStyle(Color.tidexTextMuted)
        }
      }
      Spacer()
      Button(action: onClear) {
        Image(systemName: "xmark.circle.fill")
          .foregroundStyle(Color.tidexTextMuted)
      }
    }
    .padding(Spacing.sm)
    .background(Color.tidexSurfaceSecondary)
    .cornerRadius(CornerRadius.sm)
  }
}

// MARK: - User Search Field

private struct UserSearchField: View {
  @ObservedObject var viewModel: AdminSettingsViewModel

  var body: some View {
    HStack {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(Color.tidexTextMuted)
      TextField("Search by name, email, or phone...", text: $viewModel.impersonationUserSearch)
        .textFieldStyle(.plain)
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .onChange(of: viewModel.impersonationUserSearch) { _, _ in
          viewModel.searchImpersonationUsers()
        }
      if viewModel.isSearchingImpersonationUsers {
        ProgressView().scaleEffect(0.8)
      }
    }
    .padding(Spacing.sm)
    .background(Color.tidexSurfaceSecondary)
    .cornerRadius(CornerRadius.sm)
  }
}

// MARK: - User Search Results

private struct UserSearchResults: View {
  @ObservedObject var viewModel: AdminSettingsViewModel

  var body: some View {
    VStack(spacing: 0) {
      ForEach(viewModel.impersonationUserSearchResults) { user in
        Button {
          viewModel.selectImpersonationUser(user)
        } label: {
          HStack {
            VStack(alignment: .leading, spacing: Spacing.micro) {
              Text(user.displayName)
                .font(.tidexLabel)
                .foregroundStyle(Color.tidexTextPrimary)
              if let email = user.email, email != user.displayName {
                Text(email)
                  .font(.tidexCaptionRegular)
                  .foregroundStyle(Color.tidexTextMuted)
              }
            }
            Spacer()
            Image(systemName: "chevron.right")
              .font(.tidexCaptionRegular)
              .foregroundStyle(Color.tidexTextMuted)
          }
          .padding(.vertical, Spacing.xsm)
          .padding(.horizontal, Spacing.sm)
          .contentShape(Rectangle())
        }
        if user.id != viewModel.impersonationUserSearchResults.last?.id {
          Divider()
        }
      }
    }
    .background(Color.tidexSurfaceSecondary)
    .cornerRadius(CornerRadius.sm)
  }
}

// MARK: - Reason Input Field

private struct ReasonInputField: View {
  @ObservedObject var viewModel: AdminSettingsViewModel

  private var isValidReason: Bool {
    viewModel.impersonationReason.trimmingCharacters(in: .whitespacesAndNewlines).count >= 5
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      HStack {
        Text("Reason")
          .font(.subheadline)
          .foregroundStyle(Color.tidexTextMuted)
        Text("(required for audit)")
          .font(.caption)
          .foregroundStyle(Color.tidexTextMuted)
      }

      TextField("Why are you impersonating this user?", text: $viewModel.impersonationReason)
        .textFieldStyle(.plain)
        .padding(Spacing.sm)
        .background(Color.tidexSurfaceSecondary)
        .cornerRadius(CornerRadius.sm)

      if !viewModel.impersonationReason.isEmpty && !isValidReason {
        Text("Reason must be at least 5 characters")
          .font(.caption)
          .foregroundStyle(Color.tidexError)
      }
    }
  }
}

// MARK: - Start Button

private struct StartButton: View {
  @ObservedObject var viewModel: AdminSettingsViewModel

  private var canStart: Bool {
    viewModel.impersonationSelectedUser != nil
      && viewModel.impersonationReason.trimmingCharacters(in: .whitespacesAndNewlines).count >= 5
      && !viewModel.isStartingImpersonation
  }

  var body: some View {
    Button {
      Task { await viewModel.startImpersonation() }
    } label: {
      HStack {
        if viewModel.isStartingImpersonation {
          ProgressView()
            .progressViewStyle(CircularProgressViewStyle(tint: .white))
        }
        Text(viewModel.isStartingImpersonation ? "Starting..." : "Start Impersonation")
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, Spacing.sm)
      .background(canStart ? Color.tidexWarning : Color.tidexWarning.opacity(0.5))
      .foregroundStyle(.white)
      .cornerRadius(CornerRadius.sm)
    }
    .disabled(!canStart)
  }
}

// MARK: - Instructions Card

private struct InstructionsCard: View {
  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      HStack {
        Image(systemName: "info.circle")
          .foregroundStyle(Color.tidexInfo)
        Text("About Impersonation")
          .font(.tidexLabelStrong)
          .foregroundStyle(Color.tidexTextPrimary)
      }

      VStack(alignment: .leading, spacing: Spacing.xs) {
        InstructionRow(text: "Allows viewing the app as the target user")
        InstructionRow(text: "All actions are logged for audit purposes")
        InstructionRow(text: "Session expires after 1 hour")
        InstructionRow(text: "Some sensitive actions are blocked")
      }
    }
    .padding(Spacing.md)
    .background(Color.tidexInfo.opacity(0.1))
    .cornerRadius(CornerRadius.lg)
  }
}

private struct InstructionRow: View {
  let text: String

  var body: some View {
    HStack(alignment: .top, spacing: Spacing.xs) {
      Text("•")
        .foregroundStyle(Color.tidexTextMuted)
      Text(text)
        .font(.tidexFootnote)
        .foregroundStyle(Color.tidexTextSecondary)
    }
  }
}

#Preview {
  ImpersonationTabView(viewModel: AdminSettingsViewModel())
    .background(Color.tidexBackground)
}
