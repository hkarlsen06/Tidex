/**
 * Service Worker for Tidex PWA (Next.js 16 App Router)
 * Minimal implementation focused on PWA requirements
 *
 * @fileoverview
 * This service worker provides static asset caching and offline fallback.
 *
 * Features:
 * - Cache-first for static assets (icons, fonts, Next.js static files)
 * - Offline page fallback for failed navigation requests
 * - No background sync or mutation queues
 * - No caching of API/data requests
 *
 * VERSIONING:
 * Increment CACHE_VERSION when deploying updates.
 */

// ============================================================================
// CONFIGURATION
// ============================================================================

/** @type {string} Cache version - increment on each deploy to invalidate old caches */
const CACHE_VERSION = 'v16';

/** @type {number} Navigation fetch timeout in milliseconds */
const NAV_TIMEOUT_MS = 5000;

/** @type {number} Delay before retry attempt in milliseconds */
const NAV_RETRY_DELAY_MS = 300;

/** @type {string} Cache for immutable static assets (JS, CSS, fonts, images) */
const STATIC_CACHE = `tidex-static-${CACHE_VERSION}`;

/** @type {string} Cache for offline fallback page */
const OFFLINE_CACHE = `tidex-offline-${CACHE_VERSION}`;

/** @type {string} Cache for navigation responses (app shell) */
const NAV_CACHE = `tidex-nav-${CACHE_VERSION}`;

/** @type {string} Offline fallback page path */
const OFFLINE_PAGE = '/offline.html';

// ============================================================================
// INSTALL EVENT
// ============================================================================

self.addEventListener('install', (event) => {
  console.log('[SW] Install event - version:', CACHE_VERSION);

  // Precache the offline page for app wrapper compatibility
  event.waitUntil(
    caches.open(OFFLINE_CACHE)
      .then((cache) => cache.add(OFFLINE_PAGE))
      .then(() => self.skipWaiting())
  );
});

// ============================================================================
// ACTIVATE EVENT - Cleanup & Take Control
// ============================================================================

self.addEventListener('activate', (event) => {
  console.log('[SW] Activate event - version:', CACHE_VERSION);

  event.waitUntil(
    caches.keys()
      .then((cacheNames) => {
        const cachesToDelete = cacheNames.filter((cacheName) => {
          return cacheName.startsWith('tidex-') &&
                 !cacheName.endsWith(CACHE_VERSION);
        });
        return Promise.all(
          cachesToDelete.map((cacheName) => caches.delete(cacheName))
        );
      })
      .then(() => self.clients.claim())
  );
});

// ============================================================================
// FETCH EVENT - Request Interception & Caching
// ============================================================================

self.addEventListener('fetch', (event) => {
  const { request } = event;
  const { url, method, mode } = request;

  // Only handle GET requests
  if (method !== 'GET') {
    return;
  }

  // Only handle same-origin requests
  if (!url.startsWith(self.location.origin)) {
    return;
  }

  // Never cache auth endpoints
  if (url.includes('/auth/') || url.includes('.supabase.co')) {
    return;
  }

  // Navigation requests: Network-first with offline fallback.
  // If the network fails (offline), serve the cached offline page.
  // This is essential for app store wrappers that require offline support.
  if (mode === 'navigate') {
    event.respondWith(handleNavigation(request));
    return;
  }

  // JS/CSS chunks: Network-first to prevent stale chunk errors after deploys.
  // ChunkLoadError occurs when cached chunks don't match new deployment.
  // Using network-first ensures fresh chunks are fetched, with cache fallback for offline.
  if (isChunkAsset(url)) {
    event.respondWith(handleChunkAsset(request));
    return;
  }

  // Static assets (images, fonts, etc.): Cache-first for performance
  if (isStaticAsset(url)) {
    event.respondWith(handleStaticAsset(request));
    return;
  }

  // Everything else: Network-only (no caching for API/data)
});

/**
 * Race a promise against a timeout.
 * Rejects with 'NAV_TIMEOUT' error if timeout expires first.
 */
function withTimeout(promise, ms) {
  return Promise.race([
    promise,
    new Promise((_, reject) =>
      setTimeout(() => reject(new Error('NAV_TIMEOUT')), ms)
    ),
  ]);
}

/**
 * Attempt a network fetch with timeout.
 */
async function networkAttempt(request) {
  return await withTimeout(fetch(request), NAV_TIMEOUT_MS);
}

