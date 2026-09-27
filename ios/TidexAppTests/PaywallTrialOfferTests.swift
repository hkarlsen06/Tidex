import XCTest

@testable import Tidex

final class PaywallTrialOfferTests: XCTestCase {
  private let monthly = ProductID.proMonthly.rawValue

  func testEligibleProductWithTrialEnabledOffersTheTrial() {
    XCTAssertEqual(resolve(eligibility: [monthly: true]), .freeTrial)
  }

  func testReturningSubscriberGetsSubscribeCopy() {
    XCTAssertEqual(resolve(eligibility: [monthly: false]), .noTrial)
  }

  func testTrialSwitchedOffIgnoresEligibility() {
    XCTAssertEqual(resolve(trialEnabled: false, eligibility: [monthly: true]), .noTrial)
  }

  func testUncheckedProductWaitsWhileLoading() {
    XCTAssertEqual(resolve(eligibility: [:], isLoading: true), .checking)
  }

  func testUncheckedProductAfterLoadingNeverPromisesTrial() {
    XCTAssertEqual(resolve(eligibility: [:], isLoading: false), .noTrial)
  }

  func testEligibilityForAnotherProductDoesNotCarryOver() {
    XCTAssertEqual(resolve(eligibility: [ProductID.proYearly.rawValue: true]), .noTrial)
  }

  func testMissingProductHasNoTrial() {
    XCTAssertEqual(resolve(productID: nil, eligibility: [monthly: true], isLoading: true), .noTrial)
  }

  private func resolve(
    trialEnabled: Bool = true,
    productID: String? = ProductID.proMonthly.rawValue,
    eligibility: [String: Bool],
    isLoading: Bool = false
  ) -> PaywallTrialOffer {
    .resolve(
      trialEnabled: trialEnabled,
      productID: productID,
      eligibility: eligibility,
      isLoading: isLoading
    )
  }
}
