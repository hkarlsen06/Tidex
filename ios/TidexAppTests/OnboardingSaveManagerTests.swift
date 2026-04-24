import XCTest

@testable import Tidex

@MainActor
final class OnboardingSaveManagerTests: XCTestCase {
  func testSaveStatusAllowsCompletionOnlyAfterSuccess() {
    XCTAssertFalse(OnboardingSaveManager.SaveStatus.idle.allowsCompletion)
    XCTAssertFalse(OnboardingSaveManager.SaveStatus.saving.allowsCompletion)
    XCTAssertFalse(OnboardingSaveManager.SaveStatus.error.allowsCompletion)
    XCTAssertTrue(OnboardingSaveManager.SaveStatus.success.allowsCompletion)
  }

  func testPrepareForSaveBlocksCompletionUntilSaveSucceeds() {
    let manager = OnboardingSaveManager()

    manager.prepareForSave(completionMode: .friendOnlySkip)

    XCTAssertEqual(manager.status, .saving)
    XCTAssertNil(manager.errorMessage)
    XCTAssertFalse(manager.status.allowsCompletion)
  }
}
