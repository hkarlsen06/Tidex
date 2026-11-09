# iOS 3.1.2 release preparation

Build `20261109.2228`, archived from signed commit `4f8243a7`, passed the device privacy retest. Its archive and both exports passed without warnings or errors, and Apple binary validation passed. Subsequent connection checks exposed delayed Schedule updates after local saves and incorrect job setup after a failed first sync. Both fixes require a new archive and device retests before submission. The earlier build `20261109.2113` failed the privacy check and must not be submitted.

Hjalmar clarified that his earlier decision deferred further Siri checks only. The Admin offline-refresh, Schedule Copy and calendar hint checks passed during release preparation. [RELEASE_CHECKS.md](../RELEASE_CHECKS.md) records the remaining checks. Keep that file until the release ships.

After the connection checks, Hjalmar also deferred the extra-phone checks for queued messages across another 3.1.1 upgrade and smaller physical iPhone layout. These remain unverified. That decision does not mark the two newly discovered offline failures as passed.

## Metadata

- Uploaded the current release notes in all 32 App Store locales.
- Removed keywords that repeated subtitle terms in 15 locales.
- Updated App Review notes to include the calendar, Home, Spotlight and Live Activity changes.
- Read back all 32 listings and verified that every managed field matches the local JSON.
- Verified that App Review credentials and contact details remain unchanged.
- Confirmed that all 330 screenshots in 66 sets have individual delivery state `COMPLETE`.
- Inspected representative English and Norwegian iPhone, iPad and Duo artwork.

App Store validation with public URL checks and the attached IPA reports zero blockers and no metadata warnings. The draft retains manual release after approval. Deep validation reports one warning because no cached Apple web session is available. App Privacy publication remains unverified through the public API.

The corrected build ID is `6ee2c937-7991-46e7-a11c-d5cd608a3337`. Apple processing is `VALID`, and this build is attached to the 3.1.2 draft in place of build `20261109.2113`. It is available to the existing internal TestFlight group containing Hjalmar's account only. Automatic tester notifications are disabled. No App Review submission has been created.

The metadata source had a stale comment saying that the generator writes TXT files. It now describes the native asc JSON output.

## Initial binary and verification

The initial build `20261109.2113`, Apple build ID `c6e36a7d-5f14-48cc-afa8-4df6a444cdc7`, was archived and exported through `scripts/xcode-build-agent.sh` with actions `archive` and `exportArchive`. Both succeeded without warnings or errors. The export preserves the archive's version and build number. The corrected candidate is documented below.

The IPA and all four extensions passed strict signature checks. They use App Store provisioning profiles for team `48ZSLD4RMP`, with debugging disabled. The app uses production Convex and Clerk configuration and the production APNs environment. The minimum supported system is iOS 26.0, and the IPA supports iPhone and iPad.

The IPA SHA-256 is `264a693ae0a170f5eff0b26e1204e947b00935dfc668193287ea7758e63ed0a3`.

Existing tests ran through `scripts/xcode-test-agent.sh`:

- All 56 tests passed on Cold Harbor across `AssistantPrivacyTests`, `AssistantEarningsTests`, `AppGateTests`, `HomeScheduleLoadingHelperTests` and `SyncOfflineBehaviorTests`.
- All three UI tests passed on Shared iPhone. They cover adding and deleting a shift, the Add layout after selecting a date, and the Schedule tab's return-to-today behavior.
- Local metadata validation passed with no warnings or errors.
- The production `auth-smoke.sh` check passed.
- The initial SwiftLint run exited successfully with 272 existing warnings and no errors. Initial preparation changed no Swift code. The privacy fix below adds eight regression tests in the existing auth and calendar-subscription test files.

The archive uses app source at `aa09a692` and the pre-existing Xcode project and string-catalog edits in the main checkout. Those unrelated edits remain uncommitted. Release metadata is committed as `9eff64fb`.

