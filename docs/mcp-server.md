# Tidex MCP server

People can connect Tidex to an AI agent (Claude, ChatGPT, Cursor and other MCP clients) and let it do what they can do in the app: manage shifts, recurring shifts, events, jobs, pay and tariffs, payroll adjustments and settings, read their earnings, and talk to and share with friends. Account deletion, blocking and reporting, and features that live only on the phone stay out. The server is a Convex HTTP action at `/mcp` on the HTTP actions host, `https://actions.tidex.no/mcp` in production. Clerk is the OAuth authorization server.

The HTTP actions, token checks and rate limits are in `backend/convex/mcp.ts`. Each area's tools are in their own module: `mcpShifts.ts`, `mcpPay.ts` (jobs, pay, tariffs), `mcpPlans.ts` (recurring shifts, events, payroll adjustments, settings) and `mcpSocial.ts` (friends and messages). The parts that need no Convex runtime are in `backend/convex/lib/mcp/`. The tests are `backend/scripts/mcp*.test.ts`, plus the iOS contract test described under [Tools](#tools). Production stays off until the steps in [Production setup](#production-setup) are done: without a valid `MCP_RESOURCE_URL`, every MCP route returns 404.

## Protocol

The server speaks MCP over Streamable HTTP without sessions and answers both protocol eras. Most clients still open with `initialize`; the official TypeScript SDK v2 does too unless told to negotiate.

- **2026-07-28.** No `initialize`. Each request carries `MCP-Protocol-Version: 2026-07-28`, `Mcp-Method`, `Mcp-Name` for `tools/call`, and `_meta["io.modelcontextprotocol/protocolVersion"]`. A header that is missing or disagrees with the body gets `400` and JSON-RPC error `-32020`; a body that declares 2026-07-28 gets these checks even without the version header. The server answers `server/discover` and adds `resultType`, the server's identity, and `ttlMs` and `cacheScope` to list results.
- **2025-06-18 and 2025-11-25.** The client opens with `initialize`. The server answers with the client's version when it supports it, else `2025-11-25`, and never sets `Mcp-Session-Id`. A request without `MCP-Protocol-Version` is treated as this era.

Other versions get `400` with error `-32022` and the supported list. 2025-03-26 is not supported, because those clients can't find the authorization server through protected resource metadata.

Every reply is one `application/json` body; the server never opens an SSE stream. Notifications get `202`. `GET` and `DELETE` on `/mcp` get `405` with `Allow: POST`. Batches get `400`. Bodies over 64 KB get `413`, counted while the body streams in. A request with an `Origin` header other than `https://claude.ai`, `https://chatgpt.com` or `https://chat.openai.com` gets `403`: agents connect from servers and apps, and a web page must not be able to use a token it got hold of. Those three are allowed as a precaution, in case the hosted Claude or ChatGPT connectors send their own origin from the server; neither has been seen to. The endpoint answers no CORS preflight, so browser-based clients such as the MCP Inspector's web UI can't connect.

## Authorization

The MCP server is an OAuth resource server (RFC 9728):

- `GET /.well-known/oauth-protected-resource/mcp`, and the same at `/.well-known/oauth-protected-resource` for clients that only try the root, return `{ resource, authorization_servers: [<Clerk issuer>], bearer_methods_supported, scopes_supported: ["tidex:read", "tidex:write"], resource_name, resource_documentation }`.
- A request without a token gets `401` with `WWW-Authenticate: Bearer scope="tidex:read", resource_metadata="<that URL>"`, and a bad token adds `error="invalid_token"`. A valid token for a banned user, or for a Clerk user without a Tidex account, gets `403`, because signing in again would not help. The client then reads Clerk's metadata at `<issuer>/.well-known/oauth-authorization-server`, registers with a Client ID Metadata Document or Dynamic Client Registration, and runs the authorization code flow with PKCE, `resource=<MCP URL>` and the scopes it asks for. The user signs in on Clerk's hosted page and approves the client on Clerk's consent screen.
- `lib/mcp/token.ts` verifies the access token against Clerk's JWKS: `RS256`, `typ: at+jwt`, `iss` equal to `CLERK_JWT_ISSUER_DOMAIN`, `aud` exactly `MCP_RESOURCE_URL`, an unexpired `exp`, and a `client_id`. The space-separated `scope` claim lists the scopes the token grants. Action memory doesn't last between requests, so the keys are kept in `mcp_signing_keys` for an hour. A token naming a key they lack fetches them again. Only one request a minute may fetch, failed attempts included, so junk tokens can't make every request reach Clerk. When a fetch fails, the stored keys stand in; without stored keys, or when a token names a key Clerk may have just rotated in, the request gets `503`, not `401`. `sub` is the Clerk user ID, which maps to a Tidex user through `userByClerkId`, the same lookup the app's sessions use.
- The app's Convex session tokens have `aud: "convex"`, no `client_id` and no `at+jwt` type, so `/mcp` rejects them. The OAuth tokens are not in `auth.config.ts`, so the app's Convex functions reject them. A leaked agent token reaches only the tools below.
- Admin impersonation never applies. It is keyed to the app's Clerk session, and OAuth tokens carry no session.
- Clerk access tokens last one day. Verification is local, so a client the user disconnects in Clerk keeps working until its token expires.

