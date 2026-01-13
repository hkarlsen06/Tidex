import Foundation

/// Localized strings for auth screens
/// Mirrors the web app's dictionary structure at t.pages.auth
enum AuthStrings {

    // MARK: - String Access

    /// Get a localized string for the given key and locale
    static func string(_ key: String, locale: LocalizationManager.AppLocale) -> String {
        let dictionary = locale == .norwegian ? norwegianStrings : englishStrings
        return dictionary[key] ?? key
    }

    // MARK: - Norwegian Strings

    private static let norwegianStrings: [String: String] = [
        // Login Screen
        "login.title": "Logg inn p\u{00E5} Tidex",
        "login.subtitle": "Velkommen tilbake! Logg inn for \u{00E5} fortsette",
        "login.emailOrPhoneLabel": "E-post eller telefonnummer",
        "login.emailOrPhonePlaceholder": "navn@eksempel.no eller +47 12345678",
        "login.passwordLabel": "Passord",
        "login.passwordPlaceholder": "Skriv inn passordet ditt",
        "login.submitButton": "Logg inn",
        "login.emailOrPhoneReveal": "Logg inn med e-post eller telefon",
        "login.forgotPassword": "Glemt passord?",
        "login.noAccount": "Har du ikke en konto?",
        "login.createAccount": "Opprett konto",
        "login.separator": "eller",

        // Login Success Messages
        "login.success.smsSent": "En kode er sendt til telefonen din",

        // Login Errors
        "login.errors.fillEmailOrPhone": "Fyll inn e-post eller telefonnummer.",
        "login.errors.invalidEmailOrPhone": "Ugyldig e-post eller telefonnummer.",
        "login.errors.genericError": "En feil oppstod",
        "login.errors.googleSignInFailed": "Kunne ikke starte Google-innlogging. Pr\u{00F8}v igjen senere.",
        "login.errors.appleSignInFailed": "Kunne ikke starte Apple-innlogging. Pr\u{00F8}v igjen senere.",
        "login.errors.passwordRequired": "Passord er p\u{00E5}krevd",

        // OTP Screen
        "otp.title": "Skriv inn koden",
        "otp.subtitle": "Vi har sendt en kode til %@",
        "otp.submitButton": "Bekreft",
        "otp.resendCode": "Send kode p\u{00E5} nytt",
        "otp.backToLogin": "Tilbake til innlogging",

        // OAuth Buttons
        "oauth.continueWithGoogle": "Fortsett med Google",
        "oauth.continueWithApple": "Fortsett med Apple",
        "oauth.signInWithGoogle": "Logg inn med Google",
        "oauth.signInWithApple": "Logg inn med Apple",

        // MFA Screen
        "mfa.title": "To-faktor autentisering",
        "mfa.subtitle": "Skriv inn koden fra autentiseringsappen din",
        "mfa.codeLabel": "Bekreftelseskode",
        "mfa.codePlaceholder": "000000",
        "mfa.submitButton": "Bekreft",
        "mfa.backToLogin": "Tilbake til innlogging",
        "mfa.errors.codeRequired": "Vennligst skriv inn 6-sifret kode",
        "mfa.errors.challengeExpired": "Sesjonen har utl\u{00F8}pt. Pr\u{00F8}v igjen.",

        // Signup Screen
        "signup.title": "Opprett konto",
        "signup.subtitle": "Kom i gang med Tidex",
        "signup.emailLabel": "E-post",
        "signup.phoneLabel": "Telefonnummer",
        "signup.passwordLabel": "Passord",
        "signup.confirmPasswordLabel": "Bekreft passord",
        "signup.submitButton": "Opprett konto",
        "signup.hasAccount": "Har du allerede en konto?",
        "signup.login": "Logg inn",

        // Reset Password Screen
        "resetPassword.title": "Tilbakestill passord",
        "resetPassword.subtitle": "Skriv inn e-postadressen din for \u{00E5} f\u{00E5} en tilbakestillingslenke",
        "resetPassword.emailLabel": "E-post",
        "resetPassword.submitButton": "Send tilbakestillingslenke",
        "resetPassword.backToLogin": "Tilbake til innlogging",
        "resetPassword.success": "Sjekk e-posten din for en tilbakestillingslenke",

        // Locale Switcher
        "locale.norwegian": "Norsk",
        "locale.english": "English",

        // Common
        "common.loading": "Laster...",
        "common.error": "Feil",
        "common.retry": "Pr\u{00F8}v igjen",
        "common.cancel": "Avbryt",
        "common.continue": "Fortsett",

        // Tabs
        "tabs.home": "Hjem",
        "tabs.shifts": "Vakter",
        "tabs.stats": "Statistikk",
        "tabs.sharing": "Venner",

        // Dashboard
        "dashboard.title": "Hjem",
        "dashboard.welcome": "Velkommen til Tidex!",
        "dashboard.subtitle": "Du er n\u{00E5} logget inn",
        "dashboard.signOut": "Logg ut",
        "dashboard.comingSoon": "Full dashboard kommer snart",
        "dashboard.comingSoonDescription": "Vi jobber med \u{00E5} bygge en fullstendig native iOS-app. F\u{00F8}lg med!",

        // Placeholders
        "placeholder.shiftsDescription": "Vaktene dine vises her",
        "placeholder.addShift": "Legg til vakt",
        "placeholder.addShiftDescription": "Legg til en ny vakt her",
        "placeholder.statsDescription": "Statistikken din vises her",
        "placeholder.sharingDescription": "Del vakter med venner her"
    ]

