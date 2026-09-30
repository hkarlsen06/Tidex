import XCTest

@testable import Tidex

@MainActor
internal final class LoginEmailNotConfirmedTests: XCTestCase {
  internal func testUnconfirmedEmailRoutesToCodeStepInsteadOfShowingError() async throws {
    let stub = StubEmailAuth()
    stub.signInError = try makeAuthAPIError(.emailNotConfirmed)
    let viewModel = LoginViewModel(emailAuth: stub)
    viewModel.emailOrPhone = " user@example.com "
    viewModel.password = "password123"
    var routedEmails: [String] = []
    viewModel.onEmailNotConfirmed = { routedEmails.append($0) }

    await viewModel.signIn()

    XCTAssertEqual(routedEmails, ["user@example.com"])
    XCTAssertNil(viewModel.errorMessage)
    XCTAssertFalse(viewModel.isLoading)
  }

  internal func testOtherSignInErrorsStillShowMessage() async throws {
    let stub = StubEmailAuth()
    stub.signInError = try makeAuthAPIError(.invalidCredentials)
    let viewModel = LoginViewModel(emailAuth: stub)
    viewModel.emailOrPhone = "user@example.com"
    viewModel.password = "wrong-password"
    var routedEmails: [String] = []
    viewModel.onEmailNotConfirmed = { routedEmails.append($0) }

    await viewModel.signIn()

    XCTAssertTrue(routedEmails.isEmpty)
    XCTAssertNotNil(viewModel.errorMessage)
  }

  internal func testErrorClassification() throws {
    XCTAssertTrue(AuthService.isEmailNotConfirmed(try makeAuthAPIError(.emailNotConfirmed)))
    XCTAssertFalse(AuthService.isEmailNotConfirmed(try makeAuthAPIError(.invalidCredentials)))
    XCTAssertFalse(AuthService.isEmailNotConfirmed(URLError(.timedOut)))
    XCTAssertTrue(AuthService.isInvalidVerificationCode(try makeAuthAPIError(.otpExpired)))
    XCTAssertFalse(AuthService.isInvalidVerificationCode(URLError(.timedOut)))
    XCTAssertTrue(AuthService.isRateLimited(try makeAuthAPIError(.overEmailSendRateLimit)))
    XCTAssertFalse(AuthService.isRateLimited(try makeAuthAPIError(.otpExpired)))
  }

  deinit {
    // Required by SwiftLint for XCTestCase subclasses.
  }
}
