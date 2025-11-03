# Troubleshoot Supabase Cookie Configuration

Guide for diagnosing and fixing "Refresh Token Not Found" errors caused by cookie configuration mismatches.

## When to use this skill

- Seeing "Refresh Token Not Found" errors
- Authentication randomly fails or users get logged out
- Cookies not persisting across requests
- Token refresh failing silently
- After deploying to new environment (localhost → production)

## Problem: Cookie Configuration Mismatches

**Root cause**: Different Supabase clients (proxy, server, browser) must use **identical cookie configurations**. Any mismatch in `secure`, `httpOnly`, `sameSite`, `path`, or `maxAge` will cause cookies to be unreadable, breaking token refresh.

Common scenarios:
- `secure: true` in server client but `secure: false` in proxy
- Different `sameSite` values between clients
- Hardcoded cookie options instead of shared config

## Solution: Centralized Cookie Configuration

All cookie configuration is centralized in `lib/auth/cookie-config.ts`. All Supabase clients MUST import from this file.

### Three Clients, One Config

```tsx
// 1. Proxy (proxy.ts)
import { buildProxyCookieOptions } from '@/lib/auth/cookie-config';

export async function proxy(request: NextRequest) {
  const response = NextResponse.next({ request });

  await createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    buildProxyCookieOptions(request, response) // Request-aware
  );
}

// 2. Server client (lib/supabase/server.ts)
import { buildServerCookieOptions } from '@/lib/auth/cookie-config';

export async function createSupabaseServerClient() {
  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    await buildServerCookieOptions() // Environment-based
  );
}

// 3. Browser client (lib/supabase/browser.ts)
import { buildBrowserCookieOptions } from '@/lib/auth/cookie-config';

export const supabase = createBrowserClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
  buildBrowserCookieOptions() // Window-aware
);
```

## Diagnostic Steps

### Step 1: Check for inline cookie configurations

Search for hardcoded cookie options:

```bash
# Search for inline cookie configs
grep -r "httpOnly.*sameSite" --include="*.ts" --include="*.tsx"
```

**Bad (inline config):**
```tsx
// ❌ DON'T DO THIS
createServerClient(url, key, {
  cookies: {
    get(name) { ... },
    set(name, value, options) { ... },
    remove(name, options) { ... }
  },
  cookieOptions: {
    httpOnly: true,
    sameSite: 'lax',
    secure: true, // Hardcoded!
    path: '/'
  }
});
```

**Good (shared config):**
```tsx
// ✅ DO THIS
import { buildServerCookieOptions } from '@/lib/auth/cookie-config';

createServerClient(url, key, await buildServerCookieOptions());
```

### Step 2: Verify cookie-config.ts implementation

Check `lib/auth/cookie-config.ts` exists and has consistent logic:

```tsx
// lib/auth/cookie-config.ts

// Determine if cookies should be secure
function isSecure(): boolean {
  // Use NEXT_PUBLIC_SITE_URL if available
  if (process.env.NEXT_PUBLIC_SITE_URL) {
    return process.env.NEXT_PUBLIC_SITE_URL.startsWith('https://');
  }

  // Production = secure, development = not secure (for localhost)
  return process.env.NODE_ENV === 'production';
}

// Shared cookie settings (MUST be identical across all clients)
const SHARED_COOKIE_OPTIONS = {
  httpOnly: true,
  sameSite: 'lax' as const,
  path: '/',
  maxAge: 60 * 60 * 24 * 7, // 7 days
};

export function buildProxyCookieOptions(request, response) {
  const secure = isSecure();

  return {
    cookies: {
      get(name) {
        return request.cookies.get(name)?.value;
      },
      set(name, value, options) {
        response.cookies.set({ name, value, ...options });
      },
      remove(name, options) {
        response.cookies.set({ name, value: '', ...options });
      }
    },
    cookieOptions: {
      ...SHARED_COOKIE_OPTIONS,
      secure
    }
  };
}

export async function buildServerCookieOptions() {
  const cookieStore = await cookies();
  const secure = isSecure();

  return {
    cookies: {
      get(name) {
        return cookieStore.get(name)?.value;
      },
      set(name, value, options) {
        cookieStore.set({ name, value, ...options });
      },
      remove(name, options) {
        cookieStore.set({ name, value: '', ...options });
      }
    },
    cookieOptions: {
      ...SHARED_COOKIE_OPTIONS,
      secure
    }
  };
}

export function buildBrowserCookieOptions() {
  const secure = window.location.protocol === 'https:';

  return {
    cookieOptions: {
      ...SHARED_COOKIE_OPTIONS,
      secure
    }
  };
}
```

### Step 3: Inspect browser cookies

Open DevTools → Application → Cookies and check:

1. **Cookie names**: Should see `sb-<project>-auth-token` and related cookies
2. **Secure flag**:
   - Localhost: Should be unchecked (HTTP)
   - Production: Should be checked (HTTPS)
3. **SameSite**: Should be "Lax"
4. **HttpOnly**: Should be checked for auth tokens
5. **Path**: Should be "/"
6. **Expiry**: Should be ~7 days from now

