import 'server-only';
import { cache } from 'react';
import { cacheTag } from 'next/cache';
import { verifySession } from '@/data-access/auth';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { logger } from '@/lib/logger';
import type { WageSnapshot, SupplementRule, BreakMethod } from '@/lib/payroll/types';

// Re-export types for convenience
export type { WageSnapshot, SupplementRule };

/**
 * Get all wage snapshots for the authenticated user
 * - Uses React cache() for request deduplication
 * - Returns snapshots ordered by from_date DESC (newest first)
 * - Automatically verifies user session
 */
export const getUserWageSnapshots = cache(async (): Promise<WageSnapshot[]> => {
  'use cache: private';
  try {
    const { user } = await verifySession();
    cacheTag(`user-${user.id}`, 'user-wages');
    const supabase = await createSupabaseServerClient();

    const { data, error } = await supabase
      .from('wage_snapshots')
      .select('*')
      .eq('user_id', user.id)
      .is('deleted_at', null) // Exclude soft-deleted snapshots
      .order('from_date', { ascending: false, nullsFirst: false });

    if (error) {
      logger.error('Failed to fetch wage snapshots:', error);
      return [];
    }

    return (data ?? []) as WageSnapshot[];
  } catch (error) {
    logger.error('Unexpected error fetching wage snapshots:', error);
    return [];
  }
});

/**
 * Get the applicable wage snapshot for a specific shift date
 * - Finds the most recent snapshot where from_date <= shiftDate
 * - Falls back to baseline snapshot (from_date = NULL) if no dated snapshot matches
 * - Returns null if no applicable snapshot found
 * - Uses getUserWageSnapshots() which is cached
 *
 * @param shiftDate - ISO date string (YYYY-MM-DD) of the shift
 * @returns The applicable WageSnapshot or null
 */
export async function getSnapshotForDate(
  shiftDate: string
): Promise<WageSnapshot | null> {
  const snapshots = await getUserWageSnapshots();

  // snapshots are already ordered by from_date DESC (newest first)
  // Find the first dated snapshot where from_date <= shiftDate
  const applicableSnapshot = snapshots.find(
    (snapshot) => snapshot.from_date !== null && snapshot.from_date <= shiftDate
  );

  if (applicableSnapshot) {
    return applicableSnapshot;
  }

  // If no dated snapshot matches, use the baseline snapshot (from_date = NULL)
  const baselineSnapshot = snapshots.find((snapshot) => snapshot.from_date === null);

  return baselineSnapshot ?? null;
}

/**
 * Get applicable snapshots for multiple shift dates (batch lookup)
 * - Optimized for performance: fetches all snapshots once, then maps them
 * - Returns a Map of shiftDate -> WageSnapshot
 * - Falls back to baseline snapshot (from_date = NULL) if no dated snapshot matches
 * - Dates without applicable snapshots are omitted from the map
 *
 * @param shiftDates - Array of ISO date strings (YYYY-MM-DD)
 * @returns Map of shift date to applicable WageSnapshot
 */
export async function getSnapshotsForDates(
  shiftDates: string[]
): Promise<Map<string, WageSnapshot>> {
  const snapshots = await getUserWageSnapshots();
  const snapshotMap = new Map<string, WageSnapshot>();

  // Find baseline snapshot once for fallback
  const baselineSnapshot = snapshots.find((snapshot) => snapshot.from_date === null);

  for (const shiftDate of shiftDates) {
    // Find the first dated snapshot where from_date <= shiftDate
    const applicableSnapshot = snapshots.find(
      (snapshot) => snapshot.from_date !== null && snapshot.from_date <= shiftDate
    );

    // Use dated snapshot if found, otherwise fall back to baseline
    const snapshotToUse = applicableSnapshot || baselineSnapshot;

    if (snapshotToUse) {
      snapshotMap.set(shiftDate, snapshotToUse);
    }
  }

  return snapshotMap;
}

/**
 * Check if a wage snapshot with the given from_date already exists
 * - Used for validation before creating/updating snapshots
 * - Handles both dated snapshots and baseline (NULL from_date)
 *
 * @param fromDate - ISO date string (YYYY-MM-DD) or null for baseline
 * @param excludeId - Optional snapshot ID to exclude (for update operations)
 * @returns true if a snapshot exists for this date
 */
