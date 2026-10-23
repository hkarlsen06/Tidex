import XCTest

@testable import Tidex

internal final class AuthIdentityInputTests: XCTestCase {
  internal func testDetectsEmail() {
    XCTAssertTrue(AuthIdentityInput.isEmail("user@example.com"))
    XCTAssertTrue(AuthIdentityInput.isEmail(" user@example.com "))
  }

  internal func testRejectsPhoneAndPlainText() {
    XCTAssertFalse(AuthIdentityInput.isEmail("+47 123 45 678"))
    XCTAssertFalse(AuthIdentityInput.isEmail("user"))
  }

  deinit {
    // Required by SwiftLint for XCTestCase subclasses.
  }
}
