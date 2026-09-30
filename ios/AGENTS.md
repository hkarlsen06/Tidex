# iOS AGENTS.md

iOS-specific development guidance for the Tidex native app.

## iOS Development Rules

**Deployment target: iOS 26.0** for every target, so don't add `#available` checks or fallbacks for iOS 26 or earlier. An API introduced in iOS 27 needs an `#available(iOS 27, *)` check and an iOS 26 fallback, because about half of active users were still on iOS 26 in September 2026. Apple changed version numbering at WWDC 2025 to align all operating systems. iOS 26 introduced the "Liquid Glass" design language.

Run commands from the repository root unless explicitly stated otherwise.

When running verification or diagnostic commands, prefer flags that reduce non-actionable output and preserve useful diagnostics. Examples: use `swiftlint --quiet` for fast Swift checks, use `--json` on repository build/test wrappers when you need structured diagnostics, and use focused test filters where possible. Avoid verbose command modes unless the extra output is needed to debug the issue.

Do not build or run tests unless the user asks or the root AGENTS.md exception applies; the user runs them in Xcode. When asked, use [the verification guide](docs/AGENT_VERIFICATION.md). Use the existing wrappers, investigate failures within scope, and do not bypass a hung wrapper with raw xcodebuild; report a concrete blocker if it cannot be resolved.

## Backend access

Use the existing Swift Supabase client with the user's JWT for RLS-protected queries and authorized public RPCs. Keep privileged operations server-side in the existing Edge Functions or reviewed SQL functions. Do not introduce a web API layer or put service-role credentials in the iOS app. Inspect the affected service and handler before choosing a route.

The current service layer uses `.rpc(...)` and `supabase.functions.invoke(...)`; examples include `Services/Data/FriendsMessagingService.swift` and `Services/Auth/ImpersonationManager.swift` under `ios/TidexApp/`. Backend source and self-hosted deployment guidance are in the root AGENTS.md. Static marketing and compatibility sites are not an authenticated application API server.

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
- Did not build or run tests unless the user asked; listed in one or two lines what the user should run or check.

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
| Blue text | `tidexBlueText` for blue text, links and small blue icons. `tidexBlue` is a fill; as text it fails 4.5:1 contrast in dark mode |
| Border | `tidexBorder`, `tidexBorderSubtle` |
| Status | `tidexError`, `tidexSuccess`, `tidexWarning` |

Usage: `Color.tidexSurfacePrimary`, `Color.tidexTextSecondary`, etc.

### No system grey surfaces

iOS's default grouped grey (about `#1C1C1E` in dark mode) looks brown next to the navy Tidex palette. Never let it show:

- Don't use `Color(.systemGroupedBackground)`, `Color(.secondarySystemGroupedBackground)`, `Color(.tertiarySystemGroupedBackground)`, `Color(.systemBackground)`, `Color(.secondarySystemBackground)` or `Color(.systemGray*)` for backgrounds or fills.
- A `List` or `Form` draws its rows in that grey unless you replace it. Hiding the scroll background alone is not enough; the rows stay grey. Style every `List` and `Form` like this:

```swift
Form {
  Group {
    // sections and rows
  }
  .listRowBackground(Color.tidexSurfacePrimary)
}
.tidexListBackground()
```

`tidexListBackground()` (in `Shared/Components/TidexAppBackground.swift`) puts `tidexBackground` behind the list. A row that should show the page background, such as a header or footer, can use `.listRowBackground(Color.clear)` on its own section instead. See `Features/Settings/SettingsView.swift` for the full pattern.

App extensions can't read the app's color assets. Code in `ios/Shared` that runs in the share extension uses `SharedPalette` (`ios/Shared/SharedPalette.swift`), and the widget uses `WidgetPalette`.

## Project Documentation

See `ios/docs/` for more details:
- `ARCHITECTURE.md` - App architecture overview
- `DATA_FLOW.md` - Data flow patterns
- `LOCALIZATION.md` - Localization details
- `LIQUID_GLASS_FINDINGS.md` - iOS 26 Liquid Glass findings
