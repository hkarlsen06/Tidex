import XCTest

final class TidexAppUITests: XCTestCase {
  private enum AccessibilityID {
    static let composerTextField = "friends-thread-composer.text-field"
    static let sendButton = "friends-thread-composer.send-button"
    static let replyCancelButton = "friends-thread-composer.reply-cancel"
    static let attachmentToggleButton = "friends-thread-composer.attachment-toggle"
    static let uiTestingError = "ui-testing.error"
    static let popoverDismissRegion = "PopoverDismissRegion"
    static let loginRevealEmail = "login.reveal-email"
    static let loginEmailOrPhone = "login.email-or-phone"
    static let loginCreateAccount = "login.create-account"
    static let loginForgotPassword = "login.forgot-password"
  }

  private let defaultTimeout: TimeInterval = 15
  private let composerPlaceholder = "Message"
  private let sendButtonLabel = "Send message"
  private let seededIncomingMessage = "Initial incoming message"
  private let sentMessageText = "UI test send"
  private let commonDeleteLabel = "Delete"
  private let commonCancelLabel = "Cancel"
  private let deleteConfirmationTitle = "Delete this conversation?"

  override internal func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor
  func testPaywallWithoutConfirmedTrialEligibilityDoesNotPromiseATrial() {
    let app = makeApp(scenario: "design-review")
    app.launchEnvironment["TIDEX_DESIGN_SCREEN"] = "paywall"
    app.launch()
    XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: defaultTimeout))
    attachAppStoreScreenshot(app, name: "billing-paywall")
    XCTAssertTrue(app.staticTexts["Unlock Tidex Pro"].exists, app.debugDescription)
    XCTAssertFalse(app.staticTexts["Try Tidex Pro free"].exists)
    XCTAssertFalse(app.buttons["Start my free trial"].exists)
  }

  @MainActor
  func testDeleteAccountWarnsThatTheAppStoreSubscriptionKeepsBilling() {
    let app = makeApp(scenario: "design-review")
    app.launchEnvironment["TIDEX_DESIGN_SCREEN"] = "profile-subscribed"
    app.launch()
    let signOut = app.buttons["Log out"]
    XCTAssertTrue(signOut.waitForExistence(timeout: defaultTimeout), app.debugDescription)
    for _ in 0..<3 where !app.buttons["Delete Account"].isHittable { app.swipeUp() }
    attachAppStoreScreenshot(app, name: "billing-profile-sessions")
    app.buttons["Delete Account"].tap()
    let alert = app.alerts.firstMatch
    XCTAssertTrue(alert.waitForExistence(timeout: defaultTimeout), app.debugDescription)
    attachAppStoreScreenshot(app, name: "billing-delete-account-dialog")
    XCTAssertTrue(
      alert.staticTexts.matching(
        NSPredicate(format: "label CONTAINS %@", "doesn't cancel your App Store subscription")
      ).firstMatch.exists, alert.debugDescription)
    XCTAssertTrue(alert.buttons["Manage subscription"].exists, alert.debugDescription)
  }

  @MainActor
  func testTaxSettingExplainsTheFlatPercentage() {
    let app = makeApp(scenario: "design-review")
    app.launchEnvironment["TIDEX_DESIGN_SCREEN"] = "pay-history-tariff-editor"
    app.launch()
    let taxToggle = app.switches["pay-settings.tax-toggle"]
    XCTAssertTrue(taxToggle.waitForExistence(timeout: defaultTimeout), app.debugDescription)
    taxToggle.tap()
    let hint = text(containingLabel: "one flat percentage", in: app)
    _ = hint.waitForExistence(timeout: 3)
    attachAppStoreScreenshot(app, name: "billing-tax-flat-rate")
    XCTAssertTrue(hint.exists, app.debugDescription)
  }

  @MainActor
  func testPayReviewOpensThePayoutTaxPeriodDirectly() {
    let app = makeApp(scenario: "design-review")
    app.launchEnvironment["TIDEX_DESIGN_SCREEN"] = "pay-settings-review"
    app.launch()
    let review = app.buttons["pay-settings.review-disclosure"]
    XCTAssertTrue(review.waitForExistence(timeout: defaultTimeout), app.debugDescription)
    XCTAssertTrue(review.label.contains("Check pay settings for a date"), review.label)
    XCTAssertTrue(review.label.contains("November 15, 2026"), review.label)
    let taxSettings = app.buttons["Review these tax settings"]
    XCTAssertFalse(taxSettings.exists, "The pay-settings date review should start collapsed")
    attachAppStoreScreenshot(app, name: "pay-review-collapsed")
    review.tap()
    XCTAssertTrue(taxSettings.waitForExistence(timeout: defaultTimeout), app.debugDescription)
    attachAppStoreScreenshot(app, name: "pay-review-date-settings")
    if !taxSettings.isHittable { app.swipeUp() }
    taxSettings.tap()
    let taxToggle = app.switches["pay-settings.tax-toggle"]
    XCTAssertTrue(taxToggle.waitForExistence(timeout: defaultTimeout), app.debugDescription)
    XCTAssertTrue(taxToggle.isHittable, "Tax settings should open at the tax section")
    attachAppStoreScreenshot(app, name: "pay-review-payout-tax-period")
    app.buttons["Save"].tap()
    let saved = app.staticTexts["pay-history.saved-result"]
    XCTAssertTrue(saved.waitForExistence(timeout: defaultTimeout), app.debugDescription)
    XCTAssertEqual(saved.label, "250.0|2026-12-01")
  }

  @MainActor
  func testAddingPayHistoryUsesTheSelectedWorkDateSettings() {
    let app = makeApp(scenario: "design-review")
    app.launchEnvironment["TIDEX_DESIGN_SCREEN"] = "pay-settings-review"
    app.launch()
    let add = app.buttons["pay-history.add-change"]
    XCTAssertTrue(add.waitForExistence(timeout: defaultTimeout), app.debugDescription)
    if !add.isHittable { app.swipeUp() }
    add.tap()
    let rate = app.staticTexts["pay-settings.hourly-wage"]
    XCTAssertTrue(rate.waitForExistence(timeout: defaultTimeout), app.debugDescription)
    XCTAssertTrue(rate.label.contains("200"), rate.label)
    app.buttons["Save"].tap()
    let saved = app.staticTexts["pay-history.saved-result"]
    XCTAssertTrue(saved.waitForExistence(timeout: defaultTimeout), app.debugDescription)
    XCTAssertEqual(saved.label, "200.0|2026-11-15")
  }

  @MainActor
  func testPayHistoryPeriodRowOpensItsSettings() {
    let app = makeApp(scenario: "design-review")
    app.launchEnvironment["TIDEX_DESIGN_SCREEN"] = "pay-settings-review"
    app.launch()
    let period = app.buttons["pay-history.period.future"]
    XCTAssertTrue(period.waitForExistence(timeout: defaultTimeout), app.debugDescription)
    for _ in 0..<4 where !period.isHittable { app.swipeUp() }
    XCTAssertTrue(period.isHittable, app.debugDescription)
    attachAppStoreScreenshot(app, name: "pay-history-periods")
    period.tap()
    let rate = app.staticTexts["pay-settings.hourly-wage"]
    XCTAssertTrue(rate.waitForExistence(timeout: defaultTimeout), app.debugDescription)
    XCTAssertTrue(rate.label.contains("250"), rate.label)
    attachAppStoreScreenshot(app, name: "pay-history-period-editor")
    app.buttons["Save"].tap()
    let saved = app.staticTexts["pay-history.saved-result"]
    XCTAssertTrue(saved.waitForExistence(timeout: defaultTimeout), app.debugDescription)
    XCTAssertEqual(saved.label, "250.0|2026-12-01")
  }

  @MainActor
  func testEditingTaxPreservesSavedTariffWageAndSupplements() {
    let app = makeApp(scenario: "design-review")
    app.launchEnvironment["TIDEX_DESIGN_SCREEN"] = "pay-history-tariff-editor"
    app.launch()
    let taxToggle = app.switches["pay-settings.tax-toggle"]
    XCTAssertTrue(taxToggle.waitForExistence(timeout: defaultTimeout), app.debugDescription)
    XCTAssertTrue(taxToggle.isHittable, app.debugDescription)
    taxToggle.tap()
    app.buttons["Save"].tap()
    let saved = app.staticTexts["pay-history.saved-result"]
    XCTAssertTrue(saved.waitForExistence(timeout: defaultTimeout), app.debugDescription)
    XCTAssertEqual(saved.label, "184.12|1|true")
  }

  @MainActor
  func testAdditionalWorkplaceSetupIncludesBreakAndTaxChoices() {
    verifyWorkplaceDeductionsSetup(screen: "job-pay-setup")
  }

  @MainActor
  func testAddingAWorkplaceIncludesBreakAndTaxChoices() {
    verifyWorkplaceDeductionsSetup(screen: "add-job-setup")
  }

  @MainActor
  private func verifyWorkplaceDeductionsSetup(screen: String) {
    let app = makeApp(scenario: "design-review")
    app.launchEnvironment["TIDEX_DESIGN_SCREEN"] = screen
    app.launch()
    let proceed = app.buttons["Continue"]
    XCTAssertTrue(proceed.waitForExistence(timeout: defaultTimeout), app.debugDescription)
    proceed.tap()
    XCTAssertTrue(
      app.staticTexts["Choose your wage type"].waitForExistence(timeout: defaultTimeout))
    proceed.tap()
    let skip = app.buttons["Skip"]
    XCTAssertTrue(skip.waitForExistence(timeout: defaultTimeout), app.debugDescription)
    skip.tap()
    XCTAssertTrue(app.staticTexts["Break deduction"].waitForExistence(timeout: defaultTimeout))
    attachAppStoreScreenshot(app, name: "\(screen)-deductions")
    proceed.tap()
    let taxChoice = app.switches.matching(
      NSPredicate(format: "label CONTAINS %@", "Show pay after tax")
    )
    .firstMatch
    XCTAssertTrue(taxChoice.waitForExistence(timeout: defaultTimeout), app.debugDescription)
    taxChoice.tap()
    if !proceed.isHittable { app.swipeUp() }
    proceed.tap()
    app.buttons["Save"].tap()
    let saved = app.staticTexts["pay-history.saved-result"]
    XCTAssertTrue(saved.waitForExistence(timeout: defaultTimeout), app.debugDescription)
    XCTAssertEqual(saved.label, "true|true")
  }

  @MainActor
  func testPayReviewRemainsUsableWithLargeText() {
    let app = makeApp(scenario: "design-review")
    app.launchEnvironment["TIDEX_DESIGN_SCREEN"] = "pay-settings-accessibility"
    app.launch()
    let review = app.buttons["pay-settings.review-disclosure"]
    XCTAssertTrue(review.waitForExistence(timeout: defaultTimeout), app.debugDescription)
    attachAppStoreScreenshot(app, name: "pay-review-large-text-top")
    review.tap()
    let taxSettings = app.buttons["Review these tax settings"]
    for _ in 0..<6 where !taxSettings.isHittable { app.swipeUp() }
    XCTAssertTrue(taxSettings.isHittable, app.debugDescription)
    attachAppStoreScreenshot(app, name: "pay-review-large-text")
    taxSettings.tap()
    let toggle = app.switches["pay-settings.tax-toggle"]
    XCTAssertTrue(toggle.waitForExistence(timeout: defaultTimeout))
    XCTAssertTrue(toggle.isHittable, app.debugDescription)
    let preset = app.buttons["25%"]
    for _ in 0..<3 where !preset.isHittable { app.swipeUp() }
    XCTAssertTrue(preset.isHittable, app.debugDescription)
    XCTAssertGreaterThanOrEqual(preset.frame.height, 44)
    preset.tap()
    XCTAssertTrue(preset.isSelected, app.debugDescription)
    attachAppStoreScreenshot(app, name: "pay-review-large-text-tax-editor")
    let methods = app.buttons["pay-settings.break-method"]
    for _ in 0..<5 where !methods.isHittable { app.swipeUp() }
    XCTAssertTrue(methods.isHittable, app.debugDescription)
    methods.tap()
    let threshold = app.steppers["pay-settings.break-threshold"]
    for _ in 0..<3 where !threshold.isHittable { app.swipeUp() }
    XCTAssertTrue(threshold.isHittable, app.debugDescription)
    threshold.buttons["pay-settings.break-threshold-Increment"].tap()
    XCTAssertEqual(threshold.value as? String, "6 hours")
    attachAppStoreScreenshot(app, name: "pay-review-large-text-break-editor")
  }

  @MainActor
  func testOvernightPayrollBreakdownSeparatesOvertimeAndUnpaidBreak() {
    let app = makeApp(scenario: "design-review")
    app.launchEnvironment["TIDEX_DESIGN_SCREEN"] = "payroll-breakdown"
    app.launch()
    let overtime = app.buttons["Overtime"]
    XCTAssertTrue(overtime.waitForExistence(timeout: defaultTimeout), app.debugDescription)
    XCTAssertTrue(app.staticTexts["Gross Pay"].exists, app.debugDescription)
    overtime.tap()
    let midnight = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "(+1)"))
      .firstMatch
    XCTAssertTrue(midnight.waitForExistence(timeout: defaultTimeout), app.debugDescription)
    let deduction = app.buttons.matching(
      NSPredicate(format: "label CONTAINS %@", "Break deduction")
    )
    .firstMatch
    if !deduction.isHittable { app.swipeUp() }
    XCTAssertTrue(deduction.waitForExistence(timeout: defaultTimeout), app.debugDescription)
    deduction.tap()
    attachAppStoreScreenshot(app, name: "payroll-night-overtime-and-break")
  }

  @MainActor
  func testAppStoreScreenshots() {
    for (language, locale, shiftsTitle, statsTitle) in [
      ("en", "en_US", "Schedule", "Stats"),
      ("nb", "nb_NO", "Vaktplan", "Statistikk"),
    ] {
      let app = XCUIApplication()
      app.launchArguments = [
        "-ui-testing", "-AppleLanguages", "(\(language))", "-AppleLocale", locale,
        "-defaultStartupTab", "home", "-AppleInterfaceStyle", "Dark", "-cachedTheme", "dark",
      ]
      app.launchEnvironment["TIDEX_UI_TEST_SCENARIO"] = "app-store-screenshots"
      app.launch()
      let earnings = app.staticTexts.matching(
        NSPredicate(format: "label MATCHES %@", ".*22[^0-9]?400.*")
      ).firstMatch
      XCTAssertTrue(earnings.waitForExistence(timeout: 30), app.debugDescription)
      XCTAssertFalse(app.staticTexts["screenshot.error"].exists)
      if language == "en" {
        assertHomeContentInsets(app)
      }
      attachAppStoreScreenshot(app, name: "\(language)-01-home")

      capturePayrollScreenshot(app, language: language)

      let statsButton = app.buttons[statsTitle]
      XCTAssertTrue(statsButton.waitForExistence(timeout: defaultTimeout), app.debugDescription)
      statsButton.tap()
      XCTAssertTrue(app.buttons["BackButton"].waitForExistence(timeout: defaultTimeout))
      XCTAssertTrue(earnings.waitForExistence(timeout: defaultTimeout), app.debugDescription)
      attachAppStoreScreenshot(app, name: "\(language)-02-statistics")

      app.buttons["BackButton"].tap()
      app.buttons[shiftsTitle].firstMatch.tap()
      let calendarAmount = app.staticTexts.matching(
        NSPredicate(format: "label == %@", "09:00")
      ).firstMatch
      XCTAssertTrue(calendarAmount.waitForExistence(timeout: 30), app.debugDescription)
      XCTAssertTrue(app.buttons[shiftsTitle].firstMatch.exists, app.debugDescription)
      attachAppStoreScreenshot(app, name: "\(language)-03-schedule")
      captureAddScreenshot(app, language: language)
    }
  }

  @MainActor
  private func assertHomeContentInsets(_ app: XCUIApplication) {
    let clockIn = app.buttons["Clock in"]
    let clockOut = app.buttons["Clock out"]
    let payout = app.staticTexts["Next payout"]
    XCTAssertTrue(clockIn.waitForExistence(timeout: defaultTimeout))
    XCTAssertTrue(clockOut.exists)
    XCTAssertTrue(payout.waitForExistence(timeout: defaultTimeout))
    XCTAssertGreaterThanOrEqual(
      clockIn.frame.minX - app.frame.minX, 39,
      "Home content must leave a 40-point margin at each screen edge")
    XCTAssertGreaterThanOrEqual(app.frame.maxX - clockOut.frame.maxX, 39)
    XCTAssertEqual(payout.frame.minX, clockIn.frame.minX, accuracy: 1)
  }

  @MainActor
  private func capturePayrollScreenshot(_ app: XCUIApplication, language: String) {
    let payroll = app.staticTexts[language == "en" ? "Next payout" : "Neste utbetaling"]
    XCTAssertTrue(payroll.waitForExistence(timeout: defaultTimeout), app.debugDescription)
    payroll.tap()
    let done = app.buttons[language == "en" ? "Done" : "Ferdig"]
    XCTAssertTrue(done.waitForExistence(timeout: defaultTimeout), app.debugDescription)
    let supplements = app.buttons.matching(
      NSPredicate(
        format: "label CONTAINS %@", language == "en" ? "Total Supplement" : "Totalt tillegg"
      )
    ).firstMatch
    XCTAssertTrue(supplements.waitForExistence(timeout: defaultTimeout), app.debugDescription)
    supplements.tap()
    // The expanded breakdown includes the pay-settings link and needs the large detent.
    let header = done.coordinate(withNormalizedOffset: CGVector(dx: -1, dy: 0.5))
    let expandedPosition = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
    header.press(forDuration: 0.1, thenDragTo: expandedPosition)
    let paySettings = app.buttons[
      language == "en" ? "Check the pay settings" : "Sjekk lønnsinnstillingene"
    ]
    XCTAssertTrue(paySettings.waitForExistence(timeout: defaultTimeout), app.debugDescription)
    XCTAssertTrue(
      app.frame.contains(paySettings.frame), "Pay-settings link must fit in the screenshot")
    attachAppStoreScreenshot(app, name: "\(language)-04-payroll")
    done.tap()
  }

  @MainActor
  private func captureAddScreenshot(_ app: XCUIApplication, language: String) {
    app.buttons[language == "en" ? "Add" : "Legg til"].firstMatch.tap()
    let recentTime = app.buttons.matching(NSPredicate(format: "label MATCHES %@", "09:00[–-]17:00"))
      .firstMatch
    XCTAssertTrue(recentTime.waitForExistence(timeout: 30), app.debugDescription)
    let previewTotal = app.staticTexts.matching(
      NSPredicate(format: "label MATCHES %@", ".*24[^0-9]?000.*")
    ).firstMatch
    // A restored draft may already have this range selected; tapping it again clears it.
    if !previewTotal.waitForExistence(timeout: 2) {
      recentTime.tap()
    }
    XCTAssertTrue(previewTotal.waitForExistence(timeout: defaultTimeout), app.debugDescription)
    attachAppStoreScreenshot(app, name: "\(language)-05-add")
    app.terminate()
  }

  @MainActor
  private func attachAppStoreScreenshot(_ app: XCUIApplication, name: String) {
    // Currency transitions can still be animating after their accessibility value updates.
    Thread.sleep(forTimeInterval: 1)
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  /// Walks the screens that show money amounts and checks that each amount says what it is.
  @MainActor
  func testMoneyAmountsSayWhatTheyAre() {
    let app = makeApp(scenario: "app-store-screenshots")
    app.launchArguments += [
      "-defaultStartupTab", "home", "-AppleInterfaceStyle", "Dark", "-cachedTheme", "dark",
    ]
    app.launch()
    let earnings = app.staticTexts.matching(
      NSPredicate(format: "label MATCHES %@", ".*22[^0-9]?400.*")
    )
    .firstMatch
    XCTAssertTrue(earnings.waitForExistence(timeout: 30), app.debugDescription)
    XCTAssertTrue(text(containingLabel: "After tax in September", in: app).exists)
    XCTAssertTrue(text(containingLabel: "+17% vs previous month", in: app).exists)
    attachAppStoreScreenshot(app, name: "money-01-home")

    app.buttons["Stats"].tap()
    XCTAssertTrue(app.buttons["BackButton"].waitForExistence(timeout: defaultTimeout))
    XCTAssertTrue(earnings.waitForExistence(timeout: defaultTimeout), app.debugDescription)
    XCTAssertTrue(text(containingLabel: "+17% vs previous month", in: app).exists)
    attachAppStoreScreenshot(app, name: "money-02-stats")

    app.buttons["BackButton"].tap()
    app.buttons["Schedule"].firstMatch.tap()
    let shiftTime = app.staticTexts.matching(NSPredicate(format: "label == %@", "09:00")).firstMatch
    XCTAssertTrue(shiftTime.waitForExistence(timeout: 30), app.debugDescription)
    XCTAssertTrue(text(containingLabel: "before tax", in: app).exists)
    attachAppStoreScreenshot(app, name: "money-03-schedule")

    app.buttons["Add"].firstMatch.tap()
    let recentTime = app.buttons.matching(NSPredicate(format: "label MATCHES %@", "09:00[–-]17:00"))
      .firstMatch
    XCTAssertTrue(recentTime.waitForExistence(timeout: 30), app.debugDescription)
    let previewTotal = app.staticTexts.matching(
      NSPredicate(format: "label MATCHES %@", ".*24[^0-9]?000.*")
    ).firstMatch
    if !previewTotal.waitForExistence(timeout: 2) {
      recentTime.tap()
    }
    XCTAssertTrue(previewTotal.waitForExistence(timeout: defaultTimeout), app.debugDescription)
    XCTAssertTrue(text(containingLabel: "after tax", in: app).exists)
    attachAppStoreScreenshot(app, name: "money-04-add")
    app.terminate()
    captureMoneyFixtureScreens()
  }

  /// Payday, adjustments and mixed-basis totals, which the fixture account doesn't reach.
  @MainActor
  private func captureMoneyFixtureScreens() {
    let cards = makeApp(scenario: "design-review")
    cards.launchEnvironment["TIDEX_DESIGN_SCREEN"] = "money"
    cards.launch()
    let markReceived = cards.buttons["Mark as received"].firstMatch
    XCTAssertTrue(markReceived.waitForExistence(timeout: defaultTimeout), cards.debugDescription)
    XCTAssertTrue(text(containingLabel: "Includes adjustments", in: cards).exists)
    attachAppStoreScreenshot(cards, name: "money-05-payday")
    markReceived.tap()
    XCTAssertTrue(cards.buttons["Received"].firstMatch.waitForExistence(timeout: defaultTimeout))
    attachAppStoreScreenshot(cards, name: "money-06-received")
    cards.terminate()

    let details = makeApp(scenario: "design-review")
    details.launchEnvironment["TIDEX_DESIGN_SCREEN"] = "money-payroll"
    details.launch()
    let adjustments = details.buttons.matching(
      NSPredicate(format: "label BEGINSWITH %@", "Adjustments")
    )
    .firstMatch
    XCTAssertTrue(adjustments.waitForExistence(timeout: defaultTimeout), details.debugDescription)
    adjustments.tap()
    attachAppStoreScreenshot(details, name: "money-07-payroll-details")
    details.swipeUp()
    XCTAssertTrue(
      text(containingLabel: "Total estimate", in: details).waitForExistence(timeout: defaultTimeout)
    )
    XCTAssertTrue(text(containingLabel: "for jobs without", in: details).exists)
    attachAppStoreScreenshot(details, name: "money-08-payroll-total")
  }

  @MainActor
  func testAddTabNamesItsModesAndSaveAction() {
    for (language, locale, addTitle, singleTitle, saveTitle) in [
      ("en", "en_US", "Add", "Single", "Save"),
      ("nb", "nb_NO", "Legg til", "Enkel", "Lagre"),
    ] {
      let app = XCUIApplication()
      app.launchArguments = [
        "-ui-testing", "-AppleLanguages", "(\(language))", "-AppleLocale", locale,
        "-defaultStartupTab", "home", "-AppleInterfaceStyle", "Dark", "-cachedTheme", "dark",
      ]
      app.launchEnvironment["TIDEX_UI_TEST_SCENARIO"] = "app-store-screenshots"
      app.launch()
      let addTab = app.tabBars.buttons[addTitle]
      XCTAssertTrue(addTab.waitForExistence(timeout: 30), app.debugDescription)
      addTab.tap()

      let singleMode = app.buttons["add-shift.mode.single"]
      XCTAssertTrue(singleMode.waitForExistence(timeout: defaultTimeout), app.debugDescription)
      XCTAssertTrue(singleMode.staticTexts[singleTitle].exists, "The selected mode shows its name")
      let save = app.buttons["add-shift.save"]
      XCTAssertTrue(save.exists, app.debugDescription)
      XCTAssertTrue(save.staticTexts[saveTitle].exists, "The save button shows its label")
      attachAppStoreScreenshot(app, name: "\(language)-add-single")

      if language == "en" {
        captureOvernightEventHint(app)
      }
      app.terminate()
    }
  }

  @MainActor
  private func captureOvernightEventHint(_ app: XCUIApplication) {
    app.buttons["add-shift.mode.events"].tap()
    let start = app.textFields["Start"]
    let end = app.textFields["End"]
    XCTAssertTrue(start.waitForExistence(timeout: defaultTimeout), app.debugDescription)
    // The time fields sit below the event calendar.
    app.scrollViews.firstMatch.swipeUp()
    Thread.sleep(forTimeInterval: 1)
    // Four deletes empty "HH:mm"; a fifth would move focus back to the start field.
    let clear = String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4)
    let focused = NSPredicate(format: "hasKeyboardFocus == true")
    start.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
    XCTAssertEqual(
      XCTWaiter.wait(
        for: [expectation(for: focused, evaluatedWith: start)], timeout: defaultTimeout),
      .completed)
    app.typeText(clear + "2200")
    XCTAssertEqual(
      XCTWaiter.wait(
        for: [expectation(for: focused, evaluatedWith: end)], timeout: defaultTimeout),
      .completed)
    app.typeText(clear + "0200")
    XCTAssertEqual(start.value as? String, "22:00")
    XCTAssertEqual(end.value as? String, "02:00")
    let hint = app.staticTexts["event.time-range-hint"]
    XCTAssertTrue(hint.waitForExistence(timeout: defaultTimeout), app.debugDescription)
    XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: defaultTimeout))
    attachAppStoreScreenshot(app, name: "en-add-event-overnight")
  }

  @MainActor
  func testScheduleRetapScrollsToTopThenGoesToToday() {
    let app = makeApp(scenario: "app-store-screenshots")
    app.launchArguments += ["-defaultStartupTab", "shifts", "-shiftsViewMode", "YES"]
    app.launch()
    let scheduleTab = app.tabBars.buttons["Schedule"]
    XCTAssertTrue(scheduleTab.waitForExistence(timeout: 30), app.debugDescription)
    let currentMonth = app.buttons[
      Date.now.formatted(.dateTime.month(.wide).locale(Locale(identifier: "en_US")))]
    XCTAssertTrue(currentMonth.waitForExistence(timeout: 30), app.debugDescription)

    app.buttons["Next month"].firstMatch.tap()
    XCTAssertTrue(currentMonth.waitForNonExistence(timeout: 5))
    scheduleTab.tap()
    // The first re-tap only scrolls the list, so the month stays the same.
    Thread.sleep(forTimeInterval: 1)
    XCTAssertFalse(currentMonth.exists)
    scheduleTab.tap()
    XCTAssertTrue(
      currentMonth.waitForExistence(timeout: defaultTimeout),
      "The second re-tap goes to today")
  }

  @MainActor
  func testEmptyPastMonthCanAddAShiftAfterUsingEventMode() {
    let app = makeApp(scenario: "app-store-screenshots")
    app.launchArguments += ["-defaultStartupTab", "home", "-shiftsViewMode", "YES"]
    app.launch()
    let addTab = app.tabBars.buttons["Add"]
    XCTAssertTrue(addTab.waitForExistence(timeout: 30), app.debugDescription)
    addTab.tap()
    let eventsMode = app.buttons["add-shift.mode.events"]
    XCTAssertTrue(eventsMode.waitForExistence(timeout: defaultTimeout), app.debugDescription)
    eventsMode.tap()
    XCTAssertTrue(eventsMode.isSelected)

    app.tabBars.buttons["Schedule"].tap()
    let september = app.staticTexts["September"].firstMatch
    XCTAssertTrue(september.waitForExistence(timeout: defaultTimeout), app.debugDescription)
    september.tap()
    let monthWheel = app.pickerWheels.element(boundBy: 0)
    XCTAssertTrue(monthWheel.waitForExistence(timeout: defaultTimeout), app.debugDescription)
    monthWheel.adjust(toPickerWheelValue: "December")
    app.pickerWheels.element(boundBy: 1).adjust(toPickerWheelValue: "2025")
    app.buttons["Done"].tap()

    let addShift = app.buttons["schedule-empty.add-shift"]
    XCTAssertTrue(addShift.waitForExistence(timeout: defaultTimeout), app.debugDescription)
    XCTAssertTrue(addShift.isHittable)
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = "Past month with an action to record a shift"
    attachment.lifetime = .keepAlways
    add(attachment)
    addShift.tap()

    let singleMode = app.buttons["add-shift.mode.single"]
    XCTAssertTrue(singleMode.waitForExistence(timeout: defaultTimeout), app.debugDescription)
    XCTAssertTrue(singleMode.isSelected, "Add shift must leave the previous event mode")
    XCTAssertTrue(app.staticTexts["December"].firstMatch.exists)
    XCTAssertTrue(app.staticTexts["2025"].firstMatch.exists)
  }

  @MainActor
  func testAddDraftRefreshesWorkplaceAfterEditingSettings() {
    let app = makeApp(scenario: "app-store-screenshots")
    app.launchArguments += ["-defaultStartupTab", "home"]
    app.launch()
    let addTab = app.tabBars.buttons["Add"]
    XCTAssertTrue(addTab.waitForExistence(timeout: 30))
    addTab.tap()
    let jobPicker = app.buttons["add-shift.job-picker"]
    XCTAssertTrue(jobPicker.waitForExistence(timeout: defaultTimeout))
    XCTAssertTrue(jobPicker.label.contains("Nord"))
    let recentTime = app.buttons.matching(NSPredicate(format: "label MATCHES %@", "09:00[–-]17:00"))
      .firstMatch
    XCTAssertTrue(recentTime.waitForExistence(timeout: defaultTimeout))
    if app.textFields["Start"].value as? String != "09:00" {
      recentTime.tap()
    }
    jobPicker.tap()
    app.buttons["Jobs & Pay"].tap()
    let workplace = app.buttons.containing(.staticText, identifier: "Nord").firstMatch
    XCTAssertTrue(workplace.waitForExistence(timeout: defaultTimeout), app.debugDescription)
    workplace.tap()
    let edit = app.buttons["Edit job"]
    XCTAssertTrue(edit.waitForExistence(timeout: defaultTimeout))
    edit.tap()
    let name = app.textFields["Job name"]
    XCTAssertTrue(name.waitForExistence(timeout: defaultTimeout))
    name.tap()
    name.typeText(
      String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4) + "Updated workplace")
    app.buttons["Save"].tap()
    XCTAssertTrue(edit.waitForExistence(timeout: defaultTimeout))

    // The workplace detail sheet dismisses with the standard pull-down gesture.
    app.navigationBars.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
      .press(
        forDuration: 0.1,
        thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)))
    let done = app.buttons["Done"]
    XCTAssertTrue(done.waitForExistence(timeout: defaultTimeout), app.debugDescription)
    done.tap()

    XCTAssertTrue(jobPicker.waitForExistence(timeout: defaultTimeout))
    XCTAssertTrue(jobPicker.label.contains("Updated workplace"), app.debugDescription)
    XCTAssertEqual(app.textFields["Start"].value as? String, "09:00")
    XCTAssertEqual(app.textFields["End"].value as? String, "17:00")
  }

  @MainActor
  func testAddShiftAutoAdvanceKeepsKeyboardVisible() {
    let app = makeApp(scenario: "app-store-screenshots")
    app.launchArguments += ["-defaultStartupTab", "home"]
    app.launchEnvironment["TIDEX_TEST_KEYBOARD"] = "1"
    app.launch()
    let addTab = app.tabBars.buttons["Add"]
    XCTAssertTrue(addTab.waitForExistence(timeout: 30))
    addTab.tap()

    let start = app.textFields["Start"]
    let end = app.textFields["End"]
    XCTAssertTrue(start.waitForExistence(timeout: defaultTimeout))
    if start.value as? String != "09:00" || end.value as? String != "17:00" {
      app.buttons.matching(NSPredicate(format: "label MATCHES %@", "09:00[–-]17:00")).firstMatch
        .tap()
    }
    let hides = app.staticTexts["ui-testing.keyboard-hide-count"]
    start.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
    start.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 2))
    XCTAssertEqual(start.value as? String, "09")
    let hidesBeforeAdvance = hides.label
    app.typeText("30")
    XCTAssertEqual(start.value as? String, "09:30")
    XCTAssertTrue(app.keyboards.firstMatch.exists)
    XCTAssertEqual(hides.label, hidesBeforeAdvance, "Auto-advance must not dismiss the keyboard")

    app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 2) + "30")
    XCTAssertEqual(end.value as? String, "17:30")
    XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: defaultTimeout))
    XCTAssertEqual(Int(hides.label), (Int(hidesBeforeAdvance) ?? 0) + 1)
  }

  @MainActor
  func testTimeInputInvalidEditClearsSavedValueAndCanBeCorrected() {
    let app = makeApp(scenario: "design-review")
    app.launchEnvironment["TIDEX_DESIGN_SCREEN"] = "time-input"
    app.launch()

    let start = app.textFields.element(boundBy: 0)
    XCTAssertTrue(start.waitForExistence(timeout: defaultTimeout))
    let save = app.buttons["Save"]
    XCTAssertTrue(save.isEnabled)
    start.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
    start.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 2))
    XCTAssertEqual(start.value as? String, "09")
    XCTAssertFalse(save.isEnabled, "An incomplete time must not retain the previous saved value")
    start.typeText("99")
    XCTAssertEqual(start.value as? String, "09:99")
    XCTAssertFalse(save.isEnabled, "Invalid minutes must not leave the previous time ready to save")
    XCTAssertTrue(app.staticTexts["Enter a valid time (HH:mm)."].exists)
    let invalidTime = XCTAttachment(screenshot: app.screenshot())
    invalidTime.name = "Invalid time with correction guidance"
    invalidTime.lifetime = .keepAlways
    add(invalidTime)
    start.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 2) + "30")
    XCTAssertEqual(start.value as? String, "09:30")
    XCTAssertTrue(save.isEnabled)
  }

  @MainActor
  func testTimeInputCompletesPartialTimeWhenFocusMoves() {
    let app = makeApp(scenario: "design-review")
    app.launchEnvironment["TIDEX_DESIGN_SCREEN"] = "time-input"
    app.launch()

    let start = app.textFields["Start"]
    let end = app.textFields["End"]
    XCTAssertTrue(start.waitForExistence(timeout: defaultTimeout))
    start.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
    start.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 2) + "3")
    XCTAssertFalse(app.buttons["Save"].isEnabled)
    end.tap()
    XCTAssertEqual(start.value as? String, "09:30")
    XCTAssertTrue(app.buttons["Save"].isEnabled)
  }

  @MainActor
  func testTimeInputControlsFitAtAccessibilitySize() {
    let app = makeApp(scenario: "design-review")
    app.launchEnvironment["TIDEX_DESIGN_SCREEN"] = "time-input-accessibility"
    app.launch()

    let start = app.textFields.element(boundBy: 0)
    let end = app.textFields.element(boundBy: 1)
    XCTAssertTrue(end.waitForExistence(timeout: defaultTimeout))
    XCTAssertEqual(start.label, "Start")
    XCTAssertEqual(end.label, "End")
    for field in [start, end] {
      XCTAssertGreaterThanOrEqual(field.frame.minX, app.frame.minX + 16)
      XCTAssertLessThanOrEqual(field.frame.maxX, app.frame.maxX - 16)
      XCTAssertTrue(field.isHittable)
    }
    XCTAssertGreaterThan(end.frame.minY, start.frame.maxY)
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = "Time input with accessibility text size"
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  @MainActor
  func testShiftEditorKeepsInvalidDraftWhenSwipedDown() {
    let app = makeApp(scenario: "design-review")
    app.launchEnvironment["TIDEX_DESIGN_SCREEN"] = "shift-editor"
    app.launch()
    app.buttons["Edit"].tap()

    let start = app.textFields["Start"]
    XCTAssertTrue(start.waitForExistence(timeout: defaultTimeout))
    start.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
    start.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 2) + "99")
    XCTAssertEqual(start.value as? String, "09:99")
    XCTAssertFalse(app.buttons["Save"].isEnabled)

    let navigationBar = app.navigationBars.firstMatch
    navigationBar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
      .press(
        forDuration: 0.1,
        thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)))
    XCTAssertTrue(
      app.buttons["Cancel"].exists, "Invalid edits must survive a sheet dismissal gesture")
    XCTAssertEqual(start.value as? String, "09:99")
    app.buttons["Cancel"].tap()
    XCTAssertFalse(start.exists)
    XCTAssertTrue(app.buttons["Done"].exists, "Cancel must still allow leaving the editor")
  }

  @MainActor
  func testRecentTimePresetHasAccessibleTapTargetAndSelection() {
    let app = makeApp(scenario: "design-review")
    app.launchEnvironment["TIDEX_DESIGN_SCREEN"] = "time-input"
    app.launch()

    let preset = app.buttons.matching(NSPredicate(format: "label MATCHES %@", "09:00[–-]17:00"))
      .firstMatch
    XCTAssertTrue(preset.waitForExistence(timeout: defaultTimeout))
    XCTAssertGreaterThanOrEqual(preset.frame.height, 44)
    XCTAssertTrue(preset.isSelected)
    preset.tap()
    XCTAssertFalse(app.buttons["Save"].isEnabled)
    XCTAssertFalse(preset.isSelected)
    preset.tap()
    XCTAssertTrue(app.buttons["Save"].isEnabled)
    XCTAssertTrue(preset.isSelected)
  }

  @MainActor
  func testLoginProviderScreenCanScrollToEmailAtAccessibilitySize() {
    let app = makeApp(scenario: "design-review")
    app.launchEnvironment["TIDEX_DESIGN_SCREEN"] = "login-accessibility"
    app.launch()

    let revealEmail = app.buttons[AccessibilityID.loginRevealEmail]
    XCTAssertTrue(revealEmail.waitForExistence(timeout: defaultTimeout))
    let createAccount = app.buttons[AccessibilityID.loginCreateAccount]
    let forgotPassword = app.buttons[AccessibilityID.loginForgotPassword]
    let scrollView = app.scrollViews.firstMatch
    for _ in 0..<8 {
      if forgotPassword.isHittable && app.frame.contains(forgotPassword.frame) { break }
      scrollView.swipeUp()
    }

    XCTAssertTrue(revealEmail.isHittable, "Email sign-in must be reachable with large text")
    XCTAssertGreaterThan(revealEmail.frame.height, 50, "Email sign-in must grow to fit its label")
    XCTAssertTrue(createAccount.isHittable && app.frame.contains(createAccount.frame))
    XCTAssertTrue(forgotPassword.isHittable && app.frame.contains(forgotPassword.frame))
    XCTAssertGreaterThan(createAccount.frame.height, 44)
    XCTAssertGreaterThan(forgotPassword.frame.height, 44)
    XCTAssertGreaterThanOrEqual(forgotPassword.frame.minY, createAccount.frame.maxY)
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "Login footer at largest accessibility text size"
    screenshot.lifetime = .keepAlways
    add(screenshot)
    revealEmail.tap()
    XCTAssertTrue(
      app.textFields[AccessibilityID.loginEmailOrPhone].waitForExistence(timeout: defaultTimeout),
      "Opening email sign-in should render the input form"
    )
  }

  private struct TerminologyLabels {
    let language: String
    let locale: String
    let login: String
    let signup: String
    let payoutDetails: String
    let schedule: String
    let add: String
    let jobsAndPay: String
    let manageJobs: String
    let defaultJob: String
  }

  @MainActor
  func testTerminologyScreens() {
    for labels in [
      TerminologyLabels(
        language: "en", locale: "en_US", login: "Log in", signup: "Create account",
        payoutDetails: "Payout details", schedule: "Schedule", add: "Add",
        jobsAndPay: "Jobs & Pay", manageJobs: "Manage jobs", defaultJob: "Default job"),
      TerminologyLabels(
        language: "nb", locale: "nb_NO", login: "Logg inn", signup: "Opprett konto",
        payoutDetails: "Utbetalingsdetaljer", schedule: "Vaktplan", add: "Legg til",
        jobsAndPay: "Jobber og lønn", manageJobs: "Administrer jobber", defaultJob: "Standardjobb"),
    ] {
      captureTerminologyScreens(labels)
    }
  }

  @MainActor
  private func captureTerminologyScreens(_ labels: TerminologyLabels) {
    let language = labels.language
    let localeArguments = [
      "-ui-testing", "-AppleLanguages", "(\(language))", "-AppleLocale", labels.locale,
    ]
    for (screen, heading) in [("login", labels.login), ("signup", labels.signup)] {
      let app = XCUIApplication()
      app.launchArguments = localeArguments
      app.launchEnvironment["TIDEX_UI_TEST_SCENARIO"] = "design-review"
      app.launchEnvironment["TIDEX_DESIGN_SCREEN"] = screen
      app.launch()
      let title = app.staticTexts[heading].firstMatch
      XCTAssertTrue(title.waitForExistence(timeout: defaultTimeout), app.debugDescription)
      attachAppStoreScreenshot(app, name: "\(language)-\(screen)")
      app.terminate()
    }

    let app = XCUIApplication()
    app.launchArguments = localeArguments + ["-defaultStartupTab", "home"]
    app.launchEnvironment["TIDEX_UI_TEST_SCENARIO"] = "app-store-screenshots"
    app.launch()
    let payout = app.staticTexts[language == "en" ? "Next payout" : "Neste utbetaling"]
    XCTAssertTrue(payout.waitForExistence(timeout: 30), app.debugDescription)
    payout.tap()
    let details = app.navigationBars[labels.payoutDetails]
    XCTAssertTrue(details.waitForExistence(timeout: defaultTimeout), app.debugDescription)
    attachAppStoreScreenshot(app, name: "\(language)-payout-details")
    app.buttons[language == "en" ? "Done" : "Ferdig"].tap()

    let schedule = app.buttons[labels.schedule].firstMatch
    XCTAssertTrue(schedule.waitForExistence(timeout: defaultTimeout), app.debugDescription)
    schedule.tap()
    attachAppStoreScreenshot(app, name: "\(language)-schedule-tab")

    app.buttons[labels.add].firstMatch.tap()
    let jobPicker = app.buttons["add-shift.job-picker"]
    XCTAssertTrue(jobPicker.waitForExistence(timeout: 30), app.debugDescription)
    jobPicker.tap()
    app.buttons[labels.jobsAndPay].tap()
    XCTAssertTrue(
      app.navigationBars[labels.manageJobs].waitForExistence(timeout: defaultTimeout),
      app.debugDescription)
    attachAppStoreScreenshot(app, name: "\(language)-manage-jobs")
    app.buttons.containing(.staticText, identifier: "Nord").firstMatch.tap()
    let defaultJob = app.staticTexts[labels.defaultJob]
    XCTAssertTrue(defaultJob.waitForExistence(timeout: defaultTimeout), app.debugDescription)
    for _ in 0..<6 where !defaultJob.isHittable { app.swipeUp() }
    XCTAssertTrue(defaultJob.isHittable, app.debugDescription)
    attachAppStoreScreenshot(app, name: "\(language)-job-actions")
    app.terminate()
  }

  @MainActor
  func testFriendsChatScenarioRendersThread() {
    let app = makeApp(scenario: "friends-chat")
    app.launch()

    assertExists(
      staticText(withExactLabel: seededIncomingMessage, in: app),
      in: app,
      timeout: defaultTimeout,
      message: "Expected seeded incoming message to render"
    )
    assertExists(
      waitForComposerInput(in: app, timeout: defaultTimeout),
      in: app,
      timeout: 0,
      message: "Expected chat composer text field to render"
    )
  }

  @MainActor
  func testFriendsChatScenarioCanSendMessage() {
    let app = makeApp(scenario: "friends-chat")
    app.launch()

    assertExists(
      staticText(withExactLabel: seededIncomingMessage, in: app),
      in: app,
      timeout: defaultTimeout,
      message: "Expected seeded incoming message before sending"
    )

    let composer = waitForComposerInput(in: app, timeout: defaultTimeout)
    assertExists(
      composer,
      in: app,
      timeout: 0,
      message: "Expected chat composer text field before sending"
    )

    composer.tap()
    composer.typeText(sentMessageText)

    let sendButton = sendButton(in: app)
    assertExists(
      sendButton,
      in: app,
      timeout: defaultTimeout,
      message: "Expected send button before submitting message"
    )
    sendButton.tap()

    XCTAssertTrue(
      waitForComposerToClear(in: app, timeout: defaultTimeout),
      "Expected composer to clear after submitting message"
    )
  }

  @MainActor
  func testFriendsChatReplyScenarioCanDismissReplyBanner() {
    let app = makeApp(scenario: "friends-chat-reply")
    app.launch()

    assertExists(
      staticText(withExactLabel: seededIncomingMessage, in: app),
      in: app,
      timeout: defaultTimeout,
      message: "Expected seeded incoming message before dismissing reply mode"
    )

    let cancelButton = replyCancelButton(in: app)
    assertExists(
      cancelButton,
      in: app,
      timeout: defaultTimeout,
      message: "Expected reply cancel button to render"
    )
    cancelButton.tap()

    XCTAssertFalse(cancelButton.waitForExistence(timeout: 1), "Expected reply banner to dismiss")
  }

  @MainActor
  func testFriendsChatReplyScenarioKeepsReplyBannerVisibleWhenAttachmentDrawerOpens() {
    let app = makeApp(scenario: "friends-chat-reply")
    app.launch()

    assertExists(
      staticText(withExactLabel: seededIncomingMessage, in: app),
      in: app,
      timeout: defaultTimeout,
      message: "Expected seeded incoming message before opening attachments"
    )

    let cancelButton = replyCancelButton(in: app)
    assertExists(
      cancelButton,
      in: app,
      timeout: defaultTimeout,
      message: "Expected reply cancel button to render before opening attachments"
    )

    let attachmentToggle = attachmentToggleButton(in: app)
    assertExists(
      attachmentToggle,
      in: app,
      timeout: defaultTimeout,
      message: "Expected attachment toggle button to render"
    )
    attachmentToggle.tap()

    assertExists(
      cancelButton,
      in: app,
      timeout: defaultTimeout,
      message: "Expected reply banner to remain visible when attachment drawer opens"
    )
  }

  @MainActor
  func testFriendsScreensStateTheirConsequences() {
    let cards = makeFriendsDesignApp(view: "cards")
    cards.launch()
    assertExists(
      text(containingLabel: "Ella was notified", in: cards), in: cards, timeout: defaultTimeout,
      message: "Expected the screenshot bubble to say who was notified")
    assertExists(
      text(containingLabel: "the next day", in: cards), in: cards, timeout: 0,
      message: "Expected an overnight end time to read as ending the next day")
    attachAppStoreScreenshot(cards, name: "friends-cards")
    cards.terminate()

    let addFriend = makeFriendsDesignApp(view: "add-friend")
    addFriend.launch()
    assertExists(
      text(containingLabel: "sees your shifts and earnings right away", in: addFriend),
      in: addFriend, timeout: defaultTimeout,
      message: "Expected the add friend form to say sharing starts right away")
    assertExists(
      text(containingLabel: "Friend limit. Sharing your shifts with 4 of 5.", in: addFriend),
      in: addFriend, timeout: 0, message: "Expected the friend limit counter to have a label")
    attachAppStoreScreenshot(addFriend, name: "friends-add-friend")
    addFriend.terminate()

    let profile = makeFriendsDesignApp(view: "profile")
    profile.launch()
    assertExists(
      text(containingLabel: "Move to bottom only changes the order", in: profile),
      in: profile, timeout: defaultTimeout,
      message: "Expected the profile to explain Move to bottom and Hide")
    attachAppStoreScreenshot(profile, name: "friends-profile")
  }

  @MainActor
  func testFriendsChatDeleteAsksBeforeDeletingForEveryone() {
    let chat = makeApp(scenario: "friends-chat")
    chat.launch()
    let outgoing = staticText(withExactLabel: "Earlier outgoing message", in: chat)
    assertExists(
      outgoing, in: chat, timeout: defaultTimeout, message: "Expected the outgoing message")
    outgoing.press(forDuration: 1)
    let deleteAction = text(containingLabel: "Delete for everyone", in: chat)
    assertExists(
      deleteAction, in: chat, timeout: defaultTimeout,
      message: "Expected the message menu to say delete removes it for everyone")
    attachAppStoreScreenshot(chat, name: "friends-chat-menu")
    deleteAction.tap()
    assertExists(
      text(containingLabel: "Delete this message for everyone?", in: chat), in: chat,
      timeout: defaultTimeout, message: "Expected a delete confirmation")
    attachAppStoreScreenshot(chat, name: "friends-chat-delete-confirm")
    // iPhone confirmation dialogs may drop the Cancel button, so fall back to tapping outside.
    if chat.buttons[commonCancelLabel].waitForExistence(timeout: 1) {
      chat.buttons[commonCancelLabel].firstMatch.tap()
    } else {
      chat.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.05)).tap()
    }
    assertExists(
      outgoing, in: chat, timeout: defaultTimeout,
      message: "Expected the message to remain after cancelling")
  }

  @MainActor
  func testFriendsChatDeleteConfirmRemovesMessage() {
    let chat = makeApp(scenario: "friends-chat")
    chat.launch()
    let outgoing = staticText(withExactLabel: "Earlier outgoing message", in: chat)
    assertExists(
      outgoing, in: chat, timeout: defaultTimeout, message: "Expected the outgoing message")
    outgoing.press(forDuration: 1)
    let deleteAction = text(containingLabel: "Delete for everyone", in: chat)
    assertExists(
      deleteAction, in: chat, timeout: defaultTimeout, message: "Expected the message menu")
    deleteAction.tap()
    let confirm = chat.buttons.matching(
      NSPredicate(format: "label CONTAINS %@", "Delete for everyone")
    ).firstMatch
    assertExists(
      confirm, in: chat, timeout: defaultTimeout, message: "Expected the destructive confirm button"
    )
    confirm.tap()
    XCTAssertTrue(
      outgoing.waitForNonExistence(timeout: defaultTimeout),
      "Expected the message to be deleted after confirming")
  }

  private func makeFriendsDesignApp(view: String) -> XCUIApplication {
    let app = makeApp(scenario: "design-review")
    app.launchEnvironment["TIDEX_DESIGN_SCREEN"] = "friends"
    app.launchEnvironment["TIDEX_DESIGN_FRIENDS_VIEW"] = view
    return app
  }

  private func makeApp(scenario: String) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments += ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    app.launchEnvironment["TIDEX_UI_TEST_SCENARIO"] = scenario
    return app
  }

  private func staticText(withExactLabel label: String, in app: XCUIApplication) -> XCUIElement {
    app.staticTexts.matching(NSPredicate(format: "label == %@", label)).firstMatch
  }

  private func text(containingLabel label: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any)
      .matching(NSPredicate(format: "label CONTAINS %@", label))
      .firstMatch
  }

  private func sendButton(in app: XCUIApplication) -> XCUIElement {
    let identifiedButton = app.buttons[AccessibilityID.sendButton]
    if identifiedButton.exists {
      return identifiedButton
    }

    let labeledButton = app.buttons[sendButtonLabel]
    if labeledButton.exists {
      return labeledButton
    }

    return identifiedButton
  }

  private func replyCancelButton(in app: XCUIApplication) -> XCUIElement {
    let identifiedButton = app.buttons[AccessibilityID.replyCancelButton]
    if identifiedButton.exists {
      return identifiedButton
    }

    let labeledButton = app.buttons["Cancel"]
    if labeledButton.exists {
      return labeledButton
    }

    return identifiedButton
  }

  private func attachmentToggleButton(in app: XCUIApplication) -> XCUIElement {
    let candidates = [
      app.buttons[AccessibilityID.attachmentToggleButton],
      app.buttons["Open attachments"],
      app.buttons["Close attachments"],
      app.otherElements[AccessibilityID.attachmentToggleButton],
      app.descendants(matching: .any)
        .matching(identifier: AccessibilityID.attachmentToggleButton)
        .firstMatch,
      app.descendants(matching: .button)
        .matching(
          NSPredicate(format: "label == %@ OR label == %@", "Open attachments", "Close attachments")
        )
        .firstMatch,
    ]

    return candidates.first(where: \.exists)
      ?? app.descendants(matching: .any)[AccessibilityID.attachmentToggleButton]
  }

  private func waitForComposerInput(
    in app: XCUIApplication,
    timeout: TimeInterval
  ) -> XCUIElement {
    let deadline = Date().addingTimeInterval(timeout)

    while Date() < deadline {
      if let errorElement = uiTestingError(in: app) {
        XCTFail("UI test host failed to render: \(errorElement.label)")
        return errorElement
      }

      let candidates = [
        app.descendants(matching: .any)[AccessibilityID.composerTextField],
        app.textViews[composerPlaceholder],
        app.textFields[composerPlaceholder],
        app.textViews.firstMatch,
        app.textFields.firstMatch,
      ]

      if let matchingElement = candidates.first(where: \.exists) {
        return matchingElement
      }

      RunLoop.current.run(until: Date().addingTimeInterval(0.25))
    }

    return app.descendants(matching: .any)[AccessibilityID.composerTextField]
  }

  private func waitForComposerToClear(
    in app: XCUIApplication,
    timeout: TimeInterval
  ) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)

    while Date() < deadline {
      let composer = waitForComposerInput(in: app, timeout: 0.5)
      let value = composer.value as? String

      if value == nil || value == composerPlaceholder || value?.isEmpty == true {
        return true
      }

      RunLoop.current.run(until: Date().addingTimeInterval(0.25))
    }

    return false
  }

  private func uiTestingError(in app: XCUIApplication) -> XCUIElement? {
    let errorElement = app.descendants(matching: .any)[AccessibilityID.uiTestingError]
    return errorElement.exists ? errorElement : nil
  }

  private func assertExists(
    _ element: XCUIElement,
    in app: XCUIApplication,
    timeout: TimeInterval,
    message: String
  ) {
    guard element.waitForExistence(timeout: timeout) else {
      let screenshot = XCUIScreen.main.screenshot()
      let screenshotAttachment = XCTAttachment(screenshot: screenshot)
      screenshotAttachment.name = "UI Test Failure Screenshot"
      screenshotAttachment.lifetime = .keepAlways
      add(screenshotAttachment)

      let hierarchyAttachment = XCTAttachment(string: app.debugDescription)
      hierarchyAttachment.name = "UI Hierarchy"
      hierarchyAttachment.lifetime = .keepAlways
      add(hierarchyAttachment)

      XCTFail(message)
      return
    }
  }
}
