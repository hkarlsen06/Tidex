# iOS CLAUDE.md

iOS-specific development guidance for the Tidex native app.

## iOS Development Rules

**Current iOS version: iOS 26** (released September 2025). Apple changed version numbering at WWDC 2025 to align all operating systems. iOS 26 introduced the "Liquid Glass" design language.

**NEVER run Xcode builds automatically.** Prompt the user to build in Xcode themselves.

**ONLY create API routes when service role privileges are required.** Everything that can be done in the iOS binary using the user's JWT + RLS policies should stay there. Examples:
- API route needed: `/api/delete-account` (needs admin API), `/api/push-device` (needs `internal` schema)
- No API route: Subscription/entitlement data, settings, shifts - use Supabase client directly or RPC functions

## Localization (String Catalogs)

- Use Xcode-generated `LocalizedStringResource` symbols (auto from `Localizable.xcstrings`), not raw string keys.
  - Example: `Text(.statsMonthlyGoalRemaining)` or `String(localized: .statsMonthlyGoalRemaining)`
  - For formatted strings: `String(localized: .commonInDays(Int32(days)))` - format symbols become functions
  - Note: `%lld` format specifiers generate `Int32` parameters, so wrap `Int` values with `Int32()`
- Use system locale; do not override `.environment(\.locale, ...)`.
- Prefer `FormatStyle` for numbers/dates/currency instead of `String(format:)`; use `String(focusYear)` when you must avoid locale grouping (e.g., years).
- Catalog source of truth: `App/TidexApp/Localizable.xcstrings`
- Scripts:
  - Validate: `swift run --package-path App/Scripts validate-localization`

## Color System

**ALWAYS use semantic Tidex colors** from `Color+Tidex.swift`. Never use hardcoded colors or non-existent color names.

Available colors (all adapt to light/dark mode):
| Category | Colors |
|----------|--------|
| Background | `tidexBackground`, `tidexBackgroundSecondary`, `tidexLaunchBackground` |
| Surface | `tidexSurfacePrimary`, `tidexSurfaceSecondary` |
| Text | `tidexTextPrimary`, `tidexTextSecondary`, `tidexTextMuted`, `tidexTextInverse` |
| Brand | `tidexBlue`, `tidexBrandPrimary`, `tidexPurple` |
| Border | `tidexBorder`, `tidexBorderSubtle` |
| Status | `tidexError`, `tidexSuccess`, `tidexWarning`, `tidexInfo` |

Usage: `Color.tidexSurfacePrimary`, `Color.tidexTextSecondary`, etc.

## API Routes for iOS

**Only create API routes when service role privileges are required.** Most operations should use the Supabase client directly in Swift with the user's JWT.

When an API route IS needed:

1. **Auth is automatic** - Both `getSession()` and `createSupabaseServerClient()` handle Bearer tokens (iOS) and cookies (web)
2. **Use DAL functions when available** - They work with Bearer auth automatically
3. **Use service client for internal schema** - `createSupabaseServiceClient()` for `internal` schema (when no DAL function exists)
4. **Return simple JSON responses** - Keep shapes flat and Swift-Codable friendly

**Current iOS API routes (all require service role):**
- `/api/delete-account` - Needs admin API to delete auth user
- `/api/push-device` - Needs access to `internal` schema
- `/api/profile-picture` - Needs storage operations with user context
- `/api/sharing/previews` - Uses DAL function with Bearer auth

## Project Documentation

See `ios/docs/` for more details:
- `ARCHITECTURE.md` - App architecture overview
- `DATA_FLOW.md` - Data flow patterns
- `DESIGN_DECISIONS.md` - Design decisions and rationale
- `LOCALIZATION.md` - Localization details
- `NATIVE_MIGRATION.md` - Migration notes
- `PATTERNS.md` - Code patterns
- `PAYROLL_SYSTEM.md` - Payroll calculation system
- `QUICK_REFERENCE.md` - Quick reference guide
- `APPLE_IAP_SETUP.md` - Apple In-App Purchase setup
- `APP_STORE_WRAPPER.md` - App Store wrapper
