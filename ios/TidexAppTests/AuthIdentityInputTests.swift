import XCTest

@testable import Tidex

internal final class AuthIdentityInputTests: XCTestCase {
  internal func testDetectTypeReturnsEmailForEmailInput() {
    XCTAssertEqual(AuthIdentityInput.detectType("user@example.com"), .email)
  }

  internal func testDetectTypeReturnsPhoneForPhoneInput() {
    XCTAssertEqual(AuthIdentityInput.detectType("+47 123 45 678"), .phone)
  }

  internal func testDetectTypeReturnsUnknownForIncompleteInput() {
    XCTAssertEqual(AuthIdentityInput.detectType("user"), .unknown)
  }

  internal func testNormalizedPhonePreservesExplicitCountryCode() {
    XCTAssertEqual(AuthIdentityInput.normalizedPhone("+4712345678"), "+4712345678")
  }

  internal func testNormalizedPhoneConvertsInternationalPrefix() {
    XCTAssertEqual(AuthIdentityInput.normalizedPhone("004712345678"), "+4712345678")
  }

  internal func testNormalizedPhoneAppliesDefaultCountryCodeForLocalNumbers() {
    XCTAssertEqual(AuthIdentityInput.normalizedPhone("12345678"), "+4712345678")
  }

  deinit {
    // Required by SwiftLint for XCTestCase subclasses.
  }
}
