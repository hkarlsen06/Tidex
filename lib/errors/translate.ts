/**
 * Translate common Supabase error messages to Norwegian
 * Falls back to original message if no translation available
 */
export function translateError(message: string): string {
  // Common authentication errors
  const translations: Record<string, string> = {
    "Invalid login credentials": "Ugyldig e-post eller passord",
    "Email not confirmed": "E-postadressen er ikke bekreftet",
    "User already registered": "Brukeren er allerede registrert",
    "Password should be at least 6 characters": "Passordet må være minst 6 tegn",
    "Password should be at least 8 characters": "Passordet må være minst 8 tegn",
    "Unable to validate email address: invalid format": "Ugyldig e-postformat",
    "Invalid email": "Ugyldig e-post",
    "Signup requires a valid password": "Registrering krever et gyldig passord",
    "For security purposes, you can only request this once every 60 seconds": "Av sikkerhetsgrunner kan du bare be om dette én gang hvert 60. sekund",
    "User not found": "Bruker ikke funnet",
    "Invalid refresh token": "Ugyldig oppdateringstoken",
    "Token has expired or is invalid": "Token har utløpt eller er ugyldig",
    "Email link is invalid or has expired": "E-postlenken er ugyldig eller har utløpt",
    "Database error saving new user": "Databasefeil ved lagring av ny bruker",
    "Failed to fetch": "Kunne ikke koble til serveren",
    "Network request failed": "Nettverksforespørsel feilet",
    // Phone-related errors
    "Invalid phone number": "Ugyldig telefonnummer",
    "Phone not confirmed": "Telefonnummeret er ikke bekreftet",
    "SMS OTP has expired": "SMS-koden har utløpt",
    "Invalid OTP": "Ugyldig kode",
    "OTP expired": "Koden har utløpt",
    "Token expired": "Koden har utløpt",
    "Phone number already in use": "Telefonnummeret er allerede i bruk",
    "A user with this phone number has already been registered": "Dette telefonnummeret er allerede registrert på en annen konto",
    "Unable to send SMS": "Kunne ikke sende SMS",
    "SMS rate limit exceeded": "For mange SMS-forespørsler. Prøv igjen senere.",
    "Signups not allowed for otp": "Du må registrere deg før du kan logge inn",
    "Signups not allowed": "Du må registrere deg før du kan logge inn",
  };

  // Check for exact match
  if (translations[message]) {
    return translations[message];
  }

  // Check for partial matches
  for (const [english, norwegian] of Object.entries(translations)) {
    if (message.includes(english)) {
      return message.replace(english, norwegian);
    }
  }

  // Return original message if no translation found
  return message;
}
