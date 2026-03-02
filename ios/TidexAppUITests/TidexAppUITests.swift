import XCTest

final class TidexAppUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor
  func testAppLaunches() {
    let app = XCUIApplication()
    app.launchArguments.append("-ui-testing")
    app.launch()

    XCTAssertEqual(app.state, .runningForeground)
  }
}
