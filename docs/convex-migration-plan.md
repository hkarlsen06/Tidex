# Moving Tidex from Supabase to Convex and Clerk

Written 2026-10-16, changed 2026-10-18. One release, N+1, moves the data to Convex and sign-in to Clerk. Phases 0 and 1 change nothing for users, so we can stop after either of them.

## Starting point

These numbers come from production on 2026-10-16.

- 29 users opened the app between 2026-09-29 and 2026-10-16. In most hours 0 or 1 user is active.
- The database is 93 MB. `user_shifts` has about 3,100 rows, `wage_snapshots` 277, `profiles` 241, `messages` 64.
- The app queries 12 tables directly, calls 43 RPCs, and subscribes to Realtime changes on `threads`, `messages`, reactions and thread state in `FriendsMessagingRealtimeCoordinator.swift`.
- Auth uses Sign in with Apple and Google ID tokens, email OTP, password sign-up and reset, phone sign-in with SMS codes or a password, passkeys (`PasskeyAuthService.swift`), TOTP MFA and `linkIdentity`.
- `supabase/functions/` has 14 edge functions, and the cron table in `AGENTS.md` lists 8 cron jobs.
- The last release is 3.0.0, from 2026-09-30. The gate described below ships in 3.0.1, called N here. The Convex app is N+1.

A full copy of the data takes seconds, so cutover needs a maintenance window of 15 to 30 minutes, not a day.

## Rules that hold for every phase

- N+1 talks only to Convex and signs in only with Clerk, so pressing Release in App Store Connect is the cutover. Submit N+1 with manual release, and press Release only during the cutover (phase 3).
- Nothing in Convex is keyed by an auth provider's user ID. Every row points to a Convex `users` document, and that document stores `supabase_user_id` and `clerk_user_id`. Rows point to a user by `users.id`, the user's UUID. Convex finds the `users` row from the Clerk token by `clerk_user_id`.
- Before the last step of the cutover, rolling back must be free: turn maintenance off, remove the Caddy block, and nothing is lost. Nothing before that step changes GoTrue or Postgres.

## Phase 0. Minimum-version gate (N)

`ios/TidexApp/App/AppGate.swift` reads `https://tidex.no/app-config.json` (source in `marketing/public/app-config.json`) at launch and every time the app becomes active.

```json
{
  "minimumVersion": "3.0.0",
  "maintenance": false
}
```

- If the app's version is lower than `minimumVersion`, the app shows only an update screen with a button to the App Store.
- If `maintenance` is true, the app shows only a maintenance screen with a retry button.
- If the file can't be fetched, the app keeps its last answer. On a cold launch with no answer the app opens normally, so an outage of tidex.no never locks anyone out.

Changing either value means editing the file and deploying the marketing site (`bun run pages:deploy:marketing`). The site serves the file with `max-age=0`. The app skips its local cache for this request and checks at launch, on every return to the foreground, and every 60 seconds while it's open, so a running app sees a change within a minute.

N decodes only these two fields and ignores the rest. Keep `minimumVersion` a string and `maintenance` a boolean for as long as N is in use. If either changes type, N fails to decode the file and keeps its last answer.

Versions before N don't have the gate. On cutover night they see the server as offline, like every other version (see phase 3). Afterwards they keep failing to reach it, because they never learn they need to update.

## Phase 1. Build the Convex backend and set up Clerk

Start with the Clerk checks below. Any of them can change the plan, so answer them before writing app code. They were answered on 2026-10-18 and 2026-10-20, except Apple account linking, which needs the N+1 build.

1. Run a separate Convex deployment for Tidex on one-s next to Paeonia's. Give it its own domain under `tidex.no` and its own backups. Add its containers to the watchdog.
   - Set up on 2026-10-18 in `/srv/tidex/convex`. The API is `convex.tidex.no`, HTTP actions are on `actions.tidex.no`, and the dashboard is on the tailnet-only `convex-dashboard.tidex.no`. `tidex-convex-backup.sh` backs it up hourly and at 03:40, and the watchdog checks it.
   - The dev deployment runs on the Mac, not on one-s, so one-s keeps its headroom. It is the same backend image under colima. The simulator reaches it on `127.0.0.1`, and a phone reaches it over Tailscale with `tailscale serve`. The rehearsal copy of production data stays on the Mac. Set up on 2026-10-20 in `backend/dev/compose.yml`.
