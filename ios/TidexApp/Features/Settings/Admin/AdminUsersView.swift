import Observation
import SwiftUI

/// What the users list shows. Changing any field reloads from page 1.
struct AdminUsersRequest: Equatable {
  var search: String = ""
  var query = AdminUserQuery()
}

@MainActor
@Observable
final class AdminUsersModel {
  private(set) var users: [AdminUser] = []
  private(set) var totalCount: Int = 0
  private(set) var appVersions: [String] = []
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
      appVersions = result.appVersions
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
      query: request.query
    )
  }
}

struct AdminUsersView: View {
  @State private var model = AdminUsersModel()
  @State private var request = AdminUsersRequest()
  @State private var isSuperadmin = false

  /// A list row rather than a safe area inset: on iOS 27.2 the inset under the search
  /// drawer stays blank.
  private var filterSection: some View {
    Section {
      AdminUserFilterBar(query: $request.query, appVersions: model.appVersions)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
    .listSectionSeparator(.hidden)
    // Full width, so the chips scroll out to the screen edges.
    .listSectionMargins(.horizontal, 0)
    .listSectionSpacing(Spacing.xs)
  }

  var body: some View {
    List {
      filterSection

      Group {
        if model.hasLoaded {
          Section {
            ForEach(model.users) { user in
              NavigationLink {
                AdminUserDetailView(user: user, viewerIsSuperadmin: isSuperadmin) {
                  model.replace($0)
                }
              } label: {
                AdminUserRow(user: user, sort: model.request.query.sort)
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
    .contentMargins(.top, Spacing.xs, for: .scrollContent)
    .overlay {
      if !model.hasLoaded {
        ProgressView()
      } else if model.users.isEmpty {
        if !request.search.isEmpty {
          ContentUnavailableView.search(text: request.search)
        } else if request.query.hasFilters {
          ContentUnavailableView {
            Label("No matching users", systemImage: "line.3.horizontal.decrease.circle")
          } actions: {
            Button("Clear filters") { request.query = request.query.withoutFilters }
          }
        } else {
          ContentUnavailableView("No users", systemImage: "person.2.slash")
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
    case .name, .lastSignIn, .shifts, .messages, .friends: return ("Signed in", user.lastSignIn)
    }
  }

  /// The count that matches the sort order, if the list is sorted by one.
  private var count: String? {
    switch sort {
    case .shifts: return user.shiftCount.map { "\($0) shifts" }
    case .messages: return user.messageCount.map { "\($0) messages" }
    case .friends: return user.friendCount.map { "\($0) friends" }
    case .name, .newest, .lastSignIn, .lastActive: return nil
    }
  }

  var body: some View {
    HStack(spacing: Spacing.sm) {
      AdminUserLabel(user: user)
      Spacer(minLength: Spacing.xs)
      VStack(alignment: .trailing, spacing: Spacing.xxs) {
        AdminUserBadges(user: user)
        Group {
          if let count {
            Text(count)
          } else if let value = date.value {
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

/// Sort and filter chips under the search field. Each chip opens its options; set filters are tinted.
private struct AdminUserFilterBar: View {
  @Binding var query: AdminUserQuery
  let appVersions: [String]

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: Spacing.xs) {
        sortChips
        if query.hasFilters {
          Button {
            query = query.withoutFilters
          } label: {
            AdminChipLabel(text: "Clear", systemImage: "xmark", isActive: true)
          }
        }
        accountChips
        usageChips
      }
      .padding(.horizontal, Spacing.md)
      // Without this, a tap anywhere in the list row fires every button in it.
      .buttonStyle(.borderless)
    }
  }

  @ViewBuilder private var sortChips: some View {
    Menu {
      Picker("Sort by", selection: $query.sort) {
        ForEach(AdminUserSort.allCases) { Text($0.title).tag($0) }
      }
    } label: {
      AdminChipLabel(
        text: "Sort: \(query.sort.title)", systemImage: "arrow.up.arrow.down", isActive: false)
    }
    Button {
      query.reversed.toggle()
    } label: {
      AdminChipLabel(
        text: query.reversed
          ? query.sort.directionTitles.reversed : query.sort.directionTitles.normal,
        isActive: query.reversed)
    }
  }

  @ViewBuilder private var accountChips: some View {
    chip("Account", $query.account, AdminUserAccount.allCases.map { ($0, $0.title) })
    chip(
      "Language", $query.language, any: "Any language",
      AdminLanguage.allCases.map { ($0, $0.title) })
    chip(
      "Sign-in", $query.provider, any: "Any sign-in",
      AdminUserProvider.allCases.map { ($0, $0.title) })
    chip(
      "Signed up", $query.signedUpWithin, any: "Any time",
      AdminUserPeriod.allCases.map { ($0, "Signed up in last \($0.title)") })
    chip(
      "Activity", $query.activity, any: "Any activity",
      AdminUserActivity.allCases.map { ($0, $0.title) })
  }

  @ViewBuilder private var usageChips: some View {
    chip("Shifts", $query.shifts, [(.any, "Any"), (.with, "Has shifts"), (.without, "No shifts")])
    chip(
      "Messages", $query.messages,
      [(.any, "Any"), (.with, "Has sent messages"), (.without, "Never sent messages")])
    chip(
      "Friends", $query.friends, [(.any, "Any"), (.with, "Has friends"), (.without, "No friends")])
    chip(
      "App version", $query.appVersion, any: "Any version",
      appVersions.map { ($0, "Version \($0)") }
        + [(AdminUserQuery.noAppVersion, "No version reported")])
  }

  /// A chip for an optional filter, where nil means any.
  private func chip<Value: Hashable>(
    _ name: String, _ selection: Binding<Value?>, any: String, _ options: [(Value, String)]
  ) -> some View {
    let all: [(Value?, String)] = [(nil, any)] + options.map { ($0.0, $0.1) }
    return chip(name, selection, all)
  }

  /// A menu chip that shows `name` until a value other than the first option is picked.
  private func chip<Value: Hashable>(
    _ name: String, _ selection: Binding<Value>, _ options: [(Value, String)]
  ) -> some View {
    let isActive: Bool = selection.wrappedValue != options.first?.0
    let selected: String? = options.first { $0.0 == selection.wrappedValue }?.1
    return Menu {
      Picker(name, selection: selection) {
        ForEach(options, id: \.0) { Text($0.1).tag($0.0) }
      }
    } label: {
      AdminChipLabel(
        text: isActive ? selected ?? name : name, systemImage: "chevron.down", trailingIcon: true,
        isActive: isActive)
    }
    .accessibilityLabel(isActive ? "\(name): \(selected ?? name)" : name)
  }
}

private struct AdminChipLabel: View {
  let text: String
  var systemImage: String?
  var trailingIcon = false
  let isActive: Bool

  var body: some View {
    HStack(spacing: Spacing.xxs) {
      if let systemImage, !trailingIcon {
        Image(systemName: systemImage).accessibilityHidden(true)
      }
      Text(text)
      if let systemImage, trailingIcon {
        Image(systemName: systemImage).imageScale(.small).accessibilityHidden(true)
      }
    }
    .font(.tidexFootnoteMedium)
    .foregroundStyle(isActive ? Color.tidexBlueText : Color.tidexTextPrimary)
    .padding(.horizontal, Spacing.sm)
    .padding(.vertical, Spacing.xs)
    .background(
      isActive ? Color.tidexBlue.opacity(0.15) : Color.tidexSurfaceSecondary, in: Capsule()
    )
    .contentShape(Capsule())
  }
}
