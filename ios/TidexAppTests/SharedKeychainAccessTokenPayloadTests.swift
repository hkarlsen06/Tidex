import Supabase
import XCTest

@testable import Tidex

internal final class SharedKeychainAccessTokenPayloadTests: XCTestCase {
  internal func testPayloadCopiesAccessTokenAndIntegerExpiryFromSession() {
    let timestamp: TimeInterval = TimeInterval(1_800_000_000)
    guard let userId = UUID(uuidString: "032d8c2a-9af6-4777-99f0-24e2c4058bf3") else {
      XCTFail("Expected fixture user ID to be valid")
      return
    }

    let session: Session = Session(
      accessToken: "access-token",
      tokenType: "bearer",
      expiresIn: 3_600,
      expiresAt: timestamp + 3_600.75,
      refreshToken: "refresh-token",
      user: User(
        id: userId,
        appMetadata: [:],
        userMetadata: [:],
        aud: "authenticated",
        email: "user@example.com",
        createdAt: Date(timeIntervalSince1970: timestamp),
        updatedAt: Date(timeIntervalSince1970: timestamp)
      )
    )

    let payload: SharedKeychainAccessTokenPayload = SharedKeychainAccessTokenPayload(session: session)

    XCTAssertEqual(payload.token, "access-token")
    XCTAssertEqual(payload.expiresAt, 1_800_003_600)
  }

  deinit {
    // Required by SwiftLint for XCTestCase subclasses.
  }
}
