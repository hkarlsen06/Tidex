# iOS 3.1.2 release status

Version `3.1.2`, build `20261109.2324`, was withdrawn at Hjalmar's request on November 10 before publication. Apple confirms `DEVELOPER_REJECTED`, and the review submission is `COMPLETE`. Release remains `MANUAL`, with no phased release. The app has not been published. Do not resubmit this build while the Friends time-zone issue is unresolved.

The original submission was accepted at `2026-11-09T22:44:58.943Z`. Withdrawal was independently verified at `2026-11-09T23:37:58.212Z`, November 10 in Europe/Oslo. Private receipts are `review-withdrawal.json` and `withdrawal-verified.json` alongside the final archive.

The build was archived from signed commit `e5544021`. Its archive, exports and Apple binary validation passed. It includes the offline Schedule and failed-first-sync fixes. Both focused device retests passed on Depressed Harbor. Earlier builds `20261109.2113` and `20261109.2228` were not submitted.

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

Final App Store validation with public URL checks and the attached IPA reports zero errors or blockers and no metadata warnings. Manual release after approval is retained. Deep validation reports one warning because no cached Apple web session is available. App Privacy publication remains unverified through the public API. Apple accepted the review submission.

Final build `20261109.2324`, ID `1389b554-fe22-4905-a754-fadb1eef1895`, replaced build `20261109.2228` on the submitted version. Review submission ID is `bda67e96-4594-41f6-a957-3967410da1d0`. Only the existing internal TestFlight group containing Hjalmar's account was added. Automatic tester notifications are disabled.

The metadata source had a stale comment saying that the generator writes TXT files. It now describes the native asc JSON output.

## Friends time-zone release hold

Hjalmar reported that at 00:30 in his time zone, a friend's 05:00 shift in Great Britain showed a four-and-a-half-hour countdown. With the stated one-hour difference, that shift starts at 06:00 for him and is five and a half hours away. The withdrawn build interpreted the stored clock time using the viewer's calendar. Its shared payload carried no schedule time zone.

The admin zone follows the phone. A fixed, owner-editable sharing zone was chosen after market research and Fable 5.2 review, so travel cannot silently move an established schedule. The backend initializes it once from valid reported data. Friend previews and widgets use the viewer's zone, while calendar dates and payroll grouping keep the schedule's zone. Both times are labelled when they differ. The full decision and evidence are in [Friends time zones](friends-time-zones.md).

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

A device readback confirmed build `20261109.2113`. A read-only preferences copy confirmed that `auth.currentUser` remained marked as impersonation, with a different actor and presented user. This failed candidate was not submitted.

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

Before the fix, the new regression failed with `Schedule could not reload its owner's local shifts without a fresh token: notSignedIn`. The separate stored-impersonation check passed. After the fix, all 73 focused auth, local loading, Add Shift, sync and shift UI tests passed on Shared iPhone. The final six loading tests also passed after removing a lint warning from the test setup. Sol review found no issues. Lint reports no errors and retains the existing Schedule file-size, complexity and naming warnings. The final combined archive and its device save/display retest passed, as recorded below.

## Failed first sync

On build `20261109.2228`, Hjalmar signed out after syncing, enabled Network Link Conditioner's Edge profile and signed back into his own account. When Home showed its loading skeleton, he switched to `100% Loss`. Home then showed the job-setup placeholder instead of a sync error and Retry. His screenshot shows the setup card and action with no visible sync warning. Disabling the conditioner restored his existing jobs, shifts and totals without setting up a new job. Recovery passed, but the failed-sync presentation did not.

The old coordinator marked the initial sync complete even when the sync timed out or failed. Work setup then treated an incomplete local cache as an account without jobs. The archive containing only the Schedule fix was stopped during export after this result. Both fixes are included in the submitted build.

The new Home UI test reproduced the same setup prompt before the fix and failed because Retry was absent. Full-sync completion is now recorded separately from finishing an attempt and belongs to a specific user. Failed and targeted downloads cannot confirm that jobs are missing. A successful full retry can confirm that state, and a failed later refresh keeps an already established local account usable. The offline indicator also offers Retry while initial data remains unconfirmed. That UI regression now passes.

