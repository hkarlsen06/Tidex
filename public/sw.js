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
const CACHE_VERSION = 'v14';

/** @type {string} Cache for immutable static assets (JS, CSS, fonts, images) */
const STATIC_CACHE = `tidex-static-${CACHE_VERSION}`;

/** @type {string} Cache for offline fallback page */
const OFFLINE_CACHE = `tidex-offline-${CACHE_VERSION}`;

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

  // Static assets: Cache-first for performance
  if (isStaticAsset(url)) {
    event.respondWith(handleStaticAsset(request));
    return;
  }

  // Everything else: Network-only (no caching for API/data)
});

/**
 * Handle navigation requests with network-first strategy.
 * Falls back to offline page if network is unavailable.
 */
async function handleNavigation(request) {
  try {
    // Try network first
    const response = await fetch(request);
    return response;
  } catch (error) {
    // Network failed - serve offline page
    console.log('[SW] Navigation failed, serving offline page');
    const offlineResponse = await caches.match(OFFLINE_PAGE);
    if (offlineResponse) {
      return offlineResponse;
    }
    // If offline page not cached (shouldn't happen), throw original error
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

function isStaticAsset(url) {
  return (
    url.includes('/_next/static/') ||
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
