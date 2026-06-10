import XCTest

@testable import Tidex

internal final class ShiftDetailsPresentationPolicyTests: XCTestCase {
  internal func testOwnShiftShowsEarningsDetails() {
    let policy: ShiftDetailsPresentationPolicy = ShiftDetailsPresentationPolicy(
      snapshotShareContext: .own
    )

    XCTAssertTrue(policy.showsEarningsDetails)
    XCTAssertNil(policy.automaticBreakOwnerName)
  }

  internal func testSharedShiftHidesEarningsDetailsWhenOwnerDoesNotShareEarnings() {
    let policy: ShiftDetailsPresentationPolicy = ShiftDetailsPresentationPolicy(
      snapshotShareContext: .shared(owner: makeSharedUser(showEarnings: false))
    )

    XCTAssertFalse(policy.showsEarningsDetails)
    XCTAssertNil(policy.automaticBreakOwnerName)
  }

  internal func testSharedShiftUsesOwnerNameForAutomaticBreakSummaryWhenEarningsAreVisible() {
    let policy: ShiftDetailsPresentationPolicy = ShiftDetailsPresentationPolicy(
      snapshotShareContext: .shared(owner: makeSharedUser(firstName: "Ask Karlsen"))
    )

    XCTAssertTrue(policy.showsEarningsDetails)
    XCTAssertEqual(policy.automaticBreakOwnerName, "Ask")
  }

  private func makeSharedUser(
    firstName: String? = "Ask",
    showEarnings: Bool = true
  ) -> SharedUser {
    SharedUser(
      id: "11111111-2222-4333-8444-555555555555",
      email: "ask@example.com",
      phone: nil,
      firstName: firstName,
      profilePictureUrl: nil,
      oauthAvatarUrl: nil,
      sharedAt: "2026-03-11T10:00:00Z",
      showEarnings: showEarnings,
      hidden: false
    )
  }

  deinit {
    // Required by SwiftLint for XCTestCase subclasses.
  }
}
