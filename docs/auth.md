# Supabase Auth Architecture

This document outlines how authentication is wired into the project today, how the different pieces interact, and what to consider when extending the system.

## Overview

- We rely on [`@supabase/ssr`](https://supabase.com/docs/guides/auth/server-side/nextjs) alongside `@supabase/supabase-js` to manage sessions on both the server and browser.
- All environment variables needed for auth must live in `.env.local` (see `.env.local.example` for required keys). The minimum set is:
  - `NEXT_PUBLIC_SUPABASE_URL`
  - `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`
  - `NEXT_PUBLIC_SUPABASE_REDIRECT_URL`
- Sessions are cookie-based. Server components and route handlers read/write auth cookies using the helpers in `lib/supabase`.

## Runtime Flow

1. **Anonymous visit** → `/` checks session server-side and redirects unauthenticated visitors to `/login` (`app/page.tsx`).
2. **Login** → `/login` renders a client-side form that calls `supabase.auth.signInWithPassword`, `signUp`, or `signInWithOAuth` via the browser client from `lib/supabase/client.ts`.
3. **OAuth/email callbacks** → Supabase redirects back to `/auth/callback` with a `code`. The route handler exchanges the code for a session via `createSupabaseRouteHandlerClient`, updates cookies, and redirects to the `next` destination (`app/auth/callback/route.ts`).
4. **Session hydration** → `app/layout.tsx` creates a server client, fetches the session, and renders `SupabaseListener`. The listener subscribes to auth changes in the browser and triggers `router.refresh()` when the access token changes (`app/supabase-listener.tsx`). This keeps server components in sync after login/logout without a full page reload.
5. **Subsequent requests** → Server components read cookies through `createSupabaseServerClient`. When the user is authenticated, the Supabase client’s cookie jar contains the session and requests are made with the right access token.

## Key Modules

- `lib/supabase/client.ts`
  - Creates the **browser client** using `createBrowserClient`.
  - Validates required env vars at module load to fail fast during development/deployment.
- `lib/supabase/server.ts`
  - Provides helpers to instantiate the **server client** for RSCs/actions and **route handler client** when both cookies and response headers are needed.
  - Wraps Next’s `cookies()` API and `NextResponse` to bridge Supabase’s cookie expectations.
- `app/supabase-listener.tsx`
  - Client component subscribed to `supabase.auth.onAuthStateChange`.
  - Refreshes the router when the access token changes so server components receive up-to-date session info.
- `app/auth/callback/route.ts`
  - Exchanges auth codes returned by Supabase (OAuth, magic links) into persisted sessions by writing cookies via the response object.
- `app/login/page.tsx`
  - Client route for password, sign-up, and Google OAuth flows.
  - Uses optimistic UI state (loading flags, inline messaging) and redirects to `/` after success.
- `app/page.tsx`
  - Server-protected route. Fetches the user via the server client and redirects to `/login` if absent.

## Implementation Guidelines

- **Centralize Supabase imports**: Always use the helpers in `lib/supabase`. Do not call `createBrowserClient` / `createServerClient` in arbitrary files—this keeps cookie configuration and env validation consistent.
- **Server components**: Call `createSupabaseServerClient()` at the top of the async component or loader, then use the returned client. If you need to send responses (e.g., API routes, route handlers), use `createSupabaseRouteHandlerClient(request, response)` so that cookies are persisted.
- **Client components**: Use `createSupabaseBrowserClient()` and memoize it (e.g., with `useMemo`) when the component re-renders frequently.
- **Session-dependent rendering**: Prefer server-side checks (redirecting before render) to avoid flashes of unauthenticated UI.
- **Auth state changes**: When you add logout flows or session updates, trigger `router.refresh()` after the operation so server components re-evaluate.
- **Environment variables**: Never hardcode Supabase credentials. Update `.env.local.example` when new keys are required and keep `.env.local` out of version control.
- **New routes requiring auth**: Use the same pattern as `app/page.tsx`. If you need more complex authorization logic, fetch the user on the server and branch before returning UI.

## Supabase Dashboard Checklist

- Configure **Site URL** to your production domain (`https://kkarlsen.dev`) and optionally localhost for dev.
- Add `https://kalkulator.kkarlsen.dev/auth/callback` and other environments to **Redirect URLs** in the Supabase Auth settings.
- Ensure the Google OAuth credentials in Supabase match the configured redirect URL if you plan to use social login.

## Extending the System

- To implement logout, create a client action that calls `supabase.auth.signOut()` and then `router.refresh()`.
- For server actions that mutate auth state (e.g., admin UI), use `createSupabaseRouteHandlerClient` so cookies are kept consistent.
- When adding database interactions, prefer type-safe queries with a generated typescript definition of your database (e.g., by using `supabase gen types typescript --project-ref`). Update `lib/supabase` helpers to pass the generated types to the client.

Following these practices keeps the auth flow consistent, predictable, and easy to reason about as the project grows.
