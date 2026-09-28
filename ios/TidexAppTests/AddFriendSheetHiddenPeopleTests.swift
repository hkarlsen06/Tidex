import XCTest

@testable import Tidex

@MainActor
final class AddFriendSheetHiddenPeopleTests: XCTestCase {
  func testNoHiddenOrBlockedPeopleHidesTheRow() {
    let viewModel = makeViewModel(friends: [makeFriend(id: "ella", name: "Ella", hidden: false)])

    XCTAssertFalse(viewModel.hasHiddenOrBlockedPeople)
    XCTAssertTrue(viewModel.hiddenFriends.isEmpty)
  }

  func testHiddenFriendsAreSortedByName() {
    let viewModel = makeViewModel(friends: [
      makeFriend(id: "oskar", name: "Oskar", hidden: true),
      makeFriend(id: "ella", name: "Ella", hidden: false),
      makeFriend(id: "anna", name: "Anna", hidden: true),
    ])

    XCTAssertTrue(viewModel.hasHiddenOrBlockedPeople)
    XCTAssertEqual(viewModel.hiddenFriends.map(\.id), ["anna", "oskar"])
  }

  func testBlockedPersonAloneShowsTheRow() {
    let viewModel = makeViewModel(
      friends: [],
      blocked: [makeFriend(id: "jonas", name: "Jonas", hidden: false)]
    )

    XCTAssertTrue(viewModel.hasHiddenOrBlockedPeople)
    XCTAssertTrue(viewModel.hiddenFriends.isEmpty)
  }

  private func makeViewModel(friends: [Friend], blocked: [Friend] = []) -> ManageSharingViewModel {
    let suiteName = "AddFriendSheetHiddenPeopleTests"
    let defaults = UserDefaults(suiteName: suiteName) ?? .standard
    defaults.removePersistentDomain(forName: suiteName)
    return ManageSharingViewModel(
      initialSnapshot: FriendsManagementSnapshot(friends: friends, blockedFriends: blocked),
      visibilityStore: FriendsVisibilityStore(defaults: defaults)
    )
  }

  private func makeFriend(id: String, name: String, hidden: Bool) -> Friend {
    Friend(
      id: id, email: "\(id)@example.com", phone: nil, username: nil, firstName: name,
      profilePictureUrl: nil, oauthAvatarUrl: nil,
      sharesWithMe: Friend.SharesWithMe(
        hidden: hidden, showEarningsToMe: false, sharedAt: "2026-01-01",
        notificationFrequency: .instant),
      iShareWith: nil)
  }
}
