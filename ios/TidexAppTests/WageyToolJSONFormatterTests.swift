import XCTest

@testable import Tidex

final class WageyToolJSONFormatterTests: XCTestCase {
  func testFormatsToolResponseNumbersWithoutFloatingPointArtifacts() {
    let formatted = WageyToolJSONFormatter.format(
      """
      {"currency":"kr","data":{"averageRate":208.49000000000001,"shiftCount":15,"totalEarnings":19754.389999999999,"totalEarningsNet":18766.669999999998,"totalHours":94.75},"message":"Current month statistics","success":true}
      """
    )

    XCTAssertEqual(
      formatted,
      """
      {
        "currency" : "kr",
        "data" : {
          "averageRate" : 208.49,
          "shiftCount" : 15,
          "totalEarnings" : 19754.39,
          "totalEarningsNet" : 18766.67,
          "totalHours" : 94.75
        },
        "message" : "Current month statistics",
        "success" : true
      }
      """
    )
  }

  func testReturnsOriginalStringWhenInputIsNotJSON() {
    XCTAssertEqual(WageyToolJSONFormatter.format("Network timeout"), "Network timeout")
  }
}
