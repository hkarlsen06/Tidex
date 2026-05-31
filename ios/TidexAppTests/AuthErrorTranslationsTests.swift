import XCTest

@testable import Tidex

final class AuthErrorTranslationsTests: XCTestCase {
  func testPasskeyVerificationPayloadIsTranslatedToUserMessage() {
    let message =
      #"{"code":400,"error_code":"webauthn_verification_failed","msg":"Credential verification failed"}"#

    XCTAssertEqual(
      ErrorTranslations.translate(message),
      "Passnøkkelen kunne ikke bekreftes. Prøv igjen, eller bruk en annen innloggingsmetode."
    )
  }
}
