import XCTest

@testable import Tidex

final class ImpersonationExpirationFormatterTests: XCTestCase {
  func testTextReturnsExpiredStateWhenRemainingIsZeroOrNegative() {
    XCTAssertEqual(
      ImpersonationExpirationFormatter.text(remaining: 0),
      String(localized: .impersonationBannerSessionExpiredState)
    )
    XCTAssertEqual(
      ImpersonationExpirationFormatter.text(remaining: -5),
      String(localized: .impersonationBannerSessionExpiredState)
    )
  }

  func testTextShowsOnlySecondsUnderOneMinute() {
    XCTAssertEqual(
      ImpersonationExpirationFormatter.text(remaining: 45),
      String(localized: .impersonationBannerExpiresInSeconds(45))
    )
  }

  func testTextShowsMinutesAndSecondsUnderOneHour() {
    XCTAssertEqual(
      ImpersonationExpirationFormatter.text(remaining: 125),
      String(localized: .impersonationBannerExpiresInMinutesSeconds(2, 5))
    )
  }

  func testTextShowsHoursAndMinutesAtOneHourOrMore() {
    let expected =
      "\(String(localized: .impersonationBannerExpiresInPrefix)) 1\(String(localized: .commonHoursShort)) 1\(String(localized: .commonMinutesShort))"  // swiftlint:disable:this line_length
    XCTAssertEqual(ImpersonationExpirationFormatter.text(remaining: 3_661), expected)
  }
}
