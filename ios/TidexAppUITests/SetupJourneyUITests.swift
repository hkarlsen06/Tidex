import XCTest

/// Setup after sign-up, walked through the real screens in the offline `onboarding-setup` fixture.
@MainActor
final class SetupJourneyUITests: XCTestCase {
  private let timeout: TimeInterval = 30

  override internal func setUpWithError() throws {
    continueAfterFailure = false
  }

  /// The target is four taps plus the job name from the purpose screen to a saved demo shift.
  func testCarriedShiftIsSavedWithFourTapsAfterTypingTheJobName() {
    let app = makeApp(result: "carried")
    app.launch()

    let payChoice = button(startingWith: "Calculate my pay", in: app)
    XCTAssertTrue(payChoice.waitForExistence(timeout: timeout), app.debugDescription)
    payChoice.tap()

    // The name field has focus on arrival and Continue stays above the keyboard.
    XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: timeout), app.debugDescription)
    app.typeText("Harbor Cafe")
    let proceed = app.buttons["Continue"]
    XCTAssertTrue(proceed.isHittable, "Continue must be usable while typing.\n\(app.debugDescription)")
    proceed.tap()

    XCTAssertTrue(app.staticTexts["Step 2 of 2"].waitForExistence(timeout: timeout))
    proceed.tap()

    XCTAssertTrue(
      app.staticTexts["What your shift pays"].waitForExistence(timeout: timeout),
      app.debugDescription)
    XCTAssertTrue(app.staticTexts["Gross Pay"].exists, app.debugDescription)
    let save = app.buttons["Save the shift"]
    XCTAssertTrue(save.isHittable, app.debugDescription)
    save.tap()

    XCTAssertTrue(payChoice.waitForExistence(timeout: timeout), "The fixture restarts after Save")
  }

  func testFailedSaveGoesBackToTheWageWithTheJobNameKept() {
    let app = makeApp(result: "failed")
    app.launch()

    let payChoice = button(startingWith: "Calculate my pay", in: app)
    XCTAssertTrue(payChoice.waitForExistence(timeout: timeout), app.debugDescription)
    payChoice.tap()
    XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: timeout), app.debugDescription)
    app.typeText("Harbor Cafe")
    app.buttons["Continue"].tap()
    XCTAssertTrue(app.staticTexts["Step 2 of 2"].waitForExistence(timeout: timeout))
    app.buttons["Continue"].tap()

    XCTAssertTrue(
      app.staticTexts["Something went wrong"].waitForExistence(timeout: timeout),
      app.debugDescription)
    XCTAssertTrue(app.buttons["Try again"].exists, app.debugDescription)
    app.buttons["Back"].tap()

    XCTAssertTrue(app.staticTexts["Step 2 of 2"].waitForExistence(timeout: timeout))
    app.buttons["Back"].tap()
    let name = app.textFields["Job name"]
    XCTAssertTrue(name.waitForExistence(timeout: timeout), app.debugDescription)
    XCTAssertEqual(name.value as? String, "Harbor Cafe")
  }

  private func makeApp(result: String) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments += ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    app.launchEnvironment["TIDEX_UI_TEST_SCENARIO"] = "design-review"
    app.launchEnvironment["TIDEX_DESIGN_SCREEN"] = "onboarding-setup"
    app.launchEnvironment["TIDEX_DESIGN_RESULT"] = result
    return app
  }

  private func button(startingWith label: String, in app: XCUIApplication) -> XCUIElement {
    app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch
  }
}
