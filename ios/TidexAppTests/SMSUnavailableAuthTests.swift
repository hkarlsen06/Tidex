import XCTest

@testable import Tidex

/// Production has no SMS provider, so phone flows that need a code must stop before calling the server.
@MainActor
internal final class SMSUnavailableAuthTests: XCTestCase {
  override internal func setUpWithError() throws {
    try XCTSkipIf(AuthService.isSMSAvailable, "SMS is configured; the OTP flows are allowed")
  }

  internal func testPhoneLoginWithoutPasswordAsksForPasswordInsteadOfSendingCode() async {
    let viewModel = LoginViewModel()
    viewModel.emailOrPhone = "+47 123 45 678"

    await viewModel.signIn()

    XCTAssertEqual(viewModel.fieldErrors.password, String(localized: .loginErrorsPasswordRequired))
    XCTAssertEqual(viewModel.currentStep, .input)
  }

  internal func testPhonePasswordResetIsRejectedBeforeSendingCode() async {
    let viewModel = ResetPasswordViewModel()
    viewModel.emailOrPhone = "+47 123 45 678"

    await viewModel.sendResetCode()

    XCTAssertEqual(
      viewModel.fieldErrors.emailOrPhone,
      String(localized: .resetPasswordErrorsPhoneUnavailable)
    )
    XCTAssertEqual(viewModel.currentStep, .input)
  }

  deinit {
    // Required by SwiftLint for XCTestCase subclasses.
  }
}
