import XCTest

@testable import Tidex

/// A call retried after a 401 must never run as a different user than it started as.
internal final class ConvexAPIRetryIdentityTests: XCTestCase {
  internal func testRefreshedTokenForTheSameUserIsUsed() {
    let first = Self.jwt(subject: "user_a", expiry: 1_800_000_000)
    let refreshed = Self.jwt(subject: "user_a", expiry: 1_800_003_600)
    XCTAssertTrue(
      ConvexAPI.isSameUser(
        retryToken: refreshed, firstTokenUser: SharedAuthToken.subject(ofJWT: first)))
  }

  internal func testTokenForAnotherUserIsRefused() {
    let first = Self.jwt(subject: "user_a", expiry: 1_800_000_000)
    let other = Self.jwt(subject: "user_b", expiry: 1_800_003_600)
    XCTAssertFalse(
      ConvexAPI.isSameUser(retryToken: other, firstTokenUser: SharedAuthToken.subject(ofJWT: first)))
  }

  internal func testSignInDuringAnUnsignedCallIsRefused() {
    let signedIn = Self.jwt(subject: "user_b", expiry: 1_800_003_600)
    XCTAssertFalse(ConvexAPI.isSameUser(retryToken: signedIn, firstTokenUser: nil))
  }

  private static func jwt(subject: String, expiry: Int) -> String {
    func base64URL(_ json: String) -> String {
      Data(json.utf8).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    }
    let header = base64URL(#"{"alg":"RS256","typ":"JWT"}"#)
    let payload = base64URL(#"{"sub":"\#(subject)","exp":\#(expiry)}"#)
    return "\(header).\(payload).signature"
  }

  deinit {
    // Required by SwiftLint for XCTestCase subclasses.
  }
}
