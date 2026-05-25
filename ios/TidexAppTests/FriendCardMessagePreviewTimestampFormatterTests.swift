import XCTest

@testable import Tidex

final class FriendCardMessagePreviewTimestampFormatterTests: XCTestCase {
  func testMessagesUnderOneMinuteShowNow() {
    let referenceDate = Date(timeIntervalSince1970: 1_700_000_100)
    let messageDate = referenceDate.addingTimeInterval(-12)

    XCTAssertEqual(
      FriendCardMessagePreviewTimestampFormatter.relativeTimestamp(
        messageDate: messageDate,
        referenceDate: referenceDate,
        nowText: "now"
      ),
      "now"
    )
  }

  func testFutureMessagesShowNow() {
    let referenceDate = Date(timeIntervalSince1970: 1_700_000_100)
    let messageDate = referenceDate.addingTimeInterval(5)

    XCTAssertEqual(
      FriendCardMessagePreviewTimestampFormatter.relativeTimestamp(
        messageDate: messageDate,
        referenceDate: referenceDate,
        nowText: "now"
      ),
      "now"
    )
  }

  func testMessagesAtOneMinuteKeepMinuteAbbreviation() {
    let referenceDate = Date(timeIntervalSince1970: 1_700_000_100)
    let messageDate = referenceDate.addingTimeInterval(-60)

    XCTAssertEqual(
      FriendCardMessagePreviewTimestampFormatter.relativeTimestamp(
        messageDate: messageDate,
        referenceDate: referenceDate,
        nowText: "now"
      ),
      "1m"
    )
  }

  func testMessagesAtOneMonthDoNotUseBareMinuteAbbreviation() throws {
    let referenceDate = Date(timeIntervalSince1970: 1_700_000_100)
    let messageDate = try XCTUnwrap(
      Calendar.current.date(byAdding: .month, value: -1, to: referenceDate)
    )

    XCTAssertNotEqual(
      FriendCardMessagePreviewTimestampFormatter.relativeTimestamp(
        messageDate: messageDate,
        referenceDate: referenceDate,
        nowText: "now"
      ),
      "1m"
    )
  }
}
