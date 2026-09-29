import XCTest

@testable import Tidex

final class OfflineAuthTests: XCTestCase {
  // MARK: - Sign-out user id

  func testSignOutUserIdPrefersCoordinatorUser() {
    let id = AppCoordinator.signOutUserId(
      current: "a", local: "b", offlineFallback: { "c" })
    XCTAssertEqual(id, "a")
  }

  func testSignOutUserIdFallsBackToLocalSession() {
    let id = AppCoordinator.signOutUserId(
      current: nil, local: "b", offlineFallback: { "c" })
    XCTAssertEqual(id, "b")
  }

  func testSignOutUserIdFallsBackToOfflineSettings() {
    let id = AppCoordinator.signOutUserId(
      current: "", local: nil, offlineFallback: { "c" })
    XCTAssertEqual(id, "c")
  }

  func testSignOutUserIdIsNilWhenUnknown() {
    let id = AppCoordinator.signOutUserId(
      current: nil, local: nil, offlineFallback: { nil })
    XCTAssertNil(id, "An unknown user must not count as safe to wipe")
  }

  // MARK: - Retained local data

  func testRetainedDataIsKeptForSameUser() {
    XCTAssertFalse(
      AppCoordinator.shouldWipeRetainedData(
        retainedUserId: "ABC-1", sessionUserId: "abc-1"))
  }

  func testRetainedDataIsWipedForDifferentUser() {
    XCTAssertTrue(
      AppCoordinator.shouldWipeRetainedData(retainedUserId: "abc-1", sessionUserId: "def-2"))
  }

  func testNothingRetainedNeverWipes() {
    XCTAssertFalse(
      AppCoordinator.shouldWipeRetainedData(retainedUserId: nil, sessionUserId: "def-2"))
    XCTAssertFalse(
      AppCoordinator.shouldWipeRetainedData(retainedUserId: "", sessionUserId: "def-2"))
  }

  // MARK: - Terms gate offline

  func testUnreachableManifestDefersTermsCheck() {
    XCTAssertNil(
      TermsVersion.needsTermsReAcceptance(
        "2020-01-01T00:00:00Z", liveVersionReference: nil))
  }

  func testLiveManifestDecidesReAcceptance() {
    XCTAssertEqual(
      TermsVersion.needsTermsReAcceptance(
        "2026-01-01T00:00:00Z", liveVersionReference: "2026-03-01T00:00:00Z"),
      true)
    XCTAssertEqual(
      TermsVersion.needsTermsReAcceptance(
        "2026-04-01T00:00:00Z", liveVersionReference: "2026-03-01T00:00:00Z"),
      false)
  }

  func testNeverAcceptedNeedsAcceptanceWhenManifestIsLive() {
    XCTAssertEqual(
      TermsVersion.needsTermsReAcceptance(nil, liveVersionReference: "2026-03-01T00:00:00Z"),
      true)
  }
}
