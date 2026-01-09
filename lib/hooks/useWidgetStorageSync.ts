"use client";

import { useCallback, useRef, useEffect } from "react";
import { saveShiftsToWidgetStorage } from "@/lib/capacitor/widget-storage";
import { isIOSPlatform } from "@/lib/capacitor/platform";
import type { ShiftWithComputations } from "@/lib/payroll/types";

/** Debounce window in milliseconds */
const DEBOUNCE_MS = 500;

type UseWidgetStorageSyncOptions = {
  /** User's locale ("no" or "en") */
  locale: string;
  /** Currency symbol to display (e.g., "kr", "$", "€") */
  currencySymbol: string;
  /** User-specific cache key for API requests */
  cacheKey?: string;
};

type SyncOptions = {
  /** Pass existing shifts to avoid refetch. If omitted, fetches from API. */
  shifts?: ShiftWithComputations[];
};

/**
 * Hook to sync widget storage after shift mutations.
 *
 * Features:
 * - Accepts optional shifts payload to avoid refetching
 * - 500ms debounce to batch rapid mutations
 * - "Latest wins" deduplication for overlapping calls
 * - Fire-and-forget API - callers don't await
 * - No-op on non-iOS platforms
 *
 * @example
 * ```tsx
 * const { syncWidgetStorage } = useWidgetStorageSync({
 *   locale,
 *   currencySymbol,
 *   cacheKey,
 * });
 *
 * // After successful mutation - pass existing shifts
 * router.refresh();
 * syncWidgetStorage({ shifts });
 *
 * // Or let hook fetch if shifts not available
 * syncWidgetStorage();
 * ```
 */
export function useWidgetStorageSync({
  locale,
  currencySymbol,
  cacheKey = "",
}: UseWidgetStorageSyncOptions) {
  // Track pending debounce timer
  const debounceTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  // Track latest pending data (for "latest wins")
  const pendingDataRef = useRef<ShiftWithComputations[] | null>(null);
  // Track if a fetch is currently in progress
  const isFetchingRef = useRef(false);
  // Track if another sync was requested during fetch
  const queuedSyncRef = useRef<SyncOptions | null>(null);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      if (debounceTimerRef.current) {
        clearTimeout(debounceTimerRef.current);
      }
    };
  }, []);

  /**
   * Fetch shifts for current and next month from API.
   * Returns combined, deduplicated array.
   */
  const fetchShifts = useCallback(async (): Promise<ShiftWithComputations[]> => {
    const now = new Date();
    const currentYear = now.getFullYear();
    const currentMonth = now.getMonth() + 1;

    // Also fetch next month in case we're near month end
    const nextMonthDate = new Date(now);
    nextMonthDate.setMonth(nextMonthDate.getMonth() + 1);
    const nextYear = nextMonthDate.getFullYear();
    const nextMonth = nextMonthDate.getMonth() + 1;

    const fetchMonth = async (year: number, month: number): Promise<ShiftWithComputations[]> => {
      try {
        // Add timestamp to bust any browser cache
        const response = await fetch(
          `/api/shifts?year=${year}&month=${month}&_ck=${cacheKey}&_t=${Date.now()}`
        );
        if (!response.ok) return [];
        const data = await response.json();
        return (data.shifts ?? []) as ShiftWithComputations[];
      } catch {
        return [];
      }
    };

    const [currentShifts, nextShifts] = await Promise.all([
      fetchMonth(currentYear, currentMonth),
      fetchMonth(nextYear, nextMonth),
    ]);

    // Combine and dedupe by ID
    const allShifts = [...currentShifts, ...nextShifts];
    return Array.from(new Map(allShifts.map((s) => [s.id, s])).values());
  }, [cacheKey]);

  /**
   * Execute the actual sync operation.
   * Uses provided shifts or fetches from API.
   */
  const executeSync = useCallback(
    async (shifts: ShiftWithComputations[] | null) => {
      let shiftsToSave = shifts;

      if (!shiftsToSave) {
        // Need to fetch - track in-flight state
        isFetchingRef.current = true;
        try {
          shiftsToSave = await fetchShifts();
        } finally {
          isFetchingRef.current = false;
        }
      }

      // Save to widget storage
      await saveShiftsToWidgetStorage(shiftsToSave, locale, currencySymbol);

      // Check if another sync was queued while we were fetching
      const queued = queuedSyncRef.current;
      if (queued) {
        queuedSyncRef.current = null;
        // Execute the queued sync (will use its own data or fetch)
        executeSync(queued.shifts ?? null);
      }
    },
    [fetchShifts, locale, currencySymbol]
  );

  /**
   * Trigger a widget storage sync.
   * Debounced and deduplicated - safe to call rapidly.
   */
  const syncWidgetStorage = useCallback(
    (options?: SyncOptions) => {
      // Early exit for non-iOS platforms
      if (!isIOSPlatform()) return;

      const shifts = options?.shifts ?? null;

      // If a fetch is currently in progress, queue this sync
      if (isFetchingRef.current) {
        queuedSyncRef.current = { shifts: shifts ?? undefined };
        return;
      }

      // Store latest data (for "latest wins" behavior)
      pendingDataRef.current = shifts;

      // Clear any existing debounce timer
      if (debounceTimerRef.current) {
        clearTimeout(debounceTimerRef.current);
      }

      // Set up debounced execution
      debounceTimerRef.current = setTimeout(() => {
        debounceTimerRef.current = null;
        const dataToSync = pendingDataRef.current;
        pendingDataRef.current = null;

        // Fire and forget - don't await
        executeSync(dataToSync).catch((error) => {
          console.error("[WidgetStorageSync] Sync failed:", error);
        });
      }, DEBOUNCE_MS);
    },
    [executeSync]
  );

  return { syncWidgetStorage };
}
