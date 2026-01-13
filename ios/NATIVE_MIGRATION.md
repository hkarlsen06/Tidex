# iOS Native Migration

This document describes the fully native iOS app architecture for Tidex.

## Goal

Build a fully native iOS app that:
- Provides better performance and native feel
- Enables offline-first functionality
- Uses native authentication (no web redirects)
- Is built entirely in SwiftUI with no Capacitor/WebView dependencies

## Architecture Overview

The app uses a **fully native SwiftUI architecture** with a coordinator pattern for navigation.

```
                    +---------------------------+
                    |       SceneDelegate       |
                    |   (UIKit entry point)     |
                    +---------------------------+
                              |
                    +---------------------------+
                    |        RootView           |
                    |   (SwiftUI host)          |
                    +---------------------------+
                              |
                    +---------------------------+
                    |     AppCoordinator        |
                    |   (Auth state manager)    |
                    +---------------------------+
                              |
           +------------------+------------------+
           |                  |                  |
    +------------------+  +-------------+  +-------------+
    | AuthNavigation   |  | MFAVerify   |  | MainTabView |
    |  ├── Login       |  +-------------+  +-------------+
    |  ├── Signup      |        ↓                ↓
    |  └── ResetPwd    |  MFA Required     Authenticated
    +------------------+
           ↓
    Unauthenticated
```

### Navigation Flow

1. App launches → `SceneDelegate` creates `RootView`
2. `RootView` observes `AppCoordinator.appState`
3. `AppCoordinator` checks Supabase auth state on launch
4. Based on state, `RootView` displays:
   - `.loading` → Loading spinner
   - `.unauthenticated` → Login screen
   - `.mfaRequired` → MFA verification screen
   - `.authenticated` → Main tab view (dashboard)

## Current Status

### Completed (Phase 1: Auth + Basic Navigation)

| Component | Status | Description |
|-----------|--------|-------------|
| `AppCoordinator` | Done | Central auth state and navigation manager |
| `RootView` | Done | Root SwiftUI view with state transitions |
| `AuthService` | Done | Supabase auth wrapper with all methods |
| `SupabaseClient` | Done | Configured client with Keychain storage |
| `AppleAuthProvider` | Done | Native Apple Sign-In via ASAuthorization |
| `GoogleAuthProvider` | Done | Native Google Sign-In via SDK |
| `LoginView` | Done | Full login screen UI |
| `LoginViewModel` | Done | Login logic, validation, MFA handling |
| `MFAVerifyView` | Done | Two-factor auth verification |
| `MFAVerifyViewModel` | Done | MFA challenge and verification logic |
| `MainTabView` | Done | Authenticated home (placeholder dashboard) |
| `LocalizationManager` | Done | i18n support (Norwegian/English) |
| `AuthStrings` | Done | Localized strings for auth screens |
| `ErrorTranslations` | Done | Supabase error message translation |
| Shared Components | Done | Buttons, text fields, cards, etc. |

### Completed (Phase 2: Signup + Password Reset)

| Component | Status | Description |
|-----------|--------|-------------|
| `AuthNavigationView` | Done | Navigation container for login/signup/reset flows |
| `SignupView` | Done | User registration screen with OAuth + email/phone |
| `SignupViewModel` | Done | Signup logic, validation, OTP handling |
| `SignupForm` | Done | Email/phone + password form with terms agreement |
| `SignupOTPForm` | Done | OTP verification for phone signup |
| `TermsAgreementView` | Done | Terms/privacy checkbox with legal document sheets |
| `ResetPasswordView` | Done | Three-step password reset flow |
| `ResetPasswordViewModel` | Done | Reset logic for email and phone flows |
| Auth screen animations | Done | Spring entrance animations on all auth screens |

### Not Yet Implemented

| Component | Status | Notes |
|-----------|--------|-------|
| Dashboard data | Not started | Real shift data display |
| Shifts CRUD | Not started | Create/read/update/delete shifts |
| Stats views | Not started | Statistics and analytics |
| Settings | Not started | User preferences |

## Folder Structure