Private artifacts and receipts are in `/Users/hkarlsen06/Library/Developer/TidexReleases/3.1.2-20261109/`. The archive is `Tidex-3.1.2.xcarchive`, and the IPA is `export/Tidex.ipa`.

## In-place upgrade check

Depressed Harbor initially had App Store 3.1.1, build `20261106.0018`. Hjalmar cached a friend's shared month, synced two temporary shifts, then went offline, edited one shift and deleted the other. He could not queue a test message, so message preservation across the upgrade remains unverified.

The ad hoc export from the same release archive installed over the existing app without an uninstall. A device readback confirmed 3.1.2, build `20261109.2113`. iOS blocked the first launch because the ad hoc distribution certificate required online verification. Tidex had not opened, so that result does not indicate a store-migration failure.

The phone has no cellular service and no developer-verification entry in Settings. Hjalmar replaced the unopened ad hoc installation through TestFlight, keeping Tidex closed during the download and disconnecting before its first launch. He confirmed that Tidex opened offline with the edited shift, pending deletion and friend's cached shifts and pay totals preserved. After reconnecting, refreshing Friends and relaunching, the data and totals still matched. The edited shift and deletion also matched on Cold Harbor, with no duplicates. The shift-edit, deletion and shared-cache upgrade checks passed.

## Expired-impersonation failure

Hjalmar loaded a test account on Depressed Harbor using the reason `Release 3.1.2 offline expiry check`, fully swiped Tidex away and disconnected the phone. The existing production `impersonation:expire` handler ended only that labelled session at `2026-11-09T20:45:30.454Z`, without a deployment or changes to the target account's data.

On the first offline reopen, the target account's data remained visible and usable. A second force-close and reopen blocked on the Norwegian session-timeout screen. Hjalmar confirmed that he had fully closed the app before the first reopen and that the visible data was not just a launch snapshot.

A device readback confirmed build `20261109.2113`. A read-only preferences copy confirmed that `auth.currentUser` remained marked as impersonation, with a different actor and presented user. The candidate remains unsubmitted.

The device log identifies the first failing return as a resumed process. PID `27123` logged at `21:40:33` and again at `21:45:42`, when the foreground session check failed offline and kept the authenticated screen. The subsequent blocked launch used PID `27214`. These times are Europe/Oslo on 2026-11-09. After reconnecting, Hjalmar confirmed that Retry restored his own account with no impersonation banner.

The fix invalidates remote identity verification across lifecycle transitions and hides impersonated presentation until the current activation verifies the identity. It also rejects presentation from a session resolved before that invalidation. Session checks share the existing update token, and transient recovery requires a local identity matching the displayed account. Calendar-subscription state resets when the verified account changes, including persisted state from another owner. Stored normal-user identity and local rows remain available offline.

With lifecycle invalidation disabled, the new tests failed with `An offline activation reused the impersonated account` and `A lookup from the previous activation restored the impersonated account`. Both returned a target session where none was allowed. With the old retry policy and calendar-owner behavior, the additional regressions exposed an authenticated fallback for the target and retained target calendar metadata and fallback URL.

After the fixes, all 89 focused auth, privacy, Home, calendar-subscription, shared-token, sync and calendar UI tests passed. Lint reports no errors. The auth-manager complexity warning predates this fix. The auth manager and two test files exceed their size guidelines. The corrected archive and device retest passed.

## Corrected archive

Build `20261109.2228` uses commit `4f8243a789bfaf13867b817d185dee35664f9a96`. Archive and exports completed through the shared Xcode wrapper, with no build or export warnings or errors. Source hashes did not change during the build. Both exports passed strict signature, profile, endpoint, entitlement, version and executable UUID checks. Apple binary validation returned `VERIFY SUCCEEDED with no errors`.

