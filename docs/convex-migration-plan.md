# Moving Tidex from Supabase to Convex and Clerk

Written 2026-10-16, changed 2026-10-18. One release, N+1, moves the data to Convex and sign-in to Clerk. Phases 0 and 1 change nothing for users, so we can stop after either of them.

## Starting point

These numbers come from production on 2026-10-16.

- 29 users opened the app between 2026-09-29 and 2026-10-16. In most hours 0 or 1 user is active.
- The database is 93 MB. `user_shifts` has about 3,100 rows, `wage_snapshots` 277, `profiles` 241, `messages` 64.
- The app queries 12 tables directly, calls 43 RPCs, and subscribes to Realtime changes on `threads`, `messages`, reactions and thread state in `FriendsMessagingRealtimeCoordinator.swift`.
- Auth uses Sign in with Apple and Google ID tokens, email OTP, password sign-up and reset, passkeys (`PasskeyAuthService.swift`), TOTP MFA and `linkIdentity`.
- `supabase/functions/` has 14 edge functions, and the cron table in `AGENTS.md` lists 8 cron jobs.
- The last release is 3.0.0, from 2026-09-30. The gate described below ships in 3.0.1, called N here. The Convex app is N+1.

A full copy of the data takes seconds, so cutover needs a maintenance window of 15 to 30 minutes, not a day.

## Rules that hold for every phase

- N+1 talks only to Convex and signs in only with Clerk, so pressing Release in App Store Connect is the cutover. Submit N+1 with manual release, and press Release only during the cutover (phase 3).
- Nothing in Convex is keyed by an auth provider's user ID. Every row points to a Convex `users` document, and that document stores `supabaseUserId` and `clerkUserId`. Convex finds the `users` row from the Clerk token by `clerkUserId`.
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

Start with the Clerk checks below. Any of them can change the plan, so answer them before writing app code.

1. Run a separate Convex deployment for Tidex on one-s next to Paeonia's. Give it its own domain under `tidex.no` and its own backups. Add its containers to the watchdog.
2. Create a development and a production Clerk instance with the sign-in methods the app has today. Connect Convex auth to Clerk with Clerk's Convex integration. Convex trusts only Clerk tokens.
3. Write the schema, starting with `users` (`supabaseUserId`, `clerkUserId`). Every other table points to `users._id`.
   - Every table keeps the Supabase UUID as an indexed `id` field, and the app keeps using UUIDs. The local store, rows created offline, push payloads, deep links and the widget all use them. A user who signs up on N+1 gets a new UUID in `users.id`.
   - Sync pulls each table from a `revision` cursor. Every Convex table needs the same kind of increasing counter. On its first launch, N+1 resets its cursors, pulls everything again, and keeps its dirty rows.
4. Port the 43 RPCs and the 12 direct table queries as queries and mutations. Messaging uses Convex subscriptions in place of Realtime. Port `record_app_activity` early, so we can see who has moved to N+1 after cutover.
5. Replace the server-side parts:
   - Cron jobs become Convex crons. This covers push notifications, Live Activities, soft-delete purges and the sync-event and diagnostics purges.
   - `send-push-notifications`, `delete-account`, `admin-user-ban`, `admin-user-role` and `impersonation` become Convex actions. `delete-account`, bans and impersonation also have to act on the Clerk user.
   - `apple-server-notifications` becomes a Convex HTTP action. Its URL changes in App Store Connect on cutover night.
   - Users have the `calendar-feed` URL saved in their calendar apps. `api.tidex.no/functions/v1/calendar-feed` must keep answering at the same path, either through a Caddy route to a Convex HTTP action or with the edge function reading from Convex.
   - `before-user-created` tells the admin about each new sign-up. A Clerk `user.created` webhook to a Convex HTTP action takes over. It creates the `users` row and sends the same notification.
6. Write the session exchange, so users who update stay signed in. A public Convex action takes a GoTrue access token and checks it against GoTrue's public keys, stored in the deployment's environment. It finds the `users` row by `supabaseUserId`, creates a Clerk sign-in token for its `clerkUserId` with the Backend API, and returns it.
7. Move Supabase Storage. On 2026-10-17 it held 154 message attachments (48 MB), 13 profile pictures and 2 legal documents.
   - `message_attachments.storage_path` stores bucket paths.
   - `user_settings.profile_picture_url` and `threads.avatar_url` store full URLs, on both `api.tidex.no` and `identity.tidex.no`.
   - Copy the files to Convex file storage and rewrite the paths and URLs in the migration. Caddy blocks `/storage/v1` at cutover (phase 3), so the old URLs stop working that night.
8. Write the migration script. It reads Postgres, maps UUIDs to Convex IDs and writes through an internal mutation. It also imports every GoTrue user into Clerk with the Backend API. It sets `external_id` to the Supabase user ID, passes the bcrypt hash from `auth.users.encrypted_password` so passwords keep working, and stores each `clerkUserId` on the `users` row. The script must be safe to run twice: it updates Clerk users it finds by `external_id` instead of creating them again. It checks row and user counts table by table when it finishes.
9. Rehearse it. Load a `pg_dump` of production into a dev Convex deployment and the development Clerk instance, run the script, time it, and compare counts. Repeat until it passes twice in a row without changes.

### Clerk checks

- How Clerk links imported users to Sign in with Apple and Google. Apple's user ID is stable per team, and users who hid their email have a relay address. Test both cases with real accounts.
- Passkeys can't move. A passkey is bound to the relying party that registered it, and GoTrue's passkeys aren't Clerk's. Users who sign in only with a passkey need another way back in, such as email OTP, and register a new passkey in N+1. Count how many users have only a passkey.
- Whether Clerk's import accepts TOTP secrets, and whether GoTrue stores them encrypted in `auth.mfa_factors`. If either fails, users with MFA set it up again after their first Clerk sign-in.
- The state of `clerk-convex-swift`. It was a work in progress when this plan was written. Without it, the app passes Clerk's session token to the Convex client through its auth provider protocol.
- Clerk is a hosted service in the US. The privacy policy must name it before N+1 is submitted, which also means bumping the legal version files listed in `AGENTS.md`.
- Clerk's price at our user count.

## Phase 2. The Convex app (N+1)

N+1 talks only to Convex and signs in only with Clerk. There is no backend flag, so the release is the cutover (phase 3).

1. Replace the Supabase data layer with Convex queries, mutations and subscriptions.
2. Replace the Supabase auth client with the Clerk iOS SDK for every sign-in method, and give the Convex client Clerk's token.
3. On launch, if N+1 finds a GoTrue session from N in the keychain, it refreshes it with GoTrue, calls the session exchange (phase 1, step 6), signs in to Clerk with the `ticket` strategy, and deletes the GoTrue session. If that fails, the user signs in again with Clerk.
4. The friends widget doesn't use the app's data layer. `ios/Shared/FriendsAPIClient.swift` calls `https://api.tidex.no/rest/v1/rpc` directly, so it needs its own Convex path and a Clerk token through the app group.
5. N+1 keeps the local store from N. Shifts edited offline and messages queued in the friends outbox on N sync to Convex after the update. N+1 must not drop them.
6. The Convex URL and Clerk key come from the build configuration. Debug builds use the dev deployment and the development Clerk instance. TestFlight and App Store builds use production.
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
