import Foundation
import XCTest

@testable import Tidex

final class LiveActivityPushTokenTests: XCTestCase {
  func testTokenHexEncodingUsesLowercaseAndPreservesLeadingZeroes() {
    let token = Data([0x00, 0x09, 0xA4, 0xFF])

    XCTAssertEqual(LiveActivityTokenCodec.hexString(for: token), "0009a4ff")
  }

  func testShiftActivityAttributesUseDefaultCodableDateRepresentation() throws {
    let startDate = Date(timeIntervalSince1970: 1_700_000_000)
    let endDate = Date(timeIntervalSince1970: 1_700_028_800)
    let attributes = makeAttributes(startDate: startDate, endDate: endDate)

    let data = try JSONEncoder().encode(attributes)
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: data) as? [String: Any]
    )

    XCTAssertEqual(
      Set(object.keys),
      [
        "shiftId",
        "shiftDate",
        "startTime",
        "endTime",
        "hourlyWage",
        "supplementRatePerHour",
        "totalGrossEstimate",
        "totalNetEstimate",
        "currencySymbol",
        "isTemporaryClock",
        "startDate",
        "endDate",
      ]
    )
    XCTAssertEqual(object["startDate"] as? Double, 721_692_800)
    XCTAssertEqual(object["endDate"] as? Double, 721_721_600)

    let decoded = try JSONDecoder().decode(ShiftActivityAttributes.self, from: data)
    XCTAssertEqual(decoded.startDate, startDate)
    XCTAssertEqual(decoded.endDate, endDate)
    XCTAssertEqual(decoded.shiftId, "shift-id")
  }

  func testContentStateCodableKeysMatchRemotePushContract() throws {
    let state = ShiftActivityAttributes.ContentState(
      currentEarnings: 625.5,
      remainingMinutes: 90,
      progressPercent: 62.5
    )

    let data = try JSONEncoder().encode(state)
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: data) as? [String: Any]
    )

    XCTAssertEqual(
      Set(object.keys),
      ["currentEarnings", "remainingMinutes", "progressPercent"]
    )
    XCTAssertEqual(object["currentEarnings"] as? Double, 625.5)
    XCTAssertEqual(object["remainingMinutes"] as? Int, 90)
    XCTAssertEqual(object["progressPercent"] as? Double, 62.5)
  }

  private func makeAttributes(
    startDate: Date,
    endDate: Date
  ) -> ShiftActivityAttributes {
    ShiftActivityAttributes(
      shiftId: "shift-id",
      shiftDate: "2023-11-14",
      startTime: "22:13",
      endTime: "06:13",
      hourlyWage: 250,
      supplementRatePerHour: 25,
      totalGrossEstimate: 2_200,
      startDate: startDate,
      endDate: endDate,
      totalNetEstimate: 1_650,
      currencySymbol: "kr",
      isTemporaryClock: false
    )
  }
}
