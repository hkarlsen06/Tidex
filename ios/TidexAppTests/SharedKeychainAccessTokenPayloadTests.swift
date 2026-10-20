import XCTest

@testable import Tidex

internal final class SharedKeychainAccessTokenPayloadTests: XCTestCase {
  internal func testPayloadCopiesAccessTokenAndIntegerExpiryFromSession() {
    let timestamp: TimeInterval = TimeInterval(1_800_000_000)
    let session: AuthSession = AuthSession(
      user: AuthUser(
        id: "032d8c2a-9af6-4777-99f0-24e2c4058bf3", email: "user@example.com", name: nil,
        avatarUrl: nil, role: nil, termsAcceptedAt: nil, finishedOnboarding: true,
        isImpersonating: false, actorId: "032d8c2a-9af6-4777-99f0-24e2c4058bf3"),
      accessToken: "access-token",
      expiresAt: timestamp + 3_600.75,
      clerkSessionId: "sess_1"
    )

    let payload: SharedKeychainAccessTokenPayload = SharedKeychainAccessTokenPayload(
      session: session
    )

    XCTAssertEqual(payload.token, "access-token")
    XCTAssertEqual(payload.expiresAt, 1_800_003_600)
  }

  deinit {
    // Required by SwiftLint for XCTestCase subclasses.
  }
}