2. Create a development and a production Clerk instance on the free Hobby plan, with Sign in with Apple, Google, email codes and email with password. Connect Convex auth to Clerk with Clerk's Convex integration. Convex trusts only Clerk tokens.
   - Set up on 2026-10-20. Development is `electric-coral-6713.clerk.accounts.dev`, and production is `clerk.tidex.no`, with its DNS records in Cloudflare. Both instances register the iOS app as `48ZSLD4RMP` / `no.tidex.app` for native Sign in with Apple, so they need no Apple Services ID or key. Production uses the Google web client "Clerk production", and development uses Clerk's shared Google credentials. The minimum password length is 8 (GoTrue allows 6), and Apple's private relay accepts mail from production Clerk.
   - `convex.tidex.no` has `CLERK_JWT_ISSUER_DOMAIN=https://clerk.tidex.no`, and the schema was first deployed on 2026-10-20.
3. Write the schema, starting with `users` (`supabase_user_id`, `clerk_user_id`). The schema is in `backend/convex/schema.ts` on the `convex` branch.
   - Tables and fields keep their Postgres names, so the migration copies rows as they are and the app's Codable models keep decoding them. Rows point to each other by UUID, not by Convex document ID, so nothing has to translate IDs for the app.
   - Every table keeps the Supabase UUID as an indexed `id` field, and the app keeps using UUIDs. The local store, rows created offline, push payloads, deep links and the widget all use them. A user who signs up on N+1 gets a new UUID in `users.id`.
   - Sync pulls each table from a `revision` cursor. Every Convex table needs the same kind of increasing counter. On its first launch, N+1 resets its cursors, pulls everything again, and keeps its dirty rows.
4. Port the 43 RPCs and the 12 direct table queries as queries and mutations. Messaging uses Convex subscriptions in place of Realtime. Port `record_app_activity` early, so we can see who has moved to N+1 after cutover.
   - Done on 2026-10-20 on the `convex` branch. The admin RPCs came with step 5. `get_my_entitlement` and `get_or_create_app_account_token` have no caller in the app and come with the StoreKit work.
   - Every row a mutation writes gets its own revision. Pull pages end at a row, so shared revisions would let a page boundary skip part of a group.
   - The synced tables keep the app's contract. An insert with a known id returns the server row as `exists`. Updates and soft deletes compare and set on `revision` and return the server row on a miss. Broken rules throw a ConvexError code in place of the SQLSTATE.
   - Messaging: the app subscribes to `threads.inbox` and `messages.thread`, and `messages.changes` catches up by revision. These replace the snapshot and event RPCs, Realtime and the 12 second poll. A reaction toggle bumps its message's revision, so reactions sync inside the message and a removal deletes the row. Typing moves from Realtime broadcasts to the `typing_indicators` table.
   - Message images upload through `POST /attachments` and download through `GET /attachments/<id>` on `actions.tidex.no`. Both check the Clerk token and thread access, like the storage owner check and the authenticated GET today. Convex's own file URLs are permanent and public, so the app never gets them for chat images.
   - Sharing by email asks Clerk for users with that verified address. Sharing by phone number matches nobody, since N+1 has no phone sign-in.
   - The app sends Clerk's ordinary session token. The Convex integration puts `aud: "convex"` on it, and there is no `convex` JWT template.
   - The widget and the share extension call the friends bootstrap and `send_message` over raw REST today. In N+1 they need the Convex client too.
   - Every push payload carries `recipient_user_id`. The notification service extension should drop a push whose recipient isn't the signed-in user, in case a device token moved between accounts while a push was in flight.
   - The app calls `users.setLocale` after sign-in and when the language changes. Push text uses it, and users who sign up on N+1 have no GoTrue metadata to copy it from.