```
ios/App/App/
├── Core/                           # App lifecycle
│   ├── AppDelegate.swift           # App delegate (Firebase, background tasks)
│   └── SceneDelegate.swift         # Scene delegate (window setup)
│
├── Native/                         # All native SwiftUI code
│   ├── Core/
│   │   ├── AppCoordinator.swift    # Auth state and navigation manager
│   │   ├── RootView.swift          # Root view with state transitions
│   │   └── FeatureFlags.swift      # Feature toggles
│   │
│   ├── Features/
│   │   ├── Auth/
│   │   │   ├── AuthNavigationView.swift  # Navigation container for auth flows
│   │   │   ├── Login/
│   │   │   │   ├── LoginView.swift
│   │   │   │   ├── LoginViewModel.swift
│   │   │   │   └── Components/
│   │   │   │       ├── EmailPasswordForm.swift
│   │   │   │       ├── PhoneOTPForm.swift
│   │   │   │       ├── OTPInputField.swift
│   │   │   │       ├── OAuthButtonsView.swift
│   │   │   │       └── LocaleSwitcherView.swift
│   │   │   │
│   │   │   ├── Signup/
│   │   │   │   ├── SignupView.swift
│   │   │   │   ├── SignupViewModel.swift
│   │   │   │   └── Components/
│   │   │   │       └── TermsAgreementView.swift
│   │   │   │
│   │   │   ├── ResetPassword/
│   │   │   │   ├── ResetPasswordView.swift
│   │   │   │   └── ResetPasswordViewModel.swift
│   │   │   │
│   │   │   └── MFA/
│   │   │       ├── MFAVerifyView.swift
│   │   │       └── MFAVerifyViewModel.swift
│   │   │
│   │   └── Dashboard/
│   │       └── MainTabView.swift   # Tab bar with placeholder screens
│   │
│   ├── Services/
│   │   ├── Auth/
│   │   │   ├── AuthService.swift
│   │   │   └── OAuthProviders/
│   │   │       ├── AppleAuthProvider.swift
│   │   │       └── GoogleAuthProvider.swift
│   │   └── Network/
│   │       ├── SupabaseClient.swift
│   │       └── APIConfiguration.swift
│   │
│   ├── Shared/
│   │   ├── Components/
│   │   │   ├── PrimaryButton.swift
│   │   │   ├── OutlineButton.swift
│   │   │   ├── TidexTextField.swift
│   │   │   ├── SecureTextField.swift
│   │   │   ├── TidexCard.swift
│   │   │   ├── ErrorBanner.swift
│   │   │   ├── SuccessBanner.swift
│   │   │   ├── LoadingOverlay.swift
│   │   │   └── LogoWatermark.swift
│   │   └── Extensions/
│   │       └── Color+Tidex.swift
│   │
│   └── Localization/
│       ├── LocalizationManager.swift
│       ├── AuthStrings.swift
│       └── ErrorTranslations.swift
│
└── Models/
    └── AuthState.swift
```

## Conventions

### 1. App State Management

The `AppCoordinator` manages the app's authentication state:

```swift
enum AppState: Equatable {
    case loading           // Initial app load, checking session
    case unauthenticated   // No valid session, show login
    case mfaRequired       // User logged in but needs MFA
    case authenticated     // Fully authenticated, show main app
}
```

### 2. Auth State Listener

`AppCoordinator` subscribes to Supabase auth state changes:

```swift
for await (event, session) in supabase.auth.authStateChanges {
    switch event {
    case .initialSession:
        // Check for existing session on launch
    case .signedIn:
        // User just signed in, check MFA
    case .signedOut:
        // User signed out
    case .mfaChallengeVerified:
        // MFA completed successfully
    // ...
    }
}
```

### 3. Brand Colors

All colors are defined in `Color+Tidex.swift`:

```swift
Color.tidexDarkBackground    // Main background
Color.tidexSurfacePrimary    // Card backgrounds
Color.tidexTextPrimary       // Primary text
Color.tidexTextSecondary     // Secondary text
Color.tidexBlue              // Brand accent
Color.tidexError             // Error states
Color.tidexSuccess           // Success states
```

### 4. Localization

Strings are accessed via `LocalizationManager`:

```swift
@Environment(\.localization) private var localization

Text(localization.string("login.title"))
Text(localization.string("otp.subtitle", phoneNumber))
```

### 5. Error Handling

Supabase errors are translated to user-friendly messages:

```swift
let translated = ErrorTranslations.translate(error)
errorMessage = translated
```

### 6. Async/Await Pattern

All async operations use Swift concurrency:

```swift
func signIn() async {
    isLoading = true
    defer { isLoading = false }

    do {
        try await authService.signInWithPassword(email: email, password: password)
        await AppCoordinator.shared.handleLoginSuccess()
    } catch {
        handleError(error)
    }
}
```

## Supabase Configuration

### Info.plist Keys Required

Add these to `Info.plist`:

```xml
<key>SUPABASE_URL</key>
<string>$(SUPABASE_URL)</string>
<key>SUPABASE_ANON_KEY</key>
<string>$(SUPABASE_ANON_KEY)</string>
```

### Keychain Storage

Auth tokens are stored in Keychain (not UserDefaults) for security:

```swift
let supabase = SupabaseClient(
    supabaseURL: APIConfiguration.supabaseURL,
    supabaseKey: APIConfiguration.supabaseAnonKey,
    options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(
            storage: KeychainLocalStorage(),
            autoRefreshToken: true
        )
    )
)
```

