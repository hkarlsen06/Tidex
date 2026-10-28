import Auth
import XCTest

@testable import Tidex

final class OfflineAuthTests: XCTestCase {
  @MainActor
  func testLookupBeforeInvalidationCannotRestoreImpersonatedUser() async throws {
    let started = expectation(description: "old lookup started")
    var pending: CheckedContinuation<AuthUser, Error>?
    var first = true
    let old = authUser("old-target")
    let current = authUser("current-target")
    let manager = AuthSessionManager(activeSessionId: { "session" }) {
      if first {
        first = false
        return try await withCheckedThrowingContinuation {
          pending = $0
          started.fulfill()
        }
      }
      return current
    }
    let lookup = Task { try await manager.currentUser(clerkUserId: "clerk", sessionId: "session") }
    await fulfillment(of: [started], timeout: 2)
    manager.clearCachedUser()
    pending?.resume(returning: old)
    let result = try await lookup.value
    XCTAssertEqual(result.id, current.id)
  }

  @MainActor
  func testAccountSwitchRejectsBothCallersOfOldLookup() async throws {
    let started = expectation(description: "old account lookup started")
    var session = "old-session"
    var pending: CheckedContinuation<AuthUser, Error>?
    let old = authUser("old-account")
    let current = authUser("new-account")
    let manager = AuthSessionManager(activeSessionId: { session }) {
      if session == "old-session" {
        return try await withCheckedThrowingContinuation {
          pending = $0
          started.fulfill()
        }
      }
      return current
    }
    let first = Task { try await manager.currentUser(clerkUserId: "old", sessionId: "old-session") }
    await fulfillment(of: [started], timeout: 2)
    let second = Task { try await manager.currentUser(clerkUserId: "old", sessionId: "old-session") }
    await Task.yield()
    session = "new-session"
    let newUser = try await manager.currentUser(clerkUserId: "new", sessionId: session)
    pending?.resume(returning: old)
    for lookup in [first, second] {
      do {
        _ = try await lookup.value
        XCTFail("An old session returned a user after switching accounts")
      } catch {
        XCTAssertTrue(manager.isMissingSessionError(error))
      }
    }
    XCTAssertEqual(newUser.id, current.id)
  }

  private func authUser(_ id: String) -> AuthUser {
    AuthUser(
      id: id, email: nil, name: nil, avatarUrl: nil, role: nil, termsAcceptedAt: nil,
      finishedOnboarding: true, isImpersonating: false, actorId: id)
  }

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

  // MARK: - Legacy GoTrue session exchange

  private func goTrueError(status: Int, code: String) throws -> Auth.AuthError {
    let url = try XCTUnwrap(URL(string: "https://api.tidex.no/auth/v1/token"))
    let response = try XCTUnwrap(
      HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil))
    return .api(
      message: "", errorCode: Auth.ErrorCode(code), underlyingData: Data(),
      underlyingResponse: response)
  }

  func testRateLimitedOrTimedOutRefreshKeepsTheOldLogin() throws {
    XCTAssertFalse(
      isLegacyGoTrueRefusal(try goTrueError(status: 429, code: "over_request_rate_limit")))
    XCTAssertFalse(isLegacyGoTrueRefusal(try goTrueError(status: 408, code: "request_timeout")))
    XCTAssertFalse(isLegacyGoTrueRefusal(try goTrueError(status: 400, code: "unknown")))
    XCTAssertFalse(
      isLegacyGoTrueRefusal(try goTrueError(status: 500, code: "unexpected_failure")))
    XCTAssertFalse(isLegacyGoTrueRefusal(URLError(.notConnectedToInternet)))
  }

  func testDeadRefreshTokenDropsTheOldLogin() throws {
    XCTAssertTrue(isLegacyGoTrueRefusal(Auth.AuthError.sessionMissing))
    XCTAssertTrue(
      isLegacyGoTrueRefusal(try goTrueError(status: 400, code: "refresh_token_not_found")))
    XCTAssertTrue(isLegacyGoTrueRefusal(try goTrueError(status: 400, code: "user_banned")))
  }
}
