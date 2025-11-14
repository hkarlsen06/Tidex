/**
 * Service Worker for Tidex PWA (Next.js 16 App Router)
 * Production-ready implementation with SSR awareness
 *
 * @fileoverview
 * This service worker provides offline support and performance optimization
 * for a server-rendered Next.js application hosted on Vercel.
 *
 * ARCHITECTURE:
 * - Multi-cache strategy: separate caches for static assets, pages, and data
 * - SSR-aware: respects server-rendered content, never over-caches HTML
 * - Network-first for HTML: ensures users see fresh content
 * - Cache-first for static assets: maximizes performance on repeat visits
 * - Stale-while-revalidate for data: balance freshness with offline support
 *
 * VERSIONING:
 * Increment CACHE_VERSION when deploying updates. This triggers:
 * - New service worker installation
 * - Precache of updated assets
 * - Automatic cleanup of old caches
 *
 * Example: Change "v2" → "v3" before deployment
 */

// ============================================================================
// CONFIGURATION
// ============================================================================

/** @type {string} Cache version - increment on each deploy to invalidate old caches */
const CACHE_VERSION = 'v8';

/** @type {string} Cache for immutable static assets (JS, CSS, fonts, images) */
const STATIC_CACHE = `tidex-static-${CACHE_VERSION}`;

/** @type {string} Cache for HTML pages and navigation requests */
const PAGES_CACHE = `tidex-pages-${CACHE_VERSION}`;

/** @type {string} Cache for API responses and dynamic data */
const DATA_CACHE = `tidex-data-${CACHE_VERSION}`;

/** @type {string} Path to offline fallback page */
const OFFLINE_URL = '/offline.html';

/**
 * Assets to precache during service worker installation
 * These are critical resources needed for offline functionality
 *
 * @type {string[]}
 */
const PRECACHE_ASSETS = [
  // Offline fallback
  OFFLINE_URL,

  // PWA manifest
  '/manifest.json',

  // Essential app icons
  '/icon-192x192.png',
  '/icon-512x512.png',
  '/apple-touch-icon.png',

  // Branding assets for offline experience
  '/icons/tidex-logo.webp',
  '/icons/tidex-wordmark.webp',
];

/**
 * App routes to precache for offline navigation
 * These are the main app pages users can access offline
 * Will be fetched after initial install to avoid blocking
 *
 * Note: Settings pages are read-only when offline (no mutations allowed)
 *
 * @type {string[]}
 */
const APP_ROUTES_TO_PRECACHE = [
  '/',           // Home/dashboard
  '/shifts',     // Shifts view
  '/shifts/add', // Add shift form (queues mutations when offline)
  '/stats',      // Statistics page
  '/settings',   // Settings hub (read-only offline)
  '/settings/pay',         // Pay settings (read-only offline)
  '/settings/display',     // Display settings (read-only offline)
  '/settings/preferences', // Preferences (read-only offline)
  '/settings/profile',     // Profile settings (read-only offline)
  '/settings/subscription', // Subscription page (read-only offline)
];

/**
 * Timeout for network requests (milliseconds)
 * Balances fresh content with offline resilience
 */
const NETWORK_TIMEOUT = {
  navigation: 3000, // HTML pages - slightly longer for SSR
  data: 2000,       // API requests - fast timeout for offline fallback
};

// ============================================================================
// INSTALL EVENT - Precache Critical Assets
// ============================================================================

/**
 * Install event handler
 * Precaches essential assets and activates immediately
 *
 * Strategy:
 * 1. Open static cache
 * 2. Add all precache assets
 * 3. Call skipWaiting() to activate immediately without waiting for tabs to close
 */
self.addEventListener('install', (event) => {
  console.log('[SW] Install event - version:', CACHE_VERSION);

  event.waitUntil(
    caches.open(STATIC_CACHE)
      .then((cache) => {
        console.log('[SW] Precaching', PRECACHE_ASSETS.length, 'essential assets');
        return cache.addAll(PRECACHE_ASSETS);
      })
      .then(() => {
        console.log('[SW] Precaching complete, skipping waiting');
        // Activate immediately - don't wait for existing tabs to close
        return self.skipWaiting();
      })
      .catch((error) => {
        console.error('[SW] Precaching failed:', error);
        // Don't block installation if precaching fails
        return self.skipWaiting();
      })
  );
});

