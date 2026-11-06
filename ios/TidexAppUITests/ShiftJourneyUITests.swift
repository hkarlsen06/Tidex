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
    app.launchEnvironment["TIDEX_SCREENSHOT_JOB"] = "NAV"
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

  func testPaymentSuggestionCancelPreservesShiftAndSaveLeavesDayWithoutHours() {
    let app = XCUIApplication()
    launchPaymentJourney(app)
    let date = Self.emptyFixtureDay()
    let emptyDay = app.descendants(matching: .any)
      .matching(NSPredicate(format: "label == %@", date)).firstMatch
    XCTAssertTrue(emptyDay.waitForExistence(timeout: timeout), app.debugDescription)
    let store = app.staticTexts["ui-testing.payment-store"]
    XCTAssertTrue(store.waitForExistence(timeout: timeout))
    let initialStore = store.label
    emptyDay.tap()
    selectNineToFive(in: app)
    let offer = app.buttons["add-shift.payment-adjustment"]
    XCTAssertTrue(offer.waitForExistence(timeout: timeout), app.debugDescription)
    retainScreenshot(app, name: "payment-suggestion")
    offer.tap()
    let amount = app.textFields["payroll-adjustment.amount"]
    XCTAssertTrue(amount.waitForExistence(timeout: timeout), app.debugDescription)
    XCTAssertEqual(amount.value as? String, "2000.0")
    retainScreenshot(app, name: "payment-editor")
    app.swipeUp()
    retainScreenshot(app, name: "payment-editor-date")
    app.swipeDown()
    app.buttons["Cancel"].tap()
    XCTAssertTrue(offer.waitForExistence(timeout: timeout), "Cancel must retain the unsaved shift")
    offer.tap()
    XCTAssertTrue(amount.waitForExistence(timeout: timeout))
    app.buttons["Save"].tap()
    let expectedStore = initialStore.replacingOccurrences(
      of: "adjustments=0;amounts=",
      with: "adjustments=1;amounts=2000.0")
    let persisted = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "label == %@", expectedStore), object: store)
    XCTAssertEqual(XCTWaiter.wait(for: [persisted], timeout: timeout), .completed, store.label)
    XCTAssertTrue(emptyDay.waitForExistence(timeout: timeout), app.debugDescription)
    XCTAssertFalse(
      app.descendants(matching: .any)
        .matching(NSPredicate(format: "label BEGINSWITH %@", date + ",")).firstMatch.exists,
      "A payment must not create a shift or add worked hours")
  }

  func testTariffSelectionSavesAdditionalSeniorityCategory() {
    let app = XCUIApplication()
    app.launchArguments = [
      "-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-cachedTheme", "dark",
    ]
    app.launchEnvironment["TIDEX_UI_TEST_SCENARIO"] = "design-review"
    app.launchEnvironment["TIDEX_DESIGN_SCREEN"] = "tariff-catalogue"
    app.launchEnvironment["TIDEX_TEST_TARIFFS"] = "1"
    app.launch()
    let picker = app.buttons["tariff.category-picker"]
    XCTAssertTrue(picker.waitForExistence(timeout: timeout), app.debugDescription)
    retainScreenshot(app, name: "tariff-hotel-en-dark")
    picker.tap()
    let category = app.buttons["tariff.category.7"]
    XCTAssertTrue(category.waitForExistence(timeout: timeout), app.debugDescription)
    for _ in 0..<5 where !category.isHittable { app.swipeUp() }
    category.tap()
    retainScreenshot(app, name: "tariff-seniority-selection")
    app.buttons["Continue"].tap()
    let saved = app.staticTexts["tariff.saved-result"]
    XCTAssertTrue(saved.waitForExistence(timeout: timeout), app.debugDescription)
    XCTAssertEqual(saved.label, "riksavtalen_hotel|7|218.9")
  }

  func testSecurityScheduleAndQualificationSaveTheirCombinedRate() {
    let app = XCUIApplication()
    launchTariffJourney(app, type: "vekter_355", language: "nb", theme: "light")
    let picker = app.buttons["tariff.category-picker"]
    XCTAssertTrue(picker.waitForExistence(timeout: timeout), app.debugDescription)
    retainScreenshot(app, name: "tariff-security-nb-light")
    picker.tap()
    let category = app.buttons["tariff.category.11"]
    XCTAssertTrue(category.waitForExistence(timeout: timeout), app.debugDescription)
    for _ in 0..<6 where !category.isHittable { app.swipeUp() }
    category.tap()
    retainScreenshot(app, name: "tariff-security-qualified")
    app.buttons["Fortsett"].tap()
    let saved = app.staticTexts["tariff.saved-result"]
    XCTAssertTrue(saved.waitForExistence(timeout: timeout), app.debugDescription)
    XCTAssertEqual(saved.label, "vekter_355|11|274.58")
  }

  func testMunicipalAnnualPayCategorySavesHourlyEquivalentAtLargeText() {
    let app = XCUIApplication()
    launchTariffJourney(app, type: "ks_ch4_375", language: "en", theme: "dark", largeText: true)
    let picker = app.buttons["tariff.category-picker"]
    XCTAssertTrue(picker.waitForExistence(timeout: timeout), app.debugDescription)
    picker.tap()
    let category = app.buttons["tariff.category.1"]
    XCTAssertTrue(category.waitForExistence(timeout: timeout), app.debugDescription)
    for _ in 0..<6 where !category.isHittable { app.swipeUp() }
    category.tap()
    app.swipeUp()
    retainScreenshot(app, name: "tariff-ks-en-large")
    app.buttons["Continue"].tap()
    let saved = app.staticTexts["tariff.saved-result"]
    XCTAssertTrue(saved.waitForExistence(timeout: timeout), app.debugDescription)
    XCTAssertTrue(saved.label.hasPrefix("ks_ch4_375|1|"))
    XCTAssertEqual(
      Double(saved.label.split(separator: "|").last ?? "") ?? 0, 418_600 / 1_950, accuracy: 0.001)
  }

  func testAgreementSetupRequiresChoicesAndSavesTheExactNightGuardVariant() {
    let app = XCUIApplication()
    launchTariffJourney(app, type: "", language: "en", theme: "dark")
    let agreement = app.buttons["tariff.agreement"]
    XCTAssertTrue(agreement.waitForExistence(timeout: timeout), app.debugDescription)
    agreement.tap()
    let search = app.searchFields.firstMatch
    XCTAssertTrue(search.waitForExistence(timeout: timeout))
    search.tap()
    search.typeText("hotel")
    retainScreenshot(app, name: "tariff-agreement-search")
    let family = app.buttons["tariff.family.riksavtalen"]
    XCTAssertTrue(family.waitForExistence(timeout: timeout), app.debugDescription)
    family.tap()
    XCTAssertFalse(app.buttons["Continue"].isEnabled)
    chooseTariffOption(app, dimension: "week", value: "35.5")
    XCTAssertFalse(app.buttons["Continue"].isEnabled)
    app.buttons["Hourly wage"].tap()
    app.buttons["Tariff"].tap()
    XCTAssertEqual(app.buttons["tariff.dimension.week"].value as? String, "35.5 hours")
    chooseTariffOption(app, dimension: "night_role", value: "manual")
    let picker = app.buttons["tariff.category-picker"]
    XCTAssertTrue(picker.waitForExistence(timeout: timeout), app.debugDescription)
    picker.tap()
    let category = app.buttons["tariff.category.7"]
    XCTAssertTrue(category.waitForExistence(timeout: timeout))
    for _ in 0..<6 where !category.isHittable { app.swipeUp() }
    category.tap()
    retainScreenshot(app, name: "tariff-night-guard-setup")
    app.buttons["Continue"].tap()
    let saved = app.staticTexts["tariff.saved-result"]
    XCTAssertTrue(saved.waitForExistence(timeout: timeout), app.debugDescription)
    XCTAssertEqual(saved.label, "riksavtalen_manual_355|7|230.98")
  }

  func testSwitchingAgreementClearsAnUnrelatedPayCategory() {
    let app = XCUIApplication()
    launchTariffJourney(app, type: "riksavtalen_hotel", language: "en", theme: "dark")
    let picker = app.buttons["tariff.category-picker"]
    XCTAssertTrue(picker.waitForExistence(timeout: timeout), app.debugDescription)
    picker.tap()
    app.buttons["tariff.category.2"].tap()
    XCTAssertTrue(app.buttons["Continue"].isEnabled)
    app.buttons["tariff.agreement"].tap()
    let search = app.searchFields.firstMatch
    XCTAssertTrue(search.waitForExistence(timeout: timeout))
    search.tap()
    search.typeText("HK")
    let family = app.buttons["tariff.family.hk_retail"]
    XCTAssertTrue(family.waitForExistence(timeout: timeout), app.debugDescription)
    family.tap()
    XCTAssertTrue(picker.waitForExistence(timeout: timeout))
    XCTAssertFalse(app.buttons["Continue"].isEnabled)
    picker.tap()
    let category = app.buttons["tariff.category.2"]
    XCTAssertTrue(category.waitForExistence(timeout: timeout))
    category.tap()
    app.buttons["Continue"].tap()
    let saved = app.staticTexts["tariff.saved-result"]
    XCTAssertTrue(saved.waitForExistence(timeout: timeout), app.debugDescription)
    XCTAssertEqual(saved.label, "hk_retail|2|195.88")
  }

  func testManualOvertimeArrangementExplainsItsCalculationLimitBesidePay() {
    let app = XCUIApplication()
    launchTariffJourney(app, type: "grossist_virke_3", language: "en", theme: "light")
    let picker = app.buttons["tariff.category-picker"]
    XCTAssertTrue(picker.waitForExistence(timeout: timeout), app.debugDescription)
    picker.tap()
    app.buttons["tariff.category.1"].tap()
    let coverage = app.staticTexts["tariff.calculation-coverage"]
    XCTAssertTrue(coverage.waitForExistence(timeout: timeout), app.debugDescription)
    for _ in 0..<5 where !coverage.isHittable { app.swipeUp() }
    XCTAssertEqual(
      coverage.label,
      "Automatic overtime is off. Add overtime adjustments manually.")
    XCTAssertTrue(coverage.isHittable)
    retainScreenshot(app, name: "tariff-manual-overtime-coverage")
  }

  func testCancelingTariffChoosersPreservesAnExistingPersonalWageAndRules() {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-cachedTheme", "dark"]
    app.launchEnvironment["TIDEX_UI_TEST_SCENARIO"] = "design-review"
    app.launchEnvironment["TIDEX_DESIGN_SCREEN"] = "tariff-pay-editor"
    app.launchEnvironment["TIDEX_TEST_TARIFFS"] = "1"
    app.launch()
    let agreement = app.buttons["tariff.agreement"]
    XCTAssertTrue(agreement.waitForExistence(timeout: timeout), app.debugDescription)
    XCTAssertEqual(app.buttons["tariff.dimension.week"].value as? String, "35.5 hours")
    XCTAssertEqual(
      app.buttons["tariff.dimension.night_role"].value as? String,
      "Yes, with agreed manual work")
    agreement.tap()
    app.navigationBars["Choose agreement"].buttons["Cancel"].tap()
    let category = app.buttons["tariff.category-picker"]
    for _ in 0..<6 where !category.isHittable { app.swipeUp() }
    category.tap()
    app.navigationBars["Pay category"].buttons["Cancel"].tap()
    retainScreenshot(app, name: "tariff-saved-personal-pay")
    app.buttons["Save"].tap()
    let saved = app.staticTexts["tariff.overtime-saved-result"]
    XCTAssertTrue(saved.waitForExistence(timeout: timeout), app.debugDescription)
    XCTAssertEqual(saved.label, "riksavtalen_manual_355|1|400.0|true|true")
  }

  private func chooseTariffOption(_ app: XCUIApplication, dimension: String, value: String) {
    let picker = app.buttons["tariff.dimension.\(dimension)"]
    XCTAssertTrue(picker.waitForExistence(timeout: timeout), app.debugDescription)
    for _ in 0..<5 where !picker.isHittable { app.swipeUp() }
    picker.tap()
    let option = app.buttons["tariff.option.\(dimension).\(value)"]
    XCTAssertTrue(option.waitForExistence(timeout: timeout), app.debugDescription)
    option.tap()
  }

  func testDatedOvertimeSurvivesSavingThePayEditor() {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-cachedTheme", "dark"]
    app.launchEnvironment["TIDEX_UI_TEST_SCENARIO"] = "design-review"
    app.launchEnvironment["TIDEX_DESIGN_SCREEN"] = "tariff-overtime-editor"
    app.launchEnvironment["TIDEX_TEST_TARIFFS"] = "1"
    app.launch()
    let rules = app.buttons["Calendar rules from the agreement"]
    XCTAssertTrue(rules.waitForExistence(timeout: timeout), app.debugDescription)
    rules.tap()
    retainScreenshot(app, name: "tariff-calendar-overtime")
    app.buttons["Save"].tap()
    let saved = app.staticTexts["tariff.overtime-saved-result"]
    XCTAssertTrue(saved.waitForExistence(timeout: timeout), app.debugDescription)
    let parts = saved.label.split(separator: "|")
    XCTAssertEqual(parts.count, 3)
    guard parts.count == 3 else { return }
    XCTAssertEqual(Double(parts[0]) ?? 0, 418_600 / 1_950, accuracy: 0.001)
    XCTAssertGreaterThan(Int(parts[1]) ?? 0, 0)
    XCTAssertEqual(Double(parts[2]) ?? 0, 400 / 3, accuracy: 0.001)
  }

  private func launchTariffJourney(
    _ app: XCUIApplication, type: String, language: String, theme: String, largeText: Bool = false
  ) {
    app.launchArguments = [
      "-ui-testing", "-AppleLanguages", "(\(language))", "-cachedTheme", theme,
    ]
    if largeText {
      app.launchArguments += [
        "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
      ]
    }
    app.launchEnvironment["TIDEX_UI_TEST_SCENARIO"] = "design-review"
    app.launchEnvironment["TIDEX_DESIGN_SCREEN"] = "tariff-catalogue"
    app.launchEnvironment["TIDEX_TEST_TARIFFS"] = "1"
    app.launchEnvironment["TIDEX_TEST_TARIFF_TYPE"] = type
    app.launch()
  }

  private func launchPaymentJourney(_ app: XCUIApplication) {
    app.launchArguments = [
      "-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
      "-defaultStartupTab", "shifts",
    ]
    app.launchEnvironment["TIDEX_UI_TEST_SCENARIO"] = "app-store-screenshots"
    app.launchEnvironment["TIDEX_SCREENSHOT_JOB"] = "NAV"
    app.launchEnvironment["TIDEX_TEST_PAYMENTS"] = "1"
    if ProcessInfo.processInfo.environment["TIDEX_QA_LARGE"] == "1" {
      app.launchArguments += [
        "-cachedTheme", "dark", "-UIPreferredContentSizeCategoryName",
        "UICTContentSizeCategoryAccessibilityXXXL",
      ]
    }
    app.launch()
    if ProcessInfo.processInfo.environment["TIDEX_QA_LARGE"] == "1" {
      app.buttons["Show calendar"].tap()
    }
  }

  private func retainScreenshot(_ app: XCUIApplication, name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  /// Saves a 09:00 to 17:00 single shift on the date the Add screen opened with.
  private func saveNineToFiveShift(in app: XCUIApplication) {
    selectNineToFive(in: app)
    app.buttons["add-shift.save"].tap()
    dismissNotificationPrompt()
  }

  private func selectNineToFive(in app: XCUIApplication) {
    let singleMode = app.buttons["add-shift.mode.single"]
    XCTAssertTrue(singleMode.waitForExistence(timeout: timeout), app.debugDescription)
    if !singleMode.isSelected {
      singleMode.tap()
    }
    let recentTime = app.buttons.matching(
      NSPredicate(format: "label MATCHES %@", "[^,]*09:00[^,]*17:00[^,]*")
    )
    .firstMatch
    XCTAssertTrue(recentTime.waitForExistence(timeout: timeout), app.debugDescription)
    let preview = app.descendants(matching: .any)
      .matching(NSPredicate(format: "label CONTAINS %@", "after tax")).firstMatch
    // A restored draft may already have this range selected; tapping it again clears it.
    if !preview.waitForExistence(timeout: 2) {
      recentTime.tap()
    }
    XCTAssertTrue(preview.waitForExistence(timeout: timeout), app.debugDescription)
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
