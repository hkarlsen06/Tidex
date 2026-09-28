import XCTest

@testable import Tidex

final class ChartSelectionSnappingTests: XCTestCase {
  func testSelectingAZeroValuePointSnapsToNearestNonZeroPoint() {
    let points: [(key: String, value: Double)] = [
      ("Mon", 100), ("Tue", 0), ("Wed", 0), ("Thu", 50),
    ]

    XCTAssertEqual(
      ChartSelectionSnapping.nearestNonZero(to: "Tue", in: points), "Mon",
      "Tue is closer to Mon (distance 1) than Thu (distance 2)")
    XCTAssertEqual(
      ChartSelectionSnapping.nearestNonZero(to: "Wed", in: points), "Thu",
      "Wed is closer to Thu (distance 1) than Mon (distance 2)")
  }

  func testSelectingANonZeroPointReturnsItUnchanged() {
    let points: [(key: String, value: Double)] = [("Mon", 100), ("Tue", 0)]

    XCTAssertEqual(ChartSelectionSnapping.nearestNonZero(to: "Mon", in: points), "Mon")
  }

  func testSelectionClearsWhenNoPointHasAPositiveValue() {
    let points: [(key: String, value: Double)] = [("Mon", 0), ("Tue", 0)]

    XCTAssertNil(ChartSelectionSnapping.nearestNonZero(to: "Mon", in: points))
  }

  func testNilSelectionStaysNil() {
    let points: [(key: String, value: Double)] = [("Mon", 100)]

    XCTAssertNil(ChartSelectionSnapping.nearestNonZero(to: nil, in: points))
  }

  func testUnknownKeyReturnsNil() {
    let points: [(key: String, value: Double)] = [("Mon", 100)]

    XCTAssertNil(ChartSelectionSnapping.nearestNonZero(to: "Fri", in: points))
  }
}
