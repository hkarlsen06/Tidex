import XCTest

final class TidexAppUITests: XCTestCase {
  private enum AccessibilityID {
    static let composerTextField = "friends-thread-composer.text-field"
    static let sendButton = "friends-thread-composer.send-button"
    static let replyCancelButton = "friends-thread-composer.reply-cancel"
    static let uiTestingError = "ui-testing.error"
  }

  private let defaultTimeout: TimeInterval = 15
  private let composerPlaceholder = "Message"
  private let sendButtonLabel = "Send message"
  private let seededIncomingMessage = "Initial incoming message"
  private let sentMessageText = "UI test send"

  override func setUpWithError() throws {
    continueAfterFailure = false
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

    assertExists(
      staticText(withExactLabel: sentMessageText, in: app),
      in: app,
      timeout: defaultTimeout,
      message: "Expected sent message to appear in the transcript"
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

  private func makeApp(scenario: String) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments += ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    app.launchEnvironment["TIDEX_UI_TEST_SCENARIO"] = scenario
    return app
  }

  private func staticText(withExactLabel label: String, in app: XCUIApplication) -> XCUIElement {
    app.staticTexts.matching(NSPredicate(format: "label == %@", label)).firstMatch
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
