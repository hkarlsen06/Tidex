# iOS 3.1.2 release preparation

Version 3.1.2, build `20261109.2113`, has a signed Release archive and an App Store IPA. Apple binary validation passed without errors on 2026-11-09. Apple processed the upload as `VALID`, and the build is attached to the 3.1.2 draft. A failed expired-impersonation privacy check blocks submission. This build must not be submitted while that failure remains unresolved.

Hjalmar clarified that his earlier decision deferred further Siri checks only. The Admin offline-refresh, Schedule Copy and calendar hint checks passed during release preparation. [RELEASE_CHECKS.md](../RELEASE_CHECKS.md) records the remaining checks. Keep that file until the release ships.

## Metadata

- Uploaded the current release notes in all 32 App Store locales.
- Removed keywords that repeated subtitle terms in 15 locales.
- Updated App Review notes to include the calendar, Home, Spotlight and Live Activity changes.
- Read back all 32 listings and verified that every managed field matches the local JSON.
- Verified that App Review credentials and contact details remain unchanged.
- Confirmed that all 330 screenshots in 66 sets have individual delivery state `COMPLETE`.
- Inspected representative English and Norwegian iPhone, iPad and Duo artwork.

App Store validation with public URL checks and the attached IPA reports zero blockers and no metadata warnings. The draft retains manual release after approval. Deep validation reports one warning because no cached Apple web session is available. App Privacy publication remains unverified through the public API.

The build ID is `c6e36a7d-5f14-48cc-afa8-4df6a444cdc7`. It is available to the existing internal TestFlight group containing Hjalmar's account only. Automatic tester notifications are disabled. No App Review submission has been created.

The metadata source had a stale comment saying that the generator writes TXT files. It now describes the native asc JSON output.

## Binary and verification

The archive and export ran through `scripts/xcode-build-agent.sh` with actions `archive` and `exportArchive`. Both succeeded without warnings or errors. The export preserves the archive's version and build number.

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

After the fixes, all 89 focused auth, privacy, Home, calendar-subscription, shared-token, sync and calendar UI tests passed. Lint reports no errors. The auth-manager complexity warning predates this fix; the added regressions take two existing test files over their size limit. A corrected archive and device retest remain pending.