Sol review found a completion race across account resets. The completion write now receives the reset generation captured when its sync started. A stale completion cannot replace the current account's successful sync. All 80 final auth, loading, work-setup, sync and shift UI tests passed on Shared iPhone, including the failed-first-sync UI check. Lint reports no errors and one existing UI test class-size warning. The combined archive and both device retests passed, as recorded below.

Without the generation guard, the new regression failed with `A late completion made the current account look unsynced`. Adding the guard rejects that previous account's completion at the write itself.

## Final combined archive

Build `20261109.2324` uses signed commit `e55440215e50193b1f9f848275b42d9c5e0fe566`. Archive and exports completed through the shared Xcode wrapper in 210, 25 and 20 seconds. Apple binary validation passed in 67 seconds. There were no build warnings or errors, source drift or unrelated-file drift.

The App Store and ad hoc exports passed strict signatures and distribution profiles for the app and all four extensions. Version, build and executable UUIDs match the archive. The device export includes Depressed Harbor. The exported app uses production Clerk, Convex and APNs configuration, with debugging disabled. The archive itself uses development signing before distribution export.

The App Store IPA SHA-256 is `28c91617e2777b2cbb5989c92accf9edbf3d47ee14477cd51b9583b127de5212`. Artifacts and private receipts are in `/Users/hkarlsen06/Library/Developer/TidexReleases/3.1.2-20261109/combined-offline-fix/`. An in-place install and independent device readback confirmed version `3.1.2`, build `20261109.2324`. The existing app was not deleted. Metadata validation still passes.

Hjalmar repeated both connection checks on this build. With `100% Loss`, a newly added shift appeared in Schedule immediately, survived a full offline relaunch and had no duplicate after reconnecting. For first sign-in, he repeated the Edge-to-`100% Loss` interruption. Error or Offline offered Retry, and his existing jobs, shifts and totals returned after reconnecting. Both retests passed.

The App Store upload was committed at `2026-11-09T22:30:46Z`, upload ID `1389b554-fe22-4905-a754-fadb1eef1895`. Apple processed it as `VALID`. The separate validation placeholder is not the committed binary upload. Private submission, preflight and independent readback receipts are stored with the final artifacts.

The owner-side comparison of shared overlapping shifts and overtime gross/net totals remains unverified in `RELEASE_CHECKS.md` before manual release. The lower-level 20-second auth request deadline is covered by automated tests; the device stall check confirmed immediate cached presentation rather than measuring that request directly. Review submission does not publish the app or close those records.

## Replacement time-zone candidate

The additive backend change is signed on main as `a07b1e87`. Five backend handler tests with 35 assertions passed, as did backend and marketing TypeScript checks. The local Convex runtime accepted the backfill, initialized 37 valid zones among 38 activity rows, and reported zero eligible rows when repeated. On November 10, Hjalmar approved production deployment, the set-if-absent backfill and the date-only privacy publication. The backend deployment succeeded. The backfill initialized 72 profiles after one account was initialized by a concurrent activity report. All 73 accounts with registered zones now have fixed zones, and a repeat preview found zero eligible records. The production auth smoke check passed.

The client correction is signed on main as `ed4e0485`. Hjalmar observed that the new client shows "Schedule" for every friend and an unknown-zone caption in their calendars. A read-only production inventory confirmed the cause before deployment: the new schedule-zone functions were absent, none of the 284 profiles had a fixed schedule zone, and 73 activity records already contained registered zones. The deployment and set-if-absent backfill described above corrected that missing production data. Do not add a device-local guess to conceal the missing backend.

Fable 5.2 agreed with the fixed-zone choice. Its implementation review found formatting, widget layout, VoiceOver and failed-setting-load defects, which have been corrected. Shared clocks retain the existing HH:mm convention. The iOS wrapper passed 48 focused tests and the expanded cross-zone Friends UI journey. The footer layout then passed the UI journey again. Depressed Harbor was locked, so these runs used Shared iPhone. Normal and maximum-text-size cards were inspected, and accessibility labels include both times. Both friend widgets were rendered with a cross-midnight shift. A clipped source caption in the small widget was corrected and rechecked. The final wrapper build passed with zero warnings or errors.