export async function checkExistingSnapshot(
  fromDate: string | null,
  excludeId?: string
): Promise<boolean> {
  try {
    const { user } = await verifySession();
    const supabase = await createSupabaseServerClient();

    let query = supabase
      .from('wage_snapshots')
      .select('id')
      .eq('user_id', user.id)
      .is('deleted_at', null); // Exclude soft-deleted snapshots

    // Handle NULL from_date (baseline snapshot)
    if (fromDate === null) {
      query = query.is('from_date', null);
    } else {
      query = query.eq('from_date', fromDate);
    }

    // Exclude specific snapshot (for update validation)
    if (excludeId) {
      query = query.neq('id', excludeId);
    }

    const { data, error } = await query.single();

    if (error && error.code !== 'PGRST116') {
      // PGRST116 = "not found" which is what we want
      logger.error('Failed to check existing snapshot:', error);
      return false;
    }

    return !!data;
  } catch (error) {
    logger.error('Unexpected error checking existing snapshot:', error);
    return false;
  }
}

/**
 * Input type for creating/updating wage snapshots
 */
export type WageSnapshotInput = {
  from_date: string | null;
  hourly_wage: number;
  wage_level: number | null;
  supplements: { rules: SupplementRule[] };
  // Tax settings
  tax_enabled: boolean;
  tax_percentage: number;
  // Break deduction settings
  break_enabled: boolean;
  break_method: BreakMethod;
  break_threshold_hours: number;
  break_deduction_minutes: number;
};

/**
 * Create a new wage snapshot
 *
 * @param data - Wage snapshot data (without id and user_id)
 *              - from_date can be null for baseline snapshot
 * @returns { success: true, id: string } or { error: string }
 */
export async function createWageSnapshot(
  data: WageSnapshotInput
): Promise<{ success: true; id: string } | { error: string }> {
  try {
    const { user } = await verifySession();
    const supabase = await createSupabaseServerClient();

    const { data: snapshot, error } = await supabase
      .from('wage_snapshots')
      .insert({
        user_id: user.id,
        from_date: data.from_date,
        hourly_wage: data.hourly_wage,
        wage_level: data.wage_level,
        supplements: data.supplements,
        tax_enabled: data.tax_enabled,
        tax_percentage: data.tax_percentage,
        break_enabled: data.break_enabled,
        break_method: data.break_method,
        break_threshold_hours: data.break_threshold_hours,
        break_deduction_minutes: data.break_deduction_minutes,
      })
      .select('id')
      .single();

    if (error) {
      logger.error('Failed to create wage snapshot:', error);
      return { error: error.message };
    }

    return { success: true, id: snapshot.id };
  } catch (error) {
    logger.error('Unexpected error creating wage snapshot:', error);
    return { error: 'Kunne ikke opprette lønnsoppføring' };
  }
}

/**
 * Update an existing wage snapshot
 *
 * @param id - Snapshot ID to update
 * @param data - New wage snapshot data (from_date can be null for baseline)
 * @returns { success: true } or { error: string }
 */
export async function updateWageSnapshot(
  id: string,
  data: WageSnapshotInput
): Promise<{ success: true } | { error: string }> {
  try {
    const { user } = await verifySession();
    const supabase = await createSupabaseServerClient();

    const { error } = await supabase
      .from('wage_snapshots')
      .update({
        from_date: data.from_date,
        hourly_wage: data.hourly_wage,
        wage_level: data.wage_level,
        supplements: data.supplements,
        tax_enabled: data.tax_enabled,
        tax_percentage: data.tax_percentage,
        break_enabled: data.break_enabled,
        break_method: data.break_method,
        break_threshold_hours: data.break_threshold_hours,
        break_deduction_minutes: data.break_deduction_minutes,
      })
      .eq('id', id)
      .eq('user_id', user.id) // Security: ensure user owns this snapshot
      .is('deleted_at', null); // Only update non-deleted snapshots

    if (error) {
      logger.error('Failed to update wage snapshot:', error);
      return { error: error.message };
    }

    return { success: true };
  } catch (error) {
    logger.error('Unexpected error updating wage snapshot:', error);
    return { error: 'Kunne ikke oppdatere lønnsoppføring' };
  }
}