5. Replace the server-side parts:
   - Cron jobs become Convex crons. This covers push notifications, Live Activities, soft-delete purges and the sync-event and diagnostics purges.
   - `send-push-notifications`, `delete-account`, `admin-user-ban`, `admin-user-role` and `impersonation` become Convex actions. `delete-account` and bans also have to act on the Clerk user. Impersonation stays inside Convex. The admin stays signed in as themselves, and while an impersonation session is active, the current-user lookup returns the target user.
   - `apple-server-notifications` becomes a Convex HTTP action. Its URL changes in App Store Connect on cutover night.
   - Users have the `calendar-feed` URL saved in their calendar apps. `api.tidex.no/functions/v1/calendar-feed` must keep answering at the same path, either through a Caddy route to a Convex HTTP action or with the edge function reading from Convex.
   - Pushes queued by triggers today move with the push sender: new message, reaction, typing, share started, shift added (and its cancel on delete), and feedback submitted and answered.
   - `before-user-created` tells the admin about each new sign-up. `users.linkOrCreate` queues the same alert when it creates a user. Every N+1 sign-up reaches it on first launch, so no Clerk webhook is needed.
   - Clerk links a Google or Apple sign-in to an imported user only by email. If no `users` row has the Clerk user's ID, the first sign-in looks up its Google or Apple account ID in the `sub` values copied from `auth.identities`. On a match it records the new Clerk user as an alias of that `users` row in `clerk_user_aliases`, so the person keeps their data and the imported Clerk user, with its password, keeps working too. Deleting or banning an account acts on every Clerk user of the row.
   - Done on 2026-10-20 on the `convex` branch:
     - **Pushes.** `push.run` sends APNs only. It must stay in Convex's default runtime, because APNs needs HTTP/2 and the Node runtime's `fetch` can't speak it. No device has used FCM since January 2026.
     - **Live Activities, purges, admin API and impersonation.** Live Activities come from `liveActivities.run`, and the purges from `maintenance.ts`, at the pg_cron times. The admin API, bans and roles are in `admin.ts`, without the old TOTP (aal2) requirement. Impersonation sessions schedule their own expiry.
     - **Account deletion.** It is batched, because Convex has no foreign keys to cascade.
     - **HTTP routes.** Apple notifications go to `POST /apple-server-notifications` on `actions.tidex.no`, verified in the Node runtime. The calendar feed is at `GET /calendar-feed/<token>.ics` there.
   - The production deployment needs these in its environment before cutover: `CLERK_SECRET_KEY` (a production key), the `APNS_*` keys from the Supabase functions, and `GOTRUE_JWKS`. The dev deployment has its own.
6. Write the session exchange, so users who update stay signed in. A public Convex action takes a GoTrue access token and checks it against GoTrue's public keys, stored in the deployment's environment. It finds the `users` row by `supabase_user_id`, creates a Clerk sign-in token for its `clerk_user_id` with the Backend API, and returns it.
   - Done on 2026-10-20 as `sessionExchange.exchange`. It also refuses the GoTrue sessions that impersonation used on N, copied to `legacy_impersonation_sessions`. Otherwise an admin's phone that updates mid-impersonation would become the target.
7. Move Supabase Storage. On 2026-10-17 it held 154 message attachments (48 MB), 13 profile pictures and 2 legal documents.
   - `message_attachments.storage_path` stores bucket paths.
   - `user_settings.profile_picture_url` and `threads.avatar_url` store full URLs, on both `api.tidex.no` and `identity.tidex.no`.
   - Copy the files to Convex file storage and rewrite the paths and URLs in the migration. Caddy blocks `/storage/v1` at cutover (phase 3), so the old URLs stop working that night.
   - The script does this. It reads each file from Storage's disk over SSH, so it works while Caddy blocks `/storage/v1`. The 2 legal documents and 12 message images that no row references stay behind.
8. Write the migration script. It reads Postgres and writes each row, UUIDs included, with `convex import`. It also imports every GoTrue user into Clerk with the Backend API, with every distinct proven email on the Clerk user. Proven means a verified email identity or a Google or Apple identity, as `find_user_by_email` counts them. Clerk treats imported addresses as verified, so an unconfirmed one must not reach it. It copies each Apple and Google `sub` to Convex for the first-sign-in match in step 5. It sets `external_id` to the Supabase user ID, passes the bcrypt hash from `auth.users.encrypted_password` so passwords keep working, and stores each `clerk_user_id` on the `users` row. It sends no phone numbers or TOTP secrets, and a user without an email gets no Clerk user. The script must be safe to run twice: it updates Clerk users it finds by `external_id` instead of creating them again. It checks row and user counts table by table when it finishes.
   - It writes timestamps in `Date.toISOString()` form, the form Convex functions write, so they sort as strings.
   - It gives every row a fresh revision from one counter and leaves `revision_counter` at the highest one. Postgres revisions count per row, so N+1 can't use them as cursors or as the expected revision on its first push. On its first launch N+1 re-pulls, and it must take each dirty row's server revision from that pull before pushing.
   - Written on 2026-10-20 as `backend/scripts/migrate.ts`. It leaves out FCM-only devices and pending pushes.
