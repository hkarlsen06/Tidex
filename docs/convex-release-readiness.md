# N+1 review preparation, 2026-10-28

Version 3.1.0, build `20261028.1856`, is uploaded and processed as `VALID` and `APP_STORE_ELIGIBLE`. It is attached to the App Store draft for app `6757129790`. The draft has manual release, phased release disabled, updated notes in all 32 locales and inherited App Review credentials. All 170 screenshots across 34 sets are complete. The draft remains `PREPARE_FOR_SUBMISSION`. It has not been submitted or released.

The uploaded source is signed commit `2ae9d319`. Later migration and readiness changes do not change that binary. All implementation changes landed as signed local commits on `main`. Nothing was pushed.

## Fixes in the uploaded build

- Starting or ending impersonation syncs pending changes first and refuses to switch while changes remain unsent.
- User lookups and token fetches cannot publish results for a replaced Clerk session. Notification replies can resolve their sender after a cold launch.
- Account deletion has a 120-second request timeout and a 180-second resource budget. A real development deletion and a delayed 16-second transport probe both passed.
- APNs carries a neutral default alert. The extension restores the private presentation only for the current recipient and checks the account again before its callback. A mismatch or sign-out delivers no sender, message, thread, badge or reply action. A neutral Tidex alert can remain without Apple's filtering entitlement.
- The test wrapper builds iOS device products for a physical destination. Its destination-selection regression passes. The final run used a shared simulator because Cold Harbor was offline.

## Verification

The final focused suite passed 64 tests with zero failures on Shared iPhone, iOS 27.0. It included `OfflineAuthTests`, `SyncOfflineBehaviorTests`, `NotificationPermissionTests`, `FriendNotificationMessagePrefetcherTests`, `FriendsMessageOutboxTests` and `ShiftJourneyUITests`. The only compiler warning was the existing unused `userId` in `FeedbackSettingsViewModel.swift`.

The final notification extension source passed a simulator callback probe for recipient restoration, signed-out and wrong-account redaction, and an account switch before expiry. The backend neutral-presentation regression and TypeScript check passed. SwiftLint completed. The Release archive and App Store export passed without warnings. The exported app and all four extensions passed signature checks and used team `48ZSLD4RMP`, distribution profiles and production endpoints. Apple validation and upload completed without errors.

On 2026-10-28, Hjalmar confirmed that the N-to-N+1 offline retry, manual sign-in priority and unsynced-shift impersonation checks all passed on Cold Harbor. Physical APNs delivery remains unchecked in [the device checklist](../RELEASE_CHECKS.md).

The initial read-only account audit found ten accounts without a Clerk mapping, excluding the review demo. Four were phone-only, three used Apple without stored email, and three were unconfirmed email sign-ups. A phone-only account used 3.0.1 on 2026-10-20, and an Apple account used 2.7.1 on 2026-10-28. Both would fail the automatic exchange. Hjalmar accepted manual help for the phone-only account on 2026-10-28. Detailed account identifiers stay in the local audit at `/tmp/tidex-n1-readiness/session-exchange-audit.md`.

The importer now creates Clerk users for Apple accounts without email, using a stable internal username and Clerk's `skip_user_requirement` migration option. It supplies no invented email or password. A retained Apple provider subject is required for this path. Phone-only and unconfirmed email accounts keep their previous handling. Repeated imports reuse the Clerk user by its Supabase external ID. The migration-only username is separate from the public Tidex username.

The development test passed the complete automatic exchange with an email-less test token in GoTrue's format, Clerk ticket redemption, the original Tidex UUID and an existing shift. The deployed exchange verified the token against a temporary development signing key. Verified email imports, bcrypt passwords, address removal and repeated imports also passed against Clerk. All temporary accounts and test data were removed, and development signing keys were restored. Five focused backend tests and TypeScript checks pass.

On 2026-10-28, Hjalmar requested that email be optional. `Require email address` is now off in both Clerk instances. Independent public API readbacks confirm that email verification, Apple authentication and the other checked authentication settings are unchanged. A public sign-up without a verified identity still returns `missing_requirements`.

The fresh-session linking test passed against the deployed development backend and real Clerk sessions. With no email, the retained Apple subject linked a new Clerk user to the original Tidex UUID and its shifts. A second email-less account's shifts stayed private, repeated linking created one alias, and public clients could not call the internal linking function. The test supplied a synthetic Apple identity at the trusted server step after Clerk verification. It does not test Apple's authentication or Clerk's validation of a real Apple token. The active customer's source Apple subject also matches exactly one imported account, which retains its 57 shifts. Completing Apple authentication on that person's device remains untested. The report is `/tmp/tidex-n1-readiness/fresh-apple-verification.md`.

Local evidence is in `/tmp/tidex-n1-readiness/`. `archive-report.md` contains the full commands, results, artifact paths and device limits. `final-asc-state.json` records the attached build and draft settings. The IPA is `export/Tidex.ipa` and the archive is `Tidex-3.1.0.xcarchive` under that directory.

## Backend rehearsal

The fresh import matches every expected table count. It copied 258 Supabase accounts, linked 251 Clerk users, and copied 144 referenced message images and 12 profile pictures. The three Apple accounts without email now have mappings. Seven accounts remain unmapped, four phone-only and three unconfirmed email sign-ups. The old `before_paywall` field and the five retired purchase tables are gone. The App Review demo account still bypasses the new-device email code.

The post-fix audit checked all 257 non-demo accounts. All 250 mappings resolve to the correct existing Clerk user. The recently active Apple account retains its original UUID and all 57 original shift IDs match Supabase. No real customer's ticket was minted or session started for this verification. The full pre-fix snapshot and migration log are in `/tmp/tidex-rehearsal.kcJWlN/`.

The backend's old 768 MiB container cap caused memory reclaim, swap use and query timeouts during imports. The isolated Tidex Convex container now has a 2 GiB limit, and the full import completed after that change. Supabase and Paeonia were unchanged. The source compose backup is recorded in [the migration plan](convex-migration-plan.md#rehearsal-backend-memory).

Production Convex still has no `APNS_RECIPIENTS`, and the public gate remains `minimumVersion: 3.0.0`, `maintenance: false`. The existing app continues to use Supabase. Rehearsal phones must sign out and back in after updating to reset their sync cursors.

## Cutover preparation

[The command checklist](convex-cutover-checklist.md) covers backup, maintenance, write freeze, cron drain, final import, calendar and push switching, release and rollback. Both generated Caddy configurations validate with the server's real credentials. An isolated Caddy test passes 26 requests across both stages, including duplicate grant parameters. Only refresh and calendar requests reach their upstreams. No Caddy candidate was installed.

The migration plan and iOS guidance now describe Convex and Clerk, the merged implementation, the native Apple connection's credentials and the device wrapper's platform selection. The old Supabase descriptions and schema-blocker instructions were corrected.

Finish the device checklist before releasing. Submit the prepared App Store draft when ready, then wait for approval and Pending Developer Release. The production cutover still needs Hjalmar's approval.

## Release notes

English:

- Improved live updates for shifts, shared calendars and messages.
- Updated sign-in with Apple, Google, email codes, or email and password.
- Improved reliability and privacy.

Norwegian Bokmal:

- Forbedret oppdatering av vakter, delte kalendere og meldinger i sanntid.
- Oppdatert innlogging med Apple, Google, e-postkode eller e-post og passord.
- Forbedret stabilitet og personvern.

The published baseline for these notes is `ios/3.0.1`. The local metadata generator ran for the source locales, and all 32 App Store release-note files were updated and validated.
