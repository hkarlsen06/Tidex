# Supabase Auth Architecture (Next.js 16)

This document outlines how authentication is wired into the project following Next.js 16 best practices, how the different pieces interact, and what to consider when extending the system.

## Overview

- We rely on [`@supabase/ssr`](https://supabase.com/docs/guides/auth/server-side/nextjs) alongside `@supabase/supabase-js` to manage sessions on both the server and browser.
- All environment variables needed for auth must live in `.env.local` (see `.env.local.example` for required keys). The minimum set is:
  - `NEXT_PUBLIC_SUPABASE_URL`
  - `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`
  - `NEXT_PUBLIC_SUPABASE_REDIRECT_URL`
- Sessions are cookie-based. Server components and route handlers read/write auth cookies using the helpers in `lib/supabase`.
- **Authentication happens in Server Components (the data access layer), NOT in proxy.ts**. This follows Next.js 16 guidance that proxy should handle token refresh and routing, not business logic or authentication.

## Runtime Flow

1. **Token refresh** → `proxy.ts` creates a Supabase client to refresh expired auth tokens and sync cookies between client/server. It does NOT check authentication or redirect—that's handled in layouts/pages. This is fast (~1-5ms) since there's no network I/O beyond what Supabase SSR needs.
2. **Authentication enforcement** → `app/(app)/layout.tsx` calls `getUser()` and redirects unauthenticated users to `/login`. This is the **single source of truth** for authentication in protected routes.
3. **Login** → `/login` renders a client-side form that calls `supabase.auth.signInWithPassword`, `signUp`, or `signInWithOAuth` via the shared browser client from `lib/supabase/browser.ts`.
4. **OAuth/email callbacks** → Supabase redirects back to `/auth/callback` with a `code`. The route handler exchanges the code for a session via `createSupabaseRouteHandlerClient`, updates cookies, and redirects to the `next` destination (`app/auth/callback/route.ts`).
5. **Session hydration** → `app/layout.tsx` creates a server client, fetches the session, and renders `SupabaseListener`. The listener subscribes to auth changes in the browser and triggers `router.refresh()` when the access token changes (`app/supabase-listener.tsx`). This keeps server components in sync after login/logout without a full page reload.
6. **Subsequent requests** → Server components read cookies through `createSupabaseServerClient`. When the user is authenticated, the Supabase client's cookie jar contains the session and requests are made with the right access token.

## Key Modules

- `proxy.ts`
  - **Token refresh only** - Creates Supabase client to refresh expired tokens and sync cookies.
  - Does NOT perform authentication checks or redirects (that's the layout's job).
  - Fast execution (~1-5ms) with minimal network I/O.
- `app/(app)/layout.tsx`
  - **Authentication enforcement** - Calls `getUser()` and redirects to `/login` if no user.
  - Single source of truth for protecting all routes under `(app)/`.
  - Follows Next.js 16 data access layer pattern.
- `lib/supabase/browser.ts`
  - Creates the shared **browser client** using `createBrowserClient`.
  - Validates required env vars at module load to fail fast during development/deployment.
- `lib/supabase/server.ts`
  - Provides helpers to instantiate the **server client** for RSCs/actions and **route handler client** when both cookies and response headers are needed.
  - Wraps Next's `cookies()` API and `NextResponse` to bridge Supabase's cookie expectations.
- `app/supabase-listener.tsx`
  - Client component subscribed to `supabase.auth.onAuthStateChange`.
  - Refreshes the router when the access token changes so server components receive up-to-date session info.
- `app/auth/callback/route.ts`
  - Exchanges auth codes returned by Supabase (OAuth, magic links) into persisted sessions by writing cookies via the response object.
- `app/(auth)/login/page.tsx`
  - Client route for password, sign-up, and Google OAuth flows.
  - Uses optimistic UI state (loading flags, inline messaging) and redirects to `/` after success.

## Implementation Guidelines

- **Don't use proxy.ts for authentication**: Following Next.js 16 best practices, `proxy.ts` only handles token refresh (cookie management). Authentication logic belongs in Server Components (layouts/pages).
- **Centralize Supabase imports**: Always use the helpers in `lib/supabase`. Do not call `createBrowserClient` / `createServerClient` in arbitrary files—this keeps cookie configuration and env validation consistent.
- **Server components**: Call `createSupabaseServerClient()` at the top of the async component or loader, then use the returned client. If you need to send responses (e.g., API routes, route handlers), use `createSupabaseRouteHandlerClient(request, response)` so that cookies are persisted.
- **Client components**: Import the shared `supabase` instance from `lib/supabase/browser` so every component interacts with the same client.
- **Protected routes**: All routes under `app/(app)/` are protected by the layout's `getUser()` check. Individual pages can trust that the user exists (the layout redirects otherwise).
- **Session-dependent rendering**: Prefer server-side checks (redirecting before render) to avoid flashes of unauthenticated UI.
- **Auth state changes**: When you add logout flows or session updates, trigger `router.refresh()` after the operation so server components re-evaluate.
- **Environment variables**: Never hardcode Supabase credentials. Update `.env.local.example` when new keys are required and keep `.env.local` out of version control.
- **New routes requiring auth**: Place them under `app/(app)/` and they'll inherit authentication from the layout. If you need the user object, call `getUser()` but you don't need to redirect (layout handles it).

## Supabase Dashboard Checklist

- Configure **Site URL** to your production domain (`https://tidex.dev`) and optionally localhost for dev.
- Add `https://kalkulator.tidex.dev/auth/callback` and other environments to **Redirect URLs** in the Supabase Auth settings.
- Ensure the Google OAuth credentials in Supabase match the configured redirect URL if you plan to use social login.

## Extending the System

- To implement logout, create a client action that calls `supabase.auth.signOut()` and then `router.refresh()`.
- For server actions that mutate auth state (e.g., admin UI), use `createSupabaseRouteHandlerClient` so cookies are kept consistent.
- When adding database interactions, prefer type-safe queries with a generated typescript definition of your database (e.g., by using `supabase gen types typescript --project-ref`). Update `lib/supabase` helpers to pass the generated types to the client.

Following these practices keeps the auth flow consistent, predictable, and easy to reason about as the project grows.
