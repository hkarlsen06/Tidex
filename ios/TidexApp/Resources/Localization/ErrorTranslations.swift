import Foundation

/// Translates Supabase error messages into the app's language
/// Mirrors the web app's lib/errors/translate.ts
enum ErrorTranslations {

  // MARK: - Translation Dictionary

  /// Supabase error messages (English) mapped to catalog strings
  private static let translations: [String: LocalizedStringResource] = [
    // Authentication errors
    "Invalid login credentials": .authErrorInvalidLoginCredentials,
    "Email not confirmed": .authErrorEmailNotConfirmed,
    "User already registered": .authErrorUserAlreadyRegistered,
    "Password should be at least 6 characters": .authErrorPasswordMin6,
    "Password should be at least 8 characters": .authErrorPasswordMin8,
    "New password should be different from the old password.": .authErrorPasswordSameAsOld,
    "Unable to validate email address: invalid format": .authErrorInvalidEmailFormat,
    "Invalid email": .authErrorInvalidEmail,
    "Signup requires a valid password": .authErrorSignupRequiresPassword,
    "For security purposes, you can only request this once every 60 seconds":
      .authErrorRequestRateLimited,
    "User not found": .authErrorUserNotFound,
    "Invalid refresh token": .authErrorInvalidRefreshToken,
    "Token has expired or is invalid": .authErrorTokenExpiredOrInvalid,
    "Email link is invalid or has expired": .authErrorEmailLinkInvalid,
    "Database error saving new user": .authErrorDatabaseSavingUser,
    "Failed to fetch": .authErrorServerUnreachable,
    "Network request failed": .authErrorNetworkRequestFailed,
    "Event not found. Please refresh and try again.": .authErrorEventNotFound,
    "Invalid event date range": .authErrorInvalidEventDateRange,

    // Phone-related errors
    "Invalid phone number": .authErrorInvalidPhone,
    "Phone not confirmed": .authErrorPhoneNotConfirmed,
    "SMS OTP has expired": .authErrorSmsCodeExpired,
    "Invalid OTP": .authErrorInvalidCode,
    "OTP expired": .authErrorCodeExpired,
    "Token expired": .authErrorCodeExpired,
    "Phone number already in use": .authErrorPhoneInUse,
    "A user with this phone number has already been registered":
      .authErrorPhoneRegisteredToOtherAccount,
    "A user with this email address has already been registered":
      .authErrorEmailRegisteredToOtherAccount,
    "Unable to send SMS": .authErrorSmsSendFailed,
    "SMS rate limit exceeded": .authErrorSmsRateLimited,
    "Error sending confirmation OTP to provider": .authErrorVerificationCodeSendFailed,
    "Authenticate More information: https://www.twilio.com/docs/errors/20003":
      .authErrorSmsProviderRejected,
    "Signups not allowed for otp": .authErrorSignupRequired,
    "Signups not allowed": .authErrorSignupRequired,

    // Reauthentication errors
    "Reauthentication not valid": .authErrorReauthCodeInvalid,
    "Reauthentication required": .authErrorReauthRequired,
    "Invalid nonce": .authErrorReauthCodeInvalidOrExpired,
    "Nonce has expired": .authErrorReauthCodeExpired,

    // MFA errors
    "Invalid TOTP code": .authErrorInvalidCode,
    "MFA verification failed": .authErrorMfaVerificationFailed,
  ]

  // MARK: - Translation Function

  /// Translate a Supabase error message into the app's language
  /// Falls back to original message if no translation is found
  /// - Parameter message: The error message to translate
  /// - Returns: The translated message, or the original if no translation exists
  static func translate(_ message: String) -> String {
    if message.contains("webauthn_verification_failed")
      || message.contains("Credential verification failed")
    {
      return String(localized: .loginPasskeyErrorsVerificationFailed)
    }

    if message.contains("Error sending confirmation OTP to provider")
      || message.contains("twilio.com/docs/errors/20003")
      || message.contains("sms_send_failed")
    {
      return String(localized: .authErrorVerificationCodeSendFailed)
    }

    // Check for exact match
    if let translated = translations[message] {
      return String(localized: translated)
    }

    // Check for partial matches
    for (english, translated) in translations where message.contains(english) {
      return message.replacingOccurrences(of: english, with: String(localized: translated))
    }

    // Return original message if no translation found
    return message
  }

  /// Translate an Error to a user-friendly localized message
  /// - Parameter error: The error to translate
  /// - Returns: A translated error message
  static func translate(_ error: Error) -> String {
    return translate(error.localizedDescription)
  }
}
