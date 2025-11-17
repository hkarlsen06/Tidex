/**
 * Service Worker for Tidex PWA (Next.js 16 App Router)
 * Minimal implementation focused on PWA requirements
 *
 * @fileoverview
 * This service worker provides basic PWA functionality without heavy caching
 * that could impact page load performance.
 *
 * Features:
 * - Minimal precaching (manifest + icons only)
 * - Simple offline fallback page
 * - No background sync or mutation queues
 * - No aggressive route precaching
 * - Cache-first only for truly static assets
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

/** @type {string} Path to offline fallback page */
const OFFLINE_URL = '/offline.html';

/**
 * Minimal assets to precache - only PWA essentials
 * @type {string[]}
 */
const PRECACHE_ASSETS = [
  OFFLINE_URL,
  '/manifest.json',
  '/icon-192x192.png',
  '/icon-512x512.png',
];

// ============================================================================
// INSTALL EVENT - Precache Critical Assets
// ============================================================================

self.addEventListener('install', (event) => {
  console.log('[SW] Install event - version:', CACHE_VERSION);

  event.waitUntil(
    caches.open(STATIC_CACHE)
      .then((cache) => cache.addAll(PRECACHE_ASSETS))
      .then(() => self.skipWaiting())
      .catch((error) => {
        console.error('[SW] Precaching failed:', error);
        return self.skipWaiting();
      })
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

  // Navigation requests: Network-first with offline fallback
  if (mode === 'navigate') {
    event.respondWith(handleNavigationRequest(request));
    return;
  }

  // Static assets: Cache-first for performance
  if (isStaticAsset(url)) {
    event.respondWith(handleStaticAsset(request));
    return;
  }

  // Everything else: Network-only (no caching for API/data)
});

// ============================================================================
// CACHING STRATEGIES
// ============================================================================

async function handleNavigationRequest(request) {
  try {
    // Always try network first for fresh content
    const response = await fetch(request);
    return response;
  } catch (error) {
    // Network failed - serve offline page
    const offlineResponse = await caches.match(OFFLINE_URL);
    return offlineResponse || new Response(
      '<html><body><h1>Offline</h1><p>Please connect to the internet.</p></body></html>',
      { headers: { 'Content-Type': 'text/html' }, status: 503 }
    );
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
    if (request.destination === 'image') {
      return new Response(
        'R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7',
        { headers: { 'Content-Type': 'image/gif' } }
      );
    }
    return new Response('Asset unavailable', { status: 503 });
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