/**
 * Handle navigation requests with network-first strategy.
 *
 * Key behavior to prevent false offline detection:
 * - 5-second timeout prevents hanging on slow networks/cold starts
 * - On timeout, immediately try cache before retrying (faster for App Review)
 * - Retry once after small delay on first failure
 * - Cache successful navigation responses for future offline fallback
 * - Only show offline.html as absolute last resort
 *
 * This prevents Apple reviewers (or users on slow networks) from seeing
 * the offline page due to a single transient failure.
 */
async function handleNavigation(request) {
  // First attempt
  try {
    const response = await networkAttempt(request);
    // Cache successful navigation responses for offline fallback
    if (response && response.ok) {
      cacheNavigationResponse(request, response.clone());
    }
    return response;
  } catch (err1) {
    console.log('[SW] Navigation attempt 1 failed:', err1.message);

    // On timeout, try cache immediately (faster UX for App Review)
    if (err1.message === 'NAV_TIMEOUT') {
      const cachedNav = await caches.match(request, { ignoreSearch: true });
      if (cachedNav) {
        console.log('[SW] Timeout - serving cached navigation response');
        return cachedNav;
      }
    }

    // Small delay helps with transient DNS/TLS/cold start issues
    await new Promise((r) => setTimeout(r, NAV_RETRY_DELAY_MS));

    // Second attempt
    try {
      const response = await networkAttempt(request);
      if (response && response.ok) {
        cacheNavigationResponse(request, response.clone());
      }
      return response;
    } catch (err2) {
      console.log('[SW] Navigation attempt 2 failed:', err2.message);

      // Try cached navigation response (app shell) before offline page
      const cachedNav = await caches.match(request, { ignoreSearch: true });
      if (cachedNav) {
        console.log('[SW] Serving cached navigation response');
        return cachedNav;
      }

      // For unauthenticated users, try serving cached login page as fallback
      // This gives users a usable UI instead of generic offline screen
      // Skip this for logged-in users (who have auth cookies) to avoid confusion
      if (!hasAuthCookie(request)) {
        const cachedLoginPage = await findCachedLoginPage(request);
        if (cachedLoginPage) {
          console.log('[SW] Serving cached login page as fallback');
          return cachedLoginPage;
        }
      }

      // Last resort: offline page
      console.log('[SW] Serving offline page');
      const offline = await caches.match(OFFLINE_PAGE);
      if (offline) {
        return offline;
      }

      // If offline page not cached (shouldn't happen), return basic response
      return new Response('Offline', {
        status: 503,
        headers: { 'Content-Type': 'text/plain; charset=utf-8' },
      });
    }
  }
}

/**
 * Check if the request has a Supabase auth cookie.
 * Used to detect logged-in users and avoid showing login page to them.
 *
 * Supabase cookie formats:
 * - sb-{projectRef}-auth-token (main session token, may be chunked: .0, .1, etc.)
 * - sb-{projectRef}-refresh-token (refresh token)
 *
 * We check for auth-token presence as the primary indicator of a logged-in user.
 */
function hasAuthCookie(request) {
  const cookieHeader = request.headers.get('cookie') || '';
  if (!cookieHeader) return false;

  // Check for Supabase auth token patterns:
  // - sb-{projectRef}-auth-token (standard)
  // - sb-{projectRef}-auth-token.0 (chunked for large tokens)
  // The pattern is: starts with 'sb-', contains '-auth-token'
  const hasAuthToken = /sb-[a-z0-9]+-auth-token/.test(cookieHeader);

  return hasAuthToken;
}

/**
 * Find a cached login page to use as fallback for failed navigation.
 * Tries to match the user's locale preference from the original request.
 *
 * @param {Request} originalRequest - The failed navigation request (used to detect locale)
 */
async function findCachedLoginPage(originalRequest) {
  try {
    const cache = await caches.open(NAV_CACHE);
    const keys = await cache.keys();

    // Extract locale from the original request URL (e.g., /en/shifts -> 'en')
    const originalUrl = new URL(originalRequest.url);
    const pathParts = originalUrl.pathname.split('/').filter(Boolean);
    const requestedLocale = pathParts[0]; // First segment is locale (en, no, etc.)

    // Collect all cached login pages
    const loginPages = [];
    for (const req of keys) {
      const url = new URL(req.url);
      if (url.pathname.includes('/login')) {
        const pageParts = url.pathname.split('/').filter(Boolean);
        const pageLocale = pageParts[0];
        loginPages.push({ request: req, locale: pageLocale });
      }
    }

    if (loginPages.length === 0) {
      return null;
    }

    // Try to find login page matching the requested locale
    const matchingLocale = loginPages.find((p) => p.locale === requestedLocale);
    if (matchingLocale) {
      console.log('[SW] Found cached login page for locale:', requestedLocale);
      return await cache.match(matchingLocale.request);
    }

    // Fall back to any cached login page
    console.log('[SW] Using fallback cached login page, locale:', loginPages[0].locale);
    return await cache.match(loginPages[0].request);
  } catch (error) {
    console.log('[SW] Error finding cached login page:', error);
  }
  return null;
}

