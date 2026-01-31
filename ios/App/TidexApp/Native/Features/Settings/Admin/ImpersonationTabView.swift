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
            VStack(alignment: .leading, spacing: 16) {
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
            .padding(16)
        }
    }

    private func stopImpersonation() async {
        do {
            try await impersonationManager.stopImpersonation()
            viewModel.successMessage = "Impersonation ended"
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "person.crop.circle.badge.exclamationmark")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.tidexWarning)
                Text("Active Impersonation")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.tidexWarning)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Impersonating: **\(targetName)**")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.tidexTextPrimary)

                if let expiresAt {
                    Text("Expires: \(expiresAt, style: .relative)")
                        .font(.system(size: 13))
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
                .padding(.vertical, 12)
                .background(Color.tidexError)
                .foregroundStyle(.white)
                .cornerRadius(8)
            }
            .disabled(isLoading)
        }
        .padding(16)
        .background(Color.tidexWarning.opacity(0.1))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.tidexWarning.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Start Impersonation Section

private struct StartImpersonationSection: View {
    @ObservedObject var viewModel: AdminSettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
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
        .padding(16)
        .background(Color.tidexSurfacePrimary)
        .cornerRadius(12)
        .tidexCardShadow(cornerRadius: 12)
    }
}

// MARK: - User Selection Field

private struct UserSelectionField: View {
    @ObservedObject var viewModel: AdminSettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.tidexTextPrimary)
                if let email = user.email, email != user.displayName {
                    Text(email)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.tidexTextMuted)
                }
            }
            Spacer()
            Button(action: onClear) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Color.tidexTextMuted)
            }
        }
        .padding(12)
        .background(Color.tidexSurfaceSecondary)
        .cornerRadius(8)
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
        .padding(12)
        .background(Color.tidexSurfaceSecondary)
        .cornerRadius(8)
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
                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.displayName)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color.tidexTextPrimary)
                            if let email = user.email, email != user.displayName {
                                Text(email)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.tidexTextMuted)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.tidexTextMuted)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .contentShape(Rectangle())
                }
                if user.id != viewModel.impersonationUserSearchResults.last?.id {
                    Divider()
                }
            }
        }
        .background(Color.tidexSurfaceSecondary)
        .cornerRadius(8)
    }
}

// MARK: - Reason Input Field

private struct ReasonInputField: View {
    @ObservedObject var viewModel: AdminSettingsViewModel

    private var isValidReason: Bool {
        viewModel.impersonationReason.trimmingCharacters(in: .whitespacesAndNewlines).count >= 5
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                .padding(12)
                .background(Color.tidexSurfaceSecondary)
                .cornerRadius(8)

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
        viewModel.impersonationSelectedUser != nil &&
        viewModel.impersonationReason.trimmingCharacters(in: .whitespacesAndNewlines).count >= 5 &&
        !viewModel.isStartingImpersonation
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
            .padding(.vertical, 12)
            .background(canStart ? Color.tidexWarning : Color.tidexWarning.opacity(0.5))
            .foregroundStyle(.white)
            .cornerRadius(8)
        }
        .disabled(!canStart)
    }
}

// MARK: - Instructions Card

private struct InstructionsCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "info.circle")
                    .foregroundStyle(Color.tidexInfo)
                Text("About Impersonation")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.tidexTextPrimary)
            }

            VStack(alignment: .leading, spacing: 8) {
                InstructionRow(text: "Allows viewing the app as the target user")
                InstructionRow(text: "All actions are logged for audit purposes")
                InstructionRow(text: "Session expires after 1 hour")
                InstructionRow(text: "Some sensitive actions are blocked")
            }
        }
        .padding(16)
        .background(Color.tidexInfo.opacity(0.1))
        .cornerRadius(12)
    }
}

private struct InstructionRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundStyle(Color.tidexTextMuted)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Color.tidexTextSecondary)
        }
    }
}

#Preview {
    ImpersonationTabView(viewModel: AdminSettingsViewModel())
        .background(Color.tidexBackground)
}

