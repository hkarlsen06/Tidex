import XCTest

@testable import Tidex

@MainActor
internal final class SignupViewModelTests: XCTestCase {
  // Continuing accepts the terms, so there is no checkbox to validate. Field checks still
  // stop an invalid email signup before any network work.
  internal func testEmailSignupStopsOnInvalidEmailBeforeNetworkWork() async {
    let viewModel: SignupViewModel = SignupViewModel()
    viewModel.firstName = "Test"
    viewModel.lastName = "User"
    viewModel.emailOrPhone = "not-an-email"
    viewModel.password = "password123"

    await viewModel.signUp()

    XCTAssertEqual(viewModel.fieldErrors.emailOrPhone, String(localized: .signupErrorsInvalidEmail))
    XCTAssertNil(viewModel.fieldErrors.firstName)
    XCTAssertNil(viewModel.fieldErrors.password)
    XCTAssertNil(viewModel.errorMessage)
    XCTAssertFalse(viewModel.isLoading)
  }

  deinit {
    // Required by SwiftLint for XCTestCase subclasses.
  }
}
