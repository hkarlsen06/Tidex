# iOS AGENTS.md

iOS-specific development guidance for the Tidex native app.

## iOS Development Rules

**Current iOS version: iOS 26** (released September 2025). Apple changed version numbering at WWDC 2025 to align all operating systems. iOS 26 introduced the "Liquid Glass" design language.

Run commands from the repository root unless explicitly stated otherwise.

When running verification or diagnostic commands, prefer flags that reduce non-actionable output and preserve useful diagnostics. Examples: use `swiftlint --quiet` for fast Swift checks, use `--json` on repository build/test wrappers when you need structured diagnostics, and use focused test filters where possible. Avoid verbose command modes unless the extra output is needed to debug the issue.

Use [the verification guide](docs/AGENT_VERIFICATION.md) when building or testing. Use the existing wrappers, investigate failures within scope, and do not bypass a hung wrapper with raw xcodebuild; report a concrete blocker if it cannot be resolved.

## Backend access

Use the existing Swift Supabase client with the user's JWT for RLS-protected queries and authorized public RPCs. Keep privileged operations server-side in the existing Edge Functions or reviewed SQL functions. Do not introduce a web API layer or put service-role credentials in the iOS app. Inspect the affected service and handler before choosing a route.

The current service layer uses `.rpc(...)` and `supabase.functions.invoke(...)`; examples include `Services/Data/FriendsMessagingService.swift`, `Services/Auth/ImpersonationManager.swift`, and `Services/Subscription/JWSUploadWorker.swift` under `ios/TidexApp/`. Backend source and self-hosted deployment guidance are in the root AGENTS.md. Static marketing and compatibility sites are not an authenticated application API server.

## Testing Requirements (REQUIRED for feature work)

Agents must add or update tests when implementing new behavior.

### Default rule

- Every feature PR/change must include test coverage for changed behavior, not just compile-clean code.
- If behavior changes and no tests are added, explicitly explain why in the final handoff.

### What to test

- Happy path: primary user flow works and returns expected values.
- Edge cases: invalid/missing input, time/date boundaries, empty states.
- Regression guard: at least one test that would fail if the new logic is removed or reverted.
- Bug fixes: add a test that reproduces the bug before/alongside the fix (when feasible).

### Where to place tests

- Business logic, parsing, sync, repositories, and view-model logic:
  - `ios/TidexAppTests/`
- UI launch/smoke and critical interaction checks:
  - `ios/TidexAppUITests/`

Prefer small focused unit tests over broad UI tests unless the behavior is UI-only.

### Coverage expectations by change type

- New service/repository logic: add unit tests for success + failure/edge paths.
- New date/time/payroll logic: add boundary tests (cross-midnight, month boundary, invalid input).
- Sync/conflict logic changes: add tests for dirty tracking, conflict states, and resolution paths.
- New user-facing flows/screens: add at least one smoke UI test when feasible.

### Agent completion checklist

- Added/updated tests for new behavior.
- Confirmed tests are included in the correct test target.
- Ran fast validation (`swiftlint --quiet`) and reported results.
- Completed focused verification, or reported exactly what remains unverified and why. Request user/device verification only for unavailable tooling, device-only behavior, or the active interactive Xcode loop.

## Localization

All user-visible strings must be localized using generated `LocalizedStringResource` symbols, not raw string keys. Use the repository catalog helper and include English, Norwegian, and translator context. Read [the localization workflow](docs/AGENT_LOCALIZATION.md) for catalog edits, generated-symbol usage, and validation. Preserve the system locale and use FormatStyle for numbers, dates, and currency.

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

## Project Documentation

See `ios/docs/` for more details:
- `ARCHITECTURE.md` - App architecture overview
- `DATA_FLOW.md` - Data flow patterns
- `LOCALIZATION.md` - Localization details
- `LIQUID_GLASS_FINDINGS.md` - iOS 26 Liquid Glass findings
