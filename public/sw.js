/**
 * Service Worker for Tidex PWA (Next.js 16 App Router)
 * Minimal implementation focused on PWA requirements
 *
 * @fileoverview
 * This service worker provides only basic static asset caching.
 *
 * Features:
 * - Cache-first for static assets (icons, fonts, Next.js static files)
 * - No offline page or HTML routing
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
const CACHE_VERSION = 'v13';

/** @type {string} Cache for immutable static assets (JS, CSS, fonts, images) */
const STATIC_CACHE = `tidex-static-${CACHE_VERSION}`;

// ============================================================================
// INSTALL EVENT
// ============================================================================

self.addEventListener('install', () => {
  console.log('[SW] Install event - version:', CACHE_VERSION);
  // No precache: everything is cached lazily on first request
  self.skipWaiting();
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

  // Navigation requests: Let the browser handle them directly.
  // This avoids Safari/iOS quirks where SW-controlled navigations
  // can cause very long blank loads and URL bar flicker.
  // We still keep SW for static asset caching.
  if (mode === 'navigate') {
    return;
  }

  // Static assets: Cache-first for performance
  if (isStaticAsset(url)) {
    event.respondWith(handleStaticAsset(request));
    return;
  }

  // Everything else: Network-only (no caching for API/data)
});

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
