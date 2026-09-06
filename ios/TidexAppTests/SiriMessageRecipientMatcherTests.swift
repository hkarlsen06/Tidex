import XCTest

@testable import Tidex

internal final class SiriMessageRecipientMatcherTests: XCTestCase {
  internal func testMatchesDisplayNameIgnoringCaseAndDiacritics() {
    let recipients: [ShareRecipient] = [
      recipient(id: "1", displayName: "José"),
      recipient(id: "2", displayName: "Ada"),
    ]

    let matches: [ShareRecipient] = SiriMessageRecipientMatcher.matches(
      for: "jose",
      in: recipients
    )

    XCTAssertEqual(matches.map(\.id), ["1"])
  }

  internal func testReturnsDisambiguationCandidatesForEqualFirstNameMatches() {
    let recipients: [ShareRecipient] = [
      recipient(id: "1", displayName: "Chris Stone"),
      recipient(id: "2", displayName: "Chris Lane"),
      recipient(id: "3", displayName: "Ada"),
    ]

    let matches: [ShareRecipient] = SiriMessageRecipientMatcher.matches(
      for: "Chris",
      in: recipients
    )

    XCTAssertEqual(matches.map(\.id), ["2", "1"])
  }

  internal func testMatchesStatusTextForUsername() {
    let recipients: [ShareRecipient] = [
      recipient(id: "1", displayName: "Hjalmar", statusText: "@hjalmar"),
      recipient(id: "2", displayName: "Ada", statusText: "@ada"),
    ]

    let matches: [ShareRecipient] = SiriMessageRecipientMatcher.matches(
      for: "ada",
      in: recipients
    )

    XCTAssertEqual(matches.map(\.id), ["2"])
  }

  private func recipient(
    id: String,
    displayName: String,
    statusText: String? = nil
  ) -> ShareRecipient {
    ShareRecipient(
      id: id,
      displayName: displayName,
      avatarURL: nil,
      statusText: statusText,
      canSeeOwnerEarnings: false
    )
  }

  deinit {
    // Required by project lint configuration.
  }
}