### Scopes

A token needs `tidex:read` for read tools and both `tidex:read` and `tidex:write` for write tools, because a write returns the changed data. `initialize`, `server/discover`, `tools/list` and `ping` need only a valid token, so a read-only client still sees every tool. Each tool's `scope` in its registry entry decides which it needs. The 401 challenge asks for `tidex:read` alone, so a client starts read-only and asks for more on its first write.

A `tools/call` whose token lacks a scope the tool needs gets `403` with a JSON-RPC error that keeps the request's `id` and tells the agent which permission the user has to allow. The header names every scope the tool needs, so one new authorization covers it:

```
WWW-Authenticate: Bearer error="insufficient_scope", scope="tidex:read tidex:write", resource_metadata="<metadata URL>", error_description="..."
```

## Tools

All dates are `YYYY-MM-DD` and all times `HH:mm` on the user's own clock, as the app shows them. A date the agent writes must be within five years of today, which catches a mistyped year. An optional argument sent as `null` counts as left out, as strict clients such as ChatGPT send them. A shift whose end is at or before its start ends the next day. A midnight end is stored as `24:00` when the start isn't `00:00`, as the app's `ShiftSchedule` does. Equal start and end times are refused, except when moving the start of a 24-hour shift keeps its length.

Every write that changes or deletes an existing row takes the `revision` the list or get tool returned. A revision that no longer matches fails with a message telling the agent to list again, so an agent can't overwrite a change made on the phone. Adds return the existing row instead of a copy when the same thing already exists, so a retried call adds nothing. Writes go through the same insert, update and remove code as the app's sync (`syncedTable` in `lib/syncWrite.ts`, and the `*For` functions split out of the messaging, sharing and settings mutations), for the user the token names and with the current `PAYROLL_REVISION`. They get new revisions, so the app pulls them on its next `sync.revisions` update.

The app reads a synced table in pages and one row it can't decode stops that table syncing for the user, so the builders in `lib/mcp/` write exactly what the app writes. `backend/scripts/mcp-contract-fixture.ts` writes `ios/TidexAppTests/Fixtures/MCPContractFixture.json` from those builders: jobs, custom and tariff pay with a raise, and shifts with the gross pay the server computes. `mcp-pay.test.ts` fails when the committed fixture is stale, and `MCPContractFixtureTests` in the iOS tests decodes every row with the app's sync types and prices the shifts with the app's payroll code, which must match the server's gross. Regenerate the fixture with `bun backend/scripts/mcp-contract-fixture.ts` after changing a builder.

### Shifts

| Tool | Kind | What it does |
| --- | --- | --- |
| `list_shifts` | read | Shifts from `from` to `to`, at most 93 days, with the schedule time zone. One-off shifts carry `shift_id` and `revision`; recurring dates carry `recurring_shift_id`, `recurring_revision` and their note. |
| `get_earnings` | read | Gross pay and paid hours per currency for shifts dated `from` to `to`, at most 93 days, and how many shifts were left out because their job has no pay set up. |
| `add_shift` | write | Adds a one-off shift, to the default job unless `job_id` is given. The job needs pay set up, as in the app. |
| `update_shift` | write | Changes date, times, job or note of a one-off shift. A new start without a new end keeps the length, as Siri's move does. |
| `delete_shift` | write, destructive | Soft-deletes a one-off shift. |