    // MARK: - English Strings

    private static let englishStrings: [String: String] = [
        // Login Screen
        "login.title": "Log in to Tidex",
        "login.subtitle": "Welcome back! Log in to continue",
        "login.emailOrPhoneLabel": "Email or phone number",
        "login.emailOrPhonePlaceholder": "name@example.com or +47 12345678",
        "login.passwordLabel": "Password",
        "login.passwordPlaceholder": "Enter your password",
        "login.submitButton": "Log in",
        "login.emailOrPhoneReveal": "Log in with email or phone",
        "login.forgotPassword": "Forgot password?",
        "login.noAccount": "Don't have an account?",
        "login.createAccount": "Create account",
        "login.separator": "or",

        // Login Success Messages
        "login.success.smsSent": "A code has been sent to your phone",

        // Login Errors
        "login.errors.fillEmailOrPhone": "Please enter email or phone number.",
        "login.errors.invalidEmailOrPhone": "Invalid email or phone number.",
        "login.errors.genericError": "An error occurred",
        "login.errors.googleSignInFailed": "Could not start Google sign-in. Please try again later.",
        "login.errors.appleSignInFailed": "Could not start Apple sign-in. Please try again later.",
        "login.errors.passwordRequired": "Password is required",

        // OTP Screen
        "otp.title": "Enter the code",
        "otp.subtitle": "We've sent a code to %@",
        "otp.submitButton": "Confirm",
        "otp.resendCode": "Resend code",
        "otp.backToLogin": "Back to login",

        // OAuth Buttons
        "oauth.continueWithGoogle": "Continue with Google",
        "oauth.continueWithApple": "Continue with Apple",
        "oauth.signInWithGoogle": "Sign in with Google",
        "oauth.signInWithApple": "Sign in with Apple",

        // MFA Screen
        "mfa.title": "Two-factor authentication",
        "mfa.subtitle": "Enter the code from your authenticator app",
        "mfa.codeLabel": "Verification code",
        "mfa.codePlaceholder": "000000",
        "mfa.submitButton": "Confirm",
        "mfa.backToLogin": "Back to login",
        "mfa.errors.codeRequired": "Please enter the 6-digit code",
        "mfa.errors.challengeExpired": "Session expired. Please try again.",

        // Signup Screen
        "signup.title": "Create account",
        "signup.subtitle": "Get started with Tidex",
        "signup.emailLabel": "Email",
        "signup.phoneLabel": "Phone number",
        "signup.passwordLabel": "Password",
        "signup.confirmPasswordLabel": "Confirm password",
        "signup.submitButton": "Create account",
        "signup.hasAccount": "Already have an account?",
        "signup.login": "Log in",

        // Reset Password Screen
        "resetPassword.title": "Reset password",
        "resetPassword.subtitle": "Enter your email to receive a reset link",
        "resetPassword.emailLabel": "Email",
        "resetPassword.submitButton": "Send reset link",
        "resetPassword.backToLogin": "Back to login",
        "resetPassword.success": "Check your email for a reset link",

        // Locale Switcher
        "locale.norwegian": "Norsk",
        "locale.english": "English",

        // Common
        "common.loading": "Loading...",
        "common.error": "Error",
        "common.retry": "Try again",
        "common.cancel": "Cancel",
        "common.continue": "Continue",

        // Tabs
        "tabs.home": "Home",
        "tabs.shifts": "Shifts",
        "tabs.stats": "Stats",
        "tabs.sharing": "Friends",

        // Dashboard
        "dashboard.title": "Home",
        "dashboard.welcome": "Welcome to Tidex!",
        "dashboard.subtitle": "You are now logged in",
        "dashboard.signOut": "Sign out",
        "dashboard.comingSoon": "Full dashboard coming soon",
        "dashboard.comingSoonDescription": "We're working on building a fully native iOS app. Stay tuned!",

        // Placeholders
        "placeholder.shiftsDescription": "Your shifts will appear here",
        "placeholder.addShift": "Add Shift",
        "placeholder.addShiftDescription": "Add a new shift here",
        "placeholder.statsDescription": "Your statistics will appear here",
        "placeholder.sharingDescription": "Share shifts with friends here"
    ]
}
