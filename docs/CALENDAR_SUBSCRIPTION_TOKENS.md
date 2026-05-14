# Calendar Subscription Tokens

Backend support exists for one subscribable Tidex calendar URL per user. This
includes token management plus a public, token-protected `.ics` feed Edge
Function. The iOS UI is still pending.

## Content Modes

The active subscription stores one of three modes:

- `events_only` - personal Tidex events only
- `shifts_only` - shifts only
- `shifts_and_events` - shifts and personal Tidex events

Changing the mode updates what the feed serves at the same URL. It does not
rotate the token.

## App RPCs

These public RPCs are for authenticated app clients:

- `get_my_calendar_subscription()`
  - Returns active metadata only.
  - If no active token exists, returns `is_active = false` and null metadata.
- `create_my_calendar_subscription(p_content_mode text default 'shifts_only')`
  - Creates the user's first active token.
  - Returns `raw_token` once. Store/copy it immediately in the client flow.
- `rotate_my_calendar_subscription(p_content_mode text default null)`
  - Revokes the active token and creates a new one.
  - Returns the new `raw_token` once.
  - Preserves the current content mode when `p_content_mode` is null.
- `set_my_calendar_subscription_content_mode(p_content_mode text)`
  - Updates the active subscription mode without changing the token.
- `disable_my_calendar_subscription()`
  - Revokes the active token.
  - Returns `true` when an active token was disabled.

Valid `p_content_mode` values are `events_only`, `shifts_only`, and
`shifts_and_events`.

## Calendar Feed

The `calendar-feed` Edge Function is configured with `verify_jwt = false`
because calendar apps fetch the feed without Supabase auth. Access is protected
by the raw bearer token in the URL.

Supported request shape:

- `GET /functions/v1/calendar-feed/<raw_token>.ics`
- `HEAD /functions/v1/calendar-feed/<raw_token>.ics`

The feed:

- accepts tokens shaped like `tidex_cal_` plus 64 lowercase hex characters
- returns `404` for invalid, unknown, or revoked tokens
- returns `405` for unsupported methods
- serves `text/calendar; charset=utf-8`
- sets `Cache-Control: private, no-store`
- includes shifts, personal events, or both according to `content_mode`
- emits a rolling window from 90 days before today through 12 months ahead

## Frontend Subscription URLs

Use two URL forms in the app:

- HTTPS feed URL for manual copy/paste into calendar apps:
  `https://identity.tidex.no/functions/v1/calendar-feed/<raw_token>.ics`
- `webcal://` launch URL when opening the user's calendar app from Tidex:
  `webcal://identity.tidex.no/functions/v1/calendar-feed/<raw_token>.ics`

Opening the HTTPS `.ics` URL directly in Safari can be treated as a one-time
import, which asks the user to add every event individually. Opening the
`webcal://` URL is what triggers Calendar-style subscription handling on Apple
platforms. The underlying feed still resolves over the same token-protected
endpoint.

## Localization Follow-Up

The feed resolver returns a normalized locale derived from
`auth.users.raw_user_meta_data->>'locale'`. Calendar apps still fetch the feed
without an authenticated session; the service-role Edge Function resolves the
token, receives `user_id`, `content_mode`, and `locale`, then localizes
feed-visible labels while loading the user's data.

This means calendar labels update automatically after the app syncs a changed
user locale to Supabase and the calendar app refreshes the subscription.

Supported locale normalization matches the shift-added friend notification
backend:

- `no-*` resolves to `nb`
- `pt-BR` resolves to `pt-br`
- `zh-Hans-*` resolves to `zh-hans`
- `zh-Hant-*` resolves to `zh-hant`
- unsupported or missing locales fall back to `en`

The first localized feed label is the shift event summary prefix, for example
`Shift: Extra` in English and `Vakt: Extra` in Norwegian Bokmal.

## Feed Resolver

`resolve_calendar_subscription_token(p_raw_token text)` is granted only to
`service_role` for the `.ics` feed function.

It:

- resolves only active, non-revoked tokens
- returns `user_id`, `content_mode`, and normalized `locale`
- updates `last_used_at` at most once every 15 minutes
- returns no row for invalid, unknown, or revoked tokens

## Security Notes

Raw tokens are bearer secrets. The database stores only
`encode(digest(raw_token, 'sha256'), 'hex')`, plus the last 8 token characters
as `token_suffix` for display/debugging. Existing raw tokens cannot be recovered
from the backend; if a user needs a new copy after losing the URL, rotate the
subscription.

There is only one active subscription per user to avoid duplicate subscribed
calendars in external calendar apps.
