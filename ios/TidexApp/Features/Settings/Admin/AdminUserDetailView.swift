import SwiftUI

struct AdminUserDetailView: View {
  let viewerIsSuperadmin: Bool
  let onChange: (AdminUser) -> Void

  @State private var user: AdminUser
  @State private var isWorking = false
  @State private var errorMessage: String?
  @State private var confirmBan = false
  @State private var confirmAdmin = false
  @State private var impersonationReason = ""
  @State private var stats: AdminUserStats?

  init(user: AdminUser, viewerIsSuperadmin: Bool, onChange: @escaping (AdminUser) -> Void) {
    _user = State(initialValue: user)
    self.viewerIsSuperadmin = viewerIsSuperadmin
    self.onChange = onChange
  }

  /// The server refuses to ban admins, so only offer unbanning them.
  private var canToggleBan: Bool { !user.isSuperAdmin && (!user.isAdmin || user.isBanned) }
  private var canToggleAdmin: Bool { viewerIsSuperadmin && !user.isSuperAdmin }
  private var canImpersonate: Bool { !user.isAdmin || canToggleAdmin }
  private var trimmedReason: String {
    impersonationReason.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var body: some View {
    List {
      header
      AdminUserStatTiles(stats: stats)
      Group {
        accountSection
        activitySection
        if let stats {
          AdminUserStatsSections(stats: stats)
        }
        actionsSection
        if canImpersonate {
          impersonationSection
        }
        Section("Related") {
          NavigationLink("Shares") { AdminSharesView(initialSearch: user.id) }
          NavigationLink("Audit history") { AdminAuditLogView(targetUserID: user.id) }
        }
      }
      .listRowBackground(Color.tidexSurfacePrimary)
    }
    .tidexListBackground()
    .navigationTitle(user.displayName)
    .navigationBarTitleDisplayMode(.inline)
    .disabled(isWorking)
    .task { await loadStats() }
    .refreshable { await loadStats() }
    .adminErrorAlert($errorMessage)
    .confirmationDialog(
      user.isBanned ? "Unban \(user.displayName)?" : "Ban \(user.displayName)?",
      isPresented: $confirmBan,
      titleVisibility: .visible
    ) {
      Button(user.isBanned ? "Unban" : "Ban", role: user.isBanned ? nil : .destructive) {
        run {
          try await AdminAPI.setBanned(!user.isBanned, for: user)
        } then: {
          $0.isBanned.toggle()
        }
      }
    } message: {
      Text(user.isBanned ? "They can sign in again." : "They are signed out and can't sign in.")
    }
    .confirmationDialog(
      user.isAdmin
        ? "Revoke admin from \(user.displayName)?" : "Make \(user.displayName) an admin?",
      isPresented: $confirmAdmin,
      titleVisibility: .visible
    ) {
      Button(user.isAdmin ? "Revoke admin" : "Grant admin", role: user.isAdmin ? .destructive : nil)
      {
        run {
          try await AdminAPI.setAdmin(!user.isAdmin, for: user)
        } then: {
          $0.isAdmin.toggle()
        }
      }
    }
  }

  private var header: some View {
    Section {
      VStack(spacing: Spacing.xs) {
        AvatarView(url: user.avatarUrl, initials: initials, size: 64)
        Text(user.displayName)
          .font(.tidexTitle)
          .foregroundStyle(Color.tidexTextPrimary)
          .multilineTextAlignment(.center)
        AdminUserBadges(user: user)
      }
      .frame(maxWidth: .infinity)
      .listRowBackground(Color.clear)
    }
  }

  private var accountSection: some View {
    Section("Account") {
      if let email = user.email?.nilIfBlank {
        LabeledContent("Email") { Text(email).textSelection(.enabled) }
      }
      if let phone = user.phone?.nilIfBlank {
        LabeledContent("Phone") { Text(phone).textSelection(.enabled) }
      }
      LabeledContent("User ID") {
        Text(user.id)
          .font(.tidexMonoCaptionRegular)
          .lineLimit(1)
          .truncationMode(.middle)
          .textSelection(.enabled)
      }
    }
  }

  private var activitySection: some View {
    Section("Activity") {
      LabeledContent("Signed up") {
        if let created = user.created {
          Text(created, format: .dateTime.day().month().year())
        }
      }
      LabeledContent("Broadcast language", value: user.broadcastLanguage.title)
      LabeledContent("Last active") {
        if user.lastActive == nil {
          Text("Never")
        } else {
          AdminRelativeDate(date: user.lastActive)
        }
      }
      LabeledContent("Last sign-in") {
        if user.lastSignIn == nil {
          Text("Never")
        } else {
          AdminRelativeDate(date: user.lastSignIn)
        }
      }
    }
  }

  private var actionsSection: some View {
    Section("Actions") {
      NavigationLink {
        AdminBroadcastView(recipient: user)
      } label: {
        Label("Send notification", systemImage: "bell.badge")
      }
      if canToggleBan {
        Button(user.isBanned ? "Unban user" : "Ban user", systemImage: "nosign") {
          confirmBan = true
        }
        .foregroundStyle(user.isBanned ? Color.tidexBlueText : Color.tidexError)
      }
      if canToggleAdmin {
        Button(user.isAdmin ? "Revoke admin" : "Grant admin", systemImage: "shield.lefthalf.filled")
        {
          confirmAdmin = true
        }
        .foregroundStyle(user.isAdmin ? Color.tidexError : Color.tidexBlueText)
      }
    }
  }

  private var impersonationSection: some View {
    Section {
      TextField("Reason", text: $impersonationReason, axis: .vertical)
        .textInputAutocapitalization(.sentences)
      Button("Impersonate", systemImage: "person.crop.circle.badge.questionmark") {
        run {
          _ = try await ImpersonationManager.shared.startImpersonation(
            targetUserId: user.id, reason: trimmedReason)
        } then: { _ in
        }
      }
      .disabled(trimmedReason.count < 5)
    } header: {
      Text("Impersonate")
    } footer: {
      Text(
        "Signs you in as this user until you end the session. The reason (5+ characters) goes in the audit log."
      )
    }
  }

  private func loadStats() async {
    do {
      stats = try await AdminAPI.userStats(id: user.id)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private var initials: String {
    let words: [Substring] = user.displayName.split(separator: " ")
    return words.prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
  }

  private func run(
    _ work: @escaping () async throws -> Void, then update: @escaping (inout AdminUser) -> Void
  ) {
    Task {
      isWorking = true
      defer { isWorking = false }
      do {
        try await work()
        update(&user)
        onChange(user)
        Haptics.play(.success)
      } catch {
        Haptics.play(.error)
        errorMessage = AdminError(error).message
      }
    }
  }
}
