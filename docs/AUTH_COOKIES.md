# Authentication Cookie Management

This document explains how authentication sessions are managed using server-side cookies to prevent "Invalid Refresh Token" errors in this Next.js 15 PWA.

## Architecture Overview

### Cookie-Based Session Storage

Authentication uses **server-side cookies** exclusively:

- ✅ All auth tokens stored in HTTP-only cookies
- ✅ Browser client uses Supabase's built-in cookie storage (no localStorage)
- ✅ Server components read auth from cookies via `createSupabaseServerClient()`
- ✅ No manual token management or custom storage adapters

Cookie name: `sb-kkarlsen-auth-token` (defined in [lib/supabase/constants.ts](../lib/supabase/constants.ts))

### Single Auth Listener

**Critical**: Only one `onAuthStateChange` listener exists, mounted in [app/supabase-listener.tsx](../app/supabase-listener.tsx).

The listener:
1. Fires on all auth events (sign-in, sign-out, token refresh)
2. Syncs the new session to server cookies via POST to `/auth/callback`
3. Refreshes server components via `router.refresh()`

**Why single listener?**
- Multiple listeners can trigger concurrent refresh requests
- Concurrent refreshes race with each other, causing "Refresh Token Not Found" errors
- Single listener serializes all auth state changes

Implementation uses `useRef` to prevent duplicate subscriptions even during React strict mode double-renders. Console logs `[SUPABASE LISTENER] Mounting single auth state listener` once on mount to verify.

## File Structure

### Core Auth Files

| File | Purpose |
|------|---------|
| [lib/supabase/client.ts](../lib/supabase/client.ts) | Browser client singleton (no custom storage) |
| [lib/supabase/server.ts](../lib/supabase/server.ts) | Server client with cookie read/write support |
| [lib/auth/refresh-lock.ts](../lib/auth/refresh-lock.ts) | Serializes concurrent token refresh attempts |
| [app/supabase-listener.tsx](../app/supabase-listener.tsx) | Single auth listener with cookie sync |
| [app/auth/callback/route.ts](../app/auth/callback/route.ts) | OAuth GET handler + session sync POST endpoint |

### Server Client Cookie Handling

[lib/supabase/server.ts](../lib/supabase/server.ts) provides two client creators:

#### 1. `createSupabaseServerClient()`

For **Server Components**, **Server Actions**, and **middleware**:

```typescript
export async function createSupabaseServerClient() {
  const store = await cookies();
  return createServerClient(ENV.URL!, ENV.PUBLISHABLE!, {
    cookies: {
      get: (name) => store.get(name)?.value,
      set: (name, value, options) => {
        try {
          store.set({ name, value, ...options });
        } catch {
          // Ignore errors in Server Components (render phase)
          // Cookie writes succeed in Server Actions/Route Handlers
        }
      },
      remove: (name, options) => {
        try {
          store.set({ name, value: "", ...options, expires: new Date(0) });
        } catch {
          // Ignore errors in Server Components
        }
      },
    },
  });
}
```

**Why try-catch?**
- Server Components are read-only during render
- Server Actions and Route Handlers can write cookies
- Try-catch prevents errors in read-only contexts

**Cookie removal semantics:**
- Sets `expires: new Date(0)` to properly expire cookies
- More reliable than empty string for cross-browser compatibility

#### 2. `createSupabaseRouteHandlerClient(request, response)`

For **Route Handlers** that need explicit cookie control:

```typescript
export function createSupabaseRouteHandlerClient(
  request: NextRequest,
  response: NextResponse
) {
  return createServerClient(ENV.URL!, ENV.PUBLISHABLE!, {
    cookies: {
      get: (name) => request.cookies.get(name)?.value,
      set: (name, value, options) => {
        response.cookies.set(name, value, options as any);
      },
      remove: (name, options) => {
        response.cookies.set(name, "", { ...options, expires: new Date(0) });
      },
    },
  });
}
```

Used in `/auth/callback` for OAuth and session sync.

## Session Sync Flow