### Step 4: Check environment variables

```bash
# Verify NEXT_PUBLIC_SITE_URL is correct
echo $NEXT_PUBLIC_SITE_URL

# Localhost should be http://
# Production should be https://
```

If `NEXT_PUBLIC_SITE_URL` is missing, the `isSecure()` logic falls back to `NODE_ENV === 'production'`.

### Step 5: Test token refresh

Monitor the Network tab for auth token refresh:

1. Open DevTools → Network
2. Filter by "token"
3. Trigger a page navigation
4. Look for POST to `/auth/v1/token?grant_type=refresh_token`
5. Check response: Should be 200 with new tokens

**Common failures:**
- 400 "Refresh Token Not Found" → Cookie mismatch
- 401 "Invalid Refresh Token" → Token expired or revoked
- No request at all → Middleware not running

## Fixing Cookie Mismatches

### Fix 1: Remove inline configurations

**Before:**
```tsx
// proxy.ts
const response = NextResponse.next({ request });

await createServerClient(url, key, {
  cookies: { ... },
  cookieOptions: {
    secure: true, // ❌ Hardcoded
    httpOnly: true,
    sameSite: 'lax',
    path: '/'
  }
});
```

**After:**
```tsx
// proxy.ts
import { buildProxyCookieOptions } from '@/lib/auth/cookie-config';

const response = NextResponse.next({ request });

await createServerClient(
  url,
  key,
  buildProxyCookieOptions(request, response) // ✅ Shared config
);
```

### Fix 2: Ensure consistent secure flag resolution

All three builders should use the same `isSecure()` logic:

```tsx
// lib/auth/cookie-config.ts
function isSecure(): boolean {
  if (process.env.NEXT_PUBLIC_SITE_URL) {
    return process.env.NEXT_PUBLIC_SITE_URL.startsWith('https://');
  }
  return process.env.NODE_ENV === 'production';
}
```

Then browser client can use window location:

```tsx
export function buildBrowserCookieOptions() {
  const secure = typeof window !== 'undefined'
    ? window.location.protocol === 'https:'
    : isSecure(); // Fallback for SSR

  return { cookieOptions: { ...SHARED_COOKIE_OPTIONS, secure } };
}
```

### Fix 3: Verify Next.js 16 async cookies()

In Next.js 16, `cookies()` is async. Ensure server cookie builder awaits it:

```tsx
// ❌ Next.js 15 (old)
export function buildServerCookieOptions() {
  const cookieStore = cookies(); // Sync
  // ...
}

// ✅ Next.js 16 (new)
export async function buildServerCookieOptions() {
  const cookieStore = await cookies(); // Async
  // ...
}
```

Then update callers:

```tsx
// lib/supabase/server.ts
export async function createSupabaseServerClient() {
  return createServerClient(
    url,
    key,
    await buildServerCookieOptions() // Add await
  );
}
```

## Verification

After fixes, verify:

- [ ] All three clients import from `lib/auth/cookie-config.ts`
- [ ] No inline cookie configurations in codebase
- [ ] `secure` flag resolves consistently (check DevTools)
- [ ] Token refresh works (Network tab shows successful POST)
- [ ] No "Refresh Token Not Found" errors in console
- [ ] Authentication persists across page refreshes

## Testing Checklist

1. **Localhost (HTTP):**
   - [ ] Cookies have `Secure: false`
   - [ ] Login persists across refreshes
   - [ ] Token refresh succeeds

2. **Production (HTTPS):**
   - [ ] Cookies have `Secure: true`
   - [ ] Login persists across refreshes
   - [ ] Token refresh succeeds

3. **Cross-environment:**
   - [ ] Deploying to production doesn't break auth
   - [ ] Switching from localhost to preview URL works

## Common Pitfalls

### Pitfall 1: Different secure flag logic

```tsx
// ❌ Proxy uses NODE_ENV, server uses SITE_URL
// proxy.ts: secure = NODE_ENV === 'production'
// server.ts: secure = SITE_URL.startsWith('https://')
// Result: Mismatch on preview deployments
```

**Solution:** Use consistent `isSecure()` function everywhere.

### Pitfall 2: Forgetting browser client

Developers often fix proxy.ts and server.ts but forget browser client still has hardcoded config.

**Solution:** Audit all three clients.

### Pitfall 3: Not awaiting async cookies()

```tsx
// ❌ Next.js 16
const cookieStore = cookies(); // Missing await
```

**Solution:** Always `await cookies()` in Next.js 16.

## Emergency Reset

If completely stuck:

1. **Clear all cookies** in DevTools
2. **Restart dev server**: `npm run dev`
3. **Re-login** to get fresh tokens
4. **Monitor Network tab** during login to verify cookie settings

## Reference

See also:
- `docs/auth.md` - Authentication flow documentation
- `lib/auth/cookie-config.ts` - Cookie configuration source
- `proxy.ts` - Middleware token refresh
- `lib/supabase/server.ts` - Server client
- `lib/supabase/browser.ts` - Browser client
