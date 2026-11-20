# Tidex MCP server

People can connect Tidex to an AI agent (Claude, ChatGPT, Cursor and other MCP clients) and let it read their shifts and earnings and add, move and delete shifts. The server is a Convex HTTP action at `/mcp` on the HTTP actions host, `https://actions.tidex.no/mcp` in production. Clerk is the OAuth authorization server.

The code is in `backend/convex/mcp.ts` and `backend/convex/lib/mcp/`. The tests are in `backend/scripts/mcp.test.ts`. Production stays off until the steps in [Production setup](#production-setup) are done: without a valid `MCP_RESOURCE_URL`, every MCP route returns 404.

## Protocol

The server speaks MCP over Streamable HTTP without sessions and answers both protocol eras. Most clients still open with `initialize`; the official TypeScript SDK v2 does too unless told to negotiate.

- **2026-07-28.** No `initialize`. Each request carries `MCP-Protocol-Version: 2026-07-28`, `Mcp-Method`, `Mcp-Name` for `tools/call`, and `_meta["io.modelcontextprotocol/protocolVersion"]`. A header that is missing or disagrees with the body gets `400` and JSON-RPC error `-32020`; a body that declares 2026-07-28 gets these checks even without the version header. The server answers `server/discover` and adds `resultType`, the server's identity, and `ttlMs` and `cacheScope` to list results.
- **2025-06-18 and 2025-11-25.** The client opens with `initialize`. The server answers with the client's version when it supports it, else `2025-11-25`, and never sets `Mcp-Session-Id`. A request without `MCP-Protocol-Version` is treated as this era.

Other versions get `400` with error `-32022` and the supported list. 2025-03-26 is not supported, because those clients can't find the authorization server through protected resource metadata.

Every reply is one `application/json` body; the server never opens an SSE stream. Notifications get `202`. `GET` and `DELETE` on `/mcp` get `405` with `Allow: POST`. Batches get `400`. Bodies over 64 KB get `413`, counted while the body streams in. A request with an `Origin` header other than `https://claude.ai`, `https://chatgpt.com` or `https://chat.openai.com` gets `403`: agents connect from servers and apps, and a web page must not be able to use a token it got hold of. The endpoint answers no CORS preflight, so browser-based clients such as the MCP Inspector's web UI can't connect.

## Authorization

The MCP server is an OAuth resource server (RFC 9728):

- `GET /.well-known/oauth-protected-resource/mcp`, and the same at `/.well-known/oauth-protected-resource` for clients that only try the root, return `{ resource, authorization_servers: [<Clerk issuer>], bearer_methods_supported, resource_name, resource_documentation }`.
- A request without a token gets `401` with `WWW-Authenticate: Bearer resource_metadata="<that URL>"`, and a bad token adds `error="invalid_token"`. A valid token for a banned user, or for a Clerk user without a Tidex account, gets `403`, because signing in again would not help. The client then reads Clerk's metadata at `<issuer>/.well-known/oauth-authorization-server`, registers with a Client ID Metadata Document or Dynamic Client Registration, and runs the authorization code flow with PKCE and `resource=<MCP URL>`. The user signs in on Clerk's hosted page and approves the client on Clerk's consent screen.
- `lib/mcp/token.ts` verifies the access token against Clerk's JWKS: `RS256`, `typ: at+jwt`, `iss` equal to `CLERK_JWT_ISSUER_DOMAIN`, `aud` exactly `MCP_RESOURCE_URL`, an unexpired `exp`, and a `client_id`. Action memory doesn't last between requests, so the keys are kept in `mcp_signing_keys` for an hour. A token naming an unknown key refetches them at most once a minute. If Clerk's key endpoint fails, the request gets `503`, not `401`. `sub` is the Clerk user ID, which maps to a Tidex user through `userByClerkId`, the same lookup the app's sessions use. Banned users and Clerk users without a Tidex row get `401`.
- The app's Convex session tokens have `aud: "convex"`, no `client_id` and no `at+jwt` type, so `/mcp` rejects them. The OAuth tokens are not in `auth.config.ts`, so the app's Convex functions reject them. A leaked agent token reaches only the tools below.
- Admin impersonation never applies. It is keyed to the app's Clerk session, and OAuth tokens carry no session.
- Clerk access tokens last one day. Verification is local, so a client the user disconnects in Clerk keeps working until its token expires.

Version 1 has one permission level and no custom scopes. Clerk's consent screen lists only "basic profile" and "email", so it doesn't tell the user the client can change their shifts. A `shifts` scope with a description would fix that; see [Open questions](#open-questions).

## Tools

All dates are `YYYY-MM-DD` and all times `HH:mm` on the user's own clock, as the app shows them. A shift's date must be within five years of today, which catches a mistyped year. An optional argument sent as `null` counts as left out, as strict clients such as ChatGPT send them. A shift whose end is at or before its start ends the next day. A midnight end is stored as `24:00` when the start isn't `00:00`, as the app's `ShiftSchedule` does. Equal start and end times are refused, except when moving the start of a 24-hour shift keeps its length.

| Tool | Kind | What it does |
| --- | --- | --- |
| `list_jobs` | read | Active jobs: id, name, currency, whether it is the default, whether pay is set up. |
| `list_shifts` | read | Shifts from `from` to `to`, at most 93 days, with the user's schedule time zone. One-off shifts carry `shift_id` and `revision`. Recurring occurrences carry `recurring_shift_id` and their date's note, and can only be changed in the app. |
| `get_earnings` | read | Gross pay before tax and paid hours for shifts dated `from` to `to`, at most 93 days, per currency, plus how many shifts were left out because their job has no pay set up. Those are left out before overlaps are resolved, so they can't push a paid shift out. |
| `add_shift` | write | Adds a one-off shift. Without `job_id` it uses the default job, else the first active one. The job needs a base wage snapshot, as in the app. A live shift with the same job, date and times is returned unchanged instead of a copy, so a retried call adds nothing. |
| `update_shift` | write | Changes date, start, end, job or note of a one-off shift. Needs the `revision` from `list_shifts`. A new start without a new end keeps the length, as Siri's move does. An empty note removes it. A call that changes nothing keeps the revision. |
| `delete_shift` | write, destructive | Soft-deletes a one-off shift, like a delete in the app. Needs the `revision` from `list_shifts`. |

A `revision` that no longer matches fails with a message telling the agent to list the shifts again, so an agent can't overwrite a change made on the phone.

`get_earnings` uses the TypeScript payroll code that Live Activities use (`computeShift`, conflict exclusion and weekly overtime in `lib/shared`), counting the way the app's `SharingComputeCore.computeShiftsInRange` does: recurring occurrences included, overlapping shifts on a date keep the lowest paid one, and overtime counts every shift from the Sunday before `from`'s ISO week. It leaves out net pay and payroll adjustments, because the app taxes each shift by its payout date and half-tax month, which the server doesn't model.

Writes go through the same insert, update and remove code as the app's sync (`syncedTable` in `lib/syncWrite.ts`, through `shiftWrites` in `userShifts.ts`), for the user the token names and with the current `PAYROLL_REVISION`. They get new revisions, so the app pulls them on its next `sync.revisions` update. Adding a shift queues the same debounced friend notification as adding it in the app.

Messages, friends, sharing, settings, jobs, wage setup and recurring shifts are out of scope.

## Limits

`mcp_rate_limits` holds one row per user. Each user gets 120 tool calls per 10 minutes, of which at most 40 may be writes. A call over the limit returns a tool error that says when to retry. Account deletion removes the row.

## Configuration

Deployment environment variables:

- `MCP_RESOURCE_URL`: the public MCP URL. Its path must be `/mcp`; any other value turns the server off and logs an error. Production: `https://actions.tidex.no/mcp`. Dev: `http://127.0.0.1:3211/mcp`.
- `CLERK_JWT_ISSUER_DOMAIN`: already set. It is the issuer for both app sessions and OAuth tokens.

Clerk instance settings, under OAuth applications → Settings, or `PATCH /v1/instance/oauth_application_settings` in the Backend API:

- `aud_claim_enabled` and `aud_claim_refresh_backfill_enabled`: on, so tokens carry the `resource` as `aud`.
- `client_id_metadata_documents_advertised` and `dynamic_oauth_client_registration`: on. ChatGPT and Claude use CIMD when the server offers it and DCR otherwise.
- `oauth_jwt_access_tokens` and `pkce_required`: on, the defaults.

The development instance has these settings.

## Testing against dev

1. Start the dev deployment (see AGENTS.md), push with `bunx convex dev --once` from `backend/`, and run `bunx convex env set MCP_RESOURCE_URL http://127.0.0.1:3211/mcp`.
2. Register a client: `POST https://<dev issuer>/oauth/register` with a loopback `redirect_uris` entry and `token_endpoint_auth_method: "none"`.
3. Open `<issuer>/oauth/authorize` with PKCE and `resource=http://127.0.0.1:3211/mcp` in a browser, sign in as a `+clerk_test` user (verification code `424242`), allow, and exchange the code at `<issuer>/oauth/token` with the same `resource`.
4. Connect with `@modelcontextprotocol/sdk` 1.x for the `initialize` era, or `@modelcontextprotocol/client` 2.x with `versionNegotiation: { mode: { pin: "2026-07-28" } }`, passing the token in an `Authorization` header.

## Production setup

Not done. Each step changes production and waits for Hjalmar:

1. Turn on the Clerk settings above on the production instance.
2. Check that Clerk's hosted sign-in on the production instance works for every sign-in method Tidex offers, including Sign in with Apple on the web, because the OAuth flow signs the user in there and not in the app.
3. `bunx convex env set MCP_RESOURCE_URL https://actions.tidex.no/mcp` against production, then `bun run deploy` from `backend/` on `main`.
4. Check that Caddy passes `/.well-known/oauth-protected-resource*` and `/mcp` on `actions.tidex.no` to Convex unchanged.
5. Disclose in the privacy policy that a user can let an AI service they connect read and change their Tidex shifts.

## Open questions

- The shared recurring generator in `lib/shared/recurring/utils.ts` rolls a month-based end date past the end of a short month (an end on 31 January plus one month becomes 3 March, where the app stops on 28 February). It affects the calendar feed and Live Activities as well as these tools, so it needs its own fix.

- A custom Clerk scope (for example `shifts`) would put "read and change your shifts" on the consent screen and allow a read-only connection. It needs the scope created in Clerk and added to the default scopes for dynamic clients.
- Directory listings in ChatGPT's app directory and Claude's connector directory need their own review and submission.
