# Tariff implementation verification

Checked 6 November 2026 on `feat/tariff-catalogue-and-payroll`.

## Automated results

| Check | Result |
| --- | --- |
| `bun run --cwd backend typecheck` | Passed |
| `bun test backend/scripts` | 48 tests passed, zero failures |
| `bun backend/scripts/tariffs.ts validate` | 48 choices and 548 categories validated |
| Focused payroll and tariff service tests | 47 tests passed, zero failures, Shared iPhone |
| Final `PayrollEngineOvertimeTests` recheck | 22 tests passed, including the new override regression, zero failures |
| `PayrollEngineConflictOvertimeTests` and all `ShiftJourneyUITests` | Eight tests passed, zero failures, Shared iPhone |
| `swiftlint --quiet` | No errors. Existing file, type, and closure size warnings remain. |
| `bun run ios:l10n:validate` | Passed, including translations of the four new strings |
| `bun run ios:l10n:audit` | Passed with the repository's unused-key report |
| `git diff --check` | Passed |

The final 47-test payroll run compiled in 42 seconds and tested in 14 seconds. It included `PayrollCalculatorBehaviorTests`, `PayrollEngineOvertimeTests`, and `TariffVersionServiceTests`. The eight conflict and UI tests compiled in 14 seconds and tested in 136 seconds. The final review added one overtime override regression. The focused overtime class was rerun after that fix, compiling in 34 seconds and testing in 15 seconds. The dated editor screenshot journey also passed again against the final catalogue export. Across these runs, 56 distinct Swift tests passed.

The new tests cover pay outcomes, date decoding, preservation of rule metadata, legacy behavior, offline agreement matching, extra categories, and saving a real pay editor with dated overtime rules. Existing shift and payment journeys also passed. No new test files were added to the Xcode project.

Cold Harbor compiled successfully but was locked when Xcode tried to launch tests. Testing moved to a shared simulator. The existing payment journey emitted an invalid-frame runtime warning while passing. Its payment layout was not changed by this work.

The additional pay-editor fixture initially rendered an empty group before its loading task could run. The test failed on the missing editor. Giving the loading state a real progress view fixed the fixture, and the same test passed without weaker assertions.

## Local and production reads

After the final catalogue corrections, the local Convex deployment at `http://127.0.0.1:3210` was updated with the branch's functions. Actual HTTP queries verified:

- A reviewed catalogue request returns 48 choices.
- A request without `catalogue_revision` still returns the original five database choices.
- Riksavtalen includes expanded categories and the correct youth label.
- An unknown catalogue revision is rejected.
- Public access to the internal maintenance inventory is rejected.

The public production catalogue comparison completed with 48 differences and `writes: 0`. No production functions were deployed, no user wage inventory was read, and no production data changed. Internal wage inventory requires the exact App Review account UUID as an exclusion. That account was not identified during this task.

Private proposal files are created exclusively with owner-only permissions. Tests prove that reruns do not overwrite an existing file, directory symlinks cannot redirect output outside temporary storage, and file symlinks cannot overwrite another target.

## Screenshots

Screenshots use public tariff data in debug fixtures and production UI components. They contain no customer accounts or wages. The menu container could not be tapped through `agent-device`, including its suggested child control. Manual driving stopped. XCUITest generated the remaining screenshots during passing selection journeys.

| Screen | Evidence |
| --- | --- |
| Hotel agreement, English, dark | [Screenshot](screenshots/tariff-hotel-en-dark.png) |
| Hotel seniority category | [Screenshot](screenshots/tariff-seniority-selection.png) |
| Security schedule, Norwegian, light | [Screenshot](screenshots/tariff-security-nb-light.png) |
| Security qualification included in pay | [Screenshot](screenshots/tariff-security-qualified.png) |
| Municipal category at the largest accessibility text size | [Screenshot](screenshots/tariff-ks-en-large.png) |
| Calendar overtime rules in the pay editor | [Screenshot](screenshots/tariff-calendar-overtime.png) |

## Rollout limits

Deploy the backend before releasing the new client. New clients request `catalogue_revision: 2026-11` and send `payroll_revision: 2026-11` through sync and earnings sharing. Rich rows are rejected for older readers and writers, including writes to a job whose wage snapshots need the newer engine. Legacy-only jobs keep their existing API contract. An older device may need an app update after another device saves reviewed rules for the same job.

Existing snapshots are not migrated automatically. The maintenance command produces a private, revision-checked proposal. Historical compensation requires a separate approved transaction and a review of the settlement's exclusions.

[Coverage notes and unresolved input requirements](maintenance.md#supported-estimates-and-explicit-limits) describe daily and work-plan overtime, KS night extensions and rota overtime, employer-specific Spekter agreements, and shipyard shift allowances. These are not complete payroll implementations and must not be described as such in release notes.

## Independent review

The Sol review identified seven confirmed issues. The fixes separate apprentice pay rules, retain Handel holiday-eve pay during overtime, halve security apprentice additions, correct energy-station time boundaries, apply the Riksavtalen night-guard holiday exception, remove a teaching-only KS salary band, and send the payroll capability through both Friends realtime subscriptions. Backend regression examples now cover these monetary outcomes. A second Sol review found that an explicitly empty per-shift supplement override could restore a removed addition during overtime. The new regression reproduced 489.50 instead of 293.70 before the fix. All three engines now honor that empty override.

The separate Claude decision-trail review failed with `Claude API rate limit reached. Try again later.` It did not complete, and no alternate provider was substituted.
