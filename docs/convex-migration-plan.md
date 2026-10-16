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

- The App Store release and the backend switch happen on different days. A server-side flag decides which backend an app uses, so pressing Release in App Store Connect never changes the backend.
- Nothing in Convex is keyed by an auth provider's user ID. Every row points to a Convex `users` document, and that document stores `supabaseUserId` now and `clerkUserId` later. Changing auth then only changes how we find the `users` row.
- Before the last step of a cutover, rolling back must be free: turn a flag back, restore grants, and nothing is lost.

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

Changing either value means editing the file and deploying the marketing site. The app skips its local cache for this request, so a running app sees the change the next time it comes to the foreground.

Versions before N don't have the gate. When cutover comes, they get a stub response or a database error instead, the same way `wagey-chat-v2` handles old versions today.

## Phase 1. Build the Convex backend

1. Run a separate Convex deployment for Tidex on one-s next to Paeonia's. Give it its own domain under `tidex.no` and its own backups. Add its containers to the watchdog.
2. Configure Convex auth with a `customJwt` provider that trusts the tokens GoTrue issues today (ES256, the JWKS in `SUPABASE_JWKS`). Users stay signed in and the app keeps using the Supabase auth client.
3. Write the schema, starting with `users` (`supabaseUserId`, later `clerkUserId`). Every other table points to `users._id`.
4. Port the 43 RPCs and the 12 direct table queries as queries and mutations. Messaging uses Convex subscriptions in place of Realtime.
5. Replace the server-side parts:
   - Cron jobs become Convex crons. This covers push notifications, Live Activities, soft-delete purges and the sync-event and diagnostics purges.
   - `send-push-notifications`, `delete-account`, `admin-user-ban`, `admin-user-role` and `impersonation` become Convex actions.
   - `apple-server-notifications` becomes a Convex HTTP action. Its URL changes in App Store Connect on cutover night.
   - Users have the `calendar-feed` URL saved in their calendar apps. `api.tidex.no/functions/v1/calendar-feed` must keep answering at the same path, either through a Caddy route to a Convex HTTP action or with the edge function reading from Convex.
   - `before-user-created` stays while GoTrue stays.
6. Write the migration script. It reads Postgres, maps UUIDs to Convex IDs and writes through an internal mutation. It must be safe to run twice, and it checks row counts table by table when it finishes.
7. Rehearse it. Load a `pg_dump` of production into a dev Convex deployment, run the script, time it, and compare counts. Repeat until it passes twice in a row without changes.

## Phase 2. App with both backends (N+1)

1. The data layer has a Supabase path and a Convex path. The app picks one at launch from two new fields in `app-config.json`.

   ```json
   {
     "minimumVersion": "3.0.0",
     "maintenance": false,
     "backend": "supabase",
     "convexUserIds": []
   }
   ```

   `convexUserIds` lists Supabase user IDs that use Convex early. If the backend changes while the app runs, the app shows the maintenance screen and reloads once the flag is stable.
   Local changes that haven't synced yet, such as queued messages in the friends outbox and dirty shifts, go to whichever backend is active when they flush, not the one active when they were made.
2. Test the Convex path in TestFlight against the dev deployment.
3. Release N+1 with `backend: "supabase"`. Nothing changes for users.
4. Add your own account and a test account to `convexUserIds` and use the App Store build against production Convex for a few days. Their data in Convex is a copy. Anything they change there never reaches Postgres, and the cutover copy overwrites it. Remove them again before cutover.
5. Wait until nearly all active users run N+1. Check with the app versions that `record_app_activity` stores.

## Phase 3. Cutover night

Write each step with its exact command into a checklist before the night, and only run commands from it.

1. Set `maintenance: true` and deploy the marketing site. Wait until your own phone shows the maintenance screen.
2. Revoke insert, update and delete on the public tables from `authenticated`. Versions before N can't show the maintenance screen, and this makes their writes fail with an error instead of landing in a database nobody reads anymore.
3. Run the migration script and check the counts.
4. Switch the server side. Disable the Supabase cron jobs, enable the Convex crons, change the Apple server notification URL, and point `calendar-feed` at Convex.
5. Add your own user ID to `convexUserIds`. Check shifts, pay, messages, a push notification and a calendar feed refresh.
6. Point of no return. Set `backend: "convex"`, set `minimumVersion` to N+1, set `maintenance: false`, and deploy.

Rolling back before step 6 means turning maintenance off, restoring the grants, re-enabling the Supabase crons and changing the Apple URL back. After step 6, Convex has writes that Postgres doesn't. A small script that copies changed shifts and messages from Convex back to Postgres is the fallback. Write it before the night.

## Phase 4. Remove the Supabase data path (N+2)

1. Release N+2 without the Supabase data code. It still uses the Supabase auth client.
2. Keep Postgres read-only for a month, then take a final dump to cold storage and drop the public tables. GoTrue and its `auth` schema stay until phase 5 is done.

## Phase 5. Move auth to Clerk

The aim is that nobody has to sign in again. Users who open the app during the overlap move over without noticing. Users who don't open it in that time sign in again with Clerk.

1. Import every GoTrue user into Clerk ahead of time with the Backend API. Set `external_id` to the Supabase user ID and pass the bcrypt hash from `auth.users.encrypted_password` so passwords keep working. Store each `clerkUserId` on the Convex `users` row.
2. Add Clerk as a second provider in Convex auth (the `convex` JWT template or Clerk's Convex integration). Convex then accepts both GoTrue and Clerk tokens.
3. App N+3 uses the Clerk iOS SDK. On launch, if it still has a GoTrue session, it calls a Convex action that checks the GoTrue token, creates a Clerk sign-in token for the matching user, and returns it. The app signs in to Clerk with the `ticket` strategy and drops the GoTrue session.
4. Raise `minimumVersion` to N+3 once adoption is high. Remove GoTrue from Convex auth, then shut down GoTrue and Postgres.

Check these before starting phase 5:

- How Clerk links imported users to Sign in with Apple and Google. Apple's user ID is stable per team, and users who hid their email have a relay address. Test both cases with real accounts.
- Whether Clerk's import accepts TOTP secrets, and whether GoTrue stores them encrypted in `auth.mfa_factors`. If either fails, users with MFA set it up again after their first Clerk sign-in.
- The state of `clerk-convex-swift`. It was a work in progress when this plan was written. Without it, the app passes Clerk's session token to the Convex client through its auth provider protocol.
- Clerk is a hosted service in the US. The privacy policy must name it before launch, which also means bumping the legal version files listed in `AGENTS.md`.
- Clerk's price at our user count.

## Open questions

- Should the Convex deployment run on one-s, or on Convex Cloud in an EU region? one-s keeps it next to Paeonia and costs nothing extra. Convex Cloud removes the backup and upgrade work.
- Is supporting both backends in N+1 worth the work for 29 users? Without it, N+1 talks only to Convex and the cutover happens when you press Release. Users then see the update screen for a few hours until the release reaches every App Store region.