// ============================================================================
// ACTIVATE EVENT - Cleanup & Take Control
// ============================================================================

/**
 * Activate event handler
 * Cleans up old caches and takes control of all pages
 *
 * Strategy:
 * 1. Delete all caches that don't match current version
 * 2. Call clients.claim() to control existing pages immediately
 * 3. Precache app routes in the background (after activation)
 */
self.addEventListener('activate', (event) => {
  console.log('[SW] Activate event - version:', CACHE_VERSION);

  event.waitUntil(
    caches.keys()
      .then((cacheNames) => {
        // Filter out current version caches
        const cachesToDelete = cacheNames.filter((cacheName) => {
          return cacheName.startsWith('tidex-') &&
                 !cacheName.endsWith(CACHE_VERSION);
        });

        if (cachesToDelete.length > 0) {
          console.log('[SW] Deleting', cachesToDelete.length, 'old caches:', cachesToDelete);
        }

        // Delete all old caches in parallel
        return Promise.all(
          cachesToDelete.map((cacheName) => caches.delete(cacheName))
        );
      })
      .then(() => {
        console.log('[SW] Cache cleanup complete, claiming clients');
        // Take control of all pages immediately
        return self.clients.claim();
      })
      .then(() => {
        // Precache app routes in the background (don't block activation)
        console.log('[SW] Starting background precache of app routes');
        precacheAppRoutes();
      })
  );
});

/**
 * Precache all app routes for offline navigation
 * Runs in the background after service worker activation
 * Fetches all routes and caches them for offline use
 */
async function precacheAppRoutes() {
  try {
    // Get user's locale from cookie or default to 'no'
    const locale = await getUserLocale();
    console.log('[SW] Detected user locale:', locale);

    const cache = await caches.open(PAGES_CACHE);
    console.log('[SW] Precaching', APP_ROUTES_TO_PRECACHE.length, 'app routes for locale:', locale);

    // Fetch all routes in parallel (but don't fail if one fails)
    const results = await Promise.allSettled(
      APP_ROUTES_TO_PRECACHE.map(async (route) => {
        try {
          // Add locale prefix to route
          const localizedRoute = `/${locale}${route}`;

          const response = await fetch(localizedRoute, {
            credentials: 'same-origin',
            redirect: 'follow', // Follow redirects automatically
            headers: {
              'Accept': 'text/html',
            },
          });

          if (response.ok && response.type !== 'opaqueredirect') {
            // Only cache the localized route (not the base route)
            // Caching base routes causes redirect errors
            await cache.put(localizedRoute, response);
            console.log('[SW] Precached route:', localizedRoute);
            return { route: localizedRoute, success: true };
          } else {
            console.warn('[SW] Failed to precache route (status', response.status + ', type:', response.type + '):', localizedRoute);
            return { route: localizedRoute, success: false };
          }
        } catch (error) {
          console.warn('[SW] Failed to precache route:', route, error);
          return { route, success: false };
        }
      })
    );

    const successful = results.filter(r => r.status === 'fulfilled' && r.value.success).length;
    console.log('[SW] Precached', successful, 'of', APP_ROUTES_TO_PRECACHE.length, 'app routes');
  } catch (error) {
    console.error('[SW] Failed to precache app routes:', error);
  }
}

/**
 * Get user's locale from NEXT_LOCALE cookie or default to 'no'
 * @returns {Promise<string>} User's locale code (e.g., 'no', 'en', 'de')
 */
async function getUserLocale() {
  try {
    // Try to get locale from cookie
    const cookies = await self.cookieStore?.getAll();
    if (cookies) {
      const localeCookie = cookies.find(c => c.name === 'NEXT_LOCALE');
      if (localeCookie) {
        return localeCookie.value;
      }
    }
  } catch (error) {
    // cookieStore API not available, fall back to default
  }

  // Default to Norwegian
  return 'no';
}

// ============================================================================
// FETCH EVENT - Request Interception & Caching
// ============================================================================

