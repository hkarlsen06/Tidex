import XCTest

/// Calendar taps, labels and markers, captured with offline fixture data.
final class CalendarSemanticsUITests: XCTestCase {
  private let timeout: TimeInterval = 30

  override internal func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor
  func testScheduleDayTapsFollowIOSConventions() {
    let app = XCUIApplication()
    app.launchArguments = [
      "-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
      "-defaultStartupTab", "shifts", "-AppleInterfaceStyle", "Dark", "-cachedTheme", "dark",
    ]
    app.launchEnvironment["TIDEX_UI_TEST_SCENARIO"] = "app-store-screenshots"
    app.launch()

    let shiftDay = day(beginningWith: "Thursday, September 3,", in: app)
    XCTAssertTrue(shiftDay.waitForExistence(timeout: timeout), app.debugDescription)
    XCTAssertTrue(shiftDay.label.contains("09:00 to 17:00"), shiftDay.label)
    XCTAssertTrue(shiftDay.label.contains("after tax"), shiftDay.label)
    XCTAssertTrue(app.buttons["Times"].exists, "The time toggle should say what the cells show")
    attachScreenshot(app, name: "schedule-calendar")

    // A tap on a day with a shift opens it.
    shiftDay.tap()
    let done = app.buttons["Done"]
    XCTAssertTrue(done.waitForExistence(timeout: timeout), app.debugDescription)
    XCTAssertFalse(app.buttons["Details"].exists, "A tap should not start selecting days")
    attachScreenshot(app, name: "schedule-tap-opens-shift")
    done.tap()

    addShiftFromEmptyDay(app)

    // A long-press starts selecting, and the selection bar names its Edit button.
    app.buttons["Schedule"].firstMatch.tap()
    let otherShiftDay = day(beginningWith: "Thursday, September 10,", in: app)
    XCTAssertTrue(otherShiftDay.waitForExistence(timeout: timeout), app.debugDescription)
    otherShiftDay.press(forDuration: 1)
    XCTAssertTrue(app.buttons["Details"].waitForExistence(timeout: timeout), app.debugDescription)
    XCTAssertTrue(app.buttons["Edit"].exists, app.debugDescription)
    XCTAssertTrue(otherShiftDay.isSelected)
    attachScreenshot(app, name: "schedule-long-press-selects")
  }

  @MainActor
  func testSharedCalendarMarksWhoseShiftItIs() {
    let app = XCUIApplication()
    app.launchArguments = [
      "-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
      "-AppleInterfaceStyle", "Dark", "-cachedTheme", "dark",
    ]
    app.launchEnvironment["TIDEX_UI_TEST_SCENARIO"] = "design-review"
    app.launchEnvironment["TIDEX_DESIGN_SCREEN"] = "shared-calendar"
    app.launch()

    let overnight = day(beginningWith: "Monday, September 14,", in: app)
    XCTAssertTrue(overnight.waitForExistence(timeout: timeout), app.debugDescription)
    XCTAssertTrue(overnight.label.contains("Your shift"), overnight.label)
    XCTAssertTrue(overnight.label.contains("ends the next day"), overnight.label)
    let friendDay = day(beginningWith: "Tuesday, September 15,", in: app)
    XCTAssertTrue(friendDay.label.contains("Sam's shift"), friendDay.label)
    attachScreenshot(app, name: "shared-calendar")
  }

  /// A tap on an empty day offers a new shift on that date. The Add calendar then shows the
  /// preview amounts, labeled for VoiceOver.
  @MainActor
  private func addShiftFromEmptyDay(_ app: XCUIApplication) {
    let emptyDay = app.descendants(matching: .any)
      .matching(NSPredicate(format: "label == %@", "Wednesday, September 2")).firstMatch
    XCTAssertTrue(emptyDay.waitForExistence(timeout: timeout), app.debugDescription)
    emptyDay.tap()
    let recentTime = app.buttons.matching(NSPredicate(format: "label MATCHES %@", "09:00[–-]17:00"))
      .firstMatch
    XCTAssertTrue(recentTime.waitForExistence(timeout: timeout), app.debugDescription)
    let addPreview = app.descendants(matching: .any)
      .matching(NSPredicate(format: "label CONTAINS %@", "after tax")).firstMatch
    if !addPreview.waitForExistence(timeout: 2) {
      recentTime.tap()
    }
    XCTAssertTrue(addPreview.waitForExistence(timeout: timeout), app.debugDescription)
    attachScreenshot(app, name: "add-empty-day-preview")
  }

  private func day(beginningWith prefix: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any)
      .matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
  }

  @MainActor
  private func attachScreenshot(_ app: XCUIApplication, name: String) {
    // Let sheet and selection animations settle.
    Thread.sleep(forTimeInterval: 1)
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
