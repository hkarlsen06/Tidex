import Observation
import SwiftUI

@MainActor
@Observable
final class AdminUsersModel {
  private(set) var users: [AdminUser] = []
  private(set) var totalCount: Int = 0
  private(set) var isLoading: Bool = false
  /// True once the first load finished, whether or not it succeeded.
  private(set) var hasLoaded: Bool = false
  var errorMessage: String?

  private var page: Int = 1
  private var search: String?
  private let perPage: Int = 30

  var hasMore: Bool { users.count < totalCount }

  /// Loads the first page for `query`. Cancelling the calling task drops the result.
  func load(query: String) async {
    search = query.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
    isLoading = true
    defer { isLoading = false }
    do {
      let result: AdminUsersPage = try await AdminAPI.users(
        page: 1, perPage: perPage, search: search)
      guard !Task.isCancelled else { return }
      users = result.users
      totalCount = result.totalCount
      page = 1
      hasLoaded = true
    } catch {
      guard !Task.isCancelled else { return }
      errorMessage = error.localizedDescription
      hasLoaded = true
    }
  }

  func loadMore() async {
    guard hasMore, !isLoading else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      let result: AdminUsersPage = try await AdminAPI.users(
        page: page + 1, perPage: perPage, search: search)
      let known: Set<String> = Set(users.map(\.id))
      users += result.users.filter { !known.contains($0.id) }
      totalCount = result.totalCount
      page += 1
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func replace(_ user: AdminUser) {
    guard let index = users.firstIndex(where: { $0.id == user.id }) else { return }
    users[index] = user
  }
}

struct AdminUsersView: View {
  @State private var model = AdminUsersModel()
  @State private var query = ""
  @State private var isSuperadmin = false

  var body: some View {
    List {
      Group {
        if model.hasLoaded {
          Section {
            ForEach(model.users) { user in
              NavigationLink {
                AdminUserDetailView(user: user, viewerIsSuperadmin: isSuperadmin) {
                  model.replace($0)
                }
              } label: {
                AdminUserRow(user: user)
              }
              .onAppear {
                if user.id == model.users.last?.id {
                  Task { await model.loadMore() }
                }
              }
            }
            if model.isLoading, !model.users.isEmpty {
              ProgressView().frame(maxWidth: .infinity)
            }
          } header: {
            Text("\(model.totalCount) users")
          }
        }
      }
      .listRowBackground(Color.tidexSurfacePrimary)
    }
    .tidexListBackground()
    .overlay {
      if !model.hasLoaded {
        ProgressView()
      } else if model.users.isEmpty {
        ContentUnavailableView.search(text: query)
      }
    }
    .navigationTitle("Users")
    .navigationBarTitleDisplayMode(.inline)
    .searchable(text: $query, prompt: "Name, email, phone or ID")
    .task(id: query) {
      if model.hasLoaded {
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
      }
      await model.load(query: query)
    }
    .task { isSuperadmin = await AdminAPI.currentUserIsSuperadmin() }
    .refreshable { await model.load(query: query) }
    .adminErrorAlert($model.errorMessage)
  }
}

private struct AdminUserRow: View {
  let user: AdminUser

  var body: some View {
    HStack(spacing: Spacing.sm) {
      AdminUserLabel(user: user)
      Spacer(minLength: Spacing.xs)
      VStack(alignment: .trailing, spacing: Spacing.xxs) {
        AdminUserBadges(user: user)
        AdminRelativeDate(date: user.lastSignIn)
          .font(.tidexMicro)
          .foregroundStyle(Color.tidexTextMuted)
      }
    }
  }
}

private struct AdminUserBadges: View {
  let user: AdminUser

  var body: some View {
    HStack(spacing: Spacing.xxs) {
      if user.isSuperAdmin {
        AdminBadge("Superadmin", color: .tidexPurple)
      } else if user.isAdmin {
        AdminBadge("Admin", color: .tidexPurple)
      }
      if user.isBanned {
        AdminBadge("Banned", color: .tidexError)
      }
    }
  }
}

// MARK: - Detail

struct AdminUserDetailView: View {
  let viewerIsSuperadmin: Bool
  let onChange: (AdminUser) -> Void

  @State private var user: AdminUser
  @State private var isWorking = false
  @State private var errorMessage: String?
  @State private var confirmBan = false
  @State private var confirmAdmin = false
  @State private var impersonationReason = ""

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
      Group {
        accountSection
        if canToggleBan || canToggleAdmin {
          actionsSection
        }
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
        AvatarView(url: nil, initials: initials, size: 64)
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
      LabeledContent("Joined") {
        if let created = user.created {
          Text(created, format: .dateTime.day().month().year())
        }
      }
      LabeledContent("Last sign-in") {
        if user.lastSignIn == nil {
          Text("Never")
        } else {
          AdminRelativeDate(date: user.lastSignIn)
        }
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

  private var actionsSection: some View {
    Section("Actions") {
      if canToggleBan {
        Button(user.isBanned ? "Unban user" : "Ban user", systemImage: "nosign") {
          confirmBan = true
        }
        .foregroundStyle(user.isBanned ? Color.tidexBlue : Color.tidexError)
      }
      if canToggleAdmin {
        Button(user.isAdmin ? "Revoke admin" : "Grant admin", systemImage: "shield.lefthalf.filled")
        {
          confirmAdmin = true
        }
        .foregroundStyle(user.isAdmin ? Color.tidexError : Color.tidexBlue)
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
