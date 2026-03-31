import Foundation

/// Translates Supabase error messages from English to Norwegian
/// Mirrors the web app's lib/errors/translate.ts
enum ErrorTranslations {

  // MARK: - Translation Dictionary

  /// Error message translations (English -> Norwegian)
  private static let translations: [String: String] = [
    // Authentication errors
    "Invalid login credentials": "Ugyldig e-post eller passord",
    "Email not confirmed": "E-postadressen er ikke bekreftet",
    "User already registered": "Brukeren er allerede registrert",
    "Password should be at least 6 characters": "Passordet m\u{00E5} v\u{00E6}re minst 6 tegn",
    "Password should be at least 8 characters": "Passordet m\u{00E5} v\u{00E6}re minst 8 tegn",
    "New password should be different from the old password.":
      "Det nye passordet m\u{00E5} v\u{00E6}re forskjellig fra det gamle.",
    "Unable to validate email address: invalid format": "Ugyldig e-postformat",
    "Invalid email": "Ugyldig e-post",
    "Signup requires a valid password": "Registrering krever et gyldig passord",
    "For security purposes, you can only request this once every 60 seconds":
      "Av sikkerhetsgrunner kan du bare be om dette \u{00E9}n gang hvert 60. sekund",
    "User not found": "Bruker ikke funnet",
    "Invalid refresh token": "Ugyldig oppdateringstoken",
    "Token has expired or is invalid": "Token har utl\u{00F8}pt eller er ugyldig",
    "Email link is invalid or has expired": "E-postlenken er ugyldig eller har utl\u{00F8}pt",
    "Database error saving new user": "Databasefeil ved lagring av ny bruker",
    "Failed to fetch": "Kunne ikke koble til serveren",
    "Network request failed": "Nettverksforesp\u{00F8}rsel feilet",
    "Event not found. Please refresh and try again.":
      "Fant ikke hendelsen. Oppdater og pr\u{00F8}v igjen.",
    "Invalid event date range": "Ugyldig datointervall for hendelsen",

    // Phone-related errors
    "Invalid phone number": "Ugyldig telefonnummer",
    "Phone not confirmed": "Telefonnummeret er ikke bekreftet",
    "SMS OTP has expired": "SMS-koden har utl\u{00F8}pt",
    "Invalid OTP": "Ugyldig kode",
    "OTP expired": "Koden har utl\u{00F8}pt",
    "Token expired": "Koden har utl\u{00F8}pt",
    "Phone number already in use": "Telefonnummeret er allerede i bruk",
    "A user with this phone number has already been registered":
      "Dette telefonnummeret er allerede registrert p\u{00E5} en annen konto",
    "A user with this email address has already been registered":
      "Denne e-postadressen er allerede registrert p\u{00E5} en annen konto",
    "Unable to send SMS": "Kunne ikke sende SMS",
    "SMS rate limit exceeded": "For mange SMS-foresp\u{00F8}rsler. Pr\u{00F8}v igjen senere.",
    "Signups not allowed for otp": "Du m\u{00E5} registrere deg f\u{00F8}r du kan logge inn",
    "Signups not allowed": "Du m\u{00E5} registrere deg f\u{00F8}r du kan logge inn",

    // Reauthentication errors
    "Reauthentication not valid": "Ugyldig bekreftelseskode. Pr\u{00F8}v igjen.",
    "Reauthentication required":
      "Du m\u{00E5} bekrefte identiteten din f\u{00F8}r du kan endre passordet",
    "Invalid nonce": "Ugyldig eller utl\u{00F8}pt bekreftelseskode",
    "Nonce has expired": "Bekreftelseskoden har utl\u{00F8}pt. Be om en ny kode.",

    // MFA errors
    "Invalid TOTP code": "Ugyldig kode",
    "MFA verification failed": "MFA-verifisering feilet",
  ]

  // MARK: - Translation Function

  /// Translate an error message from English to Norwegian
  /// Falls back to original message if no translation is found
  /// - Parameter message: The error message to translate
  /// - Returns: The translated message, or the original if no translation exists
  static func translate(_ message: String) -> String {
    // Check for exact match
    if let translated = translations[message] {
      return translated
    }

    // Check for partial matches
    for (english, norwegian) in translations where message.contains(english) {
      return message.replacingOccurrences(of: english, with: norwegian)
    }

    // Return original message if no translation found
    return message
  }

  /// Translate an Error to a user-friendly Norwegian message
  /// - Parameter error: The error to translate
  /// - Returns: A translated error message
  static func translate(_ error: Error) -> String {
    return translate(error.localizedDescription)
  }
}