/**
 * Cache a navigation response for offline fallback.
 *
 * Safety checks:
 * - Only cache 200 OK responses (response.ok checked by caller)
 * - Only cache HTML content (not JSON, redirects, etc.)
 * - Only cache basic/default response types (not opaque/cors)
 * - Only cache PUBLIC auth routes (login, signup, etc.) - no user-specific data
 * - Do NOT cache PROTECTED routes (/, /shifts, /stats) - they contain user data
 *
 * Terminology:
 * - "Public auth routes" = login, signup, reset-password, verify-email (no user data)
 * - "Protected routes" = /, /shifts, /stats, /settings (contain server-rendered user data)
 *
 * This ensures we cache the final HTML shell, not intermediate redirects,
 * and avoids privacy issues on shared devices.
 */
function cacheNavigationResponse(request, response) {
  // Only cache basic responses (same-origin, not opaque)
  if (response.type !== 'basic' && response.type !== 'default') {
    return;
  }

  // Only cache HTML responses
  const contentType = response.headers.get('content-type') || '';
  if (!contentType.includes('text/html')) {
    return;
  }

  // Only cache PUBLIC auth routes (login, signup, etc.)
  // These pages don't contain user-specific data and are safe to cache
  const url = new URL(request.url);
  const path = url.pathname;
  const isPublicAuthRoute =
    path.includes('/login') ||
    path.includes('/signup') ||
    path.includes('/reset-password') ||
    path.includes('/verify-email');

  if (!isPublicAuthRoute) {
    // Don't cache protected routes - they contain server-rendered user data
    // (userName, avatarUrl, currency, etc.)
    return;
  }

  caches.open(NAV_CACHE).then((cache) => {
    cache.put(request, response);
  });
}

/**
 * Handle JS/CSS chunk assets with network-first strategy.
 * Prevents ChunkLoadError after deployments by always fetching fresh chunks.
 * Falls back to cache only when offline.
 */
async function handleChunkAsset(request) {
  try {
    // Always try network first for chunks
    const response = await fetch(request);
    if (response && response.ok) {
      // Cache the fresh chunk for offline fallback
      const responseToCache = response.clone();
      caches.open(STATIC_CACHE).then((cache) => {
        cache.put(request, responseToCache);
      });
    }
    return response;
  } catch (error) {
    // Network failed - try cache as fallback (offline mode)
    const cachedResponse = await caches.match(request);
    if (cachedResponse) {
      return cachedResponse;
    }
    // No cache available, let the request fail
    throw error;
  }
}

async function handleStaticAsset(request) {
  const cachedResponse = await caches.match(request);
  if (cachedResponse) {
    return cachedResponse;
  }

  try {
    const response = await fetch(request);
    if (response && response.ok) {
      const responseToCache = response.clone();
      caches.open(STATIC_CACHE).then((cache) => {
        cache.put(request, responseToCache);
      });
    }
    return response;
  } catch (error) {
    // On failure, just let the request fail normally.
    // No custom offline responses.
    throw error;
  }
}

// ============================================================================
// UTILITY FUNCTIONS
// ============================================================================

/**
 * Check if URL is a JS/CSS chunk that should use network-first strategy.
 * These files change on each deployment and stale versions cause ChunkLoadError.
 */
function isChunkAsset(url) {
  // Match /_next/static/chunks/*.js and /_next/static/css/*.css
  return (
    url.includes('/_next/static/chunks/') ||
    url.includes('/_next/static/css/')
  );
}

/**
 * Check if URL is a static asset that can use cache-first strategy.
 * Excludes JS/CSS chunks which need network-first.
 */
function isStaticAsset(url) {
  // Exclude chunks (handled separately with network-first)
  if (isChunkAsset(url)) {
    return false;
  }

  return (
    // Other Next.js static assets (media, fonts bundled by Next)
    url.includes('/_next/static/media/') ||
    // Image and font file extensions
    url.match(/\.(png|jpg|jpeg|gif|svg|webp|ico|avif|woff|woff2|ttf|otf|eot)$/i)
  );
}

// ============================================================================
// MESSAGE HANDLER
// ============================================================================

self.addEventListener('message', (event) => {
  const { data } = event;

  if (!data || !data.type) {
    return;
  }

  if (data.type === 'SKIP_WAITING') {
    self.skipWaiting();
  }
});
