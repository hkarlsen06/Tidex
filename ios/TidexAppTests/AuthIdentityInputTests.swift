import XCTest

@testable import Tidex

final class AuthIdentityInputTests: XCTestCase {
  func testDetectTypeReturnsEmailForEmailInput() {
    XCTAssertEqual(AuthIdentityInput.detectType("user@example.com"), .email)
  }

  func testDetectTypeReturnsPhoneForPhoneInput() {
    XCTAssertEqual(AuthIdentityInput.detectType("+47 123 45 678"), .phone)
  }

  func testDetectTypeReturnsUnknownForIncompleteInput() {
    XCTAssertEqual(AuthIdentityInput.detectType("user"), .unknown)
  }

  func testNormalizedPhonePreservesExplicitCountryCode() {
    XCTAssertEqual(AuthIdentityInput.normalizedPhone("+4712345678"), "+4712345678")
  }

  func testNormalizedPhoneConvertsInternationalPrefix() {
    XCTAssertEqual(AuthIdentityInput.normalizedPhone("004712345678"), "+4712345678")
  }

  func testNormalizedPhoneAppliesDefaultCountryCodeForLocalNumbers() {
    XCTAssertEqual(AuthIdentityInput.normalizedPhone("12345678"), "+4712345678")
  }
}
