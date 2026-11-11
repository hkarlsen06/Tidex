import XCTest

/// The pre-signup journey on the offline design-review fixture: Welcome, the Add screen demo,
/// and the sign-up screen it hands the saved shift to. Nothing here needs the network.
@MainActor
final class OnboardingJourneyUITests: XCTestCase {
  private let timeout: TimeInterval = 30

  override internal func setUpWithError() throws {
    continueAfterFailure = false
  }

  /// Continue, one time chip and Save reach sign-up, which then names the shift it will save.
  func testDemoShowsPayForTheChosenTimesAndCarriesTheShiftToSignup() {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    app.launchEnvironment["TIDEX_UI_TEST_SCENARIO"] = "design-review"
    app.launchEnvironment["TIDEX_DESIGN_SCREEN"] = "onboarding"
    app.launch()

    let continueButton = app.buttons["onboarding.welcome.continue"]
    XCTAssertTrue(continueButton.waitForExistence(timeout: timeout), app.debugDescription)
    continueButton.tap()

    let save = app.buttons["onboarding.demo.save"]
    XCTAssertTrue(save.waitForExistence(timeout: timeout), app.debugDescription)
    XCTAssertFalse(save.isEnabled, "Save must wait until the shift has times")
    XCTAssertFalse(app.descendants(matching: .any)["onboarding.demo.pay"].exists)

    let chip = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "08:00")).firstMatch
    XCTAssertTrue(chip.waitForExistence(timeout: timeout), app.debugDescription)
    chip.tap()

    let pay = app.descendants(matching: .any)["onboarding.demo.pay"]
    XCTAssertTrue(pay.waitForExistence(timeout: timeout), app.debugDescription)
    XCTAssertNotNil(pay.label.rangeOfCharacter(from: .decimalDigits), pay.label)
    XCTAssertTrue(save.isEnabled)
    save.tap()

    let signupLine = app.staticTexts["Create an account to save the shift."]
    XCTAssertTrue(signupLine.waitForExistence(timeout: timeout), app.debugDescription)
  }
}
