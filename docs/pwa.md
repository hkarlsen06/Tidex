# Progressive Web App (PWA) Implementation

This document describes the PWA implementation for next-tidex.dev, including caching strategies and offline testing procedures.

## Architecture

### Service Worker

The application uses a **static Service Worker** ([public/sw.js](../public/sw.js)) implemented with **Workbox 6.6.0** loaded from CDN. This is a Turbopack-compatible solution that replaced the previous `next-pwa` webpack-based implementation.

**Key features:**

- Zero build-time dependencies (no webpack plugins)
- Works seamlessly with Next.js 16 + Turbopack
- Identical caching behavior to the previous next-pwa configuration

### Registration

The Service Worker is registered client-side via [app/sw-register.tsx](../app/sw-register.tsx), a Client Component imported in [app/layout.tsx](../app/layout.tsx). Registration only occurs:

- In production builds (`NODE_ENV === 'production'`)
- When the browser supports Service Workers
- Once on mount (via `useEffect`)

## Caching Strategy

### NetworkOnly (No Cache)

**Route:** `/auth/callback`

**Rationale:** OAuth and magic link callbacks must always hit the server to exchange tokens. Caching would break authentication flows.

```javascript
workbox.routing.registerRoute(
  ({ url }) => url.pathname === "/auth/callback",
  new workbox.strategies.NetworkOnly(),
  "GET"
);
```

### StaleWhileRevalidate

**Routes:** `/`, `/shifts`, `/stats`, `/settings` (including sub-routes)

**Cache configuration:**

- **TTL:** 60 seconds (`maxAgeSeconds: 60`)
- **Max entries:** 10 per cache (`maxEntries: 10`)

**Behavior:**

1. First request: Fetch from network, store in cache
2. Subsequent requests (within TTL): Serve from cache immediately, revalidate in background
3. After TTL expiration: Serve stale content, fetch and update cache in background
4. If cache exceeds 10 entries: Evict oldest entries (LRU)

**Cache names:**

- `page-root` - Root page
- `page-shifts` - Shifts list and detail pages
- `page-stats` - Statistics page
- `page-settings` - Settings pages

```javascript
workbox.routing.registerRoute(
  ({ url, request }) => request.method === "GET" && url.pathname === "/",
  new workbox.strategies.StaleWhileRevalidate({
    cacheName: "page-root",
    plugins: [
      new workbox.expiration.ExpirationPlugin({
        maxEntries: 10,
        maxAgeSeconds: 60,
      }),
    ],
  }),
  "GET"
);
```

## Manifest & Icons

- **Manifest:** [public/manifest.json](../public/manifest.json)
- **Icons:** Various sizes in `public/` directory
  - Android: `icon-192x192.png`, `icon-384x384.png`, `icon-512x512.png`
  - iOS: `apple-touch-icon.png` (180x180)
- **Metadata:** Configured in [app/layout.tsx](../app/layout.tsx)

## Testing

### 1. Production Build

The Service Worker only registers in production:

```bash
npm run build
npm run start
```

### 2. Verify Registration

Open Chrome DevTools → Application → Service Workers:

- **Expected:** `/sw.js` listed with status "activated and is running"
- **Scope:** `/`

### 3. Test Caching Behavior

#### Test Cached Routes

1. Navigate to `/`, `/shifts`, `/stats`, `/settings`
2. Open DevTools → Network tab
3. Check the "Size" column:
   - First visit: Size shows actual bytes (e.g., "15.2 kB")
   - Subsequent visits: Size shows "(ServiceWorker)" or "(from ServiceWorker)"

#### Test NetworkOnly Route

1. Navigate to `/auth/callback?code=test`
2. Network tab should show:
   - Request goes to network
   - **No ServiceWorker cache** indicator
   - Response comes from server (or 404/error if no valid auth code)

### 4. Test Offline Functionality

#### Simulate Offline Mode

1. Visit `/`, `/shifts`, `/stats`, `/settings` once (to prime caches)
2. Open DevTools → Network tab
3. Enable "Offline" checkbox (or throttle to "Offline")
4. Refresh the page or navigate between cached routes

**Expected behavior:**

- Cached routes (`/`, `/shifts`, etc.) load from cache
- `/auth/callback` fails (no network, no cache)
- Uncached routes fail to load

### 5. Test TTL Expiration

1. Visit `/shifts` (caches the page)
2. Wait **60+ seconds**
3. Revisit `/shifts`

**Expected behavior:**

- Page loads immediately from cache (stale content)
- Background network request fetches fresh content
- Next visit shows updated content

### 6. Test Max Entries Eviction

1. Visit 15+ unique URLs under `/shifts` (e.g., `/shifts?page=1`, `/shifts?page=2`, etc.)
2. Check DevTools → Application → Cache Storage → `page-shifts`

**Expected behavior:**

- Cache contains max 10 entries
- Oldest entries are evicted (LRU policy)

### 7. Lighthouse PWA Audit

Run Lighthouse in Chrome DevTools (Lighthouse tab):

```bash
# Or use CLI
npm install -g lighthouse
lighthouse http://localhost:3000 --view
```

**Expected scores:**

- **Installable:** ✓ Manifest and icons present
- **Offline capable:** ✓ Service Worker registered and caching pages
- **PWA optimized:** ✓ Theme color, viewport, etc.

## Troubleshooting

### Service Worker Not Registering

**Symptoms:** DevTools → Application shows "No service workers"

**Solutions:**

1. Verify you're in **production mode** (`npm run build && npm start`)
2. Check browser console for registration errors
3. Ensure `public/sw.js` exists and is accessible at `http://localhost:3000/sw.js`
4. Verify HTTPS or localhost (Service Workers require secure context)

### Stale Content Not Updating

**Symptoms:** Page shows old content even after waiting >60s

**Solutions:**

1. Hard refresh (Ctrl+Shift+R / Cmd+Shift+R)
2. Unregister SW in DevTools → Application → Service Workers → Unregister
3. Clear cache storage in DevTools → Application → Cache Storage → Delete

### Build Errors with Turbopack

**Symptoms:** `Build failed` errors mentioning webpack or next-pwa

**Solutions:**

1. Ensure `next-pwa` is **removed** from `package.json`
2. Verify `next.config.js` has **no `webpack` function**
3. Confirm `turbopack: {}` is present in config
4. Clean install: `rm -rf node_modules package-lock.json && npm install`

## Migration from next-pwa

This implementation replaced `next-pwa` (webpack-only) with a static Workbox-based Service Worker for Turbopack compatibility. Key changes:

1. **Removed:** `next-pwa` package and webpack plugin
2. **Added:** Static `public/sw.js` with Workbox CDN
3. **Added:** Client-side registration via `app/sw-register.tsx`
4. **Preserved:** Identical caching strategies, TTLs, and route handling

**No runtime behavior changes** - only the build tooling changed.

## References

- [Workbox Documentation](https://developer.chrome.com/docs/workbox/)
- [Service Worker API](https://developer.mozilla.org/en-US/docs/Web/API/Service_Worker_API)
- [Web App Manifest](https://developer.mozilla.org/en-US/docs/Web/Manifest)
- [Next.js Custom Server + PWA](https://nextjs.org/docs/advanced-features/custom-server)