/**
 * Fetch event handler
 * Routes requests to appropriate caching strategies based on request type
 *
 * Request types:
 * - Navigation (HTML pages): Network-first with cache/offline fallback
 * - Static assets (JS/CSS/images): Cache-first with network fallback
 * - API/Data requests: Network-first with stale-while-revalidate
 */
self.addEventListener('fetch', (event) => {
  const { request } = event;
  const { url, method, mode } = request;

  // ========================================
  // SECURITY: Only handle GET requests
  // ========================================
  if (method !== 'GET') {
    // Never cache POST, PUT, PATCH, DELETE requests
    return;
  }

  // ========================================
  // SECURITY: Only handle same-origin requests
  // ========================================
  if (!url.startsWith(self.location.origin)) {
    // Let browser handle cross-origin requests normally
    return;
  }

  // ========================================
  // SECURITY: Skip auth-related endpoints
  // ========================================
  // WARNING: Never cache authentication endpoints to prevent security issues
  if (url.includes('/auth/') || url.includes('.supabase.co/auth/') || url.includes('.supabase.co/realtime')) {
    console.log('[SW] Bypassing auth endpoint:', url);
    return;
  }

  // ========================================
  // STRATEGY 1: HTML Navigation Requests
  // ========================================
  // SSR-aware: Network-first with timeout, cache fallback, offline page
  // This ensures users see fresh server-rendered content when online
  if (mode === 'navigate') {
    event.respondWith(handleNavigationRequest(request));
    return;
  }

  // ========================================
  // STRATEGY 2: Static Assets
  // ========================================
  // Cache-first for immutable assets: JS, CSS, fonts, images
  if (isStaticAsset(url)) {
    event.respondWith(handleStaticAsset(request));
    return;
  }

  // ========================================
  // STRATEGY 3: API & Data Requests
  // ========================================
  // Network-first with stale-while-revalidate fallback
  if (isDataRequest(url)) {
    event.respondWith(handleDataRequest(request));
    return;
  }

  // ========================================
  // FALLBACK: Default network-first strategy
  // ========================================
  event.respondWith(
    fetch(request)
      .then((response) => cacheResponse(PAGES_CACHE, request, response))
      .catch(() => caches.match(request))
  );
});

// ============================================================================
// CACHING STRATEGIES
// ============================================================================

/**
 * Handle HTML navigation requests (page loads)
 *
 * Strategy: Network-first with timeout
 * 1. Try network with 3s timeout (respects SSR, gets fresh content)
 * 2. Fallback to cached version if network fails
 * 3. Serve offline.html if neither network nor cache available
 *
 * Why network-first?
 * - Next.js pages are server-rendered with dynamic data
 * - We want users to see fresh content when online
 * - Cache only provides offline resilience, not performance
 *
 * @param {Request} request - The navigation request
 * @returns {Promise<Response>}
 */
async function handleNavigationRequest(request) {
  try {
    // Try network first with timeout (respects SSR)
    const response = await fetchWithTimeout(request, NETWORK_TIMEOUT.navigation);

    // Cache successful navigation responses for offline access
    // IMPORTANT: Don't cache redirects - they cause "service worker has redirections" error
    if (response && response.ok && response.type !== 'opaqueredirect' && !response.redirected) {
      // Clone before caching (response body can only be read once)
      const responseToCache = response.clone();
      caches.open(PAGES_CACHE).then((cache) => {
        cache.put(request, responseToCache);
      });
    }

    return response;
  } catch (error) {
    console.log('[SW] Navigation network failed, trying cache:', request.url);

    // Try to serve cached version
    const cachedResponse = await caches.match(request);
    if (cachedResponse) {
      console.log('[SW] Serving cached page:', request.url);
      return cachedResponse;
    }

    // Last resort: serve offline page
    console.log('[SW] No cache available, serving offline page');
    const offlineResponse = await caches.match(OFFLINE_URL);
    return offlineResponse || new Response(
      '<html><body><h1>Offline</h1><p>No cached content available.</p></body></html>',
      { headers: { 'Content-Type': 'text/html' } }
    );
  }
}

