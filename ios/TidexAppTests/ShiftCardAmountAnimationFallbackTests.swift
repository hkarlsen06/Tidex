import XCTest

@testable import Tidex

final class ShiftCardAmountAnimationFallbackTests: XCTestCase {
  func testReturnsPreviousAmountWhenTrailingBottomContentAppears() {
    let animateFrom = ShiftCardAmountAnimationFallback.animateFrom(
      previousAmount: 12_500,
      previousHasTrailingBottomContent: false,
      currentHasTrailingBottomContent: true
    )

    XCTAssertEqual(animateFrom, 12_500)
  }

  func testReturnsPreviousAmountWhenTrailingBottomContentDisappears() {
    let animateFrom = ShiftCardAmountAnimationFallback.animateFrom(
      previousAmount: 18_900,
      previousHasTrailingBottomContent: true,
      currentHasTrailingBottomContent: false
    )

    XCTAssertEqual(animateFrom, 18_900)
  }

  func testReturnsNilWhenLayoutModeDoesNotChange() {
    let animateFrom = ShiftCardAmountAnimationFallback.animateFrom(
      previousAmount: 9_750,
      previousHasTrailingBottomContent: true,
      currentHasTrailingBottomContent: true
    )

    XCTAssertNil(animateFrom)
  }

  func testReturnsNilWithoutPreviousLayoutState() {
    let animateFrom = ShiftCardAmountAnimationFallback.animateFrom(
      previousAmount: 9_750,
      previousHasTrailingBottomContent: nil,
      currentHasTrailingBottomContent: true
    )

    XCTAssertNil(animateFrom)
  }
}