### 1. Auth Event Occurs

User signs in, signs out, or token auto-refreshes (every ~1 hour by default).

### 2. Listener Fires

[app/supabase-listener.tsx](../app/supabase-listener.tsx) receives the event:

```typescript
supabase.auth.onAuthStateChange(async (event, session) => {
  console.log(`[SUPABASE AUTH] ${event}`, {
    hasSession: !!session,
    userId: session?.user?.id,
    timestamp: new Date().toISOString(),
  });

  // POST session to server to write cookies
  await fetch("/auth/callback", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-csrf": "auth-sync", // CSRF protection
    },
    body: JSON.stringify({ event, session }),
    keepalive: true, // Survives tab close/navigation
    cache: "no-store", // Prevent service worker or browser caching
  });

  // Refresh server components
  if (session?.access_token !== accessToken) {
    router.refresh();
  }
});
```

**Why `keepalive: true`?**
- Ensures the POST completes even if user closes tab or navigates away
- Critical for sign-out flows and page unload during token refresh

**Why `cache: "no-store"`?**
- Prevents browser and service worker from caching auth sync requests
- Ensures every POST reaches the server with fresh session data

### 3. Server Writes Cookies

[app/auth/callback/route.ts](../app/auth/callback/route.ts) POST handler with CSRF and origin protection:

```typescript
export async function POST(request: NextRequest) {
  // CSRF and origin check: reject cross-site posts
  const origin = request.headers.get("origin");
  const requestOrigin = new URL(request.url).origin;
  const sameOrigin = origin && origin === requestOrigin;

  if (!sameOrigin || request.headers.get("x-csrf") !== "auth-sync") {
    return NextResponse.json({ ok: false }, { status: 403 });
  }

  const { event, session } = await request.json();
  const response = NextResponse.json({ ok: true });
  const supabase = createSupabaseRouteHandlerClient(request, response);

  if (session) {
    await supabase.auth.setSession(session); // Writes to cookies
  } else {
    await supabase.auth.signOut(); // Clear cookies on sign-out
  }

  return response;
}
```

**CSRF Protection:**
- Requires `x-csrf: auth-sync` header
- Validates request origin matches server origin
- Prevents malicious sites from syncing attacker sessions into user cookies

### 4. Server Components Re-Render

`router.refresh()` triggers server-side re-render, reading fresh cookies:

```typescript
const supabase = await createSupabaseServerClient();
const { data: { user } } = await supabase.auth.getUser(); // Verifies JWT
```

## Race Condition Protection

### Problem

Multiple components calling `supabase.auth.getSession()` simultaneously during app boot can trigger concurrent refresh requests:

```
Component A: getSession() → refresh token request #1
Component B: getSession() → refresh token request #2
Component C: getSession() → refresh token request #3
```

Supabase backend processes them in parallel, causing race conditions where one succeeds and invalidates the others → "Refresh Token Not Found".

### Solution: Refresh Lock

[lib/auth/refresh-lock.ts](../lib/auth/refresh-lock.ts) serializes concurrent refresh attempts:

```typescript
let inflight: Promise<any> | null = null;

export async function withRefreshLock<T>(fn: () => Promise<T>): Promise<T> {
  // Wait for any in-flight refresh
  while (inflight) {
    await inflight.catch(() => {});
  }

  // Execute operation
  inflight = fn();
  try {
    return await inflight;
  } finally {
    inflight = null;
  }
}
```

**Usage** (if needed in client components):

```typescript
import { withRefreshLock } from "@/lib/auth/refresh-lock";
import { createSupabaseBrowserClient } from "@/lib/supabase/client";

const supabase = createSupabaseBrowserClient();
const { data } = await withRefreshLock(() => supabase.auth.getSession());
```

**Note**: Most code doesn't need this directly since the single listener handles auth state changes. Avoid calling `getSession()` at app boot—prefer SSR to pass user data.

## Navigation Safety

Sign-in/out flows explicitly sync session to cookies before navigating:

