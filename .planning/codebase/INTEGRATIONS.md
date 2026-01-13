# External Integrations

**Analysis Date:** 2026-01-13

## APIs & External Services

**Payment Processing:**
- Stripe - Subscription billing and one-time payments
  - SDK/Client: stripe npm package v19.3.1
  - Auth: API key in `STRIPE_SECRET_KEY` env var
  - Products: Pro Monthly/Yearly, Max Monthly/Yearly (via `STRIPE_PRICE_TO_PRODUCT` mapping)
  - Endpoints: Checkout sessions, customer portal, webhooks

**Email/SMS:**
- Not detected - No direct email service integration in codebase

**AI Services:**
- Anthropic Claude API - AI assistant (Wagey)
  - Integration: `lib/services/claude.ts` (Effect-based service)
  - Auth: `CLAUDE_API_KEY` env var
  - Model: Configurable via `CLAUDE_MODEL` env var
  - Features: Streaming chat, tool use support, input_examples beta

**External APIs:**
- Not detected - No third-party REST API integrations beyond Stripe/Supabase

## Data Storage

**Databases:**
- PostgreSQL on Supabase - Primary data store
  - Connection: via `NEXT_PUBLIC_SUPABASE_URL` env var
  - Client: `@supabase/supabase-js` v2.90.1, `@supabase/ssr` v0.8.0
  - Access: `lib/supabase/server.ts` (server), `lib/supabase/browser.ts` (client)

**File Storage:**
- Supabase Storage - User uploads (profile pictures)
  - SDK/Client: `@supabase/supabase-js`
  - Auth: Service role key in `SUPABASE_SERVICE_ROLE_KEY`
  - Access: `app/api/profile-picture/route.ts`

**Caching:**
- React cache() - Request-level deduplication (`data-access/`)
- Effect Cache - Service-level caching (`lib/services/`)
- Next.js cacheTag/revalidateTag - User-scoped cache invalidation (`data-access/cache.ts`)

## Authentication & Identity

**Auth Provider:**
- Supabase Auth - Email/password, Magic Link, OAuth, MFA
  - Implementation: `@supabase/ssr` with cookie-based sessions
  - Token storage: httpOnly cookies via `lib/auth/cookie-config.ts`
  - Session management: JWT refresh in `proxy.ts`
  - Entry points: `data-access/auth.ts` (verifySession, getSession)

**OAuth Integrations:**
- Google OAuth - Social sign-in
  - SDK: `@capgo/capacitor-social-login` v8.2.13
  - Scopes: email, profile
- Apple OAuth - iOS social sign-in
  - SDK: `@capgo/capacitor-social-login` v8.2.13
  - Scopes: email, name

## Monitoring & Observability

**Error Tracking:**
- Custom error logging - `app/api/error-report/route.ts`
  - User-facing error submission endpoint
  - No external service (Sentry not detected)

**Analytics:**
- Vercel Analytics - `@vercel/analytics` v1.6.1
  - Auto-configured via Vercel deployment

**Logs:**
- Console logging - `lib/logger.ts` wrapper
- Vercel logs - stdout/stderr in production

## CI/CD & Deployment

**Hosting:**
- Vercel - Next.js hosting with Turbopack
  - Deployment: Automatic on main branch push
  - Environment vars: Configured in Vercel dashboard

**CI Pipeline:**
- Not detected - No `.github/workflows/` in main app

## Environment Configuration

**Development:**
- Required env vars:
  - `NEXT_PUBLIC_SUPABASE_URL`
  - `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`
  - `NEXT_PUBLIC_TURNSTILE_SITE_KEY`
- Secrets location: `.env.local` (gitignored)
- Mock services: Stripe test mode

**Staging:**
- Not explicitly configured - Same environment as production with test keys

**Production:**
- Secrets management: Vercel environment variables
- Database: Supabase production project

## Webhooks & Callbacks

**Incoming:**
- Stripe Webhook - `supabase/functions/stripe_webhook/index.ts`
  - Verification: Signature validation via `Stripe.webhooks.constructEvent`
  - Events: `checkout.session.completed`, `customer.subscription.updated`, `customer.subscription.deleted`, `invoice.payment_failed`
  - JWT: `verify_jwt: false` (uses signature verification)

- Apple Server Notifications - `supabase/functions/apple-server-notifications/index.ts`
  - Verification: JWS signature validation
  - Events: IAP subscription lifecycle events
  - JWT: `verify_jwt: false` (uses Apple signature)

- Apple Verify Purchase - `supabase/functions/apple-verify-purchase/index.ts`
  - Purpose: Verify iOS in-app purchase receipts
  - JWT: `verify_jwt: true` (requires authenticated user)

**Outgoing:**
- Push Notifications - `supabase/functions/send-push-notifications/index.ts`
  - Destination: Firebase Cloud Messaging
  - Trigger: pg_cron scheduled jobs

## Push Notifications

**Service:**
- Firebase Cloud Messaging - Push notification delivery
  - SDK: `@capacitor-firebase/messaging` v8.0.1
  - Edge Function: `supabase/functions/send-push-notifications/index.ts`
  - Scheduling: pg_cron every minute for reminders

**Edge Functions:**

| Function | verify_jwt | Purpose |
|----------|------------|---------|
| `stripe_webhook` | false | Stripe payment events |
| `apple-server-notifications` | false | Apple IAP webhook |
| `apple-verify-purchase` | true | Verify iOS purchases |
| `send-push-notifications` | false | pg_cron triggered |
| `process-shift-reminders` | false | pg_cron triggered |
| `before-user-created` | false | Auth signup hook |

## Bot Protection

**Provider:**
- Cloudflare Turnstile - Bot protection on auth forms
  - SDK: `@marsidev/react-turnstile` v1.4.1
  - Configuration: `NEXT_PUBLIC_TURNSTILE_SITE_KEY` env var
  - Usage: Login, signup, password reset forms

## Mobile Integration

**Capacitor Plugins:**
- `@capacitor/app` v8.0.0 - App lifecycle, deep links
- `@capacitor/browser` v8.0.0 - In-app browser, URL handling
- `@capacitor/device` v8.0.0 - Device information
- `@capacitor/haptics` v8.0.0 - Haptic feedback
- `@capacitor/ios` v8.0.0 - iOS-specific features
- `@capgo/native-purchases` v8.0.12 - In-app purchases

**Configuration:**
- `capacitor.config.ts` - App ID: `no.tidex.app`
- Deep linking: Universal Links via `.well-known/apple-app-site-association`

---

*Integration audit: 2026-01-13*
*Update when adding/removing external services*
