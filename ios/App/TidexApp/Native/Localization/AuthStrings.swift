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
        "signup.emailOrPhoneLabel": "E-post eller telefonnummer",
        "signup.emailOrPhonePlaceholder": "navn@eksempel.no eller +47 12345678",
        "signup.emailLabel": "E-post",
        "signup.phoneLabel": "Telefonnummer",
        "signup.passwordLabel": "Passord",
        "signup.passwordPlaceholder": "Minst 8 tegn",
        "signup.passwordHint": "Passordet m\u{00E5} v\u{00E6}re minst 8 tegn",
        "signup.confirmPasswordLabel": "Bekreft passord",
        "signup.submitButton": "Opprett konto",
        "signup.hasAccount": "Har du allerede en konto?",
        "signup.login": "Logg inn",
        "signup.emailOrPhoneReveal": "Registrer med e-post eller telefon",
        "signup.backToSignup": "Tilbake",
        "signup.errors.emailOrPhoneRequired": "Fyll inn e-post eller telefonnummer",
        "signup.errors.invalidEmailOrPhone": "Ugyldig e-post eller telefonnummer",
        "signup.errors.passwordRequired": "Passord er p\u{00E5}krevd",
        "signup.errors.passwordTooShort": "Passordet m\u{00E5} v\u{00E6}re minst 8 tegn",
        "signup.errors.passwordMismatch": "Passordene samsvarer ikke",
        "signup.errors.termsRequired": "Du m\u{00E5} godta vilk\u{00E5}rene",
        "signup.success.emailSent": "En bekreftelseslenke er sendt til e-posten din",
        "signup.success.otpSent": "En kode er sendt til telefonen din",
        "signup.success.otpResent": "En ny kode er sendt",
        "signup.emailSent.title": "Sjekk e-posten din",
        "signup.emailSent.subtitle": "Vi har sendt en bekreftelseslenke",
        "signup.emailSent.instructions": "Klikk p\u{00E5} lenken i e-posten for \u{00E5} bekrefte kontoen din. Sjekk ogs\u{00E5} spam-mappen.",
        "signup.emailSent.backToLogin": "Tilbake til innlogging",
        "signup.terms.prefix": "Jeg godtar",
        "signup.terms.termsLink": "vilk\u{00E5}rene",
        "signup.terms.and": "og",
        "signup.terms.privacyLink": "personvern",

        // OTP Errors
        "otp.errors.codeRequired": "Vennligst skriv inn koden",
        "otp.errors.codeInvalid": "Koden m\u{00E5} v\u{00E6}re 6 siffer",

        // Reset Password Screen
        "resetPassword.title": "Tilbakestill passord",
        "resetPassword.subtitle": "Skriv inn e-post eller telefonnummer for \u{00E5} tilbakestille passordet",
        "resetPassword.emailOrPhoneLabel": "E-post eller telefonnummer",
        "resetPassword.emailOrPhonePlaceholder": "navn@eksempel.no eller +47 12345678",
        "resetPassword.emailLabel": "E-post",
        "resetPassword.hint": "Vi sender en kode eller lenke for \u{00E5} tilbakestille passordet",
        "resetPassword.submitButton": "Send tilbakestillingskode",
        "resetPassword.backToLogin": "Tilbake til innlogging",
        "resetPassword.newPassword.title": "Nytt passord",
        "resetPassword.newPassword.subtitle": "Skriv inn ditt nye passord",
        "resetPassword.newPasswordLabel": "Nytt passord",
        "resetPassword.newPasswordPlaceholder": "Minst 8 tegn",
        "resetPassword.confirmPasswordLabel": "Bekreft nytt passord",
        "resetPassword.confirmPasswordPlaceholder": "Skriv passordet p\u{00E5} nytt",
        "resetPassword.passwordHint": "Passordet m\u{00E5} v\u{00E6}re minst 8 tegn",
        "resetPassword.updatePasswordButton": "Oppdater passord",
        "resetPassword.success.title": "Ferdig!",
        "resetPassword.success.subtitle": "Passordet ditt er tilbakestilt",
        "resetPassword.success.emailSent": "En tilbakestillingslenke er sendt til e-posten din",
        "resetPassword.success.otpSent": "En kode er sendt til telefonen din",
        "resetPassword.success.otpResent": "En ny kode er sendt",
        "resetPassword.success.passwordUpdated": "Passordet er oppdatert",
        "resetPassword.success.emailInstructions": "Sjekk e-posten din for en tilbakestillingslenke. Sjekk ogs\u{00E5} spam-mappen.",
        "resetPassword.success.passwordUpdatedInstructions": "Passordet ditt er oppdatert. Du kan n\u{00E5} logge inn med det nye passordet.",
        "resetPassword.errors.emailOrPhoneRequired": "Fyll inn e-post eller telefonnummer",
        "resetPassword.errors.invalidEmailOrPhone": "Ugyldig e-post eller telefonnummer",
        "resetPassword.errors.passwordRequired": "Passord er p\u{00E5}krevd",
        "resetPassword.errors.passwordTooShort": "Passordet m\u{00E5} v\u{00E6}re minst 8 tegn",
        "resetPassword.errors.confirmPasswordRequired": "Bekreft passordet",
        "resetPassword.errors.passwordMismatch": "Passordene samsvarer ikke",

        // Legal
        "legal.termsOfService": "Vilk\u{00E5}r for bruk",
        "legal.privacyPolicy": "Personvernerkl\u{00E6}ring",
        "legal.termsOfServiceContent": "Vilk\u{00E5}r for bruk av Tidex...\n\nVed \u{00E5} bruke Tidex godtar du disse vilk\u{00E5}rene.",
        "legal.privacyPolicyContent": "Personvernerkl\u{00E6}ring for Tidex...\n\nVi tar personvernet ditt p\u{00E5} alvor.",

        // Locale Switcher
        "locale.norwegian": "Norsk",
        "locale.english": "English",

        // Common
        "common.loading": "Laster...",
        "common.error": "Feil",
        "common.retry": "Pr\u{00F8}v igjen",
        "common.cancel": "Avbryt",
        "common.continue": "Fortsett",
        "common.back": "Tilbake",

        // Tabs
        "tabs.home": "Hjem",
        "tabs.shifts": "Vakter",
        "tabs.add": "Legg til",
        "tabs.stats": "Statistikk",
        "tabs.sharing": "Venner",

        // Dashboard
        "dashboard.title": "Hjem",
        "dashboard.welcome": "Velkommen til Tidex!",
        "dashboard.subtitle": "Du er n\u{00E5} logget inn",
        "dashboard.signOut": "Logg ut",
        "dashboard.comingSoon": "Full dashboard kommer snart",
        "dashboard.comingSoonDescription": "Vi jobber med \u{00E5} bygge en fullstendig native iOS-app. F\u{00F8}lg med!",
        "dashboard.earnedToDate": "Tjent hittil",
        "dashboard.nextShift": "Neste vakt",
        "dashboard.today": "I dag",
        "dashboard.earnings": "Inntekt",
        "dashboard.noShifts": "Ingen vakter funnet",
        "dashboard.loadError": "Kunne ikke laste data",
        "dashboard.nextPayout": "Neste utbetaling",
        "dashboard.previousPayout": "Forrige utbetaling",
        "dashboard.payroll": "Utbetaling",
        "dashboard.gross": "Brutto",
        "dashboard.tax": "Skatt",
        "dashboard.shift": "vakt",
        "dashboard.shifts": "vakter",
        "dashboard.planned": "planlagt",
        "dashboard.hoursShort": "t",
        "dashboard.beforeTax": "før skatt",
        "dashboard.shiftPlanned": "vakt planlagt",
        "dashboard.shiftsPlanned": "vakter planlagt",
        "dashboard.backToToday": "Tilbake til i dag",
        "dashboard.swipeHint": "Sveip for \u{00E5} bytte m\u{00E5}ned",
        "dashboard.bestShift": "Beste vakt",
        "dashboard.noShiftsMonth": "Ingen vakter denne m\u{00E5}neden",
        "dashboard.noNextShift": "Ingen kommende vakter",

        // Placeholders
        "placeholder.shiftsDescription": "Vaktene dine vises her",
        "placeholder.addShift": "Legg til vakt",
        "placeholder.addShiftDescription": "Legg til en ny vakt her",
        "placeholder.statsDescription": "Statistikken din vises her",
        "placeholder.sharingDescription": "Del vakter med venner her",

        // User Menu
        "userMenu.settings": "Innstillinger",
        "userMenu.logout": "Logg ut",
        "userMenu.loggingOut": "Logger ut...",

        // Pull to Refresh
        "pullToRefresh.pullDown": "Dra ned for å oppdatere",
        "pullToRefresh.release": "Slipp for å oppdatere",
        "pullToRefresh.refreshing": "Oppdaterer..."
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
        "signup.emailOrPhoneLabel": "Email or phone number",
        "signup.emailOrPhonePlaceholder": "name@example.com or +47 12345678",
        "signup.emailLabel": "Email",
        "signup.phoneLabel": "Phone number",
        "signup.passwordLabel": "Password",
        "signup.passwordPlaceholder": "At least 8 characters",
        "signup.passwordHint": "Password must be at least 8 characters",
        "signup.confirmPasswordLabel": "Confirm password",
        "signup.submitButton": "Create account",
        "signup.hasAccount": "Already have an account?",
        "signup.login": "Log in",
        "signup.emailOrPhoneReveal": "Sign up with email or phone",
        "signup.backToSignup": "Back",
        "signup.errors.emailOrPhoneRequired": "Please enter email or phone number",
        "signup.errors.invalidEmailOrPhone": "Invalid email or phone number",
        "signup.errors.passwordRequired": "Password is required",
        "signup.errors.passwordTooShort": "Password must be at least 8 characters",
        "signup.errors.passwordMismatch": "Passwords do not match",
        "signup.errors.termsRequired": "You must agree to the terms",
        "signup.success.emailSent": "A confirmation link has been sent to your email",
        "signup.success.otpSent": "A code has been sent to your phone",
        "signup.success.otpResent": "A new code has been sent",
        "signup.emailSent.title": "Check your email",
        "signup.emailSent.subtitle": "We've sent a confirmation link",
        "signup.emailSent.instructions": "Click the link in the email to confirm your account. Check your spam folder too.",
        "signup.emailSent.backToLogin": "Back to login",
        "signup.terms.prefix": "I agree to the",
        "signup.terms.termsLink": "terms of service",
        "signup.terms.and": "and",
        "signup.terms.privacyLink": "privacy policy",

        // OTP Errors
        "otp.errors.codeRequired": "Please enter the code",
        "otp.errors.codeInvalid": "Code must be 6 digits",

        // Reset Password Screen
        "resetPassword.title": "Reset password",
        "resetPassword.subtitle": "Enter your email or phone to reset your password",
        "resetPassword.emailOrPhoneLabel": "Email or phone number",
        "resetPassword.emailOrPhonePlaceholder": "name@example.com or +47 12345678",
        "resetPassword.emailLabel": "Email",
        "resetPassword.hint": "We'll send a code or link to reset your password",
        "resetPassword.submitButton": "Send reset code",
        "resetPassword.backToLogin": "Back to login",
        "resetPassword.newPassword.title": "New password",
        "resetPassword.newPassword.subtitle": "Enter your new password",
        "resetPassword.newPasswordLabel": "New password",
        "resetPassword.newPasswordPlaceholder": "At least 8 characters",
        "resetPassword.confirmPasswordLabel": "Confirm new password",
        "resetPassword.confirmPasswordPlaceholder": "Enter password again",
        "resetPassword.passwordHint": "Password must be at least 8 characters",
        "resetPassword.updatePasswordButton": "Update password",
        "resetPassword.success.title": "Done!",
        "resetPassword.success.subtitle": "Your password has been reset",
        "resetPassword.success.emailSent": "A reset link has been sent to your email",
        "resetPassword.success.otpSent": "A code has been sent to your phone",
        "resetPassword.success.otpResent": "A new code has been sent",
        "resetPassword.success.passwordUpdated": "Password has been updated",
        "resetPassword.success.emailInstructions": "Check your email for a reset link. Check your spam folder too.",
        "resetPassword.success.passwordUpdatedInstructions": "Your password has been updated. You can now log in with your new password.",
        "resetPassword.errors.emailOrPhoneRequired": "Please enter email or phone number",
        "resetPassword.errors.invalidEmailOrPhone": "Invalid email or phone number",
        "resetPassword.errors.passwordRequired": "Password is required",
        "resetPassword.errors.passwordTooShort": "Password must be at least 8 characters",
        "resetPassword.errors.confirmPasswordRequired": "Please confirm your password",
        "resetPassword.errors.passwordMismatch": "Passwords do not match",

        // Legal
        "legal.termsOfService": "Terms of Service",
        "legal.privacyPolicy": "Privacy Policy",
        "legal.termsOfServiceContent": "Terms of Service for Tidex...\n\nBy using Tidex you agree to these terms.",
        "legal.privacyPolicyContent": "Privacy Policy for Tidex...\n\nWe take your privacy seriously.",

        // Locale Switcher
        "locale.norwegian": "Norsk",
        "locale.english": "English",

        // Common
        "common.loading": "Loading...",
        "common.error": "Error",
        "common.retry": "Try again",
        "common.cancel": "Cancel",
        "common.continue": "Continue",
        "common.back": "Back",

        // Tabs
        "tabs.home": "Home",
        "tabs.shifts": "Shifts",
        "tabs.add": "Add",
        "tabs.stats": "Stats",
        "tabs.sharing": "Friends",

        // Dashboard
        "dashboard.title": "Home",
        "dashboard.welcome": "Welcome to Tidex!",
        "dashboard.subtitle": "You are now logged in",
        "dashboard.signOut": "Sign out",
        "dashboard.comingSoon": "Full dashboard coming soon",
        "dashboard.comingSoonDescription": "We're working on building a fully native iOS app. Stay tuned!",
        "dashboard.earnedToDate": "Earned to date",
        "dashboard.nextShift": "Next shift",
        "dashboard.today": "Today",
        "dashboard.earnings": "Earnings",
        "dashboard.noShifts": "No shifts found",
        "dashboard.loadError": "Failed to load data",
        "dashboard.nextPayout": "Next payout",
        "dashboard.previousPayout": "Previous payout",
        "dashboard.payroll": "Payroll",
        "dashboard.gross": "Gross",
        "dashboard.tax": "Tax",
        "dashboard.shift": "shift",
        "dashboard.shifts": "shifts",
        "dashboard.planned": "planned",
        "dashboard.hoursShort": "h",
        "dashboard.beforeTax": "before tax",
        "dashboard.shiftPlanned": "shift planned",
        "dashboard.shiftsPlanned": "shifts planned",
        "dashboard.backToToday": "Back to today",
        "dashboard.swipeHint": "Swipe to change month",
        "dashboard.bestShift": "Best shift",
        "dashboard.noShiftsMonth": "No shifts this month",
        "dashboard.noNextShift": "No upcoming shifts",

        // Placeholders
        "placeholder.shiftsDescription": "Your shifts will appear here",
        "placeholder.addShift": "Add Shift",
        "placeholder.addShiftDescription": "Add a new shift here",
        "placeholder.statsDescription": "Your statistics will appear here",
        "placeholder.sharingDescription": "Share shifts with friends here",

        // User Menu
        "userMenu.settings": "Settings",
        "userMenu.logout": "Log out",
        "userMenu.loggingOut": "Logging out...",

        // Pull to Refresh
        "pullToRefresh.pullDown": "Pull down to refresh",
        "pullToRefresh.release": "Release to refresh",
        "pullToRefresh.refreshing": "Refreshing..."
    ]
}
