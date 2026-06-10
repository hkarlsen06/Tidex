import XCTest

@testable import Tidex

@MainActor
internal final class SignupViewModelTests: XCTestCase {
  internal func testEmailSignupRequiresTermsAcceptanceBeforeNetworkWork() async {
    let viewModel: SignupViewModel = SignupViewModel()
    viewModel.firstName = "Test"
    viewModel.lastName = "User"
    viewModel.emailOrPhone = "test@example.com"
    viewModel.password = "password123"

    await viewModel.signUp()

    XCTAssertEqual(viewModel.fieldErrors.terms, String(localized: .acceptTermsDescription))
    XCTAssertFalse(viewModel.isLoading)
  }

  internal func testOAuthSignupRequiresTermsAcceptanceBeforeProviderWork() async {
    let viewModel: SignupViewModel = SignupViewModel()

    await viewModel.signUpWithGoogle()

    XCTAssertEqual(viewModel.fieldErrors.terms, String(localized: .acceptTermsDescription))
    XCTAssertFalse(viewModel.isLoading)
  }

  deinit {
    // Required by SwiftLint for XCTestCase subclasses.
  }
}
