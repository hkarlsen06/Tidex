/**
 * Offline Queue Manager
 * Manages queueing of failed mutations for background sync
 *
 * Client-side utility that works with the service worker to:
 * - Queue mutations when offline
 * - Trigger background sync when back online
 * - Listen for sync success/failure events
 */

import { useState, useEffect, useCallback } from 'react';

export interface QueuedMutation {
  id: string;
  type: 'CREATE' | 'UPDATE' | 'DELETE';
  timestamp: number;
  endpoint: string;
  method: string;
  body?: string;
  headers?: Record<string, string>;
}

/**
 * Check if offline queue APIs are supported
 */
export function isOfflineQueueSupported(): boolean {
  return (
    typeof window !== 'undefined' &&
    'serviceWorker' in navigator &&
    'sync' in ServiceWorkerRegistration.prototype &&
    'indexedDB' in window
  );
}

/**
 * Queue a mutation for background sync
 * Called when a mutation fails due to offline status
 *
 * @param mutation - The mutation to queue
 */
export async function queueMutation(mutation: Omit<QueuedMutation, 'id' | 'timestamp'>): Promise<void> {
  if (!isOfflineQueueSupported()) {
    throw new Error('Offline queue not supported');
  }

  // Add ID and timestamp
  const queueItem: QueuedMutation = {
    ...mutation,
    id: crypto.randomUUID(),
    timestamp: Date.now(),
  };

  // Send to service worker
  const registration = await navigator.serviceWorker.ready;

  if (registration.active) {
    registration.active.postMessage({
      type: 'QUEUE_MUTATION',
      mutation: queueItem,
    });

    // Trigger background sync registration
    // This will be retried when online
    // TypeScript doesn't have types for Background Sync API yet
    await (registration as any).sync.register('sync-mutations');
  }
}

/**
 * Get count of pending mutations in the queue
 */
export async function getPendingMutationsCount(): Promise<number> {
  if (!isOfflineQueueSupported()) {
    return 0;
  }

  try {
    const registration = await navigator.serviceWorker.ready;

    // Request count from service worker
    return new Promise((resolve) => {
      const messageChannel = new MessageChannel();

      messageChannel.port1.onmessage = (event) => {
        if (event.data.type === 'QUEUE_COUNT') {
          resolve(event.data.count || 0);
        }
      };

      registration.active?.postMessage(
        { type: 'GET_QUEUE_COUNT' },
        [messageChannel.port2]
      );

      // Timeout after 1 second
      setTimeout(() => resolve(0), 1000);
    });
  } catch {
    return 0;
  }
}

/**
 * Listen for sync events from service worker
 *
 * @param onSuccess - Called when sync succeeds
 * @param onError - Called when sync fails
 * @returns Cleanup function
 */
export function onSyncEvent(
  onSuccess?: (endpoint: string) => void,
  onError?: (endpoint: string, error: string) => void
): () => void {
  if (!isOfflineQueueSupported()) {
    return () => {};
  }

  const handler = (event: MessageEvent) => {
    if (event.data && event.data.type === 'SYNC_SUCCESS') {
      onSuccess?.(event.data.endpoint);
    } else if (event.data && event.data.type === 'SYNC_ERROR') {
      onError?.(event.data.endpoint, event.data.error);
    }
  };

  navigator.serviceWorker.addEventListener('message', handler);

  return () => {
    navigator.serviceWorker.removeEventListener('message', handler);
  };
}

/**
 * React hook for offline queue state
 *
 * Returns:
 * - isOnline: Current online status
 * - queuedCount: Number of pending mutations
 * - isSyncing: Whether sync is in progress
 */
export function useOfflineQueue() {
  const [isOnline, setIsOnline] = useState(
    typeof window !== 'undefined' ? navigator.onLine : true
  );
  const [queuedCount, setQueuedCount] = useState(0);
  const [isSyncing, setIsSyncing] = useState(false);

  // Use useCallback to prevent infinite loop while fixing missing dependency
  const updateQueueCount = useCallback(async () => {
    const count = await getPendingMutationsCount();
    setQueuedCount(count);
  }, []);

  useEffect(() => {
    if (typeof window === 'undefined') return;

    // Update online status
    const handleOnline = () => setIsOnline(true);
    const handleOffline = () => setIsOnline(false);

    window.addEventListener('online', handleOnline);
    window.addEventListener('offline', handleOffline);

    // Listen for sync events
    const cleanup = onSyncEvent(
      () => {
        setIsSyncing(false);
        // Refresh queue count
        updateQueueCount();
      },
      () => {
        setIsSyncing(false);
        // Queue count might not have changed, but refresh anyway
        updateQueueCount();
      }
    );

    // Listen for queue updates from service worker
    const handleMessage = (event: MessageEvent) => {
      if (event.data && event.data.type === 'QUEUE_UPDATED') {
        updateQueueCount();
      } else if (event.data && event.data.type === 'SYNC_STARTED') {
        setIsSyncing(true);
      }
    };

    if ('serviceWorker' in navigator) {
      navigator.serviceWorker.addEventListener('message', handleMessage);
    }

    // Initial queue count - defer to avoid setState in effect warning
    const initialLoad = setTimeout(updateQueueCount, 0);

    // Poll queue count every 30 seconds
    const interval = setInterval(updateQueueCount, 30000);

    return () => {
      window.removeEventListener('online', handleOnline);
      window.removeEventListener('offline', handleOffline);
      cleanup();
      clearTimeout(initialLoad);
      clearInterval(interval);
      if ('serviceWorker' in navigator) {
        navigator.serviceWorker.removeEventListener('message', handleMessage);
      }
    };
  }, [updateQueueCount]);

  return {
    isOnline,
    queuedCount,
    isSyncing,
    queueMutation,
    refreshQueueCount: updateQueueCount,
  };
}
