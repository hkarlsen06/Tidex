# iOS AGENTS.md

iOS-specific development guidance for the Tidex native app.

## iOS Development Rules

**Deployment target: iOS 26.** All app, test and extension targets use 26.0. Keep the test target equal to the app target, or the test build fails. Don't add `#available` checks or fallbacks for iOS 26 or earlier. An API introduced in iOS 27 needs an `#available(iOS 27, *)` check and an iOS 26 fallback, because about half of active users were still on iOS 26 in September 2026. Apple changed version numbering at WWDC 2025 to align all operating systems. iOS 26 introduced the "Liquid Glass" design language.

Run commands from the repository root unless explicitly stated otherwise.

When running verification or diagnostic commands, prefer flags that reduce non-actionable output and preserve useful diagnostics. Examples: use `swiftlint --quiet` for fast Swift checks, use `--json` on repository build/test wrappers when you need structured diagnostics, and use focused test filters where possible. Avoid verbose command modes unless the extra output is needed to debug the issue.

Build and run tests yourself to prove each change, as [the verification guide](docs/AGENT_VERIFICATION.md) describes. Use the existing wrappers, investigate failures within scope, and do not bypass a hung wrapper with raw xcodebuild; report a concrete blocker if it cannot be resolved.

## Where things live

Paths are under `ios/TidexApp/` unless they start with `ios/`.

- The string catalog is `ios/Resources/Localization/App/Localizable.xcstrings`. `TidexApp/Resources` has assets, `*.lproj/InfoPlist.strings` (permission strings), Swift helpers and `AppShortcuts.xcstrings`, which holds only the Siri phrases of `Features/Assistant/AssistantShortcuts.swift` because App Shortcuts read phrases from no other catalog.
- `Features/Assistant/SiriAIPreview/` holds the Siri AI developer preview: the intents Siri's model may call as tools and one app skill. It compiles in Debug builds made with Xcode 27.3 or later, never in Release and never with Xcode 27.2. Read [the preview guide](docs/SIRI_AI_PREVIEW.md) before changing that folder, an assistant intent's title or description, or an assistant entity.
- The marketing version is in `ios/Version.xcconfig` and the build number is in `ios/BuildNumber.xcconfig`.
- To find a screen from its visible text, run `bun run ios:l10n:search -- "<text>"`, then search Swift for the generated camelCase symbol, not the dotted key (see [localization](docs/AGENT_LOCALIZATION.md)).
- `Features/Schedule` is the shifts tab. `ScheduleViewModel.swift` defines `ShiftsViewModel`, and `Components/ScheduleCalendarView.swift` defines `ShiftsCalendarView`.
- `Features/Stats` is the Stats tab. The tab stays alive behind the other tabs, so `StatsView` lists every outside change that reloads it in one place: `statsDataChanges` and the two `onChange` handlers after it. Add a new source of Stats data there. While another tab is selected, `StatsViewModel` holds the reload until Stats shows again. Stats shows a month or a year. `MainTabView` owns the `StatsPeriod` and shows `StatsPeriodPicker` beside the floating pill, in the same row, and the pill shows `StatsYearPicker` in year mode. `StatsLattice` and `StatsYearLattice` turn the service's data into fixed slots, and `StatsContent` draws either page under the same hero. Every amount in both lattices is in the hero's tax basis, after tax when the user has tax on, so views never convert. Stats draws no comparison in red.
- The jobs list is `payChooserJobsSection` in `Features/Settings/SettingsView.swift`. `Settings/Pay/Components/AddJobSheet.swift` adds a job. `PaySettingsWorkplaceSheets.swift` is only a workplace picker.
- Friends chat is in `Features/Friends/Messages/`. `FriendsThreadView.swift` handles layout and the footer accessory. `FriendsThreadExyteChat.swift` owns the Exyte `Chat` viewport bridge. `FriendsThreadChatGestures.swift` handles navigation and timestamp gestures, `FriendsThreadChatProjection.swift` builds the row projection, and `FriendsThreadExyteMessageFactory.swift` maps messages into the fork. `FriendsThreadComposerView.swift` and `FriendsComposerAttachmentController.swift` hold the composer. The table and insets are in `../Chat/Sources/ExyteChat/Views/UIList.swift`. `UIList.updateInsets` turns the height of the view between the list and the composer into the table's `contentInset`, so anything there that appears or changes height while the user scrolls stalls the scroll for a moment. Keep that view at zero layout height and put scroll-dependent content in an overlay, as `chatFooterAccessory` does with the scroll-to-latest button.
- Two parts set tab bar visibility: `isChatTabBarHidden` in `Features/Friends/FriendsView.swift` and `addShiftRoute(on:path:hidesTabBar:)` in `Features/AddShift/AddShiftNavigator.swift`. Two `.toolbar(_:for: .tabBar)` modifiers on one view conflict. Extending the chat list behind the tab bar has been tried and dropped.
- Design tokens are in `Shared/`: `Spacing.swift`, `CornerRadius.swift`, `Typography.swift`, `MotionTokens.swift` and `Extensions/Color+Tidex.swift`. `MonthYearPickerSheet` is in `Shared/Animations/MonthTransition.swift`.
- `Storage/Testing/DesignReviewView.swift` holds the design-review screens. None of them shows a chat thread, the composer or the attachment drawer.
- After a build, SwiftPM checkouts are at `~/Library/Developer/Xcode/DerivedData/Tidex-*/SourcePackages/checkouts/`. Don't `find /` for them. If that folder is empty, read the Chat fork in `../Chat`.

