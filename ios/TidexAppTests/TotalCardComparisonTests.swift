import XCTest

@testable import Tidex

final class TotalCardComparisonTests: XCTestCase {
  func testComparisonProgressAndLabels() {
    XCTAssertEqual(
      DashboardData.percentageChange(current: 93, previous: 100) ?? .nan,
      -7,
      accuracy: 0.001
    )
    XCTAssertEqual(
      DashboardData.percentageChange(current: 107, previous: 100) ?? .nan,
      7,
      accuracy: 0.001
    )
    XCTAssertTrue(DashboardData.percentageChange(current: 1, previous: 0)?.isInfinite == true)
    XCTAssertNil(DashboardData.percentageChange(current: 0, previous: 0))

    XCTAssertEqual(TotalCard.comparisonProgressFraction(for: -7), 0.93, accuracy: 0.001)
    XCTAssertEqual(TotalCard.comparisonPercentText(for: -7), "-7%")

    XCTAssertEqual(TotalCard.comparisonProgressFraction(for: 7), 1)
    XCTAssertEqual(TotalCard.comparisonPercentText(for: 7), "+7%")

    XCTAssertEqual(TotalCard.comparisonProgressFraction(for: 0), 1)
    XCTAssertEqual(TotalCard.comparisonPercentText(for: 0), "0%")

    XCTAssertEqual(TotalCard.comparisonProgressFraction(for: .infinity), 1)
    XCTAssertEqual(TotalCard.comparisonPercentText(for: .infinity), "∞")

    XCTAssertEqual(TotalCard.comparisonProgressFraction(for: nil), 0)
    XCTAssertEqual(TotalCard.comparisonPercentText(for: nil), "—")
  }
}
