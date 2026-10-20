import Auth
import Supabase
import XCTest

@testable import Tidex

// swiftlint:disable async_without_await

/// Stand-in for `AuthService` that records calls and returns scripted results.
@MainActor
internal final class StubEmailAuth: EmailAuthProviding {
  internal var signUpResult: Result<EmailSignupResult, Error> = .success(.signedIn)
  internal var signInError: Error = URLError(.notConnectedToInternet)
  internal var verifyError: Error?
  internal var resendError: Error?

  internal private(set) var signedUpEmails: [String] = []
  internal private(set) var verifiedCodes: [String] = []
  internal private(set) var resentEmails: [String] = []

  internal func signInWithPassword(email: String, password: String) async throws -> Session {
    throw signInError
  }

  internal func signUpWithEmail(
    email: String,
    password: String,
    fullName: String?
  ) async throws -> EmailSignupResult {
    signedUpEmails.append(email)
    return try signUpResult.get()
  }

  internal func verifySignupCode(email: String, token: String) async throws {
    verifiedCodes.append("\(email):\(token)")
    if let verifyError { throw verifyError }
  }

  internal func resendSignupCode(email: String) async throws {
    resentEmails.append(email)
    if let resendError { throw resendError }
  }

  deinit {
    // Required by SwiftLint for classes with a deinit rule.
  }
}

// swiftlint:enable async_without_await

/// Builds the GoTrue API error that carries the given `error_code`.
internal func makeAuthAPIError(_ code: ErrorCode) throws -> Error {
  let response = try XCTUnwrap(
    HTTPURLResponse(
      url: try XCTUnwrap(URL(string: "https://api.tidex.no/auth/v1/verify")),
      statusCode: 400,
      httpVersion: nil,
      headerFields: nil
    )
  )
  return Auth.AuthError.api(
    message: code.rawValue,
    errorCode: code,
    underlyingData: Data(),
    underlyingResponse: response
  )
}

@MainActor
internal final class SignupViewModelTests: XCTestCase {

  // MARK: - Signup with a session (autoconfirm on)

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

  // MARK: - Signup without a session (autoconfirm off)

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

    XCTAssertEqual(stub.verifiedCodes, ["new@example.com:123456"])
    XCTAssertEqual(authenticatedCount, 1)
    XCTAssertNil(viewModel.fieldErrors.otp)
    XCTAssertNil(viewModel.errorMessage)
  }

  internal func testVerifyWithWrongOrExpiredCodeShowsMessageAndClearsCode() async throws {
    let stub = StubEmailAuth()
    stub.verifyError = try makeAuthAPIError(.otpExpired)
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
    viewModel.emailOrPhone = " new@example.com "
    viewModel.password = "password123"
    return viewModel
  }

  deinit {
    // Required by SwiftLint for XCTestCase subclasses.
  }
}
