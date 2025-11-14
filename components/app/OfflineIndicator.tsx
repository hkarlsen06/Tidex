'use client';

import { useOfflineQueue } from '@/lib/pwa/offline-queue';
import { WifiOff, CloudOff, RefreshCw, CheckCircle2, X } from 'lucide-react';
import { useState, useEffect, useRef } from 'react';

/**
 * OfflineIndicator Component
 * Shows offline status and pending sync queue
 *
 * Features:
 * - Displays "Offline" badge when navigator.onLine is false
 * - Shows "Syncing X changes..." when queue has pending items
 * - Animated spinner during sync
 * - Manual retry button
 * - Success/error notifications
 * - Auto-hides when online and queue is empty
 */
export function OfflineIndicator() {
  const { isOnline, queuedCount, isSyncing, refreshQueueCount } = useOfflineQueue();
  const [showSuccess, setShowSuccess] = useState(false);
  const prevQueuedCountRef = useRef(queuedCount);

  // Detect when queue count decreases (successful sync)
  useEffect(() => {
    const prevCount = prevQueuedCountRef.current;
    // Update ref for next render
    prevQueuedCountRef.current = queuedCount;

    // Check if sync completed successfully (count dropped to 0)
    if (!isSyncing && prevCount > 0 && queuedCount === 0) {
      // Defer state update to avoid cascading renders
      const timer = setTimeout(() => {
        setShowSuccess(true);
        const hideTimer = setTimeout(() => setShowSuccess(false), 3000);
        return () => clearTimeout(hideTimer);
      }, 0);

      // Cleanup timeout on unmount
      return () => clearTimeout(timer);
    }
  }, [queuedCount, isSyncing]);

  // Show success message briefly, then hide completely
  if (showSuccess) {
    return (
      <div className="fixed bottom-4 right-4 z-50 flex items-center gap-2 rounded-lg border border-green-500/20 bg-green-500/10 px-4 py-2 shadow-lg animate-in fade-in slide-in-from-bottom-2">
        <CheckCircle2 className="h-4 w-4 text-green-500" aria-hidden="true" />
        <span className="text-sm text-green-500 font-medium">All changes synced!</span>
        <button
          onClick={() => setShowSuccess(false)}
          className="ml-2 text-green-500/70 hover:text-green-500"
          aria-label="Dismiss"
        >
          <X className="h-4 w-4" />
        </button>
      </div>
    );
  }

  // Hide if online and no pending changes
  if (isOnline && queuedCount === 0 && !isSyncing) {
    return null;
  }

  const handleManualRetry = async () => {
    if ('serviceWorker' in navigator && 'sync' in ServiceWorkerRegistration.prototype) {
      const registration = await navigator.serviceWorker.ready;
      // TypeScript doesn't have types for Background Sync API yet
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      await (registration as any).sync.register('sync-mutations');
      refreshQueueCount();
    }
  };

  return (
    <div className="fixed bottom-4 right-4 z-50 flex items-center gap-3 rounded-lg border border-border bg-surface-primary px-4 py-2 shadow-lg">
      {/* Icon */}
      {isSyncing ? (
        <RefreshCw className="h-4 w-4 animate-spin text-brand-primary" aria-hidden="true" />
      ) : !isOnline ? (
        <WifiOff className="h-4 w-4 text-text-muted" aria-hidden="true" />
      ) : (
        <CloudOff className="h-4 w-4 text-text-muted" aria-hidden="true" />
      )}

      {/* Status Text */}
      <div className="text-sm">
        {isSyncing ? (
          <span className="text-text-primary font-medium">
            Syncing {queuedCount} {queuedCount === 1 ? 'change' : 'changes'}...
          </span>
        ) : !isOnline ? (
          <div className="flex flex-col">
            <span className="text-text-primary font-medium">Offline</span>
            {queuedCount > 0 && (
              <span className="text-text-muted text-xs">
                {queuedCount} {queuedCount === 1 ? 'change' : 'changes'} queued
              </span>
            )}
          </div>
        ) : queuedCount > 0 ? (
          <div className="flex flex-col">
            <span className="text-text-primary font-medium">
              {queuedCount} {queuedCount === 1 ? 'change' : 'changes'} pending
            </span>
            <span className="text-text-muted text-xs">Will sync when connected</span>
          </div>
        ) : null}
      </div>

      {/* Manual Retry Button - show when online with pending changes */}
      {isOnline && queuedCount > 0 && !isSyncing && (
        <button
          onClick={handleManualRetry}
          className="ml-1 rounded p-1 text-text-muted hover:bg-surface-secondary hover:text-text-primary transition-colors"
          title="Retry sync now"
          aria-label="Retry sync"
        >
          <RefreshCw className="h-4 w-4" />
        </button>
      )}
    </div>
  );
}
