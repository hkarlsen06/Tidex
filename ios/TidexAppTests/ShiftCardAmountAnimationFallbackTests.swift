import XCTest

@testable import Tidex

internal final class ShiftCardAmountAnimationFallbackTests: XCTestCase {
  internal func testReturnsPreviousAmountWhenTrailingBottomContentAppears() {
    let animateFrom: Decimal? = ShiftCardAmountAnimationFallback.animateFrom(
      previousAmount: 12_500,
      previousHasTrailingBottomContent: false,
      currentHasTrailingBottomContent: true
    )

    XCTAssertEqual(animateFrom, 12_500)
  }

  internal func testReturnsPreviousAmountWhenTrailingBottomContentDisappears() {
    let animateFrom: Decimal? = ShiftCardAmountAnimationFallback.animateFrom(
      previousAmount: 18_900,
      previousHasTrailingBottomContent: true,
      currentHasTrailingBottomContent: false
    )

    XCTAssertEqual(animateFrom, 18_900)
  }

  internal func testReturnsNilWhenLayoutModeDoesNotChange() {
    let animateFrom: Decimal? = ShiftCardAmountAnimationFallback.animateFrom(
      previousAmount: 9_750,
      previousHasTrailingBottomContent: true,
      currentHasTrailingBottomContent: true
    )

    XCTAssertNil(animateFrom)
  }

  internal func testReturnsNilWithoutPreviousLayoutState() {
    let animateFrom: Decimal? = ShiftCardAmountAnimationFallback.animateFrom(
      previousAmount: 9_750,
      previousHasTrailingBottomContent: nil,
      currentHasTrailingBottomContent: true
    )

    XCTAssertNil(animateFrom)
  }

  deinit {
    // Required by SwiftLint for XCTestCase subclasses.
  }
}
