import XCTest

@testable import Tidex

@MainActor
final class SignupViewModelTests: XCTestCase {
  func testEmailSignupRequiresTermsAcceptanceBeforeNetworkWork() async {
    let viewModel = SignupViewModel()
    viewModel.firstName = "Test"
    viewModel.lastName = "User"
    viewModel.emailOrPhone = "test@example.com"
    viewModel.password = "password123"

    await viewModel.signUp()

    XCTAssertEqual(viewModel.fieldErrors.terms, String(localized: .acceptTermsDescription))
    XCTAssertFalse(viewModel.isLoading)
  }

  func testOAuthSignupRequiresTermsAcceptanceBeforeProviderWork() async {
    let viewModel = SignupViewModel()

    await viewModel.signUpWithGoogle()

    XCTAssertEqual(viewModel.fieldErrors.terms, String(localized: .acceptTermsDescription))
    XCTAssertFalse(viewModel.isLoading)
  }
}
