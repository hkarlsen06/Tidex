# iOS AGENTS.md

iOS-specific development guidance for the Tidex native app.

## iOS Development Rules

**Current iOS version: iOS 26** (released September 2025). Apple changed version numbering at WWDC 2025 to align all operating systems. iOS 26 introduced the "Liquid Glass" design language.

Run commands from the repository root unless explicitly stated otherwise.

When running verification or diagnostic commands, prefer flags that reduce non-actionable output and preserve useful diagnostics. Examples: use `swiftlint --quiet` for fast Swift checks, use `--json` on repository build/test wrappers when you need structured diagnostics, and use focused test filters where possible. Avoid verbose command modes unless the extra output is needed to debug the issue.

Use the repository build wrapper for any iOS build. Do not run `xcodebuild` directly. If the wrapper hangs or takes unusually long, stop and report.
Use the repository test wrapper for any iOS test run. Do not run `xcodebuild test` directly.

### Build Wrapper

```bash
./scripts/xcode-build-agent.sh
```

Do NOT run `xcodebuild` directly.

JSON output is available with:

```bash
./scripts/xcode-build-agent.sh --json
```

Interpretation rules:
- Exit code `0` + `STATUS: SUCCESS` -> build succeeded
- Non-zero exit code or `STATUS: FAILURE` -> build failed
- If present, read the `WARNINGS` and `ERRORS` sections for diagnostics
- During active debugging where the user is already rebuilding in Xcode or on device/simulator after each turn, do not auto-run the build wrapper for every small change.
- In that mode, skip build execution when the edit is narrow and you are confident it should still compile; explicitly say you skipped the build so the user can validate in their normal loop.

### Test Wrapper

```bash
./scripts/xcode-test-agent.sh
```

Do NOT run `xcodebuild test` directly.

JSON output is available with:

```bash
./scripts/xcode-test-agent.sh --json
```

Pass focused test filters through to `xcodebuild test`, for example:

```bash
./scripts/xcode-test-agent.sh -- -only-testing:TidexAppTests/FriendsMessagesRepositoryTests
```

Interpretation rules:
- Exit code `0` + `STATUS: SUCCESS` -> tests passed
- Non-zero exit code or `STATUS: FAILURE` -> tests failed
- If present, read the `TESTS`, `WARNINGS`, `ERRORS`, and `test_failures` diagnostics
- During active debugging where the user is already rebuilding/rerunning manually after each turn, do not auto-run tests for every small change.
- In that mode, skip test execution when the edit is narrow and low-risk, and say so clearly in the handoff.

**ONLY create API routes when service role privileges are required.** Everything that can be done in the iOS binary using the user's JWT + RLS policies should stay there. Examples:
- API route needed: `/api/delete-account` (needs admin API), `/api/push-device` (needs `internal` schema)
- No API route: Subscription/entitlement data, settings, shifts - use Supabase client directly or RPC functions

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
- Asked the user to run tests/build in Xcode for final verification.

## Localization (REQUIRED for all UI strings)

**NEVER hardcode user-visible strings.** Every string shown to users must be localized.

### Adding new strings (AI workflow)

1. **Add the string to the catalog** with English and Norwegian:
   ```bash
   add-strings --key "feature.context.description" --en "English text" --nb "Norwegian text"
   ```

2. **Use the symbol in code:**
   ```swift
   // Simple strings
   Text(.featureContextDescription)
   String(localized: .featureContextDescription)

   // Formatted strings (symbols become functions)
   Text(String(localized: .commonInDays(Int32(days))))
   ```

3. **Remind the user** to run the translation script for other languages:
   ```bash
   node ios/Scripts/translate-xcstrings.mjs
   ```

### Key naming convention

- Format: `feature.context.description` (dot-separated, lowercase)
- Symbol becomes camelCase: `feature.context.description` → `.featureContextDescription`
- Examples:
  - `settings.profile.saveButton` → `.settingsProfileSaveButton`
  - `dashboard.earnings.title` → `.dashboardEarningsTitle`
  - `common.cancel` → `.commonCancel`

### Validation scripts

```bash
# Check for hardcoded strings in SwiftUI views
./lint-strings

# Validate string catalog integrity
ios/Scripts/validate-localization.sh
```

### Rules

- Use Xcode-generated `LocalizedStringResource` symbols, not raw string keys
- Never call localization APIs with raw string keys such as `String(localized: "settings.saveButton")`, `Text("settings.saveButton", tableName: "Localizable")`, `LocalizedStringResource("settings.saveButton", table: "Localizable")`, or `NSLocalizedString("settings.saveButton", ...)`.
- If a key has no generated symbol, add or rename the catalog entry to a dot-notation key that does generate one, then use the symbol.
- `%lld` format specifiers generate `Int32` parameters - wrap `Int` with `Int32()`
- Use system locale; do not override `.environment(\.locale, ...)`
- Prefer `FormatStyle` for numbers/dates/currency instead of `String(format:)`
- Catalog source: `ios/Resources/Localization/App/Localizable.xcstrings`

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
- `LOCALIZATION.md` - Localization details
- `LIQUID_GLASS_FINDINGS.md` - iOS 26 Liquid Glass findings