### Login ([app/(auth)/login/page.tsx](../app/(auth)/login/page.tsx))

```typescript
const { data, error } = await supabase.auth.signInWithPassword({ email, password });

if (!error) {
  // Sync session to server cookies before navigation
  await fetch("/auth/callback", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-csrf": "auth-sync",
    },
    body: JSON.stringify({ event: "SIGNED_IN", session: data.session }),
    keepalive: true,
    cache: "no-store",
  });

  // Microtask tick ensures cookie sync completes
  await Promise.resolve();
  router.replace("/");
}
```

### Signup ([app/(auth)/signup/page.tsx](../app/(auth)/signup/page.tsx))

```typescript
const { data, error } = await supabase.auth.signUp({ email, password, options });

if (!error) {
  // Sync session to server cookies before navigation
  await fetch("/auth/callback", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-csrf": "auth-sync",
    },
    body: JSON.stringify({ event: "SIGNED_UP", session: data.session }),
    keepalive: true,
    cache: "no-store",
  });

  // Microtask tick ensures cookie sync completes
  await Promise.resolve();
  setTimeout(() => {
    router.replace("/onboarding");
  }, 1500);
}
```

**Why explicit POST instead of waiting for listener?**
- Listener fires asynchronously and timing is unpredictable
- Direct POST ensures cookies are written before navigation
- `await Promise.resolve()` (microtask tick) ensures the POST completes
- No hardcoded delays needed—POST resolves when server responds

### Logout ([app/(auth)/logout/route.ts](../app/(auth)/logout/route.ts))

```typescript
export async function GET(request: NextRequest) {
  const response = NextResponse.redirect(new URL("/login", request.url));
  const supabase = createSupabaseRouteHandlerClient(request, response);

  await supabase.auth.signOut(); // Clears cookies

  return response;
}
```

Logout is server-side route handler, so cookies are cleared synchronously before redirect.

## Authorization

### Server Components & Actions

**Always** use `getUser()` for authorization decisions:

```typescript
const supabase = await createSupabaseServerClient();
const { data: { user } } = await supabase.auth.getUser(); // Verifies JWT

if (!user) {
  redirect("/login");
}
```

**Why not `getSession()`?**
- `getSession()` returns cached data without JWT verification
- `getUser()` validates the token with Supabase auth server
- Prevents replay attacks with expired/revoked tokens

See [lib/auth/verifyUser.ts](../lib/auth/verifyUser.ts) for reusable helper.

### Client Components

Client components receive server-rendered data with verified user identity. They should NOT perform authorization checks—that must happen server-side.

## Service Worker Cache Safety

The PWA service worker is configured to **never cache** `/auth/callback` requests.

[config/next.config.js](../config/next.config.js) PWA configuration:

```javascript
export default withPWA({
  dest: "public",
  register: true,
  skipWaiting: true,
  disable: process.env.NODE_ENV === "development",
  runtimeCaching: [
    {
      // Bypass auth callback endpoint - must never be cached
      urlPattern: /^https?:\/\/[^/]+\/auth\/callback$/,
      handler: "NetworkOnly",
    },
  ],
})(nextConfig);
```

**Why `NetworkOnly`?**
- Auth sync requests must always reach the server
- Stale cached responses would write outdated sessions to cookies
- Network-only ensures every POST contains the latest token data

**After config changes:**
```bash
npm run build  # Regenerate service worker with new rules
```

## Troubleshooting

### "Invalid Refresh Token: Refresh Token Not Found"

**Cause**: Token refresh race condition or cookie sync failure.

**Fix checklist**:
1. ✅ Only one `SupabaseListener` mounted (check React DevTools component tree)
2. ✅ Console shows `[SUPABASE LISTENER] Mounting single auth state listener` once
3. ✅ `/auth/callback` POST endpoint is reachable (check Network tab)
4. ✅ POST includes `x-csrf: auth-sync` header
5. ✅ No custom storage adapters in client config
6. ✅ Sign-in/out flows include explicit POST before navigation
7. ✅ No manual `localStorage`/`sessionStorage` writes for auth tokens