/**
 * Count shifts affected by a wage snapshot
 * - Returns the count of shifts between this snapshot and the next one
 *
 * @param snapshotId - Snapshot ID to check
 * @returns Number of affected shifts
 */
export async function countAffectedShifts(
  snapshotId: string
): Promise<number> {
  try {
    const { user } = await verifySession();
    const supabase = await createSupabaseServerClient();

    // First, get the snapshot's from_date
    const { data: snapshot, error: snapshotError } = await supabase
      .from('wage_snapshots')
      .select('from_date')
      .eq('id', snapshotId)
      .eq('user_id', user.id)
      .is('deleted_at', null) // Only find non-deleted snapshots
      .single();

    if (snapshotError || !snapshot) {
      logger.error('Failed to get snapshot for counting:', snapshotError);
      return 0;
    }

    // Get all snapshots to find the next one
    const snapshots = await getUserWageSnapshots();
    const currentIndex = snapshots.findIndex((s) => s.id === snapshotId);

    if (currentIndex === -1) return 0;

    // Find the next snapshot (earlier date since snapshots are ordered DESC)
    const nextSnapshot = snapshots[currentIndex + 1] ?? null;

    // Count shifts between this snapshot and the next (or all shifts >= this snapshot)
    let query = supabase
      .from('user_shifts')
      .select('id', { count: 'exact', head: true })
      .eq('user_id', user.id)
      .is('deleted_at', null) // Only count non-deleted shifts
      .gte('shift_date', snapshot.from_date);

    if (nextSnapshot) {
      query = query.lt('shift_date', nextSnapshot.from_date);
    }

    const { count, error } = await query;

    if (error) {
      logger.error('Failed to count affected shifts:', error);
      return 0;
    }

    return count ?? 0;
  } catch (error) {
    logger.error('Unexpected error counting affected shifts:', error);
    return 0;
  }
}

/**
 * Delete a wage snapshot
 *
 * Restrictions:
 * - Cannot delete the baseline snapshot (from_date = NULL) if other dated snapshots exist
 * - This ensures there's always a fallback for wage calculations
 *
 * @param id - Snapshot ID to delete
 * @returns { success: true, affectedShiftCount: number } or { error: string }
 */
export async function deleteWageSnapshot(
  id: string
): Promise<{ success: true; affectedShiftCount: number } | { error: string }> {
  try {
    const { user } = await verifySession();
    const supabase = await createSupabaseServerClient();

    // First, get the snapshot to check if it's baseline
    const { data: snapshot, error: fetchError } = await supabase
      .from('wage_snapshots')
      .select('from_date')
      .eq('id', id)
      .eq('user_id', user.id)
      .is('deleted_at', null) // Only find non-deleted snapshots
      .single();

    if (fetchError || !snapshot) {
      logger.error('Failed to fetch snapshot for deletion:', fetchError);
      return { error: 'Kunne ikke finne lønnsoppføringen' };
    }

    // If this is the baseline snapshot, check if other snapshots exist
    if (snapshot.from_date === null) {
      const snapshots = await getUserWageSnapshots();
      const datedSnapshots = snapshots.filter(s => s.from_date !== null);

      if (datedSnapshots.length > 0) {
        return {
          error: 'Kan ikke slette grunntariffen når det finnes andre lønnsendringer. Slett de andre først.',
        };
      }
    }

    // Count affected shifts before deletion
    const affectedShiftCount = await countAffectedShifts(id);

    // Soft delete by setting deleted_at
    const { error } = await supabase
      .from('wage_snapshots')
      .update({ deleted_at: new Date().toISOString() })
      .eq('id', id)
      .eq('user_id', user.id) // Security: ensure user owns this snapshot
      .is('deleted_at', null); // Only delete if not already deleted

    if (error) {
      logger.error('Failed to delete wage snapshot:', error);
      return { error: error.message };
    }

    return { success: true, affectedShiftCount };
  } catch (error) {
    logger.error('Unexpected error deleting wage snapshot:', error);
    return { error: 'Kunne ikke slette lønnsoppføring' };
  }
}