/**
 * Handle static assets (JS, CSS, fonts, images)
 *
 * Strategy: Cache-first with network fallback
 * 1. Try cache first (instant response)
 * 2. If not in cache, fetch from network and cache for future
 *
 * Why cache-first?
 * - Static assets are immutable (/_next/static/* has content hashes)
 * - Maximum performance on repeat visits
 * - Network is only fallback if asset not yet cached
 *
 * @param {Request} request - The static asset request
 * @returns {Promise<Response>}
 */
async function handleStaticAsset(request) {
  // Try cache first for instant response
  const cachedResponse = await caches.match(request);
  if (cachedResponse) {
    return cachedResponse;
  }

  console.log('[SW] Static asset not cached, fetching:', request.url);

  // Not in cache, fetch from network
  try {
    const response = await fetch(request);

    // Cache successful responses for future requests
    if (response && response.ok) {
      const responseToCache = response.clone();
      caches.open(STATIC_CACHE).then((cache) => {
        cache.put(request, responseToCache);
      });
    }

    return response;
  } catch (error) {
    console.error('[SW] Static asset fetch failed:', request.url, error);

    // Return a transparent GIF for failed images, generic error for others
    if (request.destination === 'image') {
      return new Response(
        'R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7',
        { headers: { 'Content-Type': 'image/gif' } }
      );
    }

    return new Response('Asset unavailable', { status: 503 });
  }
}

/**
 * Handle API and data requests
 *
 * Strategy: Network-first with stale-while-revalidate
 * 1. Try network with 2s timeout (fast failure for offline UX)
 * 2. If network fails, serve stale cached data
 * 3. Background update: cache fresh response for next request
 *
 * Why network-first with timeout?
 * - Prioritizes fresh data from Supabase/API
 * - Quick timeout ensures responsive offline experience
 * - Cached data prevents complete failure
 *
 * WARNING: Only cache GET requests for public/non-sensitive data
 * Do NOT cache personalized or sensitive user data
 *
 * @param {Request} request - The data request
 * @returns {Promise<Response>}
 */
async function handleDataRequest(request) {
  try {
    // Try network first with short timeout
    const response = await fetchWithTimeout(request, NETWORK_TIMEOUT.data);

    // Cache successful responses in background (stale-while-revalidate)
    if (response && response.ok) {
      const responseToCache = response.clone();
      caches.open(DATA_CACHE).then((cache) => {
        cache.put(request, responseToCache);
      });
    }

    return response;
  } catch (error) {
    console.log('[SW] Data request failed, trying cache:', request.url);

    // Serve stale cached data if available
    const cachedResponse = await caches.match(request);
    if (cachedResponse) {
      console.log('[SW] Serving stale cached data:', request.url);
      return cachedResponse;
    }

    // No cache available, return friendly JSON error
    return new Response(
      JSON.stringify({
        error: 'Offline',
        message: 'This data is not available offline. Please check your connection.',
      }),
      {
        status: 503,
        statusText: 'Service Unavailable',
        headers: { 'Content-Type': 'application/json' },
      }
    );
  }
}

// ============================================================================
// UTILITY FUNCTIONS
// ============================================================================

/**
 * Check if URL is a static asset that should be cached aggressively
 *
 * Includes:
 * - Next.js build outputs: /_next/static/* (immutable, content-hashed)
 * - Public images/icons: *.png, *.jpg, *.svg, *.webp, *.ico
 * - Fonts: *.woff, *.woff2, *.ttf
 * - Other static resources from /public
 *
 * @param {string} url - Request URL
 * @returns {boolean}
 */
function isStaticAsset(url) {
  return (
    // Next.js static assets (immutable, content-hashed)
    url.includes('/_next/static/') ||

    // Images
    url.match(/\.(png|jpg|jpeg|gif|svg|webp|ico|avif)$/i) ||

    // Fonts
    url.match(/\.(woff|woff2|ttf|otf|eot)$/i) ||

    // CSS (if not from /_next/static)
    url.match(/\.css$/i) ||

    // JS modules (if not from /_next/static)
    url.match(/\.js$/i)
  );
}

