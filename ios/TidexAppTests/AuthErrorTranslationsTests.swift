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

  internal func testKnownSupabaseMessageUsesCatalogString() {
    XCTAssertEqual(
      ErrorTranslations.translate("Invalid login credentials"),
      String(localized: .authErrorInvalidLoginCredentials)
    )
    XCTAssertEqual(ErrorTranslations.translate("Unmapped server error"), "Unmapped server error")
  }

  deinit {
    // Required by SwiftLint for XCTestCase subclasses.
  }
}
