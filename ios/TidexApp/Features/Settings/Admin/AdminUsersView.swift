import Observation
import SwiftUI

/// What the users list shows. Changing any field reloads from page 1.
struct AdminUsersRequest: Equatable {
  var search: String = ""
  var sort: AdminUserSort = .name
  var filter: AdminUserFilter = .all
}

@MainActor
@Observable
final class AdminUsersModel {
  private(set) var users: [AdminUser] = []
  private(set) var totalCount: Int = 0
  private(set) var isLoading: Bool = false
  /// True once the first load finished, whether or not it succeeded.
  private(set) var hasLoaded: Bool = false
  /// The request behind `users`.
  private(set) var request = AdminUsersRequest()
  var errorMessage: String?

  private var page: Int = 1
  private let perPage: Int = 30

  var hasMore: Bool { users.count < totalCount }

  /// Loads the first page for `request`. Cancelling the calling task drops the result.
  func load(_ request: AdminUsersRequest) async {
    isLoading = true
    defer { isLoading = false }
    do {
      let result: AdminUsersPage = try await fetch(request, page: 1)
      guard !Task.isCancelled else { return }
      users = result.users
      totalCount = result.totalCount
      page = 1
      self.request = request
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
      let result: AdminUsersPage = try await fetch(request, page: page + 1)
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

  private func fetch(_ request: AdminUsersRequest, page: Int) async throws -> AdminUsersPage {
    try await AdminAPI.users(
      page: page,
      perPage: perPage,
      search: request.search.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
      sort: request.sort,
      filter: request.filter
    )
  }
}

struct AdminUsersView: View {
  @State private var model = AdminUsersModel()
  @State private var request = AdminUsersRequest()
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
                AdminUserRow(user: user, sort: model.request.sort)
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
            if model.request.filter == .all {
              Text("\(model.totalCount) users")
            } else {
              Text("\(model.totalCount) users · \(model.request.filter.title)")
            }
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
        if request.search.isEmpty {
          ContentUnavailableView("No users", systemImage: "person.2.slash")
        } else {
          ContentUnavailableView.search(text: request.search)
        }
      }
    }
    .navigationTitle("Users")
    .navigationBarTitleDisplayMode(.inline)
    .searchable(
      text: $request.search,
      placement: .navigationBarDrawer(displayMode: .always),
      prompt: "Name, email, phone or ID"
    )
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Menu {
          Picker("Sort by", selection: $request.sort) {
            ForEach(AdminUserSort.allCases) { Text($0.title).tag($0) }
          }
          .pickerStyle(.inline)
          Picker("Show", selection: $request.filter) {
            ForEach(AdminUserFilter.allCases) { Text($0.title).tag($0) }
          }
          .pickerStyle(.inline)
        } label: {
          Label(
            "Sort and filter",
            systemImage: request.filter == .all
              ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill"
          )
        }
      }
    }
    .task(id: request) {
      // Debounce typing, but apply sort and filter changes right away.
      if model.hasLoaded, request.search != model.request.search {
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
      }
      await model.load(request)
    }
    .task { isSuperadmin = await AdminAPI.currentUserIsSuperadmin() }
    .refreshable { await model.load(request) }
    .adminErrorAlert($model.errorMessage)
  }
}

private struct AdminUserRow: View {
  let user: AdminUser
  let sort: AdminUserSort

  /// The date that matches the sort order, so the list reads top to bottom.
  private var date: (label: String, value: Date?) {
    switch sort {
    case .newest: return ("Signed up", user.created)
    case .lastActive: return ("Active", user.lastActive)
    case .name, .lastSignIn: return ("Signed in", user.lastSignIn)
    }
  }

  var body: some View {
    HStack(spacing: Spacing.sm) {
      AdminUserLabel(user: user)
      Spacer(minLength: Spacing.xs)
      VStack(alignment: .trailing, spacing: Spacing.xxs) {
        AdminUserBadges(user: user)
        Group {
          if let value = date.value {
            Text("\(date.label) \(value.formatted(.relative(presentation: .named)))")
          } else {
            Text("\(date.label) never")
          }
        }
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
        activitySection
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