`get_earnings` uses the payroll code Live Activities use (`computeShift`, conflict exclusion and weekly overtime in `lib/shared`), counting the way the app's `SharingComputeCore.computeShiftsInRange` does. It leaves out net pay and payroll adjustments, because the app taxes each shift by its payout date and half-tax month, which the server doesn't model. Adding a shift queues the same debounced friend notification as adding it in the app.

### Jobs and pay

| Tool | Kind | What it does |
| --- | --- | --- |
| `list_jobs` | read | Jobs with pay period, payday, half-tax month, colour, currency, default and archived flags, and whether pay is set up. |
| `add_job` | write | Adds a job and its base pay in one transaction, as the app does. The first active job becomes the default. Colours come from the app's palette; currency is a symbol such as `kr` or `$`, and a tariff job is always `kr`. |
| `update_job` | write | Name, colour, payday, half-tax month, pay period, default, archive or restore. Currency can't change. Archiving refuses the default job and the last active job, as the app does. |
| `delete_job` | write, destructive | Deletes an archived job and its history in two calls: the first returns counts and a `confirmation_token`, the second deletes. |
| `list_tariffs`, `get_tariff` | read | The tariff catalogue: agreements grouped by family with the choices that pick a `tariff_type_id`, then that tariff's levels, hourly rates and dates. |
| `get_pay` | read | A job's base pay and each dated pay change. |
| `set_pay` | write | Sets the base pay, or the pay from a date. Tariff pay copies the catalogue version's rate for the level, supplements and overtime, as onboarding does. Custom pay takes an hourly wage, supplement rules (days 1 to 7, Monday first, times, an amount or a percent) and optional overtime with the app's default rules. Tax and breaks are fields of their own. Anything left out comes from the pay in effect on that date. |
| `delete_pay_change` | write, destructive | Deletes a dated pay change. The base pay can't be deleted. |

Tariff pay uses the catalogue's current version only, so a tariff change dated before that version's start is refused with a suggestion to use custom pay.

### Plans and settings

| Tool | Kind | What it does |
| --- | --- | --- |
| `list_recurring_shifts` | read | Series with times, weekdays, repeat interval, end, skipped dates and notes. |
| `add_recurring_shift` | write | Adds a series from one first date per weekday, `every_weeks` (1 to 9) and `ends`. Dates that overlap existing shifts are skipped, as in the app, and returned as `skipped_dates`. |
| `update_recurring_shift`, `stop_recurring_shift`, `delete_recurring_shift` | write | Change the whole series, end it after a date, or delete it. |
| `change_recurring_occurrence` | write | One date of a series: skip it, set its note, or turn it into a one-off shift (an exclusion plus a new shift, as the app does). |
| `list_events`, `add_event`, `update_event`, `delete_event` | read, write | Timed and all-day events with up to four reminders. Reminders are local notifications, so the phone schedules them after the app next syncs. |
| `list_payroll_adjustments`, `add_payroll_adjustment`, `update_payroll_adjustment`, `delete_payroll_adjustment` | read, write | Bonuses, back pay and corrections in the job's currency. A job without tax on the payout date gets `net_manual`, as in the app. |
| `get_settings`, `update_settings` | read, write | Theme, calendar colour style, dashboard clock buttons, startup tab, schedule time zone and notification settings (shift reminders and friend shift alerts). |

A recurring series that ends at midnight is stored with the end `00:00`, which the app reads the same way. The server's time column refuses `24:00` for recurring shifts, although the app itself sends it for such a series.

### Friends and messages

| Tool | Kind | What it does | Pushes to other people |
| --- | --- | --- | --- |
| `list_friends` | read | People who share with the user and people the user shares with, with both sides' settings. Never email addresses; blocked pairs are left out and hidden ones marked. | none |
| `get_friend_schedule` | read | A friend's shifts for up to 93 days on the friend's clock, with gross pay only when the friend shares earnings. Hidden and blocked friends are refused. | none |
| `list_conversations`, `read_conversation` | read | Conversations and their messages. Images are listed by kind only, because their URLs need the app's session. Reading never marks a conversation as read. | none |
| `send_message` | write | Plain text to a friend, starting the conversation if needed, tagged `sent_via: "mcp"` in the message metadata. | a message push, unless the friend muted the conversation |
| `mark_conversation_read` | write | Marks a conversation as read. The friend sees the read receipt. | none |
| `share_shifts_with` | write | Starts sharing the user's shifts with someone found by username or verified email. Earnings stay hidden unless asked for. | a share-started push, if the other person allows it |
| `update_sharing` | write | Earnings and notifications on the user's share, and hidden and notifications for the friend's share. | none |
| `stop_sharing` | write, destructive | Stops sharing the user's shifts with a friend. | none |

