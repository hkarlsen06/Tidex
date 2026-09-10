import XCTest

final class TidexAppUITests: XCTestCase {
  private enum AccessibilityID {
    static let composerTextField = "friends-thread-composer.text-field"
    static let sendButton = "friends-thread-composer.send-button"
    static let replyCancelButton = "friends-thread-composer.reply-cancel"
    static let attachmentToggleButton = "friends-thread-composer.attachment-toggle"
    static let uiTestingError = "ui-testing.error"
    static let wageyHistoryFirstRow = "wagey-history.row.ui-test-conversation-1"
    static let wageyHistorySwipeDelete = "wagey-history.delete-swipe.ui-test-conversation-1"
    static let wageyHistoryConfirmDelete = "wagey-history.delete-confirm.ui-test-conversation-1"
    static let wageyHistoryCancelDelete = "wagey-history.delete-cancel.ui-test-conversation-1"
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
  func testAppStoreScreenshots() {
    for (language, locale, shiftsTitle, statsTitle) in [
      ("en", "en_US", "Schedule", "Stats"),
      ("nb", "nb_NO", "Agenda", "Statistikk"),
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
      captureAddAndWageyScreenshots(app, language: language)
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
    attachAppStoreScreenshot(app, name: "\(language)-04-payroll")
    done.tap()
  }

  @MainActor
  private func captureAddAndWageyScreenshots(_ app: XCUIApplication, language: String) {
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
    app.buttons["Wagey"].firstMatch.tap()
    let question = app.staticTexts[
      language == "en"
        ? "What am I earning this month?" : "Hvor mye tjener jeg denne måneden?"]
    XCTAssertTrue(question.firstMatch.waitForExistence(timeout: 30), app.debugDescription)
    attachAppStoreScreenshot(app, name: "\(language)-06-wagey")
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

  @MainActor
  func testTimeInputInvalidEditClearsSavedValueAndCanBeCorrected() {
    let app = makeApp(scenario: "design-review")
    app.launchEnvironment["TIDEX_DESIGN_SCREEN"] = "time-input"
    app.launch()

    let start = app.textFields.element(boundBy: 0)
    XCTAssertTrue(start.waitForExistence(timeout: defaultTimeout))
    let save = app.buttons["Save"]
    XCTAssertTrue(save.isEnabled)
    start.tap()
    start.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 2))
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
    start.tap()
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
  func testWageyHistoryDeleteScenarioCancelKeepsConversation() {
    let app = makeApp(scenario: "wagey-history-delete")
    app.launch()

    let row = wageyHistoryRow(in: app)
    assertExists(
      row,
      in: app,
      timeout: defaultTimeout,
      message: "Expected Wagey history row to render"
    )

    row.swipeLeft()

    let swipeDeleteButton = wageyHistorySwipeDeleteButton(in: app)
    assertExists(
      swipeDeleteButton,
      in: app,
      timeout: defaultTimeout,
      message: "Expected swipe delete action to appear"
    )
    swipeDeleteButton.tap()

    let confirmation = wageyHistoryDeleteConfirmation(in: app)
    assertExists(
      confirmation,
      in: app,
      timeout: defaultTimeout,
      message: "Expected delete confirmation to appear"
    )

    dismissWageyHistoryDeleteConfirmation(in: app)

    assertExists(
      row,
      in: app,
      timeout: defaultTimeout,
      message: "Expected row to remain after cancelling delete"
    )
  }

  @MainActor
  func testWageyHistoryDeleteScenarioConfirmRemovesConversation() {
    let app = makeApp(scenario: "wagey-history-delete")
    app.launch()

    let row = wageyHistoryRow(in: app)
    assertExists(
      row,
      in: app,
      timeout: defaultTimeout,
      message: "Expected Wagey history row to render"
    )

    row.swipeLeft()

    let swipeDeleteButton = wageyHistorySwipeDeleteButton(in: app)
    assertExists(
      swipeDeleteButton,
      in: app,
      timeout: defaultTimeout,
      message: "Expected swipe delete action to appear"
    )
    swipeDeleteButton.tap()

    let confirmButton = wageyHistoryConfirmDeleteButton(in: app)
    assertExists(
      confirmButton,
      in: app,
      timeout: defaultTimeout,
      message: "Expected delete confirmation button to appear"
    )
    confirmButton.tap()

    XCTAssertFalse(
      row.waitForExistence(timeout: defaultTimeout),
      "Expected row to be removed after confirming delete"
    )
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

  private func wageyHistoryRow(in app: XCUIApplication) -> XCUIElement {
    let candidates = [
      app.buttons[AccessibilityID.wageyHistoryFirstRow],
      app.cells[AccessibilityID.wageyHistoryFirstRow],
      app.otherElements[AccessibilityID.wageyHistoryFirstRow],
    ]

    return candidates.first(where: \.exists)
      ?? app.descendants(matching: .any)[AccessibilityID.wageyHistoryFirstRow]
  }

  private func wageyHistorySwipeDeleteButton(in app: XCUIApplication) -> XCUIElement {
    app.buttons[AccessibilityID.wageyHistorySwipeDelete]
  }

  private func wageyHistoryConfirmDeleteButton(in app: XCUIApplication) -> XCUIElement {
    let candidates = [
      app.sheets[deleteConfirmationTitle]
        .descendants(matching: .button)
        .matching(identifier: AccessibilityID.wageyHistoryConfirmDelete)
        .firstMatch,
      app.sheets[deleteConfirmationTitle].buttons[commonDeleteLabel],
      app.descendants(matching: .button)
        .matching(identifier: AccessibilityID.wageyHistoryConfirmDelete)
        .firstMatch,
      app.buttons[commonDeleteLabel],
    ]

    return firstExistingElement(
      among: candidates,
      timeout: 1,
      fallback: app.descendants(matching: .button)
        .matching(identifier: AccessibilityID.wageyHistoryConfirmDelete)
        .firstMatch
    )
  }

  private func wageyHistoryDeleteConfirmation(in app: XCUIApplication) -> XCUIElement {
    let candidates = [
      app.sheets[deleteConfirmationTitle],
      app.staticTexts[deleteConfirmationTitle],
      app.descendants(matching: .button)
        .matching(identifier: AccessibilityID.wageyHistoryConfirmDelete)
        .firstMatch,
      app.buttons[commonDeleteLabel],
    ]

    return candidates.first(where: \.exists) ?? app.sheets[deleteConfirmationTitle]
  }

  private func wageyHistoryCancelDeleteButton(in app: XCUIApplication) -> XCUIElement {
    let candidates = [
      app.sheets[deleteConfirmationTitle]
        .descendants(matching: .button)
        .matching(identifier: AccessibilityID.wageyHistoryCancelDelete)
        .firstMatch,
      app.sheets[deleteConfirmationTitle].buttons[commonCancelLabel],
      app.descendants(matching: .button)
        .matching(identifier: AccessibilityID.wageyHistoryCancelDelete)
        .firstMatch,
      app.buttons[AccessibilityID.popoverDismissRegion],
      app.buttons["dismiss popup"],
      app.buttons[commonCancelLabel],
    ]

    return firstExistingElement(
      among: candidates,
      timeout: 1,
      fallback: app.descendants(matching: .button)
        .matching(
          NSPredicate(
            format: "identifier == %@ OR identifier == %@ OR label == %@ OR label == %@",
            AccessibilityID.wageyHistoryCancelDelete,
            AccessibilityID.popoverDismissRegion,
            "dismiss popup",
            commonCancelLabel
          )
        )
        .firstMatch
    )
  }

  private func dismissWageyHistoryDeleteConfirmation(in app: XCUIApplication) {
    let cancelButton = wageyHistoryCancelDeleteButton(in: app)
    if cancelButton.waitForExistence(timeout: 1) {
      cancelButton.tap()
      return
    }

    app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.05)).tap()
  }

  private func firstExistingElement(
    among candidates: [XCUIElement],
    timeout: TimeInterval,
    fallback: XCUIElement
  ) -> XCUIElement {
    let deadline = Date().addingTimeInterval(timeout)

    while Date() < deadline {
      if let candidate = candidates.first(where: \.exists) {
        return candidate
      }

      RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }

    return fallback
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