9. Rehearse it. Load a `pg_dump` of production into the dev Convex deployment on the Mac and the development Clerk instance, run the script, time it, and compare counts. Repeat until it passes twice in a row without changes.
   - Passed twice on 2026-10-20 into the dev deployment, reading production directly and read-only instead of a dump. All 41 tables matched in under three minutes, and spot checks as a real account matched Postgres. The development Clerk instance holds at most 100 users, so dev runs import only named accounts with `--clerk-only`. The full Clerk import is rehearsed against the production instance in phase 2, step 7.
   - Timestamps lose their microseconds, so N+1's date parsing must accept millisecond ISO timestamps. Some fields, such as `viewer_state_updated_at`, are parsed with microseconds today.

### Clerk checks

- How Clerk links imported users to Sign in with Apple and Google. Clerk links an OAuth sign-in to an existing user whose verified email matches, and imported emails count as verified. Clerk can't import OAuth connections, so email is the only link.
  - Tested with Google on 2026-10-20 and it failed. The Google account's ID matched the `sub` in `auth.identities`, but Google now sends a different Gmail address than the one GoTrue stored at the last sign-in, so Clerk created a new user. That is why step 5 matches on `sub` when email fails. All 220 Apple and Google identities store a `sub`.
  - 4 users have an identity email that differs from `auth.users.email`, and 3 Apple identities have no email. Importing every identity email covers the first group, and the `sub` match covers the second.
  - 63 Apple users have a private relay address, which stays the same within one Apple team. Test Apple with the N+1 build against the development instance, because the instance's web sign-in uses Clerk's Apple team and gets a different relay address.
  - Imported bcrypt hashes work. A `$2a$10$` hash, the format GoTrue stores, passed Clerk's `verify_password` on 2026-10-20.
- N+1 drops SMS sign-in, passkeys and TOTP, so Tidex fits Clerk's free Hobby plan. MFA and passkeys need Pro ($25 a month), and SMS costs extra on top of that. Counts from 2026-10-18:
  - 9 users have a phone sign-in, and 5 of them can also sign in another way. The other 4 have no email, so they get no Clerk user. None of them opened the app in the 90 days before. Their data still moves, and their `users` row has no `clerk_user_id`. An admin can link one by hand if they get in touch.
  - The 2 users with a passkey also have a password.
  - 5 users turned on TOTP. They sign in without a second factor on N+1.
- Passwords move. All 36 are bcrypt hashes, and Clerk's import accepts `password_hasher: "bcrypt"`.
- `clerk-convex-swift` exists but has no tagged release, and Clerk's docs pin `0.1.0`. Without it, the app passes Clerk's session token to the Convex client through its auth provider protocol.
- Clerk is a hosted service in the US. The privacy policy must name it before N+1 is submitted, which also means bumping the legal version files listed in `AGENTS.md`.

## Phase 2. The Convex app (N+1)

N+1 talks only to Convex and signs in only with Clerk. There is no backend flag, so the release is the cutover (phase 3).

1. Replace the Supabase data layer with Convex queries, mutations and subscriptions.
2. Replace the Supabase auth client with the Clerk iOS SDK for Sign in with Apple, Google, email codes and email with password, and give the Convex client Clerk's token. Remove the phone, passkey and TOTP screens.
3. On launch, if N+1 finds a GoTrue session from N in the keychain, it refreshes it with GoTrue, calls the session exchange (phase 1, step 6), signs in to Clerk with the `ticket` strategy, and deletes the GoTrue session. If that fails, the user signs in again with Clerk.
4. The friends widget doesn't use the app's data layer. `ios/Shared/FriendsAPIClient.swift` calls `https://api.tidex.no/rest/v1/rpc` directly, so it needs its own Convex path and a Clerk token through the app group.
5. N+1 keeps the local store from N. Shifts edited offline and messages queued in the friends outbox on N sync to Convex after the update. N+1 must not drop them.
6. The Convex URL and Clerk key come from the build configuration. Debug builds use the dev deployment on the Mac and the development Clerk instance. TestFlight and App Store builds use production.
7. Test against the dev deployment first. Then run the migration script into the production deployment and Clerk instance (phase 1, step 8) and test the TestFlight build against that rehearsal copy. The cutover replaces it. Update a phone that is signed in on N to the TestFlight build and check that it stays signed in.
8. Ship the privacy policy that names Clerk. Then submit N+1 with "Manually release this version" and without phased release. App Review tests against production, so the rehearsal copy must include the review demo account, its password in Clerk, and its shifts.