Blocking, unblocking, reporting, typing indicators, screenshot reports, username and profile picture changes, and attachments stay in the app.

### Adding a tool

Each tool is one `McpTool` entry (`lib/mcp/registry.ts`): its `definition` for `tools/list`, its `scope` (`read` or `write`), a `parse` that checks the arguments and throws `ToolError` with a message for the agent, and a `run` that calls the area's internal Convex function for the user. Put the definition, scope and parser in `lib/mcp/<area>.ts` so `bun test` can import them without Convex. Put the internal functions in `mcp<Area>.ts`, which also exports the area's list, as `mcpShifts.ts` exports `shiftTools`. Add that list to `tools` in `mcp.ts` with one spread. The order of that array is the order `tools/list` returns. The rate limit counts a `write` tool as a write.

## Limits

`mcp_rate_limits` holds one row per user. Each user gets 120 tool calls per 10 minutes, of which at most 40 may be writes, and at most 10 of those may be messages or new shares, because each of those pushes another person. A call over a limit returns a tool error that says when to retry. Account deletion removes the row.

## Configuration

Deployment environment variables:

- `MCP_RESOURCE_URL`: the public MCP URL. Its path must be `/mcp`; any other value turns the server off and logs an error. Production: `https://actions.tidex.no/mcp`. Dev: `http://127.0.0.1:3211/mcp`.
- `CLERK_JWT_ISSUER_DOMAIN`: already set. It is the issuer for both app sessions and OAuth tokens.

Clerk instance settings, under OAuth applications → Settings, or `PATCH /v1/instance/oauth_application_settings` in the Backend API:

- `aud_claim_enabled` and `aud_claim_refresh_backfill_enabled`: on, so tokens carry the `resource` as `aud`.
- `client_id_metadata_documents_advertised` and `dynamic_oauth_client_registration`: on. ChatGPT and Claude use CIMD when the server offers it and DCR otherwise.
- `oauth_jwt_access_tokens` and `pkce_required`: on, the defaults.

The development instance has these settings. Each instance also needs the scopes `tidex:read` and `tidex:write`, created in the Clerk dashboard because the Backend API can't create scopes, with a description the consent screen shows. Without them no token carries a Tidex scope, and every `tools/call` gets `403`.

## Testing against dev

1. Start the dev deployment (see AGENTS.md), push with `bunx convex dev --once` from `backend/`, and run `bunx convex env set MCP_RESOURCE_URL http://127.0.0.1:3211/mcp`.
2. Register a client: `POST https://<dev issuer>/oauth/register` with a loopback `redirect_uris` entry and `token_endpoint_auth_method: "none"`.
3. Open `<issuer>/oauth/authorize` with PKCE, `resource=http://127.0.0.1:3211/mcp` and `scope=tidex:read tidex:write` in a browser, sign in as a `+clerk_test` user (verification code `424242`), allow, and exchange the code at `<issuer>/oauth/token` with the same `resource`.
4. Connect with `@modelcontextprotocol/sdk` 1.x for the `initialize` era, or `@modelcontextprotocol/client` 2.x with `versionNegotiation: { mode: { pin: "2026-07-28" } }`, passing the token in an `Authorization` header.

## Production setup

Not done. Each step changes production and waits for Hjalmar:

1. Turn on the Clerk settings above on the production instance and create the two scopes there.
2. Check that Clerk's hosted sign-in on the production instance works for every sign-in method Tidex offers, including Sign in with Apple on the web, because the OAuth flow signs the user in there and not in the app.
3. `bunx convex env set MCP_RESOURCE_URL https://actions.tidex.no/mcp` against production, then `bun run deploy` from `backend/` on `main`.
4. Check that Caddy passes `/.well-known/oauth-protected-resource*` and `/mcp` on `actions.tidex.no` to Convex unchanged.
5. Disclose in the privacy policy that a user can let an AI service they connect read and change their Tidex data, including messages with friends and the schedules friends share with them.

## Open questions

- Directory listings in ChatGPT's app directory and Claude's connector directory need their own review and submission.
