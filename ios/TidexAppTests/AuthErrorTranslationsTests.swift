import XCTest

@testable import Tidex

internal final class AuthErrorTranslationsTests: XCTestCase {
  internal func testPasskeyVerificationPayloadIsTranslatedToUserMessage() {
    let message: String =
      #"{"code":400,"error_code":"webauthn_verification_failed","msg":"Credential verification failed"}"#

    XCTAssertEqual(
      ErrorTranslations.translate(message),
      "Passnøkkelen kunne ikke bekreftes. Prøv igjen, eller bruk en annen innloggingsmetode."
    )
  }

  deinit {
    // Required by SwiftLint for XCTestCase subclasses.
  }
}