## Phase 3. Cutover night

Write each step with its exact command into a checklist before the night, and only run commands from it. Start once N+1 shows Pending Developer Release in App Store Connect.

1. Set `maintenance: true` and deploy the marketing site. Wait until your own phone shows the maintenance screen.
2. Make Caddy drop connections (`abort`) to `/rest/v1`, `/realtime/v1`, `/storage/v1` and `/functions/v1` on `api.tidex.no` and `identity.tidex.no`. On `/auth/v1`, keep only token refresh (`POST /auth/v1/token` with `grant_type=refresh_token`) open, so nobody signs up or changes a password after the import. Keep `calendar-feed` and `apple-server-notifications` working until step 4 moves them. Every app version, including widgets, background sync and versions before N, then sees the server as offline. Shift edits stay dirty on the phone, and queued messages stay queued.
   Don't revoke grants instead. Sync treats a 42501 refusal as that row's fault and marks the row as a conflict (`SyncCoordinator.isRowRejection`). A conflict with no server row can end with the local row dropped. Writes through `SECURITY DEFINER` RPCs such as `send_message` would also ignore revoked grants.
3. Run the migration script and check the counts. It replaces the rehearsal copy and updates the Clerk users for anyone who signed up or changed their password since the rehearsal.
4. Switch the server side. Disable the Supabase cron jobs, enable the Convex crons, change the Apple server notification URL, and point `calendar-feed` at Convex.
5. With the TestFlight build of N+1, check sign-in, shifts, pay, messages, a push notification and a calendar feed refresh.
6. Point of no return. Press Release in App Store Connect, set `minimumVersion` to N+1, set `maintenance: false`, and deploy. Users on N see the update screen. Until N+1 reaches their App Store region, which can take a few hours, the App Store button shows no update yet.

Rolling back before step 6 means turning maintenance off, removing the Caddy blocks, re-enabling the Supabase crons and changing the Apple URL back. N+1 stays unreleased. After step 6, phones run an app that only talks to Convex, and Convex has writes that Postgres doesn't. Going back would take a new release and a script that copies changed shifts and messages back to Postgres, so plan to fix forward.

## Phase 4. Retire Supabase

1. Keep GoTrue running for token refresh while users update, so the session exchange works for them. Shut it down once `record_app_activity` shows nearly every active user on N+1, or after a month. Anyone who updates later signs in again with Clerk.
2. Keep Postgres read-only for a month, then take a final dump to cold storage and shut down the Supabase stack. Remove its containers from the watchdog.

## Decisions

Made on 2026-10-18.

- The Convex deployment runs on one-s next to Paeonia's. It costs nothing extra, and we run the backups and upgrades.
- N+1 talks only to Convex, without a backend flag. With 29 users, a few hours of update screens on cutover night is cheaper than keeping two data layers working.
- Clerk ships in N+1 too, so users go through one forced update instead of two, and GoTrue only serves token refreshes after cutover. If the Clerk checks in phase 1 find a blocker, Clerk moves back to a release after N+1.
- The work happens on the `convex` branch, so `main` stays ready for 3.0.x fixes.
- The dev Convex deployment runs on the Mac. one-s runs only the Paeonia and Tidex production deployments, because it needs the headroom.
- N+1 drops SMS sign-in, passkeys and TOTP. SMS costs money and upkeep, and passkeys and TOTP need Clerk's paid plan, so Tidex stays on the free plan.
- Impersonation stays custom and runs inside Convex. Clerk's own impersonation is capped at 5 on the free plan.
