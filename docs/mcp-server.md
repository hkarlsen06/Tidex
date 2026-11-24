# Tidex MCP server

People can connect Tidex to an AI agent (Claude, ChatGPT, Cursor and other MCP clients) and let it do what they can do in the app: read their schedule and after-tax earnings, manage shifts, recurring shifts, events, jobs, pay and tariffs, payroll adjustments and settings, and talk to and share schedules with friends. Account deletion, blocking and reporting, and features that live only on the phone stay out. The server is a Convex HTTP action at `/mcp` on the HTTP actions host, `https://actions.tidex.no/mcp` in production. Clerk is the OAuth authorization server.

The HTTP actions, token checks and rate limits live in `backend/convex/mcp.ts`. Tool handlers live in four modules: `mcpPay.ts` (overview, jobs, pay, tariffs), `mcpShifts.ts` (schedule, earnings, shifts), `mcpPlans.ts` (recurring shifts, events, payroll adjustments, settings) and `mcpSocial.ts` (friends and messages). The pure helpers, argument parsers, pay-period math and after-tax earnings engine live in `backend/convex/lib/mcp/`. Tests live in `backend/scripts/mcp*.test.ts`, plus the iOS contract test described under [Tools](#tools). Production has served `/mcp` at `https://actions.tidex.no/mcp` since 2026-11-21. Without a valid `MCP_RESOURCE_URL`, every MCP route returns 404, so unsetting that variable turns it off.

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

All dates are `YYYY-MM-DD`, month shortcuts are `YYYY-MM`, and times are `HH:mm` on the user's own clock. A date the agent writes must be within five years of today, which catches a mistyped year. An optional argument sent as `null` counts as left out, as strict clients such as ChatGPT send them. A shift whose end is at or before its start ends the next day. A midnight end is stored as `24:00` when the start isn't `00:00`, as the app's `ShiftSchedule` does. Equal start and end times are refused, except when moving the start of a 24-hour shift keeps its length.

Tools do not ask agents to pass internal `revision` tokens. Mutations read the current row inside Convex and write through `syncedTable` in `lib/syncWrite.ts` (and the `*For` functions split out of messaging, sharing and settings) with the current `PAYROLL_REVISION`, so the iOS app pulls every change on its next `sync.revisions` update. Jobs and friends can be passed by ID or name (and friends also by username). Adds return the existing row instead of a copy when the same item already exists.

The app reads each synced table in pages and one row it can't decode stops that table syncing for the user, so the builders in `lib/mcp/` write the exact shapes the app writes. `backend/scripts/mcp-contract-fixture.ts` writes `ios/TidexAppTests/Fixtures/MCPContractFixture.json` from those builders: jobs with pay periods and half-tax month, custom and tariff pay with raises, and shifts with the gross, net and tax amounts the server computes. `mcp-pay.test.ts` fails when the committed fixture is stale, and `MCPContractFixtureTests` in the iOS tests decodes every row with the app's sync types and checks gross pay, net pay, tax deducted and paid hours against `PayrollEngine`. Regenerate the fixture with `bun backend/scripts/mcp-contract-fixture.ts` after changing a builder.

### Overview, schedule and shifts

| Tool | Kind | What it does |
| --- | --- | --- |
| `get_overview` | read | Today's date and time in the user's time zone, active jobs with their current pay and tax settings, recurring shift series, app and notification settings, unread message count and friend count. Pass `include_pay_history: true` for full pay timelines and supplement rules, or `include_archived: true` for archived jobs. |
| `get_schedule` | read | Shifts (one-off and recurring occurrences), calendar events and a pay summary for a `month` or `from`/`to` range (up to 366 days, defaulting to 14 days from today). Each shift includes hours, break minutes, gross pay, net pay after tax, tax deducted, effective tax percent, half-tax flag and payout date. One-off shifts use their UUID and recurring occurrences use `recurring:<series_id>:<YYYY-MM-DD>`; both work directly in `update_shift` and `delete_shifts`. |
| `get_earnings` | read | Gross pay, net pay after tax, tax deducted, base pay, supplements, overtime, paid hours and payroll adjustments per currency and job. `by: "worked"` (default) sums shifts worked in a `month` or `from`/`to` range (up to 366 days). `by: "payout"` sums paychecks paid out in a `month` using each job's pay period, half-tax month and payroll adjustments. |
| `add_shifts` | write | Adds 1 to 50 one-off shifts in one call, resolving `job` by ID or name (defaulting to the default job). Existing identical shifts are returned without creating duplicates. |
| `update_shift` | write | Updates any shift by its `id` from `get_schedule` (one-off shift or recurring occurrence). A new `start` without `end` keeps the length. On a recurring occurrence, changing only `note` updates that date's note on the series; changing date, times or job converts that date into a one-off shift. |
| `delete_shifts` | write, destructive | Deletes 1 to 50 shifts by their `ids` from `get_schedule`. One-off shifts are soft-deleted and recurring occurrences are skipped on their series. |

`lib/mcp/payPeriod.ts` ports `ios/Shared/PayPeriod.swift`, and `lib/mcp/earnings.ts` mirrors `SharingComputeCore.computeShiftsInRange` and `PayrollAdjustmentCalculator.swift`: weekly overtime from the start of the ISO week, conflict exclusion, payout-date tax snapshot lookup and Norwegian half-tax months (`november` or `december`). Adding a shift queues the same debounced friend notification as adding it in the app.

### Recurring shifts, events, adjustments and settings

| Tool | Kind | What it does |
| --- | --- | --- |
| `save_recurring_shift` | write | Creates a repeating shift series (omit `id`) or updates/stops an existing series (pass `id`). Uses flat end fields (`end_date`, `end_after_months`, `end_after_years`, `never_ends`). Overlapping dates are skipped on creation and returned as `skipped_dates`. |
| `delete_recurring_shift` | write, destructive | Deletes a whole repeating series, past dates included. |
| `save_event` | write | Creates (omit `id`) or updates (pass `id`) a private calendar event, timed or all-day, with up to four local phone reminders. |
| `delete_event` | write, destructive | Deletes an event by `id`. |
| `save_payroll_adjustment` | write | Creates (omit `id`) or updates (pass `id`) a bonus, back pay or correction on a payday, returning its taxed `net_amount`. A job without tax on `payout_date` gets `net_manual`. |
| `delete_payroll_adjustment` | write, destructive | Deletes a payroll adjustment by `id`. |
| `update_settings` | write | Updates `theme`, `calendar_color_style`, `show_clock_buttons`, `startup_tab` and `time_zone`. Notification preferences live on the phone and can only be read in `get_overview`. |

A recurring series that ends at midnight is stored with the end `24:00`, as the app sends it. An older series may store `00:00`, which the app and tools read the same way.

### Jobs, pay and tariffs

| Tool | Kind | What it does |
| --- | --- | --- |
| `save_job` | write | Creates a job and its base pay in one transaction (omit `id`) with flat pay, tax and break fields, or updates an existing job's name, color, payday, half-tax month, pay period, default flag or archived state (pass `id`). |
| `delete_job` | write, destructive | Permanently deletes an archived job and its history in two calls: first without `confirmation_token` to preview row counts and get a token, then with the token after user confirmation. |
| `set_pay` | write | Sets a job's base pay (omit `from_date`), adds or updates a dated pay change (`from_date`), or removes a dated pay change (`from_date` with `remove: true`) using flat fields (`hourly_wage`, `tariff_type_id`, `tariff_level`, `supplements`, `overtime_enabled`, `overtime_weekly_hours`, `tax_enabled`, `tax_percent`, `break_enabled`, `break_method`, `break_threshold_hours`, `break_minutes`). Omitted fields stay as they are on that date. |
| `find_tariffs` | read | Searches Norwegian collective agreements and statutory minimum wages (`search`) or returns full levels, hourly wages, validity dates and overtime rules for one `tariff_type_id`. Narrow searches (10 or fewer matching variants) include levels directly. |

Tariff pay uses the catalogue's current version only, so a tariff change dated outside that version's validity window is refused with a suggestion to pass `hourly_wage` for custom pay.

### Friends and messages

| Tool | Kind | What it does | Pushes to other people |
| --- | --- | --- | --- |
| `list_friends` | read | Friends with flat sharing flags (`shares_with_me`, `i_share_with_them`, earnings visibility, mute, hidden), `thread_id` and `unread_count`. Never returns email addresses; blocked pairs are excluded. | none |
| `get_friend_schedule` | read | A friend's shifts for a `month` or `from`/`to` range (up to 366 days, defaulting to 14 days), resolved by friend ID, username or name. Includes gross pay, net pay after tax, tax deducted and summary totals only when the friend shares earnings. Hidden and blocked friends are refused. | none |
| `get_messages` | read | Without `friend` or `thread_id`, lists conversations newest first with unread counts and pagination. With `friend` (ID, username or name) or `thread_id`, reads messages oldest first. Never marks messages as read. | none |
| `send_message` | write | Sends a plain-text message by `friend` or `thread_id`, tagged `sent_via: "mcp"` in metadata. Passing the same `client_id` makes retries idempotent. | message push, unless the friend muted the conversation |
| `mark_read` | write | Marks all messages in a conversation as read by `friend` or `thread_id`. Sends a read receipt. | none |
| `update_sharing` | write | Starts sharing with a Tidex user (`username_or_email`, earnings hidden unless `show_my_earnings: true`) or updates sharing flags (`show_my_earnings`, `notify_them`, `hidden`, `notify_me`) for an existing `friend`. | share-started push on new shares, if the other person allows it |
| `stop_sharing` | write, destructive | Stops sharing the user's shifts with a `friend`. Blocked pairs are refused so deleting a share can't lift a block. | none |

Blocking, unblocking, reporting, typing indicators, screenshot reports, username and profile picture changes, and attachments stay in the app.

### Adding a tool

Each tool is one `McpTool` entry (`lib/mcp/registry.ts`): its `definition` for `tools/list`, its `scope` (`read` or `write`), a `parse` that checks arguments and throws `ToolError`, and a `run` that calls the area's internal Convex function for the user. Put the definition, scope and parser in `lib/mcp/<area>.ts` so `bun test` can import them without Convex. Put the internal functions in `mcp<Area>.ts`, export the area's tool array, and include it in `tools` in `mcp.ts`.

## Limits

`mcp_rate_limits` holds one row per user. Each user gets 120 tool calls per 10 minutes, of which at most 40 may be writes, and at most 10 of those may be messages or new shares, because each of those pushes another person. A call over a limit returns a tool error that says when to retry. Account deletion removes the row.

## Configuration

Deployment environment variables:

- `MCP_RESOURCE_URL`: the public MCP URL. Its path must be `/mcp`; any other value turns the server off and logs an error. Production: `https://actions.tidex.no/mcp`. Dev: `http://127.0.0.1:3211/mcp`.
- `CLERK_JWT_ISSUER_DOMAIN`: already set. It is the issuer for both app sessions and OAuth tokens.

Clerk instance settings, under OAuth applications -> Settings, or `PATCH /v1/instance/oauth_application_settings` in the Backend API:

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

Done on 2026-11-21:

1. The production Clerk instance has the settings above, the scopes `tidex:read` and `tidex:write`, and `dynamic_client_allowed_scopes` set to `openid profile email offline_access tidex:read tidex:write`. A scope missing from that list can't be granted to Claude, ChatGPT or any other self-registered client.
2. Sign in with Apple on Clerk's web page uses the Services ID `no.tidex.app.web`. Its return URLs in Apple Developer include `https://clerk.tidex.no/v1/oauth_callback`; without that entry Apple shows "Sign up not completed". The app's own Apple sign-in doesn't use this ID.
3. `MCP_RESOURCE_URL` is `https://actions.tidex.no/mcp` on the production deployment.
4. Caddy passes `/.well-known/oauth-protected-resource*` and `/mcp` on `actions.tidex.no` to Convex unchanged.
5. The privacy policy (dated 2026-11-21, version unchanged) says a connected AI assistant can read and change Tidex data, including messages with friends and the schedules friends share.

## Open questions

- Directory listings in ChatGPT's app directory and Claude's connector directory need their own review and submission.