/**
 * Check if URL is a data/API request
 *
 * Includes:
 * - Internal API routes: /api/*
 * - Supabase requests: *.supabase.co/*
 * - JSON responses
 *
 * Excludes:
 * - Auth endpoints (handled separately)
 *
 * @param {string} url - Request URL
 * @returns {boolean}
 */
function isDataRequest(url) {
  return (
    url.includes('/api/') ||
    url.includes('.supabase.co/rest/') ||
    url.includes('.supabase.co/realtime/')
  );
}

/**
 * Fetch with timeout
 * Returns promise that rejects if fetch takes longer than specified timeout
 *
 * @param {Request} request - Request to fetch
 * @param {number} timeout - Timeout in milliseconds
 * @returns {Promise<Response>}
 */
function fetchWithTimeout(request, timeout) {
  return Promise.race([
    fetch(request),
    new Promise((_, reject) =>
      setTimeout(() => reject(new Error('Network timeout')), timeout)
    ),
  ]);
}

/**
 * Cache a response and return the original
 * Helper for caching successful responses
 *
 * @param {string} cacheName - Cache to store response in
 * @param {Request} request - Original request
 * @param {Response} response - Response to cache
 * @returns {Response} - Original response (not clone)
 */
function cacheResponse(cacheName, request, response) {
  // Only cache successful responses
  if (response && response.ok) {
    const responseToCache = response.clone();
    caches.open(cacheName).then((cache) => {
      cache.put(request, responseToCache);
    });
  }
  return response;
}

// ============================================================================
// BACKGROUND SYNC - Offline Mutations Queue
// ============================================================================

/**
 * Background Sync
 * Retries queued mutations when connection is restored
 */
self.addEventListener('sync', (event) => {
  console.log('[SW] Sync event:', event.tag);

  if (event.tag === 'sync-mutations') {
    event.waitUntil(syncPendingMutations());
  }
});

/**
 * Process queued mutations from IndexedDB
 * Retries failed mutations when back online
 */
async function syncPendingMutations() {
  try {
    console.log('[SW] Processing pending mutations queue');

    // Notify clients that sync started
    await notifyClients({ type: 'SYNC_STARTED' });

    // Open IndexedDB to get queued mutations
    const db = await openMutationsDB();
    const mutations = await getAllPendingMutations(db);

    console.log(`[SW] Found ${mutations.length} pending mutations`);

    for (const queuedMutation of mutations) {
      try {
        // Reconstruct request
        const requestInit = {
          method: queuedMutation.method,
          headers: {
            'Content-Type': 'application/json',
            ...queuedMutation.headers,
          },
        };

        if (queuedMutation.body) {
          requestInit.body = queuedMutation.body;
        }

        // Retry the mutation
        const response = await fetch(queuedMutation.endpoint, requestInit);

        if (response.ok) {
          console.log('[SW] Successfully synced mutation:', queuedMutation.type, queuedMutation.endpoint);
          await removeMutationFromQueue(db, queuedMutation.id);

          // Notify clients of successful sync
          await notifyClients({
            type: 'SYNC_SUCCESS',
            endpoint: queuedMutation.endpoint,
            mutationType: queuedMutation.type,
          });

          // Invalidate cached shifts data
          await invalidateShiftsCache();
        } else {
          const errorText = await response.text();
          console.error('[SW] Mutation failed with status:', response.status, errorText);

          // Remove from queue for client errors (4xx) that won't resolve on retry
          // Keep in queue for server errors (5xx) that might resolve later
          if (response.status >= 400 && response.status < 500) {
            console.log('[SW] Client error (4xx), removing mutation from queue');
            await removeMutationFromQueue(db, queuedMutation.id);

            // Notify clients of permanent failure
            await notifyClients({
              type: 'SYNC_ERROR',
              endpoint: queuedMutation.endpoint,
              error: `HTTP ${response.status}: ${errorText}`,
              mutationType: queuedMutation.type,
            });
          } else {
            // Server error (5xx) - keep in queue for next sync attempt
            console.log('[SW] Server error (5xx), will retry later');
          }
        }
      } catch (error) {
        console.error('[SW] Failed to sync mutation:', error);
        // Keep in queue for next sync attempt
      }
    }

    // Notify clients that queue was updated
    await notifyClients({ type: 'QUEUE_UPDATED' });
  } catch (error) {
    console.error('[SW] Background sync failed:', error);
    throw error; // Re-throw to trigger retry
  }
}

