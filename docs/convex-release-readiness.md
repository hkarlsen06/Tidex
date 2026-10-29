# N+1 release readiness, 2026-10-29

App Store Connect confirmed on 2026-10-29 that version 3.1.0, build `20261028.1856`, is approved and `PENDING_DEVELOPER_RELEASE`, with manual release and no phased release. It has not been released. The build is `VALID`. The review preparation included updated notes in all 32 locales, inherited App Review credentials and all 170 screenshots complete across 34 sets.

Hjalmar authorized the first two cutover steps on 2026-10-29. Backups, maintenance, the old API write freeze, the Supabase cron drain and the final import are complete. Calendar and push switching and release remain pending. The [cutover checkpoint](convex-cutover-checklist.md#current-checkpoint-2026-10-29) records the live state, verification and durable rollback files.

The final import completed at `20:18:03 UTC` with all counts matching. Independent verification compared all 42 tables and 22,597 rows against the import files, checked all 156 copied files against their Supabase SHA-256 hashes, and verified all 256 Clerk mappings for the 263 source accounts. The same seven accounts lack a supported verified identity. Maintenance, the write freeze and disabled Supabase cron jobs remain in place, and Convex push delivery is still disabled.

Promotional text in all 32 locales and the App Review notes were uploaded through `fastlane ios upload_review_metadata` on 2026-10-28. Independent API readbacks match the local files. Other localized metadata, review credentials, contact information, version settings and the attached build are unchanged. The reviewer notes are in `ios/fastlane/metadata/review_information/notes.txt`. The upload log and verification result are `/tmp/tidex-n1-readiness/fastlane-review-metadata.log` and `/tmp/tidex-n1-readiness/review-metadata-verification.json`.

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

Production Convex still has no `APNS_RECIPIENTS`. The public gate is now `minimumVersion: 3.0.0`, `maintenance: true`, and the old app's API writes are frozen. Supabase remains the source of truth until the final import and release. Rehearsal phones must sign out and back in after the final import to reset their sync cursors.

## Cutover preparation

[The command checklist](convex-cutover-checklist.md) covers backup, maintenance, write freeze, cron drain, final import, calendar and push switching, release and rollback. The isolated Caddy test passed again on 2026-10-29 with 26 requests across both stages, including duplicate grant parameters. The Supabase-calendar freeze configuration was validated and installed. Live probes on both hostnames confirm that refresh and calendar requests reach their upstreams while the other tested API routes abort.

The migration plan and iOS guidance now describe Convex and Clerk, the merged implementation, the native Apple connection's credentials and the device wrapper's platform selection. The old Supabase descriptions and schema-blocker instructions were corrected.

Finish the remaining device checklist before releasing. Apple approval and the final import are complete. The next step is switching calendar feeds and push delivery, followed by the app smoke checks. The manual App Store release remains pending.

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
