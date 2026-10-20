import XCTest

/// Whole user journeys through the real app, with the offline screenshot fixture as data.
@MainActor
final class ShiftJourneyUITests: XCTestCase {
  private let timeout: TimeInterval = 30

  override internal func setUpWithError() throws {
    continueAfterFailure = false
  }

  /// Adds a shift on an empty day, checks that the schedule shows it with its pay, then deletes it.
  /// This runs the Add screen, the local store, the payroll engine and the schedule together.
  @MainActor
  func testAddedShiftShowsOnTheScheduleWithPayAndCanBeDeleted() {
    let app = XCUIApplication()
    app.launchArguments = [
      "-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
      "-defaultStartupTab", "shifts",
    ]
    app.launchEnvironment["TIDEX_UI_TEST_SCENARIO"] = "app-store-screenshots"
    app.launch()

    let date = Self.emptyFixtureDay()
    let emptyDay = app.descendants(matching: .any)
      .matching(NSPredicate(format: "label == %@", date)).firstMatch
    XCTAssertTrue(emptyDay.waitForExistence(timeout: timeout), app.debugDescription)
    emptyDay.tap()

    saveNineToFiveShift(in: app)

    let savedDay = app.descendants(matching: .any)
      .matching(NSPredicate(format: "label BEGINSWITH %@", date + ",")).firstMatch
    XCTAssertTrue(savedDay.waitForExistence(timeout: timeout), app.debugDescription)
    XCTAssertTrue(savedDay.label.contains("09:00 to 17:00"), savedDay.label)
    XCTAssertTrue(savedDay.label.contains("after tax"), savedDay.label)

    savedDay.tap()
    let delete = app.buttons["Delete Shift"]
    XCTAssertTrue(delete.waitForExistence(timeout: timeout), app.debugDescription)
    delete.tap()
    let confirm = app.alerts["Delete Shift?"].buttons["Delete Shift"]
    XCTAssertTrue(confirm.waitForExistence(timeout: timeout), app.debugDescription)
    confirm.tap()

    XCTAssertTrue(emptyDay.waitForExistence(timeout: timeout), app.debugDescription)
    XCTAssertFalse(savedDay.exists, "The deleted shift must leave the schedule")
  }

  /// Saves a 09:00 to 17:00 single shift on the date the Add screen opened with.
  private func saveNineToFiveShift(in app: XCUIApplication) {
    let singleMode = app.buttons["add-shift.mode.single"]
    XCTAssertTrue(singleMode.waitForExistence(timeout: timeout), app.debugDescription)
    if !singleMode.isSelected {
      singleMode.tap()
    }
    let recentTime = app.buttons.matching(NSPredicate(format: "label MATCHES %@", "[^,]*09:00[^,]*17:00[^,]*"))
      .firstMatch
    XCTAssertTrue(recentTime.waitForExistence(timeout: timeout), app.debugDescription)
    let preview = app.descendants(matching: .any)
      .matching(NSPredicate(format: "label CONTAINS %@", "after tax")).firstMatch
    // A restored draft may already have this range selected; tapping it again clears it.
    if !preview.waitForExistence(timeout: 2) {
      recentTime.tap()
    }
    XCTAssertTrue(preview.waitForExistence(timeout: timeout), app.debugDescription)
    app.buttons["add-shift.save"].tap()
    dismissNotificationPrompt()
  }

  /// The day the fixture leaves empty, as the schedule's accessibility label names it.
  /// `AppStoreScreenshotFixture.shiftDays` never puts a shift on the 21st or 23rd unless it is
  /// today, so pick the one that isn't today.
  private static func emptyFixtureDay() -> String {
    let calendar = Calendar(identifier: .gregorian)
    var components = calendar.dateComponents([.year, .month, .day], from: .now)
    components.day = components.day == 23 ? 21 : 23
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US")
    formatter.dateFormat = "EEEE, MMMM d"
    return formatter.string(from: calendar.date(from: components) ?? .now)
  }

  /// Saving a shift can ask for notification permission for shift reminders.
  private func dismissNotificationPrompt() {
    let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
    if alert.waitForExistence(timeout: 3) {
      alert.buttons.element(boundBy: 0).tap()
    }
  }
}