/**
 * Open IndexedDB for mutations queue
 */
function openMutationsDB() {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open('tidex-mutations-db', 1);

    request.onerror = () => reject(request.error);
    request.onsuccess = () => resolve(request.result);

    request.onupgradeneeded = (event) => {
      const db = event.target.result;
      if (!db.objectStoreNames.contains('mutations')) {
        const store = db.createObjectStore('mutations', {
          keyPath: 'id',
        });
        store.createIndex('timestamp', 'timestamp', { unique: false });
        store.createIndex('type', 'type', { unique: false });
      }
    };
  });
}

/**
 * Get all pending mutations from IndexedDB
 */
async function getAllPendingMutations(db) {
  return new Promise((resolve, reject) => {
    const transaction = db.transaction(['mutations'], 'readonly');
    const store = transaction.objectStore('mutations');
    const request = store.getAll();

    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

/**
 * Get count of pending mutations
 */
async function getPendingMutationsCount(db) {
  return new Promise((resolve, reject) => {
    const transaction = db.transaction(['mutations'], 'readonly');
    const store = transaction.objectStore('mutations');
    const request = store.count();

    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

/**
 * Add mutation to queue
 */
async function addMutationToQueue(db, mutation) {
  return new Promise((resolve, reject) => {
    const transaction = db.transaction(['mutations'], 'readwrite');
    const store = transaction.objectStore('mutations');
    const request = store.add(mutation);

    request.onsuccess = () => resolve();
    request.onerror = () => reject(request.error);
  });
}

/**
 * Remove successfully synced mutation from queue
 */
async function removeMutationFromQueue(db, id) {
  return new Promise((resolve, reject) => {
    const transaction = db.transaction(['mutations'], 'readwrite');
    const store = transaction.objectStore('mutations');
    const request = store.delete(id);

    request.onsuccess = () => resolve();
    request.onerror = () => reject(request.error);
  });
}

/**
 * Invalidate cached shifts data after successful sync
 */
async function invalidateShiftsCache() {
  try {
    const cache = await caches.open(DATA_CACHE);
    const keys = await cache.keys();

    // Delete all cached /api/shifts* responses
    for (const request of keys) {
      if (request.url.includes('/api/shifts')) {
        await cache.delete(request);
        console.log('[SW] Invalidated cache:', request.url);
      }
    }
  } catch (error) {
    console.error('[SW] Failed to invalidate cache:', error);
  }
}

/**
 * Notify all clients of an event
 */
async function notifyClients(message) {
  const clients = await self.clients.matchAll({ includeUncontrolled: true });
  clients.forEach(client => {
    client.postMessage(message);
  });
}

// ============================================================================
// PUSH NOTIFICATIONS
// ============================================================================

/**
 * Push event handler
 * Shows notifications when push messages are received
 *
 * Use case: Weekly earnings summary, milestone achievements
 */
self.addEventListener('push', (event) => {
  console.log('[SW] Push notification received');

  // Parse push data
  let notificationData = {
    title: 'Tidex',
    body: 'You have a new notification',
    icon: '/icon-192x192.png',
    badge: '/icon-192x192.png',
    data: {}
  };

  if (event.data) {
    try {
      const data = event.data.json();
      notificationData = {
        title: data.title || notificationData.title,
        body: data.body || notificationData.body,
        icon: data.icon || notificationData.icon,
        badge: data.badge || notificationData.badge,
        data: data.data || {},
        tag: data.tag,
        requireInteraction: data.requireInteraction || false,
      };
    } catch (error) {
      console.error('[SW] Error parsing push data:', error);
    }
  }

  // Show notification
  event.waitUntil(
    self.registration.showNotification(notificationData.title, {
      body: notificationData.body,
      icon: notificationData.icon,
      badge: notificationData.badge,
      tag: notificationData.tag,
      data: notificationData.data,
      requireInteraction: notificationData.requireInteraction,
      actions: [
        {
          action: 'view',
          title: 'View',
          icon: '/icon-192x192.png'
        },
        {
          action: 'dismiss',
          title: 'Dismiss'
        }
      ]
    })
  );
});

/**
 * Notification click handler
 * Opens app when notification is clicked
 */
self.addEventListener('notificationclick', (event) => {
  console.log('[SW] Notification clicked:', event.action);

  event.notification.close();

  if (event.action === 'dismiss') {
    return;
  }

  // Determine URL based on notification data
  let url = '/en';
  if (event.notification.data && event.notification.data.url) {
    url = event.notification.data.url;
  }

  // Open or focus app window
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true })
      .then((clientList) => {
        // Focus existing window if available
        for (const client of clientList) {
          if (client.url.includes(self.registration.scope) && 'focus' in client) {
            return client.focus().then(() => {
              // Navigate to notification URL
              if ('navigate' in client) {
                return client.navigate(url);
              }
            });
          }
        }

        // No existing window, open new one
        if (clients.openWindow) {
          return clients.openWindow(url);
        }
      })
  );
});

/**
 * Notification close handler
 * Track when users dismiss notifications (for analytics)
 */
self.addEventListener('notificationclose', (event) => {
  console.log('[SW] Notification closed:', event.notification.tag);

  // Optional: Send analytics event
  // Could track which notifications users dismiss
});

// ============================================================================
// MESSAGE HANDLER
// ============================================================================

/**
 * Handle messages from client pages
 *
 * Supported messages:
 * - SKIP_WAITING: Force service worker to activate immediately
 * - CLEAR_CACHE: Clear all caches (useful for debugging)
 * - QUEUE_REQUEST: Add failed request to background sync queue
 */
self.addEventListener('message', (event) => {
  const { data } = event;

  if (!data || !data.type) {
    return;
  }

  switch (data.type) {
    case 'SKIP_WAITING':
      console.log('[SW] Received SKIP_WAITING message');
      self.skipWaiting();
      break;

    case 'CLEAR_CACHE':
      console.log('[SW] Received CLEAR_CACHE message');
      event.waitUntil(
        caches.keys().then((cacheNames) => {
          return Promise.all(
            cacheNames.map((cacheName) => {
              if (cacheName.startsWith('tidex-')) {
                console.log('[SW] Clearing cache:', cacheName);
                return caches.delete(cacheName);
              }
            })
          );
        })
      );
      break;

    case 'QUEUE_MUTATION':
      console.log('[SW] Queueing mutation:', data.mutation);
      event.waitUntil(
        openMutationsDB().then((db) => {
          return addMutationToQueue(db, data.mutation).then(() => {
            // Notify clients that queue was updated
            return notifyClients({ type: 'QUEUE_UPDATED' });
          });
        })
      );
      break;

    case 'GET_QUEUE_COUNT':
      console.log('[SW] Getting queue count');
      event.waitUntil(
        openMutationsDB().then((db) => {
          return getPendingMutationsCount(db).then((count) => {
            // Send response back to client via port
            if (event.ports && event.ports[0]) {
              event.ports[0].postMessage({
                type: 'QUEUE_COUNT',
                count: count,
              });
            }
          });
        })
      );
      break;

    default:
      console.log('[SW] Unknown message type:', data.type);
  }
});

// ============================================================================
// DEPLOYMENT CHECKLIST
// ============================================================================

/**
 * Before deploying a new version:
 *
 * 1. Increment CACHE_VERSION (e.g., "v2" → "v3")
 * 2. Review PRECACHE_ASSETS - add new critical assets
 * 3. Test offline behavior in DevTools:
 *    - Application > Service Workers > Update on reload
 *    - Network > Offline checkbox
 *    - Navigate between cached pages
 * 4. Verify cache cleanup:
 *    - Application > Cache Storage
 *    - Old caches should be deleted after activation
 * 5. Monitor console logs for errors
 *
 * Common issues:
 * - "Failed to fetch" for precache: Asset path incorrect or doesn't exist
 * - Stale content: Forgot to increment CACHE_VERSION
 * - Auth broken: Check that auth endpoints are excluded from caching
 * - Slow updates: Users need to close all tabs for new SW to activate
 */
