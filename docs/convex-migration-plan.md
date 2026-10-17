# Moving Tidex from Supabase to Convex and Clerk

Written 2026-10-16. Data moves to Convex first, with GoTrue still handling sign-in. Auth moves to Clerk later, as a separate step. Each phase can ship and run on its own, so we can stop between phases.

## Starting point

These numbers come from production on 2026-10-16.

- 29 users opened the app between 2026-09-29 and 2026-10-16. In most hours 0 or 1 user is active.
- The database is 93 MB. `user_shifts` has about 3,100 rows, `wage_snapshots` 277, `profiles` 241, `messages` 64.
- The app queries 12 tables directly, calls 43 RPCs, and subscribes to Realtime changes on `threads`, `messages`, reactions and thread state in `FriendsMessagingRealtimeCoordinator.swift`.
- Auth uses Sign in with Apple and Google ID tokens, email OTP, password sign-up and reset, TOTP MFA and `linkIdentity`.
- `supabase/functions/` has 14 edge functions, and the cron table in `AGENTS.md` lists 8 cron jobs.
- The last release is 3.0.0, from 2026-09-30. The gate described below ships in 3.0.1, called N here. The Convex app is N+1.

A full copy of the data takes seconds, so cutover needs a maintenance window of 15 to 30 minutes, not a day.

## Rules that hold for every phase

- N+1 talks only to Convex, so pressing Release in App Store Connect is the cutover. Submit N+1 with manual release, and press Release only during the cutover (phase 3).
- Nothing in Convex is keyed by an auth provider's user ID. Every row points to a Convex `users` document, and that document stores `supabaseUserId` now and `clerkUserId` later. Changing auth then only changes how we find the `users` row.
- Before the last step of a cutover, rolling back must be free: turn maintenance off, remove the Caddy block, and nothing is lost.

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

## Phase 1. Build the Convex backend

1. Run a separate Convex deployment for Tidex on one-s next to Paeonia's. Give it its own domain under `tidex.no` and its own backups. Add its containers to the watchdog.
2. Configure Convex auth with a `customJwt` provider that trusts the tokens GoTrue issues today (ES256, the JWKS in `SUPABASE_JWKS`). Users stay signed in and the app keeps using the Supabase auth client.
3. Write the schema, starting with `users` (`supabaseUserId`, later `clerkUserId`). Every other table points to `users._id`.
   - Every table keeps the Supabase UUID as an indexed `id` field, and the app keeps using UUIDs. The local store, rows created offline, push payloads, deep links and the widget all use them.
   - Sync pulls each table from a `revision` cursor. Every Convex table needs the same kind of increasing counter. On its first launch, N+1 resets its cursors, pulls everything again, and keeps its dirty rows.
4. Port the 43 RPCs and the 12 direct table queries as queries and mutations. Messaging uses Convex subscriptions in place of Realtime. Port `record_app_activity` early, so we can see who has moved to N+1 after cutover.
5. Replace the server-side parts:
   - Cron jobs become Convex crons. This covers push notifications, Live Activities, soft-delete purges and the sync-event and diagnostics purges.
   - `send-push-notifications`, `delete-account`, `admin-user-ban`, `admin-user-role` and `impersonation` become Convex actions.
   - `apple-server-notifications` becomes a Convex HTTP action. Its URL changes in App Store Connect on cutover night.
   - Users have the `calendar-feed` URL saved in their calendar apps. `api.tidex.no/functions/v1/calendar-feed` must keep answering at the same path, either through a Caddy route to a Convex HTTP action or with the edge function reading from Convex.
   - `before-user-created` stays while GoTrue stays.
6. Move Supabase Storage. On 2026-10-17 it held 154 message attachments (48 MB), 13 profile pictures and 2 legal documents.
   - `message_attachments.storage_path` stores bucket paths.
   - `user_settings.profile_picture_url` and `threads.avatar_url` store full URLs, on both `api.tidex.no` and `identity.tidex.no`.
   - Copy the files to Convex file storage and rewrite the paths and URLs in the migration. Caddy blocks `/storage/v1` at cutover (phase 3), so the old URLs stop working that night.
7. Write the migration script. It reads Postgres, maps UUIDs to Convex IDs and writes through an internal mutation. It must be safe to run twice, and it checks row counts table by table when it finishes.
8. Rehearse it. Load a `pg_dump` of production into a dev Convex deployment, run the script, time it, and compare counts. Repeat until it passes twice in a row without changes.

## Phase 2. The Convex app (N+1)

N+1 talks only to Convex. There is no backend flag, so the release is the cutover (phase 3).