## SPM Dependencies

Add to the Xcode project via Swift Package Manager:

```swift
// Supabase Swift SDK
.package(url: "https://github.com/supabase/supabase-swift.git", from: "2.0.0")

// Google Sign-In iOS SDK
.package(url: "https://github.com/google/GoogleSignIn-iOS.git", from: "8.0.0")
```

**Note**: Apple Sign-In uses the native `AuthenticationServices` framework (no external dependency).

## Login Flow

The complete login flow:

```
┌──────────────────────────────────────────────────────────────────┐
│                        LOGIN FLOW                                │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  1. App launches                                                 │
│     → SceneDelegate creates RootView                             │
│     → RootView observes AppCoordinator.appState                  │
│     → AppCoordinator is in .loading state                        │
│            ↓                                                     │
│  2. AppCoordinator checks Supabase session                       │
│     → If no session: .unauthenticated → Show LoginView           │
│     → If session exists: Check MFA status                        │
│            ↓                                                     │
│  3. User logs in (email/password, OAuth, or OTP)                 │
│     → LoginViewModel calls authService.signInWith*()             │
│     → Supabase sets session cookies                              │
│     → AppCoordinator receives .signedIn event                    │
│            ↓                                                     │
│  4. AppCoordinator checks MFA status                             │
│     → If MFA required: .mfaRequired → Show MFAVerifyView         │
│     → If no MFA: .authenticated → Show MainTabView               │
│            ↓                                                     │
│  5. (If MFA) User enters TOTP code                               │
│     → MFAVerifyViewModel creates challenge and verifies          │
│     → On success: .mfaChallengeVerified event                    │
│     → AppCoordinator: .authenticated → Show MainTabView          │
│            ↓                                                     │
│  6. User is now on the dashboard                                 │
│     → Session persists in Keychain                               │
│     → Auto-refresh handles token expiration                      │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

## Future Phases

| Phase | Scope | Status |
|-------|-------|--------|
| Phase 1 | Auth screens (Login, MFA, basic dashboard) | Complete |
| Phase 2 | Signup and password reset | Complete |
| Phase 3 | Native Dashboard with real data | Not started |
| Phase 4 | Shifts CRUD with offline-first sync | Not started |
| Phase 5 | Native Stats | Not started |
| Phase 6 | Native Settings | Not started |

## Testing Checklist

When testing the native auth:

**Login:**
- [ ] Email login: Enter email + password → Login succeeds → Dashboard loads
- [ ] Phone OTP: Enter phone → Receive SMS → Enter OTP → Login succeeds
- [ ] Apple Sign-In: Native prompt appears → Login succeeds
- [ ] Google Sign-In: Native bottom sheet appears → Login succeeds
- [ ] MFA: If MFA enabled, redirect to MFA screen → Verify TOTP → Login succeeds
- [ ] Session persistence: Close and reopen app → Session persists
- [ ] Sign out: Tap sign out → Returns to login screen

**Signup:**
- [ ] Navigate to signup: Tap "Create account" on login → Signup screen appears
- [ ] Email signup: Enter email + password + accept terms → Email confirmation sent
- [ ] Phone signup: Enter phone + password + accept terms → OTP sent → Verify OTP → Success
- [ ] OAuth signup: Google/Apple sign in works from signup screen
- [ ] Terms agreement: Must check checkbox before submitting
- [ ] Terms links: Tapping terms/privacy opens sheet with legal documents
- [ ] Back to login: "Already have account?" navigates back to login

**Password Reset:**
- [ ] Navigate to reset: Tap "Forgot password?" on login → Reset screen appears
- [ ] Email reset: Enter email → Send link → Success message shown
- [ ] Phone reset: Enter phone → OTP sent → Verify → Enter new password → Success
- [ ] Back to login: Can navigate back to login from any step

**General:**
- [ ] Locale: Norwegian/English strings display correctly based on device locale
- [ ] Error handling: Invalid credentials show translated error message
- [ ] Animations: Entrance animations play smoothly on all auth screens
- [ ] Screen transitions: Navigating between login/signup/reset animates correctly

## Build Instructions

1. Open `ios/App/App.xcworkspace` in Xcode
2. Ensure SPM dependencies are resolved (File > Packages > Resolve Package Versions)
3. Add `SUPABASE_URL` and `SUPABASE_ANON_KEY` to your scheme's environment or Info.plist
4. Build and run on a device (simulators work but OAuth may have limitations)

## Important: No More Capacitor

This version of the app is **fully native** - there is no Capacitor WebView.

- `TidexContainerViewController` and related bridge code are no longer used
- All navigation is handled by SwiftUI's `NavigationStack` and the `AppCoordinator`
- URL schemes (for OAuth callbacks) are handled directly in `SceneDelegate`