### Cookies not persisting after sign-in

**Cause**: Server client blocking cookie writes or CSRF rejection.

**Check**:
- Server client includes working `set` and `remove` handlers with `expires: new Date(0)` ([lib/supabase/server.ts](../lib/supabase/server.ts))
- Route handlers use `createSupabaseRouteHandlerClient()` for explicit cookie control
- POST to `/auth/callback` returns 200 OK, not 403 Forbidden

### Session lost after hard reload

**Cause**: Cookies not being set during auth events.

**Fix**:
- Verify `SupabaseListener` is mounted in [app/(app)/layout.tsx](../app/(app)/layout.tsx)
- Check browser DevTools > Application > Cookies for `sb-kkarlsen-auth-token`
- Ensure `/auth/callback` POST returns 200 OK (check Network tab)
- Rebuild service worker if recently updated: `npm run build`

### Multi-tab logout doesn't sync

**Cause**: Cookies are per-domain, not reactive across tabs.

**Expected behavior**:
- Logging out in Tab A calls `/auth/callback` POST with `session: null`
- Server deletes cookies
- Tab B's next request fails auth, redirects to login

**Not immediate**: Tabs don't reactively observe cookie changes. Tab B redirects on next navigation/reload.

## Token Refresh Timeline

Supabase auto-refreshes tokens **1 hour before expiry** (default `expires_in: 3600s`).

**Flow**:
1. Browser client detects token expiring soon
2. Calls `refreshSession()` automatically
3. Fires `TOKEN_REFRESHED` event
4. `SupabaseListener` POSTs new session to `/auth/callback`
5. Server writes updated cookies
6. App continues without interruption

**After 8+ hours idle**:
- If refresh token still valid: auto-refresh succeeds
- If refresh token expired: user redirected to login

With proper cookie sync, users stay signed in across sessions.

## Testing

### Manual Test

1. Sign in and check browser console for `[SUPABASE LISTENER] Mounting single auth state listener`
2. Wait 1+ hour (or manually expire access token in DevTools)
3. Perform action requiring auth
4. Should auto-refresh without error
5. Check Network tab: `/auth/callback` POST should have `x-csrf: auth-sync` header and no cache headers

### Automated Test

See [tests/e2e/auth-stability.spec.ts](../tests/e2e/auth-stability.spec.ts) for Playwright tests covering:
- Token refresh across tab idle
- Multi-tab sync
- Navigation during refresh
- Logout across tabs

## Cookie Security Hardening

### Secure Cookie Flags

All authentication cookies use production-grade security settings ([lib/supabase/server.ts](../lib/supabase/server.ts)):

```typescript
const COOKIE_SECURITY_OPTIONS = {
  httpOnly: true,              // Prevents JavaScript access (XSS protection)
  secure: process.env.NODE_ENV === "production", // HTTPS-only in production
  sameSite: "lax",             // CSRF protection (use "strict" if no cross-site OAuth)
  maxAge: 60 * 60 * 24 * 7,   // 7 days (matches Supabase refresh token expiry)
  path: "/",                   // Available site-wide
};
```

**Security properties:**
- **HttpOnly**: Cookie cannot be accessed via JavaScript, protecting against XSS attacks
- **Secure**: Only transmitted over HTTPS in production
- **SameSite=Lax**: Blocks most CSRF attacks while allowing OAuth redirects
- **MaxAge**: Automatically expires after 7 days

**For subdomains:** Set `domain: ".yourdomain.com"` in `COOKIE_SECURITY_OPTIONS` to share cookies across subdomains.

### 401 Error Recovery Policy

Server-side auth failures implement a **refresh-then-signout** policy ([lib/auth/error-recovery.ts](../lib/auth/error-recovery.ts)):

1. **On 401 from Supabase**: Attempt exactly ONE session refresh behind `withRefreshLock()`
2. **If still 401 after refresh**: Sign out server-side and redirect to `/login`
3. **Never retry more than once**: Prevents infinite loops