1. Replace the Supabase data layer with Convex queries, mutations and subscriptions. Sign-in still goes through the Supabase auth client, and the Convex client gets its token from that session.
2. The friends widget doesn't use the app's data layer. `ios/Shared/FriendsAPIClient.swift` calls `https://api.tidex.no/rest/v1/rpc` directly, so it needs its own Convex path.
3. N+1 keeps the local store from N. Shifts edited offline and messages queued in the friends outbox on N sync to Convex after the update. N+1 must not drop them.
4. The Convex URL comes from the build configuration. Debug builds use the dev deployment. TestFlight and App Store builds use production.
5. Test against the dev deployment first. Then load a rehearsal copy of production data into the production deployment (phase 1, step 8) and test the TestFlight build against it. The cutover replaces that copy.
6. Submit N+1 with "Manually release this version" and without phased release. App Review tests against the production deployment, so the rehearsal copy must include the review demo account and its shifts.

## Phase 3. Cutover night

Write each step with its exact command into a checklist before the night, and only run commands from it. Start once N+1 shows Pending Developer Release in App Store Connect.

1. Set `maintenance: true` and deploy the marketing site. Wait until your own phone shows the maintenance screen.
2. Make Caddy drop connections (`abort`) to `/rest/v1`, `/realtime/v1`, `/storage/v1` and `/functions/v1` on `api.tidex.no` and `identity.tidex.no`. Leave `/auth/v1` open, and keep `calendar-feed` and `apple-server-notifications` working until step 4 moves them. Every app version, including widgets, background sync and versions before N, then sees the server as offline. Shift edits stay dirty on the phone, and queued messages stay queued.
   Don't revoke grants instead. Sync treats a 42501 refusal as that row's fault and marks the row as a conflict (`SyncCoordinator.isRowRejection`). A conflict with no server row can end with the local row dropped. Writes through `SECURITY DEFINER` RPCs such as `send_message` would also ignore revoked grants.
3. Run the migration script and check the counts. It replaces the rehearsal copy.
4. Switch the server side. Disable the Supabase cron jobs, enable the Convex crons, change the Apple server notification URL, and point `calendar-feed` at Convex.
5. Check shifts, pay, messages, a push notification and a calendar feed refresh with the TestFlight build of N+1.
6. Point of no return. Press Release in App Store Connect, set `minimumVersion` to N+1, set `maintenance: false`, and deploy. Users on N see the update screen. Until N+1 reaches their App Store region, which can take a few hours, the App Store button shows no update yet.

Rolling back before step 6 means turning maintenance off, removing the Caddy block, re-enabling the Supabase crons and changing the Apple URL back. N+1 stays unreleased. After step 6, phones run an app that only talks to Convex, and Convex has writes that Postgres doesn't. Going back would take a new release and a script that copies changed shifts and messages back to Postgres, so plan to fix forward.

## Phase 4. Retire the Supabase data

Keep Postgres read-only for a month, then take a final dump to cold storage and drop the public tables. GoTrue and its `auth` schema stay until phase 5 is done.

## Phase 5. Move auth to Clerk

The aim is that nobody has to sign in again. Users who open the app during the overlap move over without noticing. Users who don't open it in that time sign in again with Clerk.

1. Import every GoTrue user into Clerk ahead of time with the Backend API. Set `external_id` to the Supabase user ID and pass the bcrypt hash from `auth.users.encrypted_password` so passwords keep working. Store each `clerkUserId` on the Convex `users` row.
2. Add Clerk as a second provider in Convex auth (the `convex` JWT template or Clerk's Convex integration). Convex then accepts both GoTrue and Clerk tokens.
3. App N+2 uses the Clerk iOS SDK. On launch, if it still has a GoTrue session, it calls a Convex action that checks the GoTrue token, creates a Clerk sign-in token for the matching user, and returns it. The app signs in to Clerk with the `ticket` strategy and drops the GoTrue session.
4. Raise `minimumVersion` to N+2 once adoption is high. Remove GoTrue from Convex auth, then shut down GoTrue and Postgres.

Check these before starting phase 5:

- How Clerk links imported users to Sign in with Apple and Google. Apple's user ID is stable per team, and users who hid their email have a relay address. Test both cases with real accounts.
- Whether Clerk's import accepts TOTP secrets, and whether GoTrue stores them encrypted in `auth.mfa_factors`. If either fails, users with MFA set it up again after their first Clerk sign-in.
- The state of `clerk-convex-swift`. It was a work in progress when this plan was written. Without it, the app passes Clerk's session token to the Convex client through its auth provider protocol.
- Clerk is a hosted service in the US. The privacy policy must name it before launch, which also means bumping the legal version files listed in `AGENTS.md`.
- Clerk's price at our user count.

## Decisions

Made on 2026-10-18.

- The Convex deployment runs on one-s next to Paeonia's. It costs nothing extra, and we run the backups and upgrades.
- N+1 talks only to Convex, without a backend flag. With 29 users, a few hours of update screens on cutover night is cheaper than keeping two data layers working.
- The work happens on the `convex` branch, so `main` stays ready for 3.0.x fixes.
