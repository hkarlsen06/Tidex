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

struct AdminUserBadges: View {
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
