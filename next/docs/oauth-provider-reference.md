# OAuth Provider Reference (Tidex as Identity Provider)

Last updated: February 10, 2026

This guide explains how to use Tidex/Supabase OAuth 2.1 Server from other projects.

## What this enables

Use Tidex as an OAuth/OIDC identity provider so external apps can implement:

- Sign in with Tidex
- Access token + refresh token flows
- OIDC identity claims (`openid`, `email`, `profile`, `phone`)

## Tidex provider setup

1. In Supabase for Tidex, enable **Authentication > OAuth Server**.
2. Configure **Authorization Path** as `/oauth/consent`.
3. Ensure Site URL is your Tidex app domain.
4. Register each consumer app in **Authentication > OAuth Apps**.
5. Add exact redirect URIs for each environment of each app.
6. Choose client type correctly:
- `Public`: mobile/SPA clients (no client secret)
- `Confidential`: server-side apps (client secret required)

## Tidex route behavior

Tidex implements the consent flow with these routes:

- `GET /oauth/consent`:
  - Reads `authorization_id`
  - Ensures user is authenticated
  - Shows scopes and approve/deny UI
  - Handles auto-redirect when consent already exists
- `POST /api/oauth/decision`:
  - Approve/deny action handler
  - Calls `supabase.auth.oauth.approveAuthorization(...)` or `denyAuthorization(...)`
  - Redirects back to client callback URL
- `GET /{locale}/oauth/consent`:
  - Alias that redirects to `/oauth/consent` to avoid locale-path regressions

## Endpoints external apps use

For a Supabase project ref `<project-ref>`:

- Authorization endpoint: `https://<project-ref>.supabase.co/auth/v1/oauth/authorize`
- Token endpoint: `https://<project-ref>.supabase.co/auth/v1/oauth/token`
- JWKS endpoint: `https://<project-ref>.supabase.co/auth/v1/.well-known/jwks.json`
- OAuth discovery: `https://<project-ref>.supabase.co/.well-known/oauth-authorization-server/auth/v1`
- OIDC discovery: `https://<project-ref>.supabase.co/auth/v1/.well-known/openid-configuration`

## External app integration (authorization code + PKCE)

1. Generate `code_verifier` (random) and `code_challenge` (`S256`).
2. Generate and store `state` for CSRF protection.
3. Redirect browser to authorization endpoint.
4. User authenticates and consents in Tidex.
5. Receive callback with `code` and `state`.
6. Validate returned `state` equals stored `state`.
7. Exchange `code` for tokens at token endpoint.
8. Use `access_token` for API calls.
9. Use `refresh_token` to renew tokens.

## Authorization request example

```txt
https://<project-ref>.supabase.co/auth/v1/oauth/authorize?
response_type=code&
client_id=<client-id>&
redirect_uri=<registered-callback>&
state=<csrf-random>&
code_challenge=<pkce-challenge>&
code_challenge_method=S256&
scope=openid%20email%20profile
```

## Token exchange examples

Public client:

```bash
curl -X POST 'https://<project-ref>.supabase.co/auth/v1/oauth/token' \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d 'grant_type=authorization_code' \
  -d 'code=<authorization-code>' \
  -d 'client_id=<client-id>' \
  -d 'redirect_uri=<registered-callback>' \
  -d 'code_verifier=<original-code-verifier>'
```

Confidential client:

```bash
curl -X POST 'https://<project-ref>.supabase.co/auth/v1/oauth/token' \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d 'grant_type=authorization_code' \
  -d 'code=<authorization-code>' \
  -d 'client_id=<client-id>' \
  -d 'client_secret=<client-secret>' \
  -d 'redirect_uri=<registered-callback>' \
  -d 'code_verifier=<original-code-verifier>'
```

Refresh token flow:

```bash
curl -X POST 'https://<project-ref>.supabase.co/auth/v1/oauth/token' \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d 'grant_type=refresh_token' \
  -d 'refresh_token=<refresh-token>' \
  -d 'client_id=<client-id>'
```

## OIDC notes

- Request `openid` scope to receive an `id_token`.
- Use OIDC discovery/JWKS for standards-based token validation.
- Prefer asymmetric JWT signing (RS256/ES256) for OIDC/JWKS validation.

## Security checklist

1. Always use authorization code flow with PKCE (`S256`).
2. Always validate `state` on callback.
3. Keep confidential client secrets server-side only.
4. Register exact redirect URIs; do not wildcard callback paths.
5. Validate tokens using issuer, audience, signature, and expiration.
6. Store refresh tokens securely and rotate/revoke on logout.
7. Request only minimal scopes needed by your app.

## Common errors and fixes

- `invalid_redirect_uri`:
  - Callback URL in request does not exactly match OAuth client registration.
- `invalid_grant` on code exchange:
  - Wrong/expired code or wrong `code_verifier`.
- Missing `id_token`:
  - `openid` scope not requested.
- Consent screen shows no pending authorization:
  - Direct navigation to `/oauth/consent` without Supabase-generated `authorization_id`.

## Minimal implementation checklist for a new client project

1. Register OAuth client in Tidex Supabase.
2. Implement PKCE generation and `state` management.
3. Build `/oauth/callback` handler that validates state.
4. Implement code exchange call to `/auth/v1/oauth/token`.
5. Implement refresh flow and secure token storage.
6. Add sign-out/revocation strategy.

## References

- Supabase OAuth 2.1 Server overview: https://supabase.com/docs/guides/auth/oauth-server
- Getting started: https://supabase.com/docs/guides/auth/oauth-server/getting-started
- OAuth flows: https://supabase.com/docs/guides/auth/oauth-server/oauth-flows
- MCP authentication: https://supabase.com/docs/guides/auth/oauth-server/mcp-authentication
- Token security and RLS: https://supabase.com/docs/guides/auth/oauth-server/token-security