## Local storage

`Storage/LocalStoreSchema.swift` defines `SchemaV1` and `LocalStoreMigrationPlan`. Before changing a persisted model, preserve the released model definitions under their versioned schema, add `SchemaV2`, and append a V1-to-V2 migration stage to the plan. Keep V1's entity names and stored properties unchanged. Every persisted schema change needs a version and stage, including additive fields, renames, type or optionality changes, constraints and relationships. Use a lightweight stage when SwiftData can preserve the data itself, and a custom stage when values need conversion or backfilling. Test an on-disk upgrade with dirty rows, pending deletes and queued messages. A failed store must stay on disk, with editing and sync blocked until it opens again.

## State

Model a lifecycle as one enum whose cases carry their data, so contradictory flag combinations cannot exist. When a new `Bool` or optional would have to change together with an existing one, write the enum instead. Copy these:

- `SyncOutcome` in `Storage/Sync/SyncResultModels.swift` says how an operation ended. Callers switch on it instead of comparing error strings.
- `Presentation` in `Features/Celebration/ShiftCompletionCelebrationManager.swift` holds a sheet's idle, showing and dismissing states. Dismissing exists because a sheet binding turns false before its `onDismiss` runs.
- `LoadState` in `Features/Schedule/Components/SendShiftToChatSheet.swift` separates a failed load from an empty one.
- `SyncStateStore` with `SyncStartDecision` is an actor with a generation counter, for work an account switch must cancel.

A singleton that holds per-user state gets a `resetForUserChange()` that `clearAllCachedData` in `App/AppCoordinator.swift` calls.

## Project file

App and extension folders are synchronized groups. `ios/Shared` is synchronized into the app, share extension and Siri target, while the widget and notification service include selected Shared files through per-target `membershipExceptions` lists in `project.pbxproj`, so add new dependencies there explicitly. `TidexAppTests` and `TidexAppUITests` are the exceptions. A new test file needs a `PBXBuildFile`, a `PBXFileReference`, a group child and a Sources entry in `ios/Tidex.xcodeproj/project.pbxproj`. Copy the pattern of an existing test file. A file without them never compiles or runs, and nothing warns you. Seven test files sat outside the target from September to October 2026. This prints any test file missing from the target:

```bash
for f in ios/TidexAppTests/*.swift ios/TidexAppTests/*/*.swift ios/TidexAppUITests/*.swift; do grep -q "/\* ${f##*/} in Sources \*/" ios/Tidex.xcodeproj/project.pbxproj || echo "$f"; done
```

## SwiftLint baseline

Run `swiftlint --quiet` from the repository root, or the baseline is skipped. The baseline matches violations by content. When a file grows, its old length or complexity warnings can show up again. Treat only new rule hits on lines you changed as yours. Don't copy old file versions to temporary files to compare.

## Backend access

Use the existing `ConvexAPI` client for queries, mutations and actions, and `ConvexRealtime` for subscriptions. Clerk provides the session token. Keep authorization and privileged operations in `backend/convex/`. Inspect the affected service and handler before choosing a route. Administrative deployment keys stay out of the app.

Supabase remains only for the legacy GoTrue session refresh during the N-to-N+1 exchange. New app features use Convex. Backend and deployment guidance is in the root AGENTS.md.

## Tests

[Tests](../AGENTS.md#tests) in the root AGENTS.md says when to add a test and which kind. On iOS:

- `TidexAppUITests` holds the end-to-end journeys. Launch with `-ui-testing` and `TIDEX_UI_TEST_SCENARIO=app-store-screenshots` to get the real `MainTabView` on an in-memory store that `AppStoreScreenshotFixture` seeds, with Supabase pointed at an unreachable address. `design-review` opens single screens (`TIDEX_DESIGN_SCREEN`), and `friends-chat` opens a thread with the real repository and a fake service. The fixture seeds shifts in the current month, so derive dates from today. A month name written into a test breaks the next month.
- `TidexAppTests` holds the integration tests and the unit layer. `TestSupport/TestFixtures.swift` builds wage snapshots, shifts, jobs and computed shifts.

Handoff: name any test you added and the rule that called for it, confirm new test files have `project.pbxproj` entries (see "Project file"), run `swiftlint --quiet` and the tests that cover the change, and report what you ran and the result.

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

## Accessibility

Tidex claims the Dark Interface and Reduced Motion accessibility labels in App Store Connect, and Hjalmar reviews those claims. Keep new work inside them:

- Gate movement animations on `accessibilityReduceMotion` through `MotionTokens`.
- Check a changed animation with `scripts/motion-check report`, as [Motion](docs/AGENT_VERIFICATION.md#motion) describes.
- `SemanticColorContrastTests` checks that text colors pass 4.5:1. Add a new text color pair there.
- Calendar month grids cap their text at `.xxxLarge`, as the system Calendar does. At accessibility text sizes the Shifts tab defaults to list view.
- A trailing `.accessibilityHidden(true)` does not hide a view that makes itself an element with `.accessibilityElement(children: .ignore)`. Use `.calendarDayAccessibility(isHidden:)` from `Shared/Components/Calendar/CalendarGridHelper.swift`, or skip the element setup when the view is hidden.

## Project Documentation

See `ios/docs/` for more details:
- `ARCHITECTURE.md` - App architecture overview
- `DATA_FLOW.md` - Data flow patterns
- `LOCALIZATION.md` - Localization details
- `LIQUID_GLASS_FINDINGS.md` - iOS 26 Liquid Glass findings