The App Store IPA SHA-256 is `0439d81f3c41cea03e9285dfbcd876ca9ec5935ca7b6adc6f0ca92cd842e4510`. The corrected artifacts and receipt are in `/Users/hkarlsen06/Library/Developer/TidexReleases/3.1.2-20261109/privacy-fix/`. The ad hoc export installed over the existing app on Depressed Harbor, and a device readback confirmed build `20261109.2228`.

Apple processed the corrected build as `VALID`, and it replaced the original build on the 3.1.2 draft. Final validation against the corrected IPA reports zero blockers. The only warning remains the unavailable cached Apple web session. Manual release is unchanged.

For the retest, Hjalmar loaded the same test account with reason `Release 3.1.2 offline expiry retest`, returned to the Home Screen without terminating Tidex, and disconnected the phone. The existing server handler expired only that session at `2026-11-09T21:42:27.536Z`. He confirmed that the target data stayed hidden on the first return, Retry and a full force-close and reopen. Reconnecting restored his own account. The privacy retest passed.

## iPad layout

On TestFlight build `20261109.2113`, Hjalmar checked November and December in portrait and landscape. The month picker, calendar and action bar remained reachable without clipping or overlap. Add Shift's time fields and save action stayed usable with the keyboard visible. He also confirmed that the narrowest available window and largest text size remained usable. The privacy fix does not change those layout implementations. The iPad layout checks passed.

## Stalled-network Schedule updates

On build `20261109.2228`, Hjalmar closed Tidex for two minutes, left Wi-Fi connected and enabled Network Link Conditioner's `100% Loss` profile. His own cached data appeared immediately. Add Shift cleared after saving, but Schedule did not display the new shifts until the conditioner was disabled. There was no visible error while the shifts were missing. The immediate cached launch passed, but this result does not measure the session request's 20-second deadline.

The repository writes each shift locally before starting background sync. Schedule then clears its cached user ID on a local reload and asks for a fresh session before reading those rows. Home already uses the stored normal-account identity for local reads. Schedule now uses the same guard. Stored impersonated identities still require remote verification.

Before the fix, the new regression failed with `Schedule could not reload its owner's local shifts without a fresh token: notSignedIn`. The separate stored-impersonation check passed. After the fix, all 73 focused auth, local loading, Add Shift, sync and shift UI tests passed on Shared iPhone. The final six loading tests also passed after removing a lint warning from the test setup. Sol review found no issues. Lint reports no errors and retains the existing Schedule file-size, complexity and naming warnings. The corrected archive and a repeat of the device save/display check remain pending.

## Failed first sync

On build `20261109.2228`, Hjalmar signed out after syncing, enabled Network Link Conditioner's Edge profile and signed back into his own account. When Home showed its loading skeleton, he switched to `100% Loss`. Home then showed the job-setup placeholder instead of a sync error and Retry. His screenshot shows the setup card and action with no visible sync warning. Disabling the conditioner restored his existing jobs, shifts and totals without setting up a new job. Recovery passed, but the failed-sync presentation did not.

The coordinator marks the initial sync complete even when the sync times out or fails. Work setup then treats an incomplete local cache as an account without jobs. The archive containing only the Schedule fix was stopped during export after this result. Both fixes will be included in the next candidate.

The new Home UI test reproduced the same setup prompt before the fix and failed because Retry was absent. Full-sync completion is now recorded separately from finishing an attempt and belongs to a specific user. Failed and targeted downloads cannot confirm that jobs are missing. A successful full retry can confirm that state, and a failed later refresh keeps an already established local account usable. The offline indicator also offers Retry while initial data remains unconfirmed. That UI regression now passes.

Sol review found a completion race across account resets. The completion write now receives the reset generation captured when its sync started. A stale completion cannot replace the current account's successful sync. All 80 final auth, loading, work-setup, sync and shift UI tests passed on Shared iPhone, including the failed-first-sync UI check. Lint reports no errors and one existing UI test class-size warning. The combined archive and device retests remain pending.

Without the generation guard, the new regression failed with `A late completion made the current account look unsynced`. Adding the guard rejects that previous account's completion at the write itself.
