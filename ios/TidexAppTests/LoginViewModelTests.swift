import XCTest

@testable import Tidex

@MainActor
internal final class LoginViewModelTests: XCTestCase {
  internal func testSecondFactorOpensCodeStep() async {
    let stub = StubEmailAuth()
    stub.signInResult = .success(.needsEmailCode)
    var authenticatedCount = 0
    let viewModel = LoginViewModel(emailAuth: stub) { authenticatedCount += 1 }
    viewModel.email = " user@example.com "
    viewModel.password = "password123"

    await viewModel.signIn()

    XCTAssertEqual(viewModel.currentStep, .otp)
    XCTAssertEqual(authenticatedCount, 0)
    XCTAssertNil(viewModel.errorMessage)
    XCTAssertFalse(viewModel.isLoading)
  }

  internal func testCorrectCodeFinishesSignIn() async {
    let stub = StubEmailAuth()
    stub.signInResult = .success(.needsEmailCode)
    var authenticatedCount = 0
    let viewModel = LoginViewModel(emailAuth: stub) { authenticatedCount += 1 }
    viewModel.email = "user@example.com"
    viewModel.password = "password123"
    await viewModel.signIn()

    viewModel.otpCode = "123456"
    await viewModel.verifyOTP()

    XCTAssertEqual(stub.verifiedCodes, ["123456"])
    XCTAssertEqual(authenticatedCount, 1)
  }

  internal func testUnknownEmailOffersToCreateAnAccount() async throws {
    let stub = StubEmailAuth()
    stub.signInResult = .failure(try makeClerkAPIError("form_identifier_not_found"))
    let viewModel = LoginViewModel(emailAuth: stub)
    viewModel.email = "user@example.com"
    viewModel.password = "password123"

    await viewModel.signIn()

    XCTAssertNotNil(viewModel.accountCreationPromptMessage)
    XCTAssertNil(viewModel.errorMessage)
  }

  internal func testWrongPasswordShowsMessage() async throws {
    let stub = StubEmailAuth()
    stub.signInResult = .failure(try makeClerkAPIError("form_password_incorrect"))
    let viewModel = LoginViewModel(emailAuth: stub)
    viewModel.email = "user@example.com"
    viewModel.password = "wrong-password"

    await viewModel.signIn()

    XCTAssertEqual(viewModel.errorMessage, String(localized: .authErrorInvalidLoginCredentials))
    XCTAssertNil(viewModel.accountCreationPromptMessage)
  }

  deinit {
    // Required by SwiftLint for XCTestCase subclasses.
  }
}
