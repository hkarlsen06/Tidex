'use client';

import { useOfflineQueue } from '@/lib/pwa/offline-queue';
import { WifiOff, RefreshCw } from 'lucide-react';

/**
 * OfflineIndicator Component
 * Compact badge for the header showing offline/sync status
 *
 * Features:
 * - Shows when offline or syncing
 * - Displays queued count
 * - Animated spinner during sync
 * - Auto-hides when online with no pending changes
 */
export function OfflineIndicator() {
  const { isOnline, queuedCount, isSyncing } = useOfflineQueue();

  // Hide if online and no pending changes
  if (isOnline && queuedCount === 0 && !isSyncing) {
    return null;
  }

  return (
    <div className="flex items-center gap-1.5 px-2 py-1 rounded-md bg-surface-secondary border border-border-subtle">
      {/* Icon */}
      {isSyncing ? (
        <RefreshCw className="h-3.5 w-3.5 animate-spin text-brand-primary" aria-hidden="true" />
      ) : (
        <WifiOff className="h-3.5 w-3.5 text-text-muted" aria-hidden="true" />
      )}

      {/* Status Text */}
      <span className="text-xs text-text-secondary">
        {isSyncing ? (
          `Syncing ${queuedCount}...`
        ) : !isOnline ? (
          queuedCount > 0 ? `${queuedCount} queued` : 'Offline'
        ) : (
          `${queuedCount} pending`
        )}
      </span>
    </div>
  );
}
