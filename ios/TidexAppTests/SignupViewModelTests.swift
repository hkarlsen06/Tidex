import ClerkKit
import XCTest

@testable import Tidex

// swiftlint:disable async_without_await

/// Stand-in for `AuthService` that records calls and returns scripted results.
@MainActor
internal final class StubEmailAuth: EmailAuthProviding {
  internal var signUpResult: Result<EmailSignupResult, Error> = .success(.signedIn)
  internal var signInResult: Result<EmailSignInResult, Error> = .failure(
    URLError(.notConnectedToInternet))
  internal var verifyError: Error?
  internal var resendError: Error?

  internal private(set) var signedUpEmails: [String] = []
  internal private(set) var verifiedCodes: [String] = []
  internal private(set) var resendCount = 0

  internal func signInWithPassword(email: String, password: String) async throws
    -> EmailSignInResult
  {
    try signInResult.get()
  }

  internal func verifySignInCode(_ code: String) async throws {
    verifiedCodes.append(code)
    if let verifyError { throw verifyError }
  }

  internal func resendSignInCode() async throws {
    resendCount += 1
    if let resendError { throw resendError }
  }

  internal func signUpWithEmail(
    email: String,
    password: String,
    firstName: String?,
    lastName: String?
  ) async throws -> EmailSignupResult {
    signedUpEmails.append(email)
    return try signUpResult.get()
  }

  internal func verifySignupCode(_ code: String) async throws {
    verifiedCodes.append(code)
    if let verifyError { throw verifyError }
  }

  internal func resendSignupCode() async throws {
    resendCount += 1
    if let resendError { throw resendError }
  }

  deinit {
    // Required by SwiftLint for classes with a deinit rule.
  }
}

// swiftlint:enable async_without_await

/// Builds the Clerk API error that carries the given error code.
internal func makeClerkAPIError(_ code: String) throws -> Error {
  let json = Data(#"{"code":"\#(code)","message":"\#(code)"}"#.utf8)
  return try JSONDecoder().decode(ClerkAPIError.self, from: json)
}

@MainActor
internal final class SignupViewModelTests: XCTestCase {

  // MARK: - Signup completed at once

  internal func testSignupWithSessionContinuesWithoutCodeStep() async {
    let stub = StubEmailAuth()
    stub.signUpResult = .success(.signedIn)
    var authenticatedCount = 0
    let viewModel = makeViewModel(stub) { authenticatedCount += 1 }

    await viewModel.signUp()

    XCTAssertEqual(stub.signedUpEmails, ["new@example.com"])
    XCTAssertEqual(authenticatedCount, 1)
    XCTAssertEqual(viewModel.step, .form)
    XCTAssertNil(viewModel.errorMessage)
  }

  // MARK: - Signup that needs the emailed code

  internal func testSignupWithoutSessionOpensCodeStepAndStartsCooldown() async {
    let stub = StubEmailAuth()
    stub.signUpResult = .success(.needsVerification)
    var authenticatedCount = 0
    let viewModel = makeViewModel(stub) { authenticatedCount += 1 }

    await viewModel.signUp()

    XCTAssertEqual(viewModel.step, .verifyEmail)
    XCTAssertEqual(viewModel.pendingEmail, "new@example.com")
    XCTAssertEqual(authenticatedCount, 0)
    XCTAssertNil(viewModel.errorMessage)
    XCTAssertGreaterThan(viewModel.resendSecondsRemaining(), 0)
  }

  internal func testAlreadyRegisteredEmailShowsErrorInsteadOfCodeStep() async {
    let stub = StubEmailAuth()
    stub.signUpResult = .success(.alreadyRegistered)
    var authenticatedCount = 0
    let viewModel = makeViewModel(stub) { authenticatedCount += 1 }

    await viewModel.signUp()

    XCTAssertEqual(viewModel.step, .form)
    XCTAssertEqual(viewModel.pendingEmail, "")
    XCTAssertEqual(authenticatedCount, 0)
    XCTAssertEqual(viewModel.errorMessage, String(localized: .authErrorUserAlreadyRegistered))
  }

  internal func testVerifySuccessContinuesLikeImmediateSignup() async {
    let stub = StubEmailAuth()
    stub.signUpResult = .success(.needsVerification)
    var authenticatedCount = 0
    let viewModel = makeViewModel(stub) { authenticatedCount += 1 }
    await viewModel.signUp()

    viewModel.otpCode = "123456"
    await viewModel.verifyEmailCode()

    XCTAssertEqual(stub.verifiedCodes, ["123456"])
    XCTAssertEqual(authenticatedCount, 1)
    XCTAssertNil(viewModel.fieldErrors.otp)
    XCTAssertNil(viewModel.errorMessage)
  }

  internal func testVerifyWithWrongOrExpiredCodeShowsMessageAndClearsCode() async throws {
    let stub = StubEmailAuth()
    stub.verifyError = try makeClerkAPIError("verification_expired")
    var authenticatedCount = 0
    let viewModel = makeViewModel(stub) { authenticatedCount += 1 }
    viewModel.showEmailVerification(email: "new@example.com")

    viewModel.otpCode = "000000"
    await viewModel.verifyEmailCode()

    XCTAssertEqual(viewModel.fieldErrors.otp, String(localized: .signupVerifyErrorsInvalidCode))
    XCTAssertEqual(viewModel.otpCode, "")
    XCTAssertEqual(viewModel.step, .verifyEmail)
    XCTAssertEqual(authenticatedCount, 0)
    XCTAssertFalse(viewModel.isLoading)
  }

  // MARK: - Resend

  // MARK: - Leaving the code step

  // MARK: - Helpers

  private func makeViewModel(
    _ stub: StubEmailAuth,
    onAuthenticated: @escaping () -> Void = {}
  ) -> SignupViewModel {
    let viewModel = SignupViewModel(emailAuth: stub, onAuthenticated: onAuthenticated)
    viewModel.firstName = "New"
    viewModel.lastName = "User"
    viewModel.email = " new@example.com "
    viewModel.password = "password123"
    return viewModel
  }

  deinit {
    // Required by SwiftLint for XCTestCase subclasses.
  }
}