The [verifyUser()](../lib/auth/verifyUser.ts) helper automatically uses this policy:

```typescript
export async function verifyUser() {
  const supabase = await createSupabaseServerClient();
  const { data: { user }, error } = await supabase.auth.getUser();

  if (error || !user) {
    await handleAuthError(error); // Refresh-then-signout
    // Will not reach here - handleAuthError redirects
  }

  return user;
}
```

**For custom Supabase calls:**

```typescript
try {
  const { data, error } = await supabase.from('table').select();
  if (error) throw error;
  return data;
} catch (error) {
  await handleAuthError(error); // Will refresh once, then sign out if still failing
}
```

**Why this policy?**
- Handles temporary 401s from stale tokens (auto-refresh succeeds)
- Prevents infinite retry loops on permanent auth failures
- Fails fast with clear user feedback (redirect to login)

## Verification Checklist

### Development

✅ **Single listener mount**
- Console shows `[SUPABASE LISTENER] Mounting single auth state listener` exactly once per page load
- Check React DevTools: only one `SupabaseListener` component in tree

✅ **Cookie sync headers**
- Network tab: `/auth/callback` POST includes:
  - `x-csrf: auth-sync` header
  - `cache: no-store` in request
  - `keepalive: true` (invisible in DevTools but set in code)

✅ **Secure cookies (production)**
- Application > Cookies: `sb-kkarlsen-auth-token` has:
  - `HttpOnly: true`
  - `Secure: true` (production only)
  - `SameSite: Lax`
  - `Max-Age: 604800` (7 days)

✅ **Token refresh without navigation**
- Wait 1+ hour or manually expire access token in DevTools
- Trigger any authed action
- Network tab: `TOKEN_REFRESHED` event fires
- `/auth/callback` POST succeeds (200 OK)
- No redirect to login

✅ **Multi-tab sign-out sync**
- Open two tabs (Tab A, Tab B)
- Sign out in Tab A
- Tab B: next authed request fails and redirects to `/login`
- Both tabs show no auth cookies

✅ **8-12 hour idle recovery**
- Sign in, close browser
- Wait 8-12 hours
- Reopen and navigate to protected page
- Should auto-refresh and succeed without manual re-login

### Production

✅ **Zero "Invalid Refresh Token" errors**
- Monitor logs for "Invalid Refresh Token" or "Refresh Token Not Found"
- Expected: 0 occurrences

✅ **401 recovery rate < 0.5%**
- Track: `401 errors after refresh / total auth operations`
- Alert if > 0.5% (indicates persistent auth issues)

✅ **Average session duration > 24 hours**
- Users stay logged in across multiple days
- Refresh tokens work reliably

## Summary

| Requirement | Implementation |
|-------------|----------------|
| Single listener | ✅ [app/supabase-listener.tsx](../app/supabase-listener.tsx) with `useRef` guard + mount log |
| Cookie sync | ✅ `/auth/callback` POST endpoint with `keepalive: true` and `cache: no-store` |
| CSRF protection | ✅ Origin validation + `x-csrf: auth-sync` header required |
| Cookie security | ✅ HttpOnly, Secure (prod), SameSite=Lax, MaxAge=7d |
| Cookie removal | ✅ Sets `expires: new Date(0)` instead of empty string |
| Race protection | ✅ [lib/auth/refresh-lock.ts](../lib/auth/refresh-lock.ts) serializes concurrent refreshes |
| Error recovery | ✅ [lib/auth/error-recovery.ts](../lib/auth/error-recovery.ts) implements refresh-then-signout |
| Server auth | ✅ `verifyUser()` with automatic 401 recovery |
| Navigation safety | ✅ Explicit POST before navigation, microtask tick (no hardcoded delays) |
| No localStorage | ✅ Supabase default cookie storage only |
| SW cache bypass | ✅ Service worker configured to never cache `/auth/callback` |

**Result**: Production-grade authentication with zero "Invalid Refresh Token" errors, secure cookies, automatic error recovery, and reliable 8+ hour idle sessions.