Release notes were extended from the withdrawn candidate at `e5544021`, after the published App Store 3.1.1 build `20261106.0018`. The new notes cover time zones, the fixed sharing setting, month swipes and friend-chat navigation. All 32 locale files were regenerated, only their whatsNew fields changed, and local metadata validation reports zero errors or warnings. These replacement notes have not been uploaded to App Store Connect.

Hjalmar chose a date-only privacy update on November 10. English and Norwegian policy display dates are November 10; the canonical acceptance manifests remain unchanged. The privacy disclosure was published to tidex.no through Cloudflare Pages deployment 5d0845b0 and read back in both languages. All three acceptance manifests still match their unchanged local copies. Build 2324 stays withdrawn. The replacement archive below is local, and review resubmission remains pending.

Hjalmar refreshed Friends after the production change and confirmed that registered friends regain next-shift cards and the UK shift shows 06:00 viewer time beside 05:00 shift time. Three incoming accounts have no registered zone and remain unknown. He then requested a Fable 5.2 UI review with autonomy to fix the detail-sheet title colliding with Your time, and proposed a Your time / Their time picker above the Hours/Earnings picker. That UI pass is complete, with the local candidate below awaiting his visual review before upload.


## Reviewed UI candidate on Cold Harbor

Release build `20261110.1548` was archived from signed main `62c31e09`, including Fable 5.2 commits `ec692ffb` and `de1b04df`. The Your time / Their time picker sits above Hours/Earnings and moves displayed shifts to their correct local dates. The other clock is inside the shift-details header card, clear of the navigation title. Cards and widgets use a globe beside converted clocks. All 40 focused date, ordering and UI checks passed before archiving. Normal and maximum-text-size renders were inspected.

The archive and App Store and ad-hoc exports succeeded through the shared Xcode wrapper in 235, 25 and 19 seconds, without warnings or errors. All 304 local signature, profile, endpoint, version, UUID and source-integrity checks passed. The parent independently checked the archive's version and deep signature and both IPA hashes. The Release compiler inputs exclude the Siri AI preview. The inherited catalog and project edits, untracked work and staging state have no drift.

An in-place installation on Cold Harbor independently reports `3.1.2 (20261110.1548)`. The app was not uninstalled or launched, and no data reset was performed. Hjalmar is awake and requested an app review before upload, so the candidate remains local. No remote binary validation, upload, submission or release has been performed for this build.

Artifacts and verification receipts are in `/Users/hkarlsen06/Library/Developer/TidexReleases/3.1.2-20261109/friends-time-zones/ui-reviewed-candidate/`. The App Store IPA SHA-256 is `dc5b1817e94e7da90e715bfd7d8f43c5ee6576dc29c05a415181d0ce5da332a5`; the ad-hoc IPA SHA-256 is `c2098cfec2c3ebd916738652aea1b16bacb8f6feb0d21b09017090576213a772`.

## Shared calendar layout correction

Hjalmar reviewed build 20261110.1548 and requested actual code reuse between the Friends calendar and Schedule. Both now use the same calendar page layout, bottom control stack and adaptive picker. When both controls are available, Your time / Their time sits above Times / Earnings and both sit above the month picker. The globe on a friend card now sits beside the converted start clock, rather than beside "Tomorrow".

All three focused Schedule and Friends UI tests passed on Shared iPhone. The rendered checks cover a six-week November with both controls, a 320-point fixture at the largest accessibility text size and the card's globe placement. Sol's selection-state finding was corrected by keeping one calendar instance across layout changes. Existing journeys cover this layout change; no new tests were added.

A replacement local Release candidate will be installed over Tidex on Cold Harbor without deleting its data. Build 1548 is superseded for UI review. No upload, remote binary validation, submission or release is authorized before Hjalmar reviews the corrected layout.
